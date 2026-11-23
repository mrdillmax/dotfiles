#!/usr/bin/env bash
# Battery warnings and power-profile switching for laptops.
#
# Listens to power_supply udev events instead of polling.
set -uo pipefail

CONFIG="${BATTERY_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/battery.conf}"
LOW=20
CRITICAL=10
POWER_SAVE=1
# shellcheck source=/dev/null
[[ -r $CONFIG ]] && source "$CONFIG"

BAT_DIR="${BAT_DIR:-$(find /sys/class/power_supply -maxdepth 1 -name 'BAT*' -print -quit 2>/dev/null)}"
_battery_alert_level=""

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Battery" "$@" >/dev/null 2>&1 || true
    else
        printf '%s\n' "$*"
    fi
}

set_profile() {
    command -v powerprofilesctl >/dev/null 2>&1 || return 0
    powerprofilesctl set "$1" >/dev/null 2>&1 || true
}

check_once() {
    local capacity status

    [[ -n ${BAT_DIR:-} && -d ${BAT_DIR} && -r $BAT_DIR/capacity ]] || return 0
    capacity="$(<"$BAT_DIR/capacity")"
    status="$(cat "$BAT_DIR/status" 2>/dev/null || printf 'Unknown')"

    if [[ $status != Discharging ]]; then
        if [[ -n $_battery_alert_level ]]; then
            _battery_alert_level=""
            ((POWER_SAVE)) && set_profile balanced
        fi
        return 0
    fi

    if ((capacity <= CRITICAL)) && [[ $_battery_alert_level != critical ]]; then
        _battery_alert_level=critical
        notify -u critical "Battery critical" "${capacity}% left"
        ((POWER_SAVE)) && set_profile power-saver
    elif ((capacity <= LOW)) && [[ -z $_battery_alert_level ]]; then
        _battery_alert_level=low
        notify "Battery low" "${capacity}% left"
        ((POWER_SAVE)) && set_profile power-saver
    fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case "${1:-daemon}" in
        check) check_once ;;
        status)
            [[ -n ${BAT_DIR:-} && -r $BAT_DIR/capacity ]] || exit 1
            printf 'battery: %s%% (%s)\n' "$(<"$BAT_DIR/capacity")" \
                "$(cat "$BAT_DIR/status" 2>/dev/null || printf 'Unknown')"
            ;;
        daemon|*)
            check_once
            while IFS= read -r line; do
                [[ $line == ACTION=* ]] && check_once
            done < <(udevadm monitor --subsystem-match=power_supply --property)
            ;;
    esac
fi
