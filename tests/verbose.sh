#!/usr/bin/env bash
# Verbose mode prints each mutating command; dry-run still wins.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export DOTFILES_DIR="$ROOT"
REAL_HOME="$work/home"
STATE_FILE="$work/state/managed.tsv"
BACKUP_DIR="$work/backup"
mkdir -p "$REAL_HOME" "$(dirname "$STATE_FILE")" "$BACKUP_DIR"
printf 'target\tbackup\n' >"$BACKUP_DIR/manifest.tsv"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"

export VERBOSE=1 DRY_RUN=0
out="$(run printf '%s\n' hello)"
if [[ $out == *"[cmd]"* && $out == *hello* ]]; then
    pass "run prints the command and executes it"
else
    fail "verbose run output: $out"
fi

out="$(DRY_RUN=1 VERBOSE=1 run touch "$work/marker")"
if [[ $out == *"[dry-run]"* && ! -e $work/marker ]]; then
    pass "dry-run still suppresses execution"
else
    fail "dry-run run output: $out"
fi

export VERBOSE=1
out="$(link_path "$ROOT/lib/common.sh" "$REAL_HOME/.config/demo")"
if [[ $out == *"ln -sfn"* ]]; then
    pass "link_path prints the ln command"
else
    fail "link_path verbose output: $out"
fi

out="$(copy_file "$ROOT/lib/common.sh" "$REAL_HOME/.config/demo.copy" 0644)"
if [[ $out == *"install -m 0644"* ]]; then
    pass "copy_file prints the install command"
else
    fail "copy_file verbose output: $out"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
