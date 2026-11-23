#!/usr/bin/env bash
# Battery warnings fire once per level and toggle the power profile.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/battery/home/.local/bin/battery-alert.sh"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/bat" "$work/config/dotfiles"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/notify"\n' "$work" >"$work/bin/notify-send"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/power"\n' "$work" >"$work/bin/powerprofilesctl"
chmod +x "$work/bin"/*
PATH="$work/bin:$PATH"
XDG_CONFIG_HOME="$work/config"
BAT_DIR="$work/bat"
export PATH XDG_CONFIG_HOME BAT_DIR

# shellcheck source=/dev/null
source "$SCRIPT"

printf '18\n' >"$BAT_DIR/capacity"
printf 'Discharging\n' >"$BAT_DIR/status"
check_once
if grep -q 'Battery low' "$work/notify" && grep -q 'set power-saver' "$work/power"; then
    pass "a low battery warns and enables the power saver"
else
    fail "low battery: $(cat "$work/notify" 2>/dev/null) / $(cat "$work/power" 2>/dev/null)"
fi

check_once
if [[ $(wc -l <"$work/notify") == 1 ]]; then
    pass "the low warning is not repeated"
else
    fail "warning repeated: $(cat "$work/notify")"
fi

printf '8\n' >"$BAT_DIR/capacity"
check_once
if grep -q 'Battery critical' "$work/notify" && [[ $(wc -l <"$work/notify") == 2 ]]; then
    pass "a critical battery warns once"
else
    fail "critical battery: $(cat "$work/notify")"
fi

printf 'Charging\n' >"$BAT_DIR/status"
check_once
if grep -q 'set balanced' "$work/power"; then
    pass "charging restores the balanced profile"
else
    fail "balanced profile was not restored: $(cat "$work/power")"
fi

rm -rf "$BAT_DIR"
check_once
if [[ $(wc -l <"$work/notify") == 2 ]]; then
    pass "a machine without a battery is ignored"
else
    fail "notified without a battery"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
