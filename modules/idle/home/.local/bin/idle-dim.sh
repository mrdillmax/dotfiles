#!/usr/bin/env bash
# Dim the panel for hypridle instead of turning it off.
#
# The backend (internal backlight or external monitors over DDC/CI) lives in
# panel-brightness.sh; this only tracks whether a restore is pending so the
# exact previous level comes back.
set -uo pipefail

PERCENT="${IDLE_DIM_PERCENT:-15}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
MARKER="$STATE_DIR/idle-dim"

SELF_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
find_panel() {
    local candidate
    for candidate in \
        "$SELF_DIR/panel-brightness.sh" \
        "$SELF_DIR/../../../../hypr/home/.local/bin/panel-brightness.sh"; do
        [[ -x $candidate ]] && { printf '%s' "$candidate"; return 0; }
    done
    candidate="$(command -v panel-brightness.sh 2>/dev/null)" && [[ -n $candidate ]] &&
        { printf '%s' "$candidate"; return 0; }
    return 1
}
PANEL="$(find_panel)"

case "${1:-}" in
    dim)
        [[ -n $PANEL ]] || exit 0
        current="$("$PANEL" get 2>/dev/null)" || exit 0
        [[ $current =~ ^[0-9]+$ ]] || exit 0
        mkdir -p -- "$STATE_DIR" 2>/dev/null || exit 0
        if [[ ! -e $MARKER ]]; then
            # Never brighten the panel to reach the dim level.
            ((current > PERCENT)) || exit 0
            "$PANEL" dim "$PERCENT" >/dev/null 2>&1 || exit 0
            : >"$MARKER"
        else
            "$PANEL" set "$PERCENT" >/dev/null 2>&1 || true
        fi
        ;;
    restore)
        [[ -e $MARKER ]] || exit 0
        if [[ -n $PANEL && -x $PANEL ]]; then
            "$PANEL" restore >/dev/null 2>&1 || true
        fi
        rm -f -- "$MARKER"
        ;;
    *)
        printf 'usage: %s dim|restore\n' "$(basename "$0")" >&2
        exit 2
        ;;
esac
