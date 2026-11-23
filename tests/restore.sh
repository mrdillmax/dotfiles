#!/usr/bin/env bash
# Restoring over a symlink must replace the link, not write through it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export DOTFILES_DIR="$ROOT"
export REAL_HOME="$work/home"
export DOTFILES_BACKUP_DIR="$work/backups"
export BACKUP_DIR="$work/prerestore"
export ASSUME_YES=1
export DRY_RUN=0
date="2026-01-01_000000"
mkdir -p "$REAL_HOME/.config" "$DOTFILES_BACKUP_DIR/$date/.config" "$BACKUP_DIR"
printf 'user content\n' >"$DOTFILES_BACKUP_DIR/$date/.config/demo.conf"
printf 'other file content\n' >"$work/other.conf"
ln -s "$work/other.conf" "$REAL_HOME/.config/demo.conf"
printf 'target\tbackup\n' >"$DOTFILES_BACKUP_DIR/$date/manifest.tsv"
printf '%s\t%s\n' "$REAL_HOME/.config/demo.conf" \
    "$DOTFILES_BACKUP_DIR/$date/.config/demo.conf" >>"$DOTFILES_BACKUP_DIR/$date/manifest.tsv"

# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/tui.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/restore.sh"

restore_run "$date" >/dev/null 2>&1
if [[ ! -L $REAL_HOME/.config/demo.conf ]] &&
    [[ $(cat "$REAL_HOME/.config/demo.conf") == "user content" ]]; then
    pass "restore replaces a symlink with the backed-up file"
else
    fail "target: $(ls -l "$REAL_HOME/.config/demo.conf" 2>&1)"
fi
if [[ $(cat "$work/other.conf") == "other file content" ]]; then
    pass "the symlink target is not overwritten"
else
    fail "the symlink target was overwritten: $(cat "$work/other.conf")"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
