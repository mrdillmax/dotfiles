# shellcheck shell=bash
# Shared helpers for install.sh and the maintenance scripts.
[[ -n ${_DOTFILES_COMMON:-} ]] && return 0
_DOTFILES_COMMON=1

: "${DOTFILES_DIR:?DOTFILES_DIR must be set}"
: "${DRY_RUN:=0}"
: "${ASSUME_YES:=0}"

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

# Run a mutating command, or print it in dry-run mode.
run() {
    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} $*"
    else
        "$@"
    fi
}

# yay 13 accepts --pgpfetch but never reads it. With --noconfirm it imports the
# keys declared in validpgpkeys from gpg's default keyserver, and some kernel
# build keys are not served there. Point gpg at servers that have them; the
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

    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} backup $target -> $dest"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    cp -a "$target" "$dest"
    printf '%s\t%s\n' "$target" "$dest" >>"$BACKUP_DIR/manifest.tsv"
    log "backup: $target -> $dest"
}

record_managed() {
    local kind="$1" path="$2" source="$3"
    (( DRY_RUN )) && return 0
    printf '%s\t%s\t%s\n' "$kind" "$path" "$source" >>"$STATE_FILE"
}

# Symlink a repository file into $HOME, backing up anything it replaces.
link_path() {
    local src="$1" dst="$2"

    if [[ -L $dst ]] && [[ "$(readlink -f -- "$dst" 2>/dev/null || true)" == "$(readlink -f -- "$src" 2>/dev/null || true)" ]]; then
        log "already linked: $dst"
        return 0
    fi

    if [[ -e $dst || -L $dst ]]; then
        backup_path "$dst"
    fi

    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} symlink $dst -> $src"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    ln -sfn "$src" "$dst"
    record_managed "link" "$dst" "$src"
    ok "linked $dst -> $src"
}

# Copy a file with an explicit mode (used for rendered configs).
copy_file() {
    local src="$1" dst="$2" mode="${3:-0644}"

    if [[ -f $dst ]] && cmp -s -- "$src" "$dst"; then
        log "up to date: $dst"
        if (( !DRY_RUN )); then
            chmod "$mode" "$dst"
        fi
        return 0
    fi

    if [[ -e $dst || -L $dst ]]; then
        backup_path "$dst"
    fi

    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} copy $src -> $dst (mode $mode)"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    install -m "$mode" -- "$src" "$dst"
    record_managed "copy" "$dst" "$src"
    ok "wrote $dst"
}
