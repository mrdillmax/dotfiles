#!/usr/bin/env bash
# Install the Spicetify CLI from the upstream installer.
#
# The package is intentionally not in the package catalog: upstream ships a
# supported installer that keeps the CLI in ~/.spicetify and out of pacman.
set -uo pipefail

URL="https://raw.githubusercontent.com/spicetify/cli/main/install.sh"
DRY_RUN=0
ASSUME_YES=0

usage() {
    cat <<'EOF'
Usage: install-spicetify.sh [--dry-run] [--yes]

Downloads and runs the official Spicetify installer:
  curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh

Options:
  --dry-run   print the command, change nothing
  --yes       do not ask for confirmation
  -h, --help  this help

The CLI installs under ~/.spicetify. No sudo and no system package changes.
EOF
}

die() { printf 'spicetify: %s\n' "$*" >&2; exit 1; }

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --yes|-y)  ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

if ((DRY_RUN)); then
    printf ':: [dry-run] curl -fsSL %s | sh\n' "$URL"
    exit 0
fi

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v sh >/dev/null 2>&1 || die "sh is required"

if ((!ASSUME_YES)); then
    [[ -t 0 ]] || die "refusing to run without a terminal; pass --yes"
    printf 'Install Spicetify from the official script into ~/.spicetify? [y/N]: '
    read -r reply || reply=""
    [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]] || die "not installed"
fi

tmp="$(mktemp)"
trap 'rm -f -- "$tmp"' EXIT
curl -fsSL "$URL" -o "$tmp" || die "download failed"
sh "$tmp" || die "upstream installer failed"

if command -v spicetify >/dev/null 2>&1; then
    printf 'ok spicetify installed: %s\n' "$(command -v spicetify)"
else
    printf 'ok installer finished; restart the shell or add ~/.spicetify to PATH\n'
fi
