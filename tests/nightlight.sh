#!/usr/bin/env bash
# Night light keeps its own state because hyprsunset has no query.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/modules/nightlight/home/.local/bin/nightlight.sh"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/calls"\n' "$work" >"$work/bin/hyprctl"
printf '#!/bin/sh\nexit 0\n' >"$work/bin/pgrep"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/notes"\n' "$work" >"$work/bin/notify-send"
chmod +x "$work/bin"/*
PATH="$work/bin:$PATH"
STATE_DIR="$work/state"
export PATH STATE_DIR

run() { "$HELPER" "$@"; }

run on
if [[ $(sed -n 's/^enabled=//p' "$STATE_DIR/nightlight.conf") == 1 ]] &&
    grep -q 'hyprsunset temperature 4000' "$work/calls"; then
    pass "on enables 4000 K"
else
    fail "on state/calls: $(cat "$STATE_DIR/nightlight.conf" 2>/dev/null) / $(cat "$work/calls")"
fi

run temp 5000
if grep -q 'hyprsunset temperature 5000' "$work/calls"; then
    pass "temp applies a new value"
else
    fail "temp did not apply: $(cat "$work/calls")"
fi

if run temp 50; then
    fail "an out-of-range temperature was accepted"
else
    pass "an out-of-range temperature is rejected"
fi

run off
if [[ $(sed -n 's/^enabled=//p' "$STATE_DIR/nightlight.conf") == 0 ]] &&
    grep -q 'hyprsunset identity' "$work/calls"; then
    pass "off resets the filter"
else
    fail "off failed"
fi

run toggle
if [[ $(sed -n 's/^enabled=//p' "$STATE_DIR/nightlight.conf") == 1 ]]; then
    pass "toggle turns it back on"
else
    fail "toggle left it off"
fi

: >"$work/calls"
run restore
if grep -q 'hyprsunset temperature 5000' "$work/calls"; then
    pass "restore re-applies the stored temperature"
else
    fail "restore calls: $(cat "$work/calls")"
fi

out="$(run status)"
if [[ $out == *enabled* ]]; then
    pass "status reports the state"
else
    fail "status output: $out"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
