#!/usr/bin/env bash
# Failed systemd units for Waybar. Cheap enough to poll; no event exists.
set -uo pipefail

SYSTEMCTL="${SYSTEMCTL_BIN:-systemctl}"

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

# JSON-escape tooltip inline to avoid a subprocess.
tooltip="${tooltip//\\/\\\\}"
tooltip="${tooltip//\"/\\\"}"
tooltip="${tooltip//$'\n'/\\n}"

printf '{"text":"\uf071 %d","alt":"failed","tooltip":"%s","class":"failed"}\n' \
    "$count" "$tooltip"
