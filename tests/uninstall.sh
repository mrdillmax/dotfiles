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

chmod 0640 "$STATE_FILE"
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
if [[ $(stat -c %a "$STATE_FILE") == 640 ]]; then
    pass "the manifest rewrite keeps its mode"
else
    fail "manifest mode: $(stat -c %a "$STATE_FILE")"
fi
if [[ $(cat "$work/out") == *"packages were not removed"* && $(cat "$work/out") == *chsh* ]]; then
    pass "uninstall reports packages and the shell it left alone"
else
    fail "uninstall report: $(cat "$work/out")"
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

# --force restores an edited copy instead of keeping it.
printf 'edited by user\n' >"$REAL_HOME/.config/edited.conf"
printf 'copy\t%s\t%s\t%s\t%s\n' "$REAL_HOME/.config/edited.conf" \
    "$DOTFILES_DIR/modules/demo/home/.config/repo.conf" \
    "$(sha256sum "$DOTFILES_DIR/modules/demo/home/.config/repo.conf" | cut -d' ' -f1)" \
    "$work/original-edited" >"$STATE_FILE"
ASSUME_YES=1 DRY_RUN=0 DO_SYSTEM=0 FORCE=1 uninstall_run "" >/dev/null 2>&1
if [[ $(cat "$REAL_HOME/.config/edited.conf") == "original edited" ]]; then
    pass "--force restores an edited copy's original"
else
    fail "--force edited copy: $(cat "$REAL_HOME/.config/edited.conf")"
fi

# Module filtering leaves the other module's files alone.
ln -sfn "$DOTFILES_DIR/modules/demo/home/.config/repo.conf" "$REAL_HOME/.config/repo.conf"
ln -sfn "$work/external-theme" "$REAL_HOME/.config/theme-link"
{
    printf 'link\t%s\t%s\t-\t-\n' "$REAL_HOME/.config/repo.conf" \
        "$DOTFILES_DIR/modules/demo/home/.config/repo.conf"
    printf 'link\t%s\t%s\t-\t-\n' "$REAL_HOME/.config/theme-link" "$work/external-theme"
} >"$STATE_FILE"
ASSUME_YES=1 DRY_RUN=0 DO_SYSTEM=0 FORCE=0 uninstall_run "other" >/dev/null 2>&1
if [[ -L $REAL_HOME/.config/repo.conf && ! -e $REAL_HOME/.config/theme-link && \
    ! -L $REAL_HOME/.config/theme-link ]]; then
    pass "a module filter removes only that module"
else
    fail "module filter left the wrong state"
fi

# Root processes only system rows; home rows are left for the desktop user.
printf 'system file\n' >"$work/system.conf"
printf 'original system\n' >"$work/original-system"
printf 'system\t%s\t%s\t%s\t%s\n' "$work/system.conf" \
    "$DOTFILES_DIR/system/demo.conf" \
    "$(sha256sum "$work/system.conf" | cut -d' ' -f1)" "$work/original-system" >"$STATE_FILE"
UNINSTALL_EUID=0 ASSUME_YES=1 DRY_RUN=0 DO_SYSTEM=1 FORCE=0 uninstall_run "" >/dev/null 2>&1
if [[ $(cat "$work/system.conf") == "original system" ]]; then
    pass "--system restores a system row"
else
    fail "system row restore: $(cat "$work/system.conf")"
fi

ln -sfn "$work/external-theme" "$REAL_HOME/.config/root-skip"
printf 'link\t%s\t%s\t-\t-\n' "$REAL_HOME/.config/root-skip" "$work/external-theme" >"$STATE_FILE"
UNINSTALL_EUID=0 ASSUME_YES=1 DRY_RUN=0 DO_SYSTEM=1 FORCE=0 uninstall_run "" >/dev/null 2>&1
if [[ -L $REAL_HOME/.config/root-skip ]]; then
    pass "root leaves home rows alone"
else
    fail "root removed a home row"
fi

# A three-column manifest from before v2 is readable.
ln -sfn "$work/external-theme" "$REAL_HOME/.config/v1.conf"
printf 'link\t%s\t%s\n' "$REAL_HOME/.config/v1.conf" "$work/external-theme" >"$STATE_FILE"
ASSUME_YES=1 DRY_RUN=0 DO_SYSTEM=0 FORCE=0 uninstall_run "" >/dev/null 2>&1
if [[ ! -e $REAL_HOME/.config/v1.conf && ! -L $REAL_HOME/.config/v1.conf ]]; then
    pass "a three-column manifest is still uninstallable"
else
    fail "v1 manifest row survived"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
