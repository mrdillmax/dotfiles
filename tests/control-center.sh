#!/usr/bin/env bash
# Control Center behavior: pages, hardware gating and the lock entry. These
# checks call the functions instead of grepping for them.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="$ROOT/modules/control-center/home/.local/bin/dotfiles-control-center"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# shellcheck source=/dev/null
source "$CC"

pages="$(control_center_pages)"
if [[ $pages != *Apps* ]]; then
    pass "Apps page is gone"
else
    fail "Apps page is still listed"
fi
if [[ $pages != *Docker* ]]; then
    pass "main menu has no Docker entry"
else
    fail "main menu still lists Docker"
fi
if ! declare -F apps_page >/dev/null || ! declare -F docker_page >/dev/null; then
    pass "apps_page and docker_page are removed"
else
    fail "dead pages still defined"
fi
if ! grep -q 'Maintenance help' "$CC"; then
    pass "Maintenance help is gone"
else
    fail "Maintenance help still exists"
fi

stub="$(mktemp -d)"
trap 'rm -rf "$stub"' EXIT
PATH="$stub:$PATH"

printf '#!/bin/sh\necho ethernet\necho loopback\n' >"$stub/nmcli"
printf '#!/bin/sh\nexit 0\n' >"$stub/bluetoothctl"
chmod +x "$stub/nmcli" "$stub/bluetoothctl"

if wifi_hardware_present; then
    fail "Wi-Fi reported without a Wi-Fi device"
else
    pass "Wi-Fi hidden when only ethernet exists"
fi
if bluetooth_hardware_present; then
    fail "Bluetooth reported without an adapter"
else
    pass "Bluetooth hidden without an adapter"
fi

printf '#!/bin/sh\necho wifi\necho ethernet\n' >"$stub/nmcli"
printf '#!/bin/sh\necho "Controller 00:11:22:33:44:55 host"\n' >"$stub/bluetoothctl"
chmod +x "$stub/nmcli" "$stub/bluetoothctl"

if wifi_hardware_present; then
    pass "Wi-Fi shown when the device exists"
else
    fail "Wi-Fi hidden despite a Wi-Fi device"
fi
if bluetooth_hardware_present; then
    pass "Bluetooth shown when an adapter exists"
else
    fail "Bluetooth hidden despite an adapter"
fi

printf '#!/bin/sh\necho stub-hyprlock\n' >"$stub/hyprlock"
chmod +x "$stub/hyprlock"
if [[ $(lock_screen_page) == *stub-hyprlock* ]]; then
    pass "Lock screen runs hyprlock when installed"
else
    fail "Lock screen does not run hyprlock"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
