#!/usr/bin/env bash
# doctor reads the v2 managed.tsv fields; a digest must not be an unset
# variable under `set -u` (a regression that aborted the whole check).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home" "$work/repo" "$work/state/dotfiles"

# shellcheck disable=SC2016 # the stub expands its own $FAKE_HOME
printf '#!/bin/sh\nprintf "user:x:1000:1000::%s:/bin/bash\\n" "$FAKE_HOME"\n' \
    "$work" >"$work/bin/getent"
chmod +x "$work/bin/getent"
printf 'repo content\n' >"$work/repo/file.conf"
digest="$(sha256sum "$work/repo/file.conf" | cut -d' ' -f1)"
install -m 0644 "$work/repo/file.conf" "$work/home/managed.conf"
printf 'copy\t%s\t%s\t%s\t-\n' "$work/home/managed.conf" \
    "$work/repo/file.conf" "$digest" >"$work/state/dotfiles/managed.tsv"

PATH="$work/bin:$PATH" FAKE_HOME="$work/home" XDG_STATE_HOME="$work/state" \
    bash "$ROOT/scripts/doctor.sh" --json >"$work/out" 2>"$work/err"

if ! grep -q 'unbound variable' "$work/out" "$work/err"; then
    pass "doctor reads the managed.tsv digest without an unbound variable"
else
    fail "doctor aborted: $(grep 'unbound variable' "$work/out" "$work/err" | head -n1)"
fi
if grep -q '"check":"managed files match the repository"' "$work/out"; then
    pass "a matching digest is reported as healthy"
else
    fail "the managed-file check did not run"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
