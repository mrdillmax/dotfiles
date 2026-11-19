#!/usr/bin/env bash
# Clipboard history picker. Selecting an entry copies it back to the clipboard.
set -uo pipefail

REAL_HOME="${HOME:?HOME is not set}"
THEME="$REAL_HOME/.config/rofi/launcher.rasi"

if ! command -v cliphist >/dev/null 2>&1; then
    rofi -theme "$THEME" -e "cliphist is not installed"
    exit 0
fi
if ! command -v wl-copy >/dev/null 2>&1; then
    rofi -theme "$THEME" -e "wl-copy is not installed"
    exit 0
fi

entry="$(cliphist list | rofi -theme "$THEME" -dmenu -i -p "" \
    -no-fixed-num-lines -theme-str 'entry { placeholder: "Clipboard"; }')" || exit 0
[[ -n $entry ]] || exit 0

printf '%s' "$entry" | cliphist decode | wl-copy
