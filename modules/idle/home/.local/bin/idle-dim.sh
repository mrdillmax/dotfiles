#!/usr/bin/env bash
# Dim the panel for hypridle instead of turning it off. brightnessctl keeps
# the previous level, so restore returns exactly to the user's setting.
set -uo pipefail

PERCENT="${IDLE_DIM_PERCENT:-15}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
MARKER="$STATE_DIR/idle-dim"

have() { command -v "$1" >/dev/null 2>&1; }

case "${1:-}" in
    dim)
        have brightnessctl || exit 0
        mkdir -p -- "$STATE_DIR" 2>/dev/null || exit 0
        current="$(brightnessctl -m 2>/dev/null | head -n1 |
            awk -F, '{gsub(/%/, "", $4); print $4}')"
        [[ $current =~ ^[0-9]+$ ]] || exit 0
        if [[ ! -e $MARKER ]]; then
            # Never brighten the panel to reach the dim level.
            ((current > PERCENT)) || exit 0
            brightnessctl -s set "${PERCENT}%" >/dev/null 2>&1 || exit 0
            : >"$MARKER"
        else
            brightnessctl set "${PERCENT}%" >/dev/null 2>&1 || true
        fi
        ;;
    restore)
        [[ -e $MARKER ]] || exit 0
        if have brightnessctl; then
            brightnessctl -r >/dev/null 2>&1 || true
        fi
        rm -f -- "$MARKER"
        ;;
    *)
        printf 'usage: %s dim|restore\n' "$(basename "$0")" >&2
        exit 2
        ;;
esac
