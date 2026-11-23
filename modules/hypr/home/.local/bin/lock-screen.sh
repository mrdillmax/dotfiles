#!/usr/bin/env bash
# Lock the current session. hyprlock is the preferred helper; the fallbacks
# keep the bind useful on a machine without the idle module.
set -uo pipefail

if command -v hyprlock >/dev/null 2>&1; then
    exec hyprlock
fi
if command -v swaylock >/dev/null 2>&1; then
    exec swaylock
fi
if command -v loginctl >/dev/null 2>&1; then
    exec loginctl lock-session
fi
if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Lock screen" "No lock screen helper is installed" >/dev/null 2>&1 || true
fi
printf 'lock-screen: install hyprlock (idle module) or swaylock\n' >&2
exit 1
