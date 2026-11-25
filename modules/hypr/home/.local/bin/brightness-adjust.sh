#!/usr/bin/env bash
# Adjust the backlight by a fixed step, clamped to a usable range. The panel
# must never reach 0%: the keys and the Waybar wheel stop at 5%.
set -uo pipefail

ACTION="${1:-}"
shift || true
STEP=5
OSD=0
for arg in "$@"; do
    case "$arg" in
        --osd) OSD=1 ;;
        --step=*) STEP="${arg#--step=}" ;;
    esac
done

case "$ACTION" in
    up|down) ;;
    *) printf 'usage: %s up|down [--step=N] [--osd]\n' "$(basename "$0")" >&2; exit 2 ;;
esac
[[ $STEP =~ ^[0-9]+$ ]] && ((STEP > 0)) || STEP=5

command -v brightnessctl >/dev/null 2>&1 || exit 0

current="$(brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/, "", $4); print $4}')"
[[ $current =~ ^[0-9]+$ ]] || exit 0

if [[ $ACTION == up ]]; then
    next=$((current + STEP))
else
    next=$((current - STEP))
fi
((next > 100)) && next=100
((next < 5)) && next=5

brightnessctl set "${next}%" >/dev/null 2>&1 || exit 1

if ((OSD)) && command -v swayosd-client >/dev/null 2>&1; then
    swayosd-client --custom-message "Brightness ${next}%" \
        --custom-icon display-brightness-symbolic --progress "$next" \
        >/dev/null 2>&1 || true
fi
