#!/usr/bin/env bash
# Failed systemd units for Waybar. Cheap enough to poll; no event exists.
set -uo pipefail

SYSTEMCTL="${SYSTEMCTL_BIN:-systemctl}"

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

mapfile -t system_units < <("$SYSTEMCTL" --failed --no-legend --plain 2>/dev/null | awk 'NF {print $1}')
mapfile -t user_units < <("$SYSTEMCTL" --user --failed --no-legend --plain 2>/dev/null | awk 'NF {print $1}')
units=("${system_units[@]}" "${user_units[@]}")
count=${#units[@]}

if ((count == 0)); then
    printf '{"text": ""}\n'
    exit 0
fi

tooltip="Failed units:"
for unit in "${units[@]}"; do
    tooltip+=$'\n'"  $unit"
done

printf '{"text":"\uf071 %d","alt":"failed","tooltip":"%s","class":"failed"}\n' \
    "$count" "$(json_escape "$tooltip")"
