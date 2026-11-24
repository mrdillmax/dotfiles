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

# A daemon that was just started needs a moment before hyprctl can reach it.
mkdir -p "$work/race-bin" "$work/race-state"
printf '#!/bin/sh\n[[ -e %s/daemon ]] && exit 0\nexit 1\n' "$work" >"$work/race-bin/pgrep"
printf '#!/bin/sh\n: >%s/daemon\n' "$work" >"$work/race-bin/hyprsunset"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/race-calls"\n[[ -e %s/hypr-ready ]] || { : >%s/hypr-ready; exit 1; }\n' \
    "$work" "$work" "$work" >"$work/race-bin/hyprctl"
chmod +x "$work/race-bin"/*
STATE_DIR="$work/race-state" PATH="$work/race-bin:$PATH" "$HELPER" on
if [[ $(sed -n 's/^enabled=//p' "$STATE_DIR/nightlight.conf") == 1 ]] &&
    grep -q 'hyprsunset temperature 4000' "$work/race-calls"; then
    pass "a freshly started hyprsunset is retried until it answers"
else
    fail "startup race: $(cat "$work/race-calls" 2>/dev/null)"
fi

# An absent daemon must name the package and the command that installs it.
mkdir -p "$work/iso-bin" "$work/missing-state"
ln -s "$(command -v bash)" "$work/iso-bin/bash"
printf '#!/bin/sh\nexit 1\n' >"$work/iso-bin/pgrep"
printf '#!/bin/sh\nexit 0\n' >"$work/iso-bin/hyprctl"
chmod +x "$work/iso-bin/pgrep" "$work/iso-bin/hyprctl"
if out="$(STATE_DIR="$work/missing-state" PATH="$work/iso-bin" "$HELPER" on 2>&1)"; then
    fail "on succeeded without hyprsunset"
elif [[ $out == *'hyprsunset is not installed'* && $out == *'--modules nightlight'* ]]; then
    pass "a missing hyprsunset is reported with the install command"
else
    fail "missing daemon message: $out"
fi

# A daemon that dies on startup must report its own log, not just "failed".
mkdir -p "$work/fail-bin" "$work/fail-state"
for tool in bash mkdir setsid sleep tail tr; do
    ln -s "$(command -v "$tool")" "$work/fail-bin/$tool"
done
printf '#!/bin/sh\nexit 1\n' >"$work/fail-bin/pgrep"
printf '#!/bin/sh\nexit 0\n' >"$work/fail-bin/hyprctl"
printf '#!/bin/sh\necho "no CTM support" >&2\nexit 1\n' >"$work/fail-bin/hyprsunset"
chmod +x "$work/fail-bin/pgrep" "$work/fail-bin/hyprctl" "$work/fail-bin/hyprsunset"
if out="$(STATE_DIR="$work/fail-state" PATH="$work/fail-bin" "$HELPER" on 2>&1)"; then
    fail "on succeeded although hyprsunset exited"
elif [[ $out == *'no CTM support'* ]]; then
    pass "a daemon that dies on startup reports its log"
else
    fail "startup failure message: $out"
fi

# --- schedule --------------------------------------------------------------

if [[ $(run get schedule) == off ]]; then
    pass "the schedule starts off"
else
    fail "unexpected default schedule: $(run get schedule)"
fi

if run on-time 25:00 2>/dev/null; then
    fail "an invalid on-time was accepted"
else
    pass "an invalid on-time is rejected"
fi

run on-time 00:00
run off-time 23:59
run schedule times
if [[ $(run get schedule) == times && $(run get enabled) == 1 ]] &&
    [[ $(sed -n 's/^enabled=//p' "$STATE_DIR/nightlight.conf") == 1 ]]; then
    pass "fixed times turn the filter on inside the window"
else
    fail "fixed times did not turn on: $(cat "$STATE_DIR/nightlight.conf")"
fi

later_on="$(date -d '+60 minutes' +%H:%M)"
later_off="$(date -d '+120 minutes' +%H:%M)"
run on-time "$later_on"
run off-time "$later_off"
run tick
if [[ $(sed -n 's/^enabled=//p' "$STATE_DIR/nightlight.conf") == 0 ]] &&
    grep -q 'hyprsunset identity' "$work/calls"; then
    pass "fixed times turn the filter off outside the window"
else
    fail "outside the window stayed enabled: $(cat "$STATE_DIR/nightlight.conf")"
fi

run schedule off
if [[ $(run get schedule) == off ]]; then
    pass "the schedule can be disabled without touching the filter"
else
    fail "schedule off did not stick"
fi

run location 50.45,30.52
if [[ $(run get location) == 50.45,30.52 ]]; then
    pass "the sun schedule stores its coordinates"
else
    fail "location not stored: $(run get location)"
fi
if run location 100,30 2>/dev/null; then
    fail "an invalid latitude was accepted"
else
    pass "an invalid latitude is rejected"
fi

run schedule sun
if [[ $(run get schedule) == sun ]]; then
    pass "the sunset-to-sunrise schedule is selectable"
else
    fail "sun schedule not selected: $(run get schedule)"
fi
if run status | grep -q 'sunset to sunrise'; then
    pass "status names the sunset schedule"
else
    fail "status misses the sunset schedule"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
