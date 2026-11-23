#!/usr/bin/env bash
# Uninstall: remove what is ours, restore originals, keep edits.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export DOTFILES_DIR="$work/repo"
REAL_HOME="$work/home"
STATE_DIR="$work/state"
STATE_FILE="$STATE_DIR/managed.tsv"
BACKUP_DIR="$work/backup"
mkdir -p "$DOTFILES_DIR/modules/demo/home/.config" "$REAL_HOME/.config" \
    "$STATE_DIR" "$BACKUP_DIR"
printf 'target\tbackup\n' >"$BACKUP_DIR/manifest.tsv"
printf 'repo file\n' >"$DOTFILES_DIR/modules/demo/home/.config/repo.conf"
printf 'original link target\n' >"$work/original-link"
printf 'original copy\n' >"$work/original-copy"
printf 'original edited\n' >"$work/original-edited"
printf 'external target\n' >"$work/external-theme"
printf 'system file\n' >"$work/system.conf"

# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/restore.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/uninstall.sh"

ln -s "$DOTFILES_DIR/modules/demo/home/.config/repo.conf" "$REAL_HOME/.config/repo.conf"
ln -s "$work/external-theme" "$REAL_HOME/.config/theme-link"
ln -s "$work/external-theme" "$REAL_HOME/.config/not-ours"
printf 'managed copy\n' >"$REAL_HOME/.config/copy.conf"
printf 'edited by user\n' >"$REAL_HOME/.config/edited.conf"

{
    printf 'link\t%s\t%s\t-\t%s\n' "$REAL_HOME/.config/repo.conf" \
        "$DOTFILES_DIR/modules/demo/home/.config/repo.conf" "$work/original-link"
    printf 'link\t%s\t%s\t-\t-\n' "$REAL_HOME/.config/theme-link" "$work/external-theme"
    printf 'link\t%s\t%s\t-\t-\n' "$REAL_HOME/.config/not-ours" "$work/other-theme"
    printf 'copy\t%s\t%s\t%s\t%s\n' "$REAL_HOME/.config/copy.conf" \
        "$DOTFILES_DIR/modules/demo/home/.config/repo.conf" \
        "$(sha256sum "$REAL_HOME/.config/copy.conf" | cut -d' ' -f1)" "$work/original-copy"
    printf 'copy\t%s\t%s\t%s\t%s\n' "$REAL_HOME/.config/edited.conf" \
        "$DOTFILES_DIR/modules/demo/home/.config/repo.conf" \
        "$(sha256sum "$DOTFILES_DIR/modules/demo/home/.config/repo.conf" | cut -d' ' -f1)" "$work/original-edited"
    printf 'system\t%s\t%s\t-\t-\n' "$work/system.conf" \
        "$DOTFILES_DIR/system/demo.conf"
} >"$STATE_FILE"

ASSUME_YES=1 DRY_RUN=0 DO_SYSTEM=0 FORCE=0 uninstall_run "" >"$work/out" 2>&1
if [[ ! -L $REAL_HOME/.config/repo.conf &&
    $(cat "$REAL_HOME/.config/repo.conf" 2>/dev/null) == "original link target" ]]; then
    pass "a repo link is replaced by its original file"
else
    fail "repo link not restored: $(ls -l "$REAL_HOME/.config/repo.conf" 2>&1)"
fi
if [[ ! -e $REAL_HOME/.config/theme-link && ! -L $REAL_HOME/.config/theme-link ]]; then
    pass "a link to an external recorded source is removed"
else
    fail "external link survived"
fi
if [[ -L $REAL_HOME/.config/not-ours ]]; then
    pass "a link to a different source is kept"
else
    fail "unrelated link was removed"
fi
if [[ $(cat "$REAL_HOME/.config/copy.conf") == "original copy" ]]; then
    pass "a matching copy is restored from the original"
else
    fail "copy restore: $(cat "$REAL_HOME/.config/copy.conf")"
fi
if [[ $(cat "$REAL_HOME/.config/edited.conf") == "edited by user" ]]; then
    pass "an edited copy is kept"
else
    fail "edited copy was lost"
fi
if [[ -f $work/system.conf && $(cat "$work/system.conf") == "system file" ]]; then
    pass "a system row is skipped without --system"
else
    fail "system file was touched"
fi
if grep -q "edited.conf" "$STATE_FILE" && grep -q "$work/system.conf" "$STATE_FILE" &&
    ! grep -q "$REAL_HOME/.config/repo.conf" "$STATE_FILE"; then
    pass "the manifest keeps unhandled rows"
else
    fail "manifest rewrite: $(cat "$STATE_FILE")"
fi

# Dry-run on a fresh fixture changes nothing.
printf 'link\t%s\t%s\t-\t-\n' "$REAL_HOME/.config/dry.conf" "$work/original-link" >"$STATE_FILE"
ln -s "$work/original-link" "$REAL_HOME/.config/dry.conf"
DRY_RUN=1 ASSUME_YES=1 DO_SYSTEM=0 FORCE=0 uninstall_run "" >/dev/null 2>&1
if [[ -L $REAL_HOME/.config/dry.conf ]]; then
    pass "dry-run leaves links in place"
else
    fail "dry-run removed a link"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
