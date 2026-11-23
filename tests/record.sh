#!/usr/bin/env bash
# Recorder: region, pid file, SIGINT stop, no pid when slurp is cancelled.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/modules/recorder/home/.local/bin/record.sh"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/run" "$work/videos"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/ffargs"\nsleep 30\n' "$work" >"$work/bin/wf-recorder"
printf '#!/bin/sh\nprintf "10,10 100x100\\n"\n' >"$work/bin/slurp"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/notes"\n' "$work" >"$work/bin/notify-send"
chmod +x "$work/bin"/*
PATH="$work/bin:$PATH"
XDG_RUNTIME_DIR="$work/run"
XDG_VIDEOS_DIR="$work/videos"
export PATH XDG_RUNTIME_DIR XDG_VIDEOS_DIR
pidfile="$work/run/dotfiles-record.pid"

start_out="$("$HELPER" start)"
if [[ -s $pidfile ]] && grep -q '10,10 100x100' "$work/ffargs" &&
    grep -q "$work/videos/Recordings/rec-" "$work/ffargs"; then
    pass "start records the selected region to the recordings directory"
else
    fail "start: ${start_out} / $(cat "$work/ffargs" 2>/dev/null)"
fi

if "$HELPER" start >/dev/null 2>&1; then
    fail "a second start was accepted"
else
    pass "start refuses to run twice"
fi

"$HELPER" stop >/dev/null 2>&1
if [[ ! -e $pidfile ]]; then
    pass "stop clears the pid file"
else
    fail "pid file survived stop"
fi

printf '#!/bin/sh\nexit 1\n' >"$work/bin/slurp"
chmod +x "$work/bin/slurp"
if "$HELPER" start >/dev/null 2>&1; then
    fail "start survived a cancelled slurp"
else
    pass "a cancelled slurp leaves no recording"
fi
if [[ ! -e $pidfile ]]; then
    pass "a cancelled slurp leaves no pid file"
else
    fail "pid file exists after a cancelled slurp"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
