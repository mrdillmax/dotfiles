#!/usr/bin/env bash
HISTORY=$(dunstctl history | jq -r '
  .data[0][]? | 
  "[\(.appname.data // "System")] \(.summary.data // "")" + (if (.body.data // "") != "" then " — " + .body.data else "" end)
' | sed 's/\\n/ /g')

if [ -z "$HISTORY" ] || [ "$HISTORY" = "" ]; then
    rofi -e "History clear"
else
    SELECTED=$(echo "$HISTORY" | rofi -theme "$HOME/.config/rofi/launcher.rasi" -dmenu -i -p "History")
    if [ -n "$SELECTED" ]; then
        echo "$SELECTED" | wl-copy
    fi
fi