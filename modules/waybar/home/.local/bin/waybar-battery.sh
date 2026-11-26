#!/usr/bin/env bash
# Battery status driven by power_supply udev events, not a timer.
set -uo pipefail

BAT_DIR="${BAT_DIR:-$(find /sys/class/power_supply -maxdepth 1 -name 'BAT*' -print -quit 2>/dev/null)}"

print_status() {
    local capacity status icon class
    if [[ -z ${BAT_DIR:-} || ! -r $BAT_DIR/capacity ]]; then
        printf '{"text": ""}\n'
        return 0
    fi
    capacity="$(<"$BAT_DIR/capacity")"
    status="$(cat "$BAT_DIR/status" 2>/dev/null || printf 'Unknown')"
    # Battery level thresholds for icon selection.
    local crit=10 warn=30 low=60 high=90
    class=""
    if ((capacity <= crit)); then
        icon="\uf244"
        class="critical"
    elif ((capacity <= warn)); then
        icon="\uf243"
        class="warning"
    elif ((capacity <= low)); then
        icon="\uf242"
    elif ((capacity <= high)); then
        icon="\uf241"
    else
        icon="\uf240"
    fi
    printf '{"text":"%s  %s%%","alt":"%s","tooltip":"Battery: %s%% (%s)","class":"%s"}\n' \
        "$icon" "$capacity" "$status" "$capacity" "$status" "$class"
}

if [[ ${1:-} == --once ]]; then
    print_status
    exit 0
fi

print_status
while IFS= read -r line; do
    [[ $line == ACTION=* ]] && print_status
done < <(udevadm monitor --subsystem-match=power_supply --property)
