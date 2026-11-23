#!/usr/bin/env bash
# The backlight helper clamps at 5% and 100%, for keys and the Waybar wheel.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/modules/hypr/home/.local/bin/brightness-adjust.sh"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/empty"

cat >"$work/bin/brightnessctl" <<'STUB'
#!/bin/sh
case "$1" in
    -m) printf 'intel_backlight,backlight,0,%s%%,1000\n' "${BRIGHT_PERCENT:-10}" ;;
    set) printf '%s\n' "$*" >>"$BRIGHT_CALLS" ;;
esac
STUB
chmod +x "$work/bin/brightnessctl"
export BRIGHT_CALLS="$work/calls"

run() {
    BRIGHT_PERCENT="$1" PATH="$work/bin:$PATH" "$HELPER" "$2"
}

run 6 down
if grep -qx 'set 5%' "$work/calls"; then
    pass "down from 6% stops at the 5% floor"
else
    fail "down from 6%: $(cat "$work/calls" 2>/dev/null)"
fi

: >"$work/calls"
run 5 down
if grep -qx 'set 5%' "$work/calls"; then
    pass "down from 5% stays at 5%"
else
    fail "down from 5%: $(cat "$work/calls" 2>/dev/null)"
fi

: >"$work/calls"
run 99 up
if grep -qx 'set 100%' "$work/calls"; then
    pass "up from 99% stops at 100%"
else
    fail "up from 99%: $(cat "$work/calls" 2>/dev/null)"
fi

: >"$work/calls"
run 100 up
if grep -qx 'set 100%' "$work/calls"; then
    pass "up from 100% stays at 100%"
else
    fail "up from 100%: $(cat "$work/calls" 2>/dev/null)"
fi

rm -f "$work/calls"
PATH="$work/empty" "$(command -v bash)" "$HELPER" down
if [[ ! -e $work/calls ]]; then
    pass "no backlight device is a safe no-op"
else
    fail "the helper wrote without brightnessctl"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
