#!/usr/bin/env bash
# Backlight level driven by udev events, not a polling timer.
set -uo pipefail

BACKLIGHT="${BACKLIGHT_DIR:-$(find /sys/class/backlight -maxdepth 1 -mindepth 1 -type l -print -quit 2>/dev/null)}"

print_status() {
    local current max percent icon
    if [[ -z ${BACKLIGHT:-} || ! -r $BACKLIGHT/brightness ]]; then
        printf '{"text": ""}\n'
        return 0
    fi
    current="$(<"$BACKLIGHT/brightness")"
    max="$(<"$BACKLIGHT/max_brightness")"
    ((max > 0)) || max=1
    percent=$((current * 100 / max))
    local low=25 med=70
    if ((percent <= low)); then
        icon="\uf186"
    elif ((percent <= med)); then
        icon="\uf185"
    else
        icon="\uf185"
    fi
    printf '{"text":"%s  %d%%","alt":"brightness","tooltip":"Brightness: %d%%"}\n' \
        "$icon" "$percent" "$percent"
}

if [[ ${1:-} == --once ]]; then
    print_status
    exit 0
fi

print_status
while IFS= read -r line; do
    [[ $line == ACTION=* ]] && print_status
done < <(udevadm monitor --subsystem-match=backlight --property)
