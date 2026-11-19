#!/usr/bin/env bash
# First-run bootstrap for a fresh Arch install.
#
# It installs the tools the installer needs, builds yay-bin when no AUR helper
# exists, then runs install.sh and a read-only doctor pass. Everything after
# `--` is forwarded to install.sh.
#
# Safety model:
#   * --dry-run prints every command and changes nothing
#   * packages are installed only after a confirmation (or --yes)
#   * yay-bin is built as the invoking user, never as root
#   * --no-aur keeps the old behaviour and only warns about a missing helper
#   * the installer keeps its own backup/confirmation rules
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L $SOURCE ]]; do
    dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$dir/$SOURCE"
done
ROOT="$(cd -P "$(dirname "$SOURCE")" && pwd)"

ARCH_RELEASE="${BOOTSTRAP_ARCH_RELEASE:-/etc/arch-release}"
INSTALLER="${BOOTSTRAP_INSTALLER:-$ROOT/install.sh}"

DRY_RUN=0
ASSUME_YES=0
SKIP_PACKAGES=0
SKIP_NETWORK=0
SKIP_AUR=0
INSTALLER_ARGS=()
AUR_TMP=""

BASE_PACKAGES=(base-devel git curl jq gum networkmanager)

usage() {
    cat <<'EOF'
Usage: ./bootstrap.sh [options] [-- installer options]

  --yes, -y        install packages and run install.sh --all --yes
  --dry-run        print every command, change nothing
  --no-packages    skip the package step
  --no-aur         do not build yay-bin when no AUR helper exists
  --skip-network   skip the network reachability check
  -h, --help       this help

Everything after `--` is passed to install.sh, for example:
  ./bootstrap.sh --yes -- --host laptop --gpu intel

Bootstrap installs base-devel, git, curl, jq, gum and networkmanager. When neither paru nor
yay exists, it builds yay-bin from the AUR as your user. Use --no-aur to skip
that step.
EOF
}

die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }
info() { printf ':: %s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# shellcheck source=lib/tui.sh
if [[ -r $ROOT/lib/tui.sh ]]; then
    source "$ROOT/lib/tui.sh"
else
    tui_confirm() {
        local prompt="$1" default="${2:-no}" reply
        ((ASSUME_YES)) && return 0
        [[ -t 0 ]] || return 1
        printf '%s [%s]: ' "$prompt" "$([[ $default == yes ]] && echo 'Y/n' || echo 'y/N')"
        read -r reply || true
        reply="${reply:-$default}"
        [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
    }
fi

confirm() {
    local prompt="$1"
    ((ASSUME_YES)) && return 0
    tui_confirm "$prompt" yes
}

check_host() {
    [[ -r $ARCH_RELEASE ]] \
        || die "this does not look like Arch Linux ($ARCH_RELEASE is missing); refusing to continue"

    if [[ $(id -u) -eq 0 ]]; then
        die "run bootstrap as your user, not as root (pacman will ask for sudo)"
    fi
}

check_network() {
    ((SKIP_NETWORK)) && return 0
    ((DRY_RUN)) && return 0

    command -v curl >/dev/null 2>&1 || {
        warn "curl is missing; skipping the network check"
        return 0
    }
    if ! curl -sSfI --max-time 5 https://archlinux.org >/dev/null 2>&1; then
        die "cannot reach archlinux.org; check the network or pass --skip-network"
    fi
    ok "network reachable"
}

cleanup() {
    if [[ -n $AUR_TMP && -d $AUR_TMP ]]; then
        rm -rf -- "$AUR_TMP"
    fi
    return 0
}
trap cleanup EXIT

missing_packages() {
    local pkg
    MISSING=()

    # base-devel is a group, so check a few of its tools instead of a name.
    if ! command -v makepkg >/dev/null 2>&1 \
        || ! command -v gcc >/dev/null 2>&1 \
        || ! command -v fakeroot >/dev/null 2>&1; then
        MISSING+=("base-devel")
    fi
    for pkg in git curl jq gum; do
        command -v "$pkg" >/dev/null 2>&1 || MISSING+=("$pkg")
    done
    # The catalogue no longer carries NetworkManager, so bootstrap keeps a
    # fresh machine online after the first reboot.
    command -v nmcli >/dev/null 2>&1 || MISSING+=("networkmanager")
}

install_packages() {
    ((SKIP_PACKAGES)) && {
        info "package step skipped (--no-packages)"
        return 0
    }

    missing_packages
    if ((${#MISSING[@]} == 0)); then
        ok "bootstrap packages already present: ${BASE_PACKAGES[*]}"
        return 0
    fi

    info "missing bootstrap packages: ${MISSING[*]}"
    local cmd=(sudo pacman -S --needed --noconfirm "${MISSING[@]}")

    if ((DRY_RUN)); then
        printf '[dry-run] %s\n' "${cmd[*]}"
        return 0
    fi

    if ! confirm "Install ${MISSING[*]} with pacman?"; then
        warn "package installation declined; install.sh may still work"
        return 0
    fi

    "${cmd[@]}" || die "pacman failed; install the packages manually and rerun"
    ok "bootstrap packages installed"
}

install_aur_helper() {
    ((SKIP_PACKAGES)) && return 0
    if ((SKIP_AUR)); then
        warn "AUR helper installation disabled (--no-aur)"
        return 0
    fi
    if command -v paru >/dev/null 2>&1 || command -v yay >/dev/null 2>&1; then
        ok "AUR helper found"
        return 0
    fi

    if ((DRY_RUN)); then
        printf '[dry-run] git clone https://aur.archlinux.org/yay-bin.git <tmp>/yay-bin\n'
        printf '[dry-run] (cd <tmp>/yay-bin && makepkg -si --noconfirm)\n'
        return 0
    fi

    command -v git >/dev/null 2>&1 || {
        warn "git is missing; cannot build yay-bin"
        return 0
    }
    command -v makepkg >/dev/null 2>&1 || {
        warn "makepkg is missing; cannot build yay-bin"
        return 0
    }

    if ! confirm "No AUR helper found. Build yay-bin from the AUR?"; then
        warn "AUR helper installation declined; AUR packages will be skipped"
        return 0
    fi

    AUR_TMP="$(mktemp -d)"
    if ! git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$AUR_TMP/yay-bin"; then
        warn "could not clone yay-bin; AUR packages will be skipped"
        return 0
    fi
    if (cd "$AUR_TMP/yay-bin" && makepkg -si --noconfirm); then
        ok "yay installed"
    else
        warn "yay-bin build failed; AUR packages will be skipped"
    fi
}

installer_command() {
    local -a cmd=("$INSTALLER")
    if ((ASSUME_YES)); then
        cmd+=(--all --yes)
    fi
    if ((${#INSTALLER_ARGS[@]} > 0)); then
        cmd+=("${INSTALLER_ARGS[@]}")
    fi
    printf '%s\n' "${cmd[@]}"
}

run_installer() {
    local -a cmd=()

    [[ -x $INSTALLER ]] || die "installer not found: $INSTALLER"
    mapfile -t cmd < <(installer_command)

    printf ':: %s\n' "${cmd[*]}"
    if ((DRY_RUN)); then
        printf '[dry-run] %s\n' "${cmd[*]}"
        return 0
    fi
    "${cmd[@]}"
}

run_doctor() {
    local -a cmd=("$INSTALLER" --doctor)

    ((DRY_RUN)) && {
        printf '[dry-run] %s\n' "${cmd[*]}"
        return 0
    }
    if "${cmd[@]}"; then
        ok "doctor pass finished"
    else
        warn "doctor reported problems; review the output above"
    fi
}

while (($#)); do
    case "$1" in
        --yes|-y)      ASSUME_YES=1 ;;
        --dry-run)     DRY_RUN=1 ;;
        --no-packages) SKIP_PACKAGES=1 ;;
        --no-aur)      SKIP_AUR=1 ;;
        --skip-network) SKIP_NETWORK=1 ;;
        --)
            shift
            INSTALLER_ARGS=("$@")
            break
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help; use -- to pass installer options)" ;;
    esac
    shift
done

check_host
check_network
install_packages
install_aur_helper
run_installer
run_doctor

if ((!DRY_RUN)); then
    ok "bootstrap finished; log out and back in if this was the first install"
fi
