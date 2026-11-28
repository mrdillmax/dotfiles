#!/usr/bin/env bash
# One brightness backend for the whole desktop.
#
# Laptops dim the internal panel through brightnessctl; desktops have no
# backlight device and dim the external monitors over DDC/CI instead. The keys,
# the Waybar wheel and hypridle all go through this script so the two paths
# behave the same.
#
# Usage:
#   panel-brightness.sh get
#   panel-brightness.sh set <percent>
#   panel-brightness.sh dim <percent>   (save the previous level, then lower)
#   panel-brightness.sh restore
set -uo pipefail

MIN_PERCENT=5
MAX_PERCENT=100
VCP_BRIGHTNESS=10

have() { command -v "$1" >/dev/null 2>&1; }
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
internal_marker="$state_dir/panel-brightness-internal"

internal_available() {
    have brightnessctl || return 1
    brightnessctl -m 2>/dev/null | head -n1 | grep -q .
}

internal_get() {
    brightnessctl -m 2>/dev/null | head -n1 |
        awk -F, '{ gsub(/%/, "", $4); print $4 }'
}

ddc_available() {
    have ddc-display.sh && ddc-display.sh available >/dev/null 2>&1
}

clamp() {
    local value="$1"
    ((value > MAX_PERCENT)) && value=$MAX_PERCENT
    ((value < MIN_PERCENT)) && value=$MIN_PERCENT
    printf '%s' "$value"
}

get_percent() {
    if internal_available; then
        internal_get
    elif ddc_available; then
        ddc-display.sh get "$VCP_BRIGHTNESS"
    else
        return 1
    fi
}

set_percent() {
    local percent
    percent="$(clamp "$1")"
    if internal_available; then
        brightnessctl set "${percent}%" >/dev/null 2>&1
    elif ddc_available; then
        ddc-display.sh set "$VCP_BRIGHTNESS" "$percent" >/dev/null 2>&1
    else
        return 1
    fi
}

# Save the exact level and lower the panel. brightnessctl -s does both in one
# call; DDC/CI has to read every monitor first.
dim_percent() {
    local percent current
    percent="$(clamp "$1")"
    if internal_available; then
        # Keep the exact level ourselves: brightnessctl's saved slot can be
        # overwritten, which leaves the panel dimmed after a resume.
        current="$(internal_get)"
        [[ -n $current ]] || return 1
        mkdir -p -- "$state_dir" 2>/dev/null || true
        printf '%s\n' "$current" >"$internal_marker" 2>/dev/null || return 1
        brightnessctl -s set "${percent}%" >/dev/null 2>&1
    elif ddc_available; then
        mkdir -p -- "$state_dir" 2>/dev/null || true
        ddc-display.sh save "$VCP_BRIGHTNESS" >/dev/null 2>&1 || return 1
        ddc-display.sh set "$VCP_BRIGHTNESS" "$percent" >/dev/null 2>&1
    else
        return 1
    fi
}

restore() {
    local saved
    if [[ -r $internal_marker ]]; then
        saved="$(<"$internal_marker")"
        rm -f -- "$internal_marker"
        if [[ $saved =~ ^[0-9]+$ ]] && internal_available; then
            # -r covers the normal case; the explicit set repairs the level
            # when another process overwrote brightnessctl's saved slot.
            brightnessctl -r >/dev/null 2>&1 || true
            brightnessctl set "${saved}%" >/dev/null 2>&1
            return 0
        fi
    fi
    if ddc_available; then
        ddc-display.sh restore "$VCP_BRIGHTNESS" >/dev/null 2>&1
    fi
}

case "${1:-}" in
    get) get_percent ;;
    set) set_percent "${2:?missing percent}" ;;
    dim) dim_percent "${2:?missing percent}" ;;
    restore) restore ;;
    *)
        printf 'usage: %s get|set <percent>|dim <percent>|restore\n' \
            "$(basename "$0")" >&2
        exit 2
        ;;
esac
