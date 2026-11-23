#!/usr/bin/env bash
# Waybar monitoring scripts: failed units, updates, battery and network JSON.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/modules/waybar/home/.local/bin"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/bat"

printf '#!/bin/sh\ncase "$*" in\n  *--user*--failed*) echo "user1.service loaded failed failed" ;;\n  *--failed*) echo "sys1.service loaded failed failed"; echo "sys2.service loaded failed failed" ;;\nesac\n' >"$work/bin/systemctl"
# shellcheck disable=SC2016 # the stub expands its own $1
printf '#!/bin/sh\ncase "$1" in\n  --json) echo "{\\"status\\":\\"behind\\",\\"behind\\":2,\\"ahead\\":0,\\"local\\":\\"x\\",\\"remote\\":\\"y\\",\\"cached\\":false}" ;;\n  --refresh) echo "up to date" ;;\nesac\n' >"$work/bin/update-check"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/notify"\n' "$work" >"$work/bin/notify-send"
printf '#!/bin/sh\necho "pkill $*" >>"%s/pkill.log"\n' "$work" >"$work/bin/pkill"
printf '#!/bin/sh\necho "wifi:connected:HomeNet:wl0"\n' >"$work/bin/nmcli"
printf '#!/bin/sh\necho "2: wl0    inet 10.0.0.5/24 brd 10.0.0.255 scope global wl0"\n' >"$work/bin/ip"
chmod +x "$work/bin"/*
PATH="$work/bin:$PATH"

printf '42\n' >"$work/bat/capacity"
printf 'Discharging\n' >"$work/bat/status"

out="$(SYSTEMCTL_BIN="$work/bin/systemctl" "$BIN/waybar-units.sh")"
if [[ $out == *' 3"'* ]] && [[ $out == *sys1.service* ]]; then
    pass "failed units are counted and listed"
else
    fail "units output: $out"
fi

out="$(DOTFILES_UPDATE_CHECK="$work/bin/update-check" "$BIN/waybar-update.sh")"
if [[ $out == *'"alt":"behind"'* && $out == *' 2"'* && $out == *'"class":"behind"'* ]]; then
    pass "a repo that is behind is reported"
else
    fail "update output: $out"
fi

DOTFILES_UPDATE_CHECK="$work/bin/update-check" "$BIN/waybar-update.sh" --click >/dev/null 2>&1
if grep -q 'dotfiles: up to date' "$work/notify"; then
    pass "clicking the update module checks and notifies"
else
    fail "click did not notify: $(cat "$work/notify" 2>/dev/null)"
fi

out="$(BAT_DIR="$work/bat" "$BIN/waybar-battery.sh" --once)"
if [[ $out == *'42%'* && $out == *Discharging* ]]; then
    pass "battery reports capacity and state"
else
    fail "battery output: $out"
fi
mkdir -p "$work/empty"
out="$(BAT_DIR="$work/empty" "$BIN/waybar-battery.sh" --once)"
if [[ $out == '{"text": ""}' ]]; then
    pass "no battery produces an empty module"
else
    fail "empty battery output: $out"
fi

out="$(NMCLI_BIN="$work/bin/nmcli" IP_BIN="$work/bin/ip" "$BIN/waybar-network.sh" --once)"
if [[ $out == *HomeNet* && $out == *10.0.0.5* ]]; then
    pass "network reports the connection and address"
else
    fail "network output: $out"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
