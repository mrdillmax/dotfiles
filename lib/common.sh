# shellcheck shell=bash
# Shared helpers for install.sh and the maintenance scripts.
[[ -n ${_DOTFILES_COMMON:-} ]] && return 0
_DOTFILES_COMMON=1

: "${DOTFILES_DIR:?DOTFILES_DIR must be set}"
: "${DRY_RUN:=0}"
: "${ASSUME_YES:=0}"
: "${VERBOSE:=0}"

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
else
    C_RESET="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
fi

log() {
    printf '%s\n' "$*"
    if [[ -n ${LOG_FILE:-} ]]; then
        printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG_FILE"
    fi
}

info()  { log "${C_BLUE}::${C_RESET} $*"; }
ok()    { log "${C_GREEN}ok${C_RESET} $*"; }
warn()  { log "${C_YELLOW}warning:${C_RESET} $*"; }
err()   { log "${C_RED}error:${C_RESET} $*" >&2; }
die()   { err "$*"; exit 1; }

# Quote an argv so a verbose line can be pasted back into a shell.
trace_cmd() {
    local arg out=""
    for arg in "$@"; do
        out+="$(printf '%q ' "$arg")"
    done
    printf '%s' "${out% }"
}

verbose_cmd() {
    (( VERBOSE )) && log "${C_DIM}[cmd]${C_RESET} $(trace_cmd "$@")"
    return 0
}

# Keep a rewritten state file writable by the desktop user after a sudo run.
state_file_permissions() {
    local file="$1" mode="${2:-}"
    [[ -n $mode ]] && chmod "$mode" "$file" 2>/dev/null || true
    if (( EUID == 0 )) && [[ -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]]; then
        chown "$SUDO_UID:$SUDO_GID" "$file" 2>/dev/null || true
    fi
}

# Run a mutating command, or print it in dry-run mode. Verbose mode prints
# the exact argv before running it.
run() {
    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} $(trace_cmd "$@")"
        return 0
    fi
    (( VERBOSE )) && log "${C_DIM}[cmd]${C_RESET} $(trace_cmd "$@")"
    "$@"
}

# yay 13 accepts --pgpfetch but never reads it. During a package build it
# imports the keys declared in validpgpkeys from gpg's default keyserver, and
# some kernel build keys are not served there. Point gpg at servers that have them; the
# import still happens once and later installs reuse the keyring.
# shellcheck disable=SC2034 # read by kernel.sh and packages.sh
AUR_GPG_FLAGS=(--gpgflags "--keyserver hkps://keyserver.ubuntu.com --keyserver hkps://pgp.surf.nl")

real_home() {
    local user="${SUDO_USER:-$USER}"
    getent passwd "$user" | cut -d: -f6
}

backup_path() {
    local target="$1"
    local rel="${target#"$REAL_HOME"/}"
    rel="${rel#/}"
    local dest="$BACKUP_DIR/$rel"

    LAST_BACKUP="$dest"

    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} backup $target -> $dest"
        return 0
    fi

    (( VERBOSE )) && log "${C_DIM}[cmd]${C_RESET} $(trace_cmd cp -a -- "$target" "$dest")"
    mkdir -p "$(dirname "$dest")"
    cp -a "$target" "$dest"
    printf '%s\t%s\n' "$target" "$dest" >>"$BACKUP_DIR/manifest.tsv"
    log "backup: $target -> $dest"
}

file_digest() {
    sha256sum -- "$1" | cut -d' ' -f1
}

# The latest row for a path owns its original pointer. Old rows without a
# fifth column report "-", so a pre-v2 install stays readable.
managed_original_for() {
    local want="$1" kind path source digest original found=""
    [[ -r $STATE_FILE ]] || return 0
    while IFS=$'\t' read -r kind path source digest original; do
        [[ -n ${path:-} ]] || continue
        [[ $path == "$want" ]] || continue
        found="${original:--}"
    done <"$STATE_FILE"
    [[ -n $found ]] || return 0
    printf '%s' "$found"
}

record_managed() {
    local kind="$1" path="$2" source="$3" digest="${4:--}" original="${5:-}"
    (( DRY_RUN )) && return 0
    local previous
    previous="$(managed_original_for "$path")"
    [[ -n $previous ]] && original="$previous"
    [[ -n $original ]] || original="-"
    printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$path" "$source" "$digest" "$original" \
        >>"$STATE_FILE"
    if (( EUID == 0 )) && [[ -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]]; then
        chown "$SUDO_UID:$SUDO_GID" "$STATE_FILE" 2>/dev/null || true
    fi
}

# Symlink a repository file into $HOME, backing up anything it replaces.
link_path() {
    local src="$1" dst="$2"

    if [[ -L $dst ]] && [[ "$(readlink -f -- "$dst" 2>/dev/null || true)" == "$(readlink -f -- "$src" 2>/dev/null || true)" ]]; then
        log "already linked: $dst"
        return 0
    fi

    LAST_BACKUP=""
    if [[ -e $dst || -L $dst ]]; then
        backup_path "$dst"
    fi

    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} symlink $dst -> $src"
        return 0
    fi

    (( VERBOSE )) && log "${C_DIM}[cmd]${C_RESET} $(trace_cmd ln -sfn -- "$src" "$dst")"
    mkdir -p "$(dirname "$dst")"
    ln -sfn "$src" "$dst"
    record_managed "link" "$dst" "$src" - "$LAST_BACKUP"
    ok "linked $dst -> $src"
}

# Copy a file with an explicit mode (used for rendered configs). The optional
# fourth argument records where the content came from when src is a temp file.
copy_file() {
    local src="$1" dst="$2" mode="${3:-0644}" recorded_source="${4:-$1}"

    if [[ -f $dst ]] && cmp -s -- "$src" "$dst"; then
        log "up to date: $dst"
        # chmod follows a symlink into a file this repository does not own;
        # leave the link and its target alone when the content already matches.
        if (( !DRY_RUN )) && [[ ! -L $dst ]]; then
            chmod "$mode" "$dst"
        fi
        return 0
    fi

    LAST_BACKUP=""
    if [[ -e $dst || -L $dst ]]; then
        backup_path "$dst"
    fi

    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} copy $src -> $dst (mode $mode)"
        return 0
    fi

    (( VERBOSE )) && log "${C_DIM}[cmd]${C_RESET} $(trace_cmd install -m "$mode" -- "$src" "$dst")"
    mkdir -p "$(dirname "$dst")"
    install -m "$mode" -- "$src" "$dst"
    record_managed "copy" "$dst" "$recorded_source" "$(file_digest "$src")" "$LAST_BACKUP"
    ok "wrote $dst"
}
