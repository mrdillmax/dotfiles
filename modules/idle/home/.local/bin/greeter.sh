#!/usr/bin/env bash
# Optional session-start lock. hyprlock authenticates through PAM before the
# desktop is usable. This is a convenience gate, not a display manager: the
# autologin session exists in the background while the lock is up.
set -uo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
MARKER="$RUNTIME/dotfiles-greeter.lock"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/greeter-on"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Session lock" "$@" >/dev/null 2>&1 || true
    fi
}

if [[ ! -e $CONFIG ]]; then
    rm -f -- "$MARKER"
    exit 0
fi
if ! command -v hyprlock >/dev/null 2>&1; then
    rm -f -- "$MARKER"
    notify "hyprlock is not installed; the session is not locked"
    exit 0
fi

if ! hyprlock; then
    notify -u critical "hyprlock failed" "The session is accessible without a password"
fi
rm -f -- "$MARKER"
