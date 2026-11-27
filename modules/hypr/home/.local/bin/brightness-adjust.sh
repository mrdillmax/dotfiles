#!/usr/bin/env bash
# Adjust the panel brightness by a fixed step, clamped to a usable range. The
# panel must never reach 0%: the keys and the Waybar wheel stop at 5%.
#
# panel-brightness.sh picks the backend: brightnessctl on laptops, DDC/CI on
# desktops with external monitors.
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

PANEL_FALLBACK="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/panel-brightness.sh"
PANEL=""
[[ -x $PANEL_FALLBACK ]] && PANEL="$PANEL_FALLBACK"
[[ -n $PANEL ]] || PANEL="$(command -v panel-brightness.sh 2>/dev/null || true)"
[[ -n $PANEL ]] || exit 0

current="$("$PANEL" get 2>/dev/null)"
[[ $current =~ ^[0-9]+$ ]] || exit 0

if [[ $ACTION == up ]]; then
    next=$((current + STEP))
else
    next=$((current - STEP))
fi
((next > 100)) && next=100
((next < 5)) && next=5

"$PANEL" set "$next" >/dev/null 2>&1 || exit 1

if ((OSD)) && command -v swayosd-client >/dev/null 2>&1; then
    swayosd-client --custom-message "Brightness ${next}%" \
        --custom-icon display-brightness-symbolic --progress "$next" \
        >/dev/null 2>&1 || true
fi
