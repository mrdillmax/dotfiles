#!/usr/bin/env bash
# A host without a saved monitor preset still gets workspace slots.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/hosts/test" "$work/home" "$work/state" "$work/backup"
printf 'MON_COUNT=0\n' >"$work/repo/hosts/test/monitors.conf.sh"

export DOTFILES_DIR="$work/repo"
export REAL_HOME="$work/home"
export STATE_FILE="$work/state/managed.tsv"
export BACKUP_DIR="$work/backup"
export HOST_NAME=test
export DRY_RUN=0
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/monitors.sh"

detect_monitors() {
    printf 'HDMI-A-1\t1920x1080@60\t0x0\t1\t1920\n'
    printf 'DP-1\t2560x1440@144\t1920x0\t1\t2560\n'
}

render_monitors >/dev/null 2>&1
live_conf="$REAL_HOME/.config/hypr/monitors.conf.sh"
if grep -qx 'MON_COUNT=2' "$live_conf"; then
    pass "an empty preset generates one entry per detected monitor"
else
    fail "generated monitor count: $(grep -n 'MON_COUNT' "$live_conf" 2>/dev/null)"
fi
if grep -q 'MON_WS_COUNT=(10 10)' "$live_conf" &&
    grep -q 'MON_WS_FIRST=(1 11)' "$live_conf"; then
    pass "each monitor gets ten workspace slots"
else
    fail "workspace arrays: $(grep -E 'MON_WS_' "$live_conf" 2>/dev/null)"
fi
if grep -q 'M\[#M + 1\] = { name = "HDMI-A-1"' "$REAL_HOME/.config/hypr/monitors.lua"; then
    pass "the generated Lua config carries the monitors"
else
    fail "monitors.lua was not generated"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
