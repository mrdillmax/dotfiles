#!/usr/bin/env bash
# Install the Spicetify CLI from the official GitHub release.
#
# The upstream install.sh is deliberately not used: it runs `spicetify update`
# for an existing CLI and installs the Marketplace by default. Both call
# `spicetify config`, which validates `spotify_path`; on a machine where
# Spotify is installed through spotify-launcher but has not been launched yet,
# that path does not exist and the whole install fails. Installing the CLI
# only needs the release archive.
set -uo pipefail

RELEASES="https://github.com/spicetify/cli/releases"
API="https://api.github.com/repos/spicetify/cli/releases/latest"
DEST="$HOME/.spicetify"
DRY_RUN=0
ASSUME_YES=0

usage() {
    cat <<'EOF'
Usage: install-spicetify.sh [--dry-run] [--yes]

Installs the Spicetify CLI from the official GitHub release into
~/.spicetify. No spicetify commands are run, so the CLI installs even when
Spotify (spotify-launcher) has not been launched and no Spotify path exists
yet. The Marketplace is installed later, after the first Spotify launch.

Options:
  --dry-run   print the release location, change nothing
  --yes       do not ask for confirmation
  -h, --help  this help

No sudo and no system package changes.
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
    printf ':: [dry-run] download %s/latest and extract into %s\n' "$RELEASES" "$DEST"
    printf ':: [dry-run] no spicetify commands and no Marketplace install\n'
    exit 0
fi

if [[ -x $DEST/spicetify ]]; then
    printf 'ok spicetify already installed: %s\n' "$DEST/spicetify"
    exit 0
fi

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"
command -v sed >/dev/null 2>&1 || die "sed is required"

if ((!ASSUME_YES)); then
    [[ -t 0 ]] || die "refusing to run without a terminal; pass --yes"
    printf 'Install the Spicetify CLI into %s? [y/N]: ' "$DEST"
    read -r reply || reply=""
    [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]] || die "not installed"
fi

case "$(uname -sm)" in
    "Linux x86_64")  target="linux-amd64" ;;
    "Linux aarch64"|"Linux arm64") target="linux-arm64" ;;
    "Darwin x86_64") target="darwin-amd64" ;;
    "Darwin arm64")  target="darwin-arm64" ;;
    *) die "unsupported platform: $(uname -sm)" ;;
esac

json="$(curl -fsSL "$API")" || die "cannot read the latest release"
tag="$(printf '%s\n' "$json" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
[[ -n $tag ]] || die "cannot determine the latest version"
tag="${tag#v}"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

archive="$tmp/spicetify.tar.gz"
url="$RELEASES/download/v$tag/spicetify-$tag-$target.tar.gz"
curl -fsSL "$url" -o "$archive" || die "download failed: $url"
mkdir -p "$DEST"
tar xzf "$archive" -C "$DEST" || die "extract failed"
chmod +x "$DEST/spicetify" || die "cannot make the CLI executable"

[[ -x $DEST/spicetify ]] || die "the archive did not contain the CLI"
printf 'ok spicetify installed: %s\n' "$DEST/spicetify"
printf 'note: launch Spotify once before update/apply; spotify-launcher downloads it on first start\n'
