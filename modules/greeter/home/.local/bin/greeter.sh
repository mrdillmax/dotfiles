#!/usr/bin/env bash
# Optional session-start lock. hyprlock authenticates through PAM before the
# desktop is usable. This is a convenience gate, not a display manager: the
# autologin session exists in the background while the lock is up.
set -uo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
MARKER="$RUNTIME/dotfiles-greeter.lock"
LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/greeter.log"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Session lock" "$@" >/dev/null 2>&1 || true
    fi
}

log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

if ! command -v hyprlock >/dev/null 2>&1; then
    rm -f -- "$MARKER"
    log "hyprlock not found; skipping greeter"
    notify "hyprlock is not installed; the session is not locked"
    exit 0
fi

log "starting greeter (hyprlock)"
if ! hyprlock; then
    log "hyprlock exited with error"
    notify -u critical "hyprlock failed" "The session is accessible without a password"
fi

rm -f -- "$MARKER"
log "greeter done, marker removed"
