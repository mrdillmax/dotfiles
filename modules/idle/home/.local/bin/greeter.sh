#!/usr/bin/env bash
# Optional session-start lock. hyprlock authenticates through PAM before the
# desktop is usable. This is a convenience gate, not a display manager: the
# autologin session exists in the background while the lock is up.
set -uo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
MARKER="$RUNTIME/dotfiles-greeter.lock"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/greeter-on"
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

if [[ ! -e $CONFIG ]]; then
    rm -f -- "$MARKER"
    exit 0
fi
if ! command -v hyprlock >/dev/null 2>&1; then
    rm -f -- "$MARKER"
    log "hyprlock not found; skipping greeter"
    notify "hyprlock is not installed; the session is not locked"
    exit 0
fi

log "starting greeter (hyprlock)"
# Run hyprlock with a safety timeout so the marker is always cleaned up.
# If hyprlock hangs (e.g. PAM freeze), the background watcher removes the
# marker after 60s and autostart.sh can proceed.
(
    sleep 60
    log "greeter timeout reached, removing stale marker"
    rm -f -- "$MARKER"
    notify -u critical "Greeter timed out" "The session is accessible without a password"
) &
WATCHER_PID=$!

if ! hyprlock; then
    log "hyprlock exited with error"
    notify -u critical "hyprlock failed" "The session is accessible without a password"
fi

# Stop the watcher — marker is being removed now.
kill "$WATCHER_PID" 2>/dev/null || true
wait "$WATCHER_PID" 2>/dev/null || true

rm -f -- "$MARKER"
log "greeter done, marker removed"
