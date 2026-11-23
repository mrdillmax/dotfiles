#!/usr/bin/env bash
# Wallpaper state and picker cache keys. The current marker must follow the
# same state the theme menu writes, otherwise it points at an old wallpaper.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

export DOTFILES_DIR="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/wallpaper.sh"

tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT
mkdir -p "$tmp_home/.local/state/dotfiles" "$tmp_home/.config/hypr"

export XDG_STATE_HOME="$tmp_home/.local/state"
printf 'wallpaper=/a/one.jpg\nmode=dark\n' >"$tmp_home/.local/state/dotfiles/theme.conf"
printf '/b/two.jpg\n' >"$tmp_home/.config/hypr/wallpaper.path"
export REAL_HOME="$tmp_home"

if [[ $(wallpaper_current_image) == /a/one.jpg ]]; then
    pass "theme state wins over wallpaper.path"
else
    fail "wrong current wallpaper: $(wallpaper_current_image)"
fi

rm -f "$tmp_home/.local/state/dotfiles/theme.conf"
export REAL_HOME="$tmp_home"
if [[ $(wallpaper_current_image) == /b/two.jpg ]]; then
    pass "falls back to wallpaper.path"
else
    fail "fallback is wrong: $(wallpaper_current_image)"
fi

printf 'mode=dark\n' >"$tmp_home/.local/state/dotfiles/theme.conf"
rm -f "$tmp_home/.config/hypr/wallpaper.path"
export REAL_HOME="$tmp_home"
if wallpaper_current_image >/dev/null; then
    fail "invented a wallpaper when no state exists"
else
    pass "fails when no wallpaper is recorded"
fi

key_plain="$(wallpaper_card_key photo.jpg /a/one.jpg)"
key_current="$(wallpaper_card_key 'photo.jpg (current)' /a/one.jpg)"
if [[ $key_plain != "$key_current" ]]; then
    pass "current marker changes the card cache key"
else
    fail "stale card cache: marker is ignored"
fi

if [[ $(wallpaper_card_key photo.jpg /a/one.jpg) == "$(wallpaper_card_key photo.jpg /a/one.jpg)" ]]; then
    pass "card key is stable for the same input"
else
    fail "card key is not deterministic"
fi

# The example wallpaper is installed on a first run and a dangling record is
# replaced instead of being trusted blindly.
home="$(mktemp -d)"
rm -rf "$home"; mkdir -p "$home/state" "$home/backup"
saved_home="$REAL_HOME"
REAL_HOME="$home"
DOTFILES_DIR="$ROOT"
STATE_FILE="$home/state/managed.tsv"
BACKUP_DIR="$home/backup"
DRY_RUN=0
export DOTFILES_DIR STATE_FILE BACKUP_DIR DRY_RUN
install_default_wallpaper >/dev/null 2>&1
dest="$home/.local/share/wallpapers/dotfiles/example.jpg"
state="$home/.config/hypr/wallpaper.path"
if [[ -f $dest && $(<"$state") == "$dest" ]]; then
    pass "the example wallpaper is installed on a first run"
else
    fail "example wallpaper: ${dest} / $(cat "$state" 2>/dev/null)"
fi

printf '%s\n' "$home/does-not-exist.jpg" >"$state"
rm -f "$dest"
install_default_wallpaper >/dev/null 2>&1
if [[ -f $dest && $(<"$state") == "$dest" ]]; then
    pass "a dangling wallpaper record is replaced with the example"
else
    fail "dangling record was trusted: $(cat "$state" 2>/dev/null)"
fi

printf '%s\n' "$dest" >"$state"
before="$(sha256sum "$dest" | cut -d' ' -f1)"
install_default_wallpaper >/dev/null 2>&1
if [[ $(sha256sum "$dest" | cut -d' ' -f1) == "$before" ]]; then
    pass "an existing wallpaper is left alone"
else
    fail "an existing wallpaper was rewritten"
fi
rm -rf "$home"
REAL_HOME="$saved_home"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
