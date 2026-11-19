#!/usr/bin/env bash
# Show the dunst notification history and copy the selected line.
set -uo pipefail

REAL_HOME="${HOME:?HOME is not set}"
THEME="$REAL_HOME/.config/rofi/launcher.rasi"
theme_arg=()
[[ -r $THEME ]] && theme_arg=(-theme "$THEME")

show_message() {
    if command -v rofi >/dev/null 2>&1; then
        rofi "${theme_arg[@]}" -e "$1" 2>/dev/null || printf '%s\n' "$1"
    else
        printf '%s\n' "$1"
    fi
}

if ! command -v dunstctl >/dev/null 2>&1; then
    show_message "dunstctl is not installed"
    exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
    show_message "jq is not installed"
    exit 0
fi

raw="$(dunstctl history 2>&1)"
if ! jq -e . >/dev/null 2>&1 <<<"$raw"; then
    first_line="${raw%%$'\n'*}"
    show_message "Notification history is unavailable: ${first_line:-unknown error}"
    exit 0
fi

HISTORY="$(jq -r '
  .data[0][]? |
  "[\(.appname.data // "System")] \(.summary.data // "")" +
  (if (.body.data // "") != "" then " - " + .body.data else "" end)
' <<<"$raw" | sed 's/\\n/ /g')"

if [[ -z $HISTORY ]]; then
    show_message "Notification history is empty"
    exit 0
fi

SELECTED="$(printf '%s\n' "$HISTORY" | rofi "${theme_arg[@]}" \
    -dmenu -i -p "" -no-fixed-num-lines \
    -theme-str 'entry { placeholder: "History"; }')" || exit 0
[[ -n $SELECTED ]] || exit 0

printf '%s' "$SELECTED" | wl-copy
