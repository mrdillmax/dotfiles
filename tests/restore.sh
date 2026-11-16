#!/usr/bin/env bash
# Tests for lib/restore.sh. Everything happens in a temporary $HOME.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
TMP_DIRS=()

cleanup() {
    local d
    for d in "${TMP_DIRS[@]}"; do
        rm -rf -- "$d"
    done
}
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# run_restore <home> <backup_dir> <date> <modules> <system> <dry_run>
run_restore() {
    local tmp_home="$1" backup_dir="$2" date="$3" module_filter="$4" system="$5" dry="$6"
    # Subshell keeps test state isolated; the assignments are intentional.
    # shellcheck disable=SC2030
    (
        DOTFILES_DIR="$ROOT"
        REAL_HOME="$tmp_home"
        BACKUP_DIR="$backup_dir"
        DRY_RUN="$dry"
        ASSUME_YES=1
        DO_SYSTEM="$system"
        export DOTFILES_DIR REAL_HOME BACKUP_DIR DRY_RUN ASSUME_YES DO_SYSTEM
        # shellcheck source=lib/common.sh
        source "$ROOT/lib/common.sh"
        # shellcheck source=lib/tui.sh
        source "$ROOT/lib/tui.sh"
        # shellcheck source=lib/restore.sh
        source "$ROOT/lib/restore.sh"
        restore_run "$date" "$module_filter"
    )
}

# run_restore_capture <...> -> prints output, returns restore status
run_restore_capture() {
    run_restore "$@" 2>&1
}

# 1. Full restore writes files and backs up the previous state first.
tmp_home="$(mktemp -d)"
TMP_DIRS+=("$tmp_home")
# Rebuild the fixture inside tmp_home with a predictable path.
src="$tmp_home/.dotfiles-backup/2026-01-01_000000"
pre="$tmp_home/.dotfiles-backup/pre-restore"
mkdir -p "$src/.config/hypr" "$pre"
printf 'backup-hypr\n' >"$src/.config/hypr/hyprland.lua"
printf 'target\tbackup\n' >"$src/manifest.tsv"
printf '%s\t%s\n' "$tmp_home/.config/hypr/hyprland.lua" "$src/.config/hypr/hyprland.lua" >>"$src/manifest.tsv"
mkdir -p "$tmp_home/.config/hypr"
printf 'current-hypr\n' >"$tmp_home/.config/hypr/hyprland.lua"
printf 'target\tbackup\n' >"$pre/manifest.tsv"

if run_restore "$tmp_home" "$pre" "2026-01-01_000000" "" 0 0 >/dev/null 2>&1; then
    if [[ "$(cat "$tmp_home/.config/hypr/hyprland.lua")" == "backup-hypr" ]]; then
        pass "restores the selected file"
    else
        fail "file was not restored"
    fi
    if grep -q '^current-hypr$' "$pre/.config/hypr/hyprland.lua" 2>/dev/null; then
        pass "backs up the current state before writing"
    else
        fail "pre-restore backup was not created"
    fi
    if [[ "$(cat "$pre/restore-from.txt" 2>/dev/null)" == "2026-01-01_000000" ]]; then
        pass "records the restore source date"
    else
        fail "restore-from.txt is missing or wrong"
    fi
else
    fail "full restore command failed"
fi

# 2. Dry-run never modifies files and never creates a pre-restore backup.
tmp_home="$(mktemp -d)"
TMP_DIRS+=("$tmp_home")
src="$tmp_home/.dotfiles-backup/2026-01-01_000000"
pre="$tmp_home/.dotfiles-backup/pre-restore"
mkdir -p "$src/.config/hypr" "$tmp_home/.config/hypr" "$pre"
printf 'backup-hypr\n' >"$src/.config/hypr/hyprland.lua"
printf 'target\tbackup\n' >"$src/manifest.tsv"
printf '%s\t%s\n' "$tmp_home/.config/hypr/hyprland.lua" "$src/.config/hypr/hyprland.lua" >>"$src/manifest.tsv"
printf 'current-hypr\n' >"$tmp_home/.config/hypr/hyprland.lua"
printf 'target\tbackup\n' >"$pre/manifest.tsv"

dry_output="$(run_restore_capture "$tmp_home" "$pre" "2026-01-01_000000" "" 0 1)"
if [[ "$(cat "$tmp_home/.config/hypr/hyprland.lua")" == "current-hypr" ]]; then
    pass "dry-run leaves the live file untouched"
else
    fail "dry-run modified the live file"
fi
if grep -q 'dry-run' <<<"$dry_output" && ! grep -q '^current-hypr$' "$pre/.config/hypr/hyprland.lua" 2>/dev/null; then
    pass "dry-run reports actions and creates no backup"
else
    fail "dry-run output/backup is wrong"
fi

# 3. Module filter restores only the requested module.
tmp_home="$(mktemp -d)"
TMP_DIRS+=("$tmp_home")
src="$tmp_home/.dotfiles-backup/2026-01-01_000000"
pre="$tmp_home/.dotfiles-backup/pre-restore"
mkdir -p "$src/.config/hypr" "$src/.config/waybar" "$tmp_home/.config/hypr" "$tmp_home/.config/waybar" "$pre"
printf 'backup-hypr\n'   >"$src/.config/hypr/hyprland.lua"
printf 'backup-waybar\n' >"$src/.config/waybar/config.jsonc"
printf 'target\tbackup\n' >"$src/manifest.tsv"
printf '%s\t%s\n' "$tmp_home/.config/hypr/hyprland.lua" "$src/.config/hypr/hyprland.lua" >>"$src/manifest.tsv"
printf '%s\t%s\n' "$tmp_home/.config/waybar/config.jsonc" "$src/.config/waybar/config.jsonc" >>"$src/manifest.tsv"
printf 'current-hypr\n'   >"$tmp_home/.config/hypr/hyprland.lua"
printf 'current-waybar\n' >"$tmp_home/.config/waybar/config.jsonc"
printf 'target\tbackup\n' >"$pre/manifest.tsv"

run_restore "$tmp_home" "$pre" "2026-01-01_000000" "hypr" 0 0 >/dev/null 2>&1
if [[ "$(cat "$tmp_home/.config/hypr/hyprland.lua")" == "backup-hypr" \
   && "$(cat "$tmp_home/.config/waybar/config.jsonc")" == "current-waybar" ]]; then
    pass "--modules hypr restores only hypr"
else
    fail "module filter restored the wrong set"
fi

# 4. /etc rows are skipped without --system.
tmp_home="$(mktemp -d)"
TMP_DIRS+=("$tmp_home")
src="$tmp_home/.dotfiles-backup/2026-01-01_000000"
pre="$tmp_home/.dotfiles-backup/pre-restore"
mkdir -p "$src/.config/hypr" "$tmp_home/.config/hypr" "$pre"
printf 'backup-hypr\n' >"$src/.config/hypr/hyprland.lua"
printf 'system-backup\n' >"$src/etc-marker"
printf 'target\tbackup\n' >"$src/manifest.tsv"
printf '%s\t%s\n' "$tmp_home/.config/hypr/hyprland.lua" "$src/.config/hypr/hyprland.lua" >>"$src/manifest.tsv"
printf '%s\t%s\n' "/etc/dotfiles-restore-test" "$src/etc-marker" >>"$src/manifest.tsv"
printf 'current-hypr\n' >"$tmp_home/.config/hypr/hyprland.lua"
printf 'target\tbackup\n' >"$pre/manifest.tsv"

system_output="$(run_restore_capture "$tmp_home" "$pre" "2026-01-01_000000" "" 0 1)"
if grep -q 'skipping 1 system file' <<<"$system_output"; then
    pass "system files are skipped without --system"
else
    fail "system file gate did not report a skip"
fi

# 5. The listing includes the date, file count and modules.
list_output="$(
    DOTFILES_DIR="$ROOT" REAL_HOME="$tmp_home" DRY_RUN=1 ASSUME_YES=1
    export DOTFILES_DIR REAL_HOME DRY_RUN ASSUME_YES
    # shellcheck source=lib/common.sh
    source "$ROOT/lib/common.sh"
    # shellcheck source=lib/tui.sh
    source "$ROOT/lib/tui.sh"
    # shellcheck source=lib/restore.sh
    source "$ROOT/lib/restore.sh"
    restore_list
)"
if grep -q '2026-01-01_000000' <<<"$list_output" && grep -q 'hypr' <<<"$list_output"; then
    pass "restore_list shows date and modules"
else
    fail "restore_list output is incomplete"
fi

# 6. Snapshot is skipped cleanly when snapper is unavailable.
snapshot_output="$(
    # shellcheck disable=SC2123
    DOTFILES_DIR="$ROOT" REAL_HOME="$tmp_home" DRY_RUN=0 ASSUME_YES=1 PATH="/nonexistent"
    export DOTFILES_DIR REAL_HOME DRY_RUN ASSUME_YES PATH
    # shellcheck source=lib/common.sh
    source "$ROOT/lib/common.sh"
    # shellcheck source=lib/tui.sh
    source "$ROOT/lib/tui.sh"
    # shellcheck source=lib/restore.sh
    source "$ROOT/lib/restore.sh"
    maybe_create_snapshot
)"
if grep -q 'snapper not installed' <<<"$snapshot_output"; then
    pass "missing snapper is a silent informational skip"
else
    fail "missing snapper handling is wrong"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
