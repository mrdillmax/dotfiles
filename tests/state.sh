#!/usr/bin/env bash
# managed.tsv v2: digest, original pointer and carry-forward.
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
STATE_DIR="$work/state"
STATE_FILE="$STATE_DIR/managed.tsv"
BACKUP_DIR="$work/backup"
mkdir -p "$REAL_HOME/.config" "$STATE_DIR" "$BACKUP_DIR" "$work/repo"
printf 'target\tbackup\n' >"$BACKUP_DIR/manifest.tsv"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"

src="$work/repo/file.conf"

printf 'user version\n' >"$REAL_HOME/.config/demo.conf"
printf 'repo version\n' >"$src"
link_path "$src" "$REAL_HOME/.config/demo.conf"
row="$(tail -n1 "$STATE_FILE")"
IFS=$'\t' read -r kind path source digest original <<<"$row"
if [[ $kind == link && $path == "$REAL_HOME/.config/demo.conf" && $source == "$src" && $digest == - && -f $original ]]; then
    pass "link rows record the original backup"
else
    fail "link row: $row"
fi
if [[ $(cat "$original") == "user version" ]]; then
    pass "the original backup holds the user file"
else
    fail "original content: $(cat "$original" 2>/dev/null)"
fi

printf 'copy v1\n' >"$src"
printf 'user copy\n' >"$REAL_HOME/.config/copied.conf"
copy_file "$src" "$REAL_HOME/.config/copied.conf" 0644
row="$(tail -n1 "$STATE_FILE")"
IFS=$'\t' read -r kind path source digest original <<<"$row"
if [[ $kind == copy && $digest == "$(sha256sum "$src" | cut -d' ' -f1)" && -f $original ]]; then
    pass "copy rows record the content digest and the original"
else
    fail "copy digest row: $row"
fi

printf 'copy v2\n' >"$src"
copy_file "$src" "$REAL_HOME/.config/copied.conf" 0644
row="$(tail -n1 "$STATE_FILE")"
IFS=$'\t' read -r kind path source digest original2 <<<"$row"
if [[ $original2 == "$original" && -f $original2 ]]; then
    pass "a repo update keeps the first original pointer"
else
    fail "original moved: $original -> $original2"
fi

if [[ $(file_digest "$src") == "$(sha256sum "$src" | cut -d' ' -f1)" ]]; then
    pass "file_digest returns sha256"
else
    fail "file_digest mismatch"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
