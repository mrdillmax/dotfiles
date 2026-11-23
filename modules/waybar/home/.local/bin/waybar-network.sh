#!/usr/bin/env bash
# Network status driven by `nmcli monitor`, not a timer.
set -uo pipefail

NMCLI="${NMCLI_BIN:-nmcli}"
IP="${IP_BIN:-ip}"

print_status() {
    local type state _connection device icon label ip
    icon=""
    label=""
    device=""
    state=""
    while IFS=: read -r type state _connection device; do
        [[ $state == connected ]] || continue
        case "$type" in
            wifi)
                icon="\uf1eb"
                label="Wi-Fi"
                state="wifi"
                break
                ;;
            ethernet)
                icon="\uf6ff"
                label="Ethernet"
                state="ethernet"
                break
                ;;
        esac
    done < <("$NMCLI" -t -f TYPE,STATE,CONNECTION,DEVICE device status 2>/dev/null)

    if [[ -z $label ]]; then
        printf '{"text": "", "alt": "offline", "tooltip": "Network: offline"}\n'
        return 0
    fi
    if [[ -n $device ]]; then
        ip="$("$IP" -4 -o addr show dev "$device" 2>/dev/null | awk '{print $4; exit}')"
    fi
    # The SSID stays out of the bar: the icon is enough, the tooltip names
    # only the link type and address.
    printf '{"text":"%s","alt":"%s","tooltip":"%s%s"}\n' \
        "$icon" "$state" "$label" "${ip:+ ($ip)}"
}

if [[ ${1:-} == --once ]]; then
    print_status
    exit 0
fi

print_status
while IFS= read -r _; do
    print_status
done < <("$NMCLI" monitor 2>/dev/null)
