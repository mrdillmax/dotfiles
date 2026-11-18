#!/usr/bin/env bash
# Compare the package catalog in this repository with the installed packages.
#
# `pull` only appends missing entries to packages/local.tsv; it never removes a
# package from the repository and never installs anything.
#
# A pacman hook (installed with `./install.sh --system`) touches
# /var/lib/dotfiles/pkg-sync.stamp after every package transaction. `status`
# warns when that stamp is newer than the last check, so a review can happen at
# a convenient time instead of during the transaction.
set -uo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L $SOURCE ]]; do
    dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$dir/$SOURCE"
done
REPO="${DOTFILES_DIR:-$(cd -P "$(dirname "$SOURCE")/.." && pwd)}"

PKG_SYNC_HOST="${PKG_SYNC_HOST:-}"
STAMP="${PKG_SYNC_STAMP:-/var/lib/dotfiles/pkg-sync.stamp}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LAST_CHECK="$STATE_DIR/pkg-sync.last"
EXTRA_FILE="$REPO/packages/local.tsv"

DRY_RUN=0
ASSUME_YES=0
QUIET=0
COMMAND=""

usage() {
    cat <<'EOF'
Usage: pkg-sync.sh <status|check|pull> [--dry-run] [--yes] [--quiet]

  status   show how the catalog compares with this machine
  check    same comparison; exits 1 when something differs
  pull     append installed-but-unlisted packages to packages/local.tsv
           (never removes entries)

Options:
  --dry-run   print the changes, write nothing
  --yes       do not ask before writing local.tsv
  --quiet     print only when there is drift

The catalog lives in packages/catalog.tsv. Rows with default=no are optional:
they are not reported as missing, but an installed optional package counts as
listed. Host-specific rows are compared only on the matching host.

Environment:
  PKG_SYNC_HOST   override host detection (desktop|laptop)
  PKG_SYNC_STAMP  pacman stamp path (default: /var/lib/dotfiles/pkg-sync.stamp)
EOF
}

die() { printf 'pkg-sync: %s\n' "$*" >&2; exit 1; }
info() { printf ':: %s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

detect_host() {
    if [[ -n $PKG_SYNC_HOST ]]; then
        printf '%s' "$PKG_SYNC_HOST"
        return 0
    fi
    if compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1; then
        printf 'laptop'
        return 0
    fi
    local chassis=""
    [[ -r /sys/class/dmi/id/chassis_type ]] \
        && chassis="$(cat /sys/class/dmi/id/chassis_type)"
    case "$chassis" in
        8|9|10|14) printf 'laptop' ;;
        *)         printf 'desktop' ;;
    esac
}

require_pacman() {
    command -v pacman >/dev/null 2>&1 \
        || die "pacman is not available; this check only runs on Arch Linux"
}

catalog_files() {
    local file
    for file in "$REPO/packages/catalog.tsv" "$EXTRA_FILE"; do
        [[ -r $file ]] || continue
        printf '%s\n' "$file"
    done
}

catalog_rows() {
    local file
    while IFS= read -r file; do
        awk 'NF && $0 !~ /^#/' "$file"
    done < <(catalog_files)
}

# Packages required on this host: default=yes and a matching host.
repo_required() {
    local host="$1" pkg _category _role default row_host _gpu _description
    while IFS=$'\t' read -r pkg _category _role default row_host _gpu _description; do
        [[ $default == yes ]] || continue
        [[ $row_host == any || $row_host == "$host" ]] || continue
        printf '%s\n' "$pkg"
    done < <(catalog_rows)
}

# Every package the catalog knows about, regardless of host or default.
repo_all() {
    catalog_rows | cut -f1
}

# Reads `pacman -Qq`, `pacman -Qqe` and `pacman -Sgq` results from the
# caller-provided files.
load_sets() {
    local present_file="$1" installed_file="$2" groups_file="$3" name member
    declare -gA PRESENT=()
    declare -gA INSTALLED=()
    declare -gA GROUP_MEMBERS=()
    declare -gA GROUP_DONE=()

    while IFS= read -r name; do
        [[ -n $name ]] && PRESENT[$name]=1
    done <"$present_file"

    while IFS= read -r name; do
        [[ -n $name ]] && INSTALLED[$name]=1
    done <"$installed_file"

    while IFS= read -r line; do
        [[ -n $line ]] || continue
        name="${line%% *}"
        member="${line#* }"
        GROUP_MEMBERS[$name]+=" $member"
    done <"$groups_file"
}

group_installed() {
    local group="$1" member
    local -a members

    [[ -n ${GROUP_DONE[$group]:-} ]] && return 0
    read -r -a members <<<"${GROUP_MEMBERS[$group]:-}"
    ((${#members[@]})) || return 1
    for member in "${members[@]}"; do
        [[ -n ${PRESENT[$member]:-} ]] || return 1
    done
    GROUP_DONE[$group]=1
    return 0
}

# Fills MISSING and UNLISTED for the given host.
compare() {
    local host="$1" pkg line
    local -a required=() all=() missing=() unlisted=()

    mapfile -t required < <(repo_required "$host")
    mapfile -t all < <(repo_all)
    declare -gA REPO_SET=()
    for pkg in "${all[@]}"; do
        REPO_SET[$pkg]=1
    done

    for pkg in "${required[@]}"; do
        if [[ -z ${PRESENT[$pkg]:-} ]]; then
            # A group name (for example base-devel) is satisfied when every
            # member is installed.
            if [[ -n ${GROUP_MEMBERS[$pkg]:-} ]] && group_installed "$pkg"; then
                continue
            fi
            missing+=("$pkg")
        fi
    done

    for pkg in "${!INSTALLED[@]}"; do
        [[ -n ${REPO_SET[$pkg]:-} ]] || unlisted+=("$pkg")
    done

    mapfile -t missing < <(printf '%s\n' "${missing[@]}" | sed '/^$/d' | sort)
    mapfile -t unlisted < <(printf '%s\n' "${unlisted[@]}" | sed '/^$/d' | sort)
    MISSING=("${missing[@]}")
    UNLISTED=("${unlisted[@]}")
    LISTED_COUNT="${#required[@]}"
    ALL_COUNT="${#all[@]}"
    INSTALLED_COUNT="${#INSTALLED[@]}"

    if ((${#missing[@]} == 0 && ${#unlisted[@]} == 0)); then
        return 0
    fi
    return 1
}

gather_and_compare() {
    local host tmp_present tmp_installed tmp_groups rc=0
    require_pacman
    host="$(detect_host)"

    tmp_present="$(mktemp)"
    tmp_installed="$(mktemp)"
    tmp_groups="$(mktemp)"
    pacman -Qq >"$tmp_present" 2>/dev/null || {
        rm -f -- "$tmp_present" "$tmp_installed" "$tmp_groups"
        die "pacman -Qq failed"
    }
    pacman -Qqe >"$tmp_installed" 2>/dev/null || {
        rm -f -- "$tmp_present" "$tmp_installed" "$tmp_groups"
        die "pacman -Qqe failed"
    }
    # One line per group member: "<group> <member>".
    pacman -Sgq base-devel 2>/dev/null \
        | while IFS= read -r member; do
            [[ -n $member ]] && printf 'base-devel %s\n' "$member"
        done >"$tmp_groups"

    load_sets "$tmp_present" "$tmp_installed" "$tmp_groups"
    compare "$host" || rc=1
    rm -f -- "$tmp_present" "$tmp_installed" "$tmp_groups"
    HOST="$host"
    return "$rc"
}

stamp_is_newer() {
    [[ -r $STAMP ]] || return 1
    [[ -r $LAST_CHECK ]] || return 0
    [[ $STAMP -nt $LAST_CHECK ]]
}

record_check() {
    ((DRY_RUN)) && return 0
    mkdir -p -- "$STATE_DIR"
    date +%s >"$LAST_CHECK"
}

print_report() {
    local pkg

    printf 'host: %s\n' "$HOST"
    printf 'listed: %d required, %d total   installed (explicit): %d\n' \
        "$LISTED_COUNT" "$ALL_COUNT" "$INSTALLED_COUNT"

    if ((${#MISSING[@]} == 0 && ${#UNLISTED[@]} == 0)); then
        ok "package catalog matches this machine"
        return 0
    fi

    if ((${#MISSING[@]} > 0)); then
        printf '\nrequired in the catalog but not installed (%d):\n' "${#MISSING[@]}"
        for pkg in "${MISSING[@]}"; do printf '  - %s\n' "$pkg"; done
        printf '  review them; pkg-sync never removes entries\n'
    fi
    if ((${#UNLISTED[@]} > 0)); then
        printf '\ninstalled but not listed in the catalog (%d):\n' "${#UNLISTED[@]}"
        for pkg in "${UNLISTED[@]}"; do printf '  + %s\n' "$pkg"; done
        printf '  add them with: pkg-sync.sh pull\n'
    fi
    return 1
}

show_status() {
    local host
    host="$(detect_host)"
    printf 'host: %s\n' "$host"
    printf 'repo: %s\n' "$REPO"
    printf 'stamp: %s%s\n' "$STAMP" "$([[ -r $STAMP ]] && echo '' || echo ' (missing)')"

    if ! command -v pacman >/dev/null 2>&1; then
        printf 'packages: (pacman is not available)\n'
        return 0
    fi

    gather_and_compare || true
    if ((${#MISSING[@]} == 0 && ${#UNLISTED[@]} == 0)); then
        printf 'drift: none\n'
    else
        printf 'drift: %d required-not-installed, %d installed-not-listed\n' \
            "${#MISSING[@]}" "${#UNLISTED[@]}"
    fi

    if stamp_is_newer; then
        printf 'review: packages changed since the last check (pacman hook)\n'
    else
        printf 'review: up to date\n'
    fi
}

run_check() {
    gather_and_compare || {
        print_report
        record_check
        return 1
    }
    record_check
    ((QUIET)) || print_report
    return 0
}

append_extra() {
    local pkg tmp file="$EXTRA_FILE"

    if ((DRY_RUN)); then
        info "[dry-run] would append to $file: ${UNLISTED[*]}"
        return 0
    fi

    mkdir -p -- "$(dirname "$file")"
    tmp="$(mktemp)"
    if [[ -r $file ]]; then
        cp -a -- "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)"
        cat -- "$file" >"$tmp"
    else
        printf '# Local packages recorded by pkg-sync.sh. Not part of the curated catalog.\n' >"$tmp"
        printf '# package\tcategory\trole\tdefault\thost\tgpu\tdescription\n' >>"$tmp"
    fi
    for pkg in "${UNLISTED[@]}"; do
        printf '%s\tLocal\tpkg\tno\tany\tany\tInstalled locally; not curated\n' \
            "$pkg" >>"$tmp"
    done
    mv -f -- "$tmp" "$file"
    ok "appended ${#UNLISTED[@]} package(s) to packages/local.tsv"
}

run_pull() {
    if gather_and_compare; then
        ok "nothing to add"
        record_check
        return 0
    fi

    print_report || true
    if ((${#UNLISTED[@]} == 0)); then
        warn "only required-not-installed packages differ; nothing to pull"
        record_check
        return 0
    fi

    if ! ((ASSUME_YES)); then
        local reply
        if [[ ! -t 0 ]]; then
            die "refusing to write without a terminal; pass --yes"
        fi
        printf 'Append %d package(s) to packages/local.tsv? [y/N]: ' \
            "${#UNLISTED[@]}"
        read -r reply || reply=""
        [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]] || die "not written"
    fi

    append_extra
    record_check
}

while (($#)); do
    case "$1" in
        status|check|pull)
            [[ -z $COMMAND ]] || die "only one command is allowed"
            COMMAND="$1"
            ;;
        --dry-run) DRY_RUN=1 ;;
        --yes|-y)  ASSUME_YES=1 ;;
        --quiet)   QUIET=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

case "$COMMAND" in
    status) show_status ;;
    check)  run_check ;;
    pull)   run_pull ;;
    "")     usage >&2; exit 2 ;;
esac
