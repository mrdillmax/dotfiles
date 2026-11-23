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

# A new install run uses a new backup directory; the original must not move.
BACKUP_DIR="$work/backup2"
mkdir -p "$BACKUP_DIR"
printf 'target\tbackup\n' >"$BACKUP_DIR/manifest.tsv"
printf 'copy v2\n' >"$src"
copy_file "$src" "$REAL_HOME/.config/copied.conf" 0644
row="$(tail -n1 "$STATE_FILE")"
IFS=$'\t' read -r kind path source digest original2 <<<"$row"
if [[ $original2 == "$original" && -f $original2 && $(cat "$original2") == "user copy" ]]; then
    pass "a repo update keeps the first original pointer and its content"
else
    fail "original moved: $original -> $original2 ($(cat "$original2" 2>/dev/null))"
fi

copy_file "$src" "$REAL_HOME/.config/override.conf" 0644 "$ROOT/lib/common.sh"
row="$(tail -n1 "$STATE_FILE")"
IFS=$'\t' read -r kind path source digest original <<<"$row"
if [[ $source == "$ROOT/lib/common.sh" ]]; then
    pass "copy_file accepts a source override"
else
    fail "source override not recorded: $source"
fi

if [[ $(file_digest "$src") == "$(sha256sum "$src" | cut -d' ' -f1)" ]]; then
    pass "file_digest returns sha256"
else
    fail "file_digest mismatch"
fi

# A symlinked destination must not be chmod'ed or written through: both would
# touch a file this repository does not own.
host="$(mktemp)"
cp -- /etc/hostname "$host"
ln -sfn /etc/hostname "$REAL_HOME/.config/host-link"
( set -e; copy_file "$host" "$REAL_HOME/.config/host-link" 0644 ) >/dev/null 2>&1
rc=$?
if ((rc == 0)); then
    pass "an up-to-date symlink is not chmod'ed"
else
    fail "copy_file failed on an up-to-date symlink (rc=$rc)"
fi
if [[ -L $REAL_HOME/.config/host-link ]]; then
    pass "the symlink is left in place"
else
    fail "the symlink was replaced"
fi
rm -f -- "$host"

printf 'old\n' >"$work/target"
printf 'new\n' >"$work/source"
ln -sfn "$work/target" "$REAL_HOME/.config/changed-link"
copy_file "$work/source" "$REAL_HOME/.config/changed-link" 0644
if [[ ! -L $REAL_HOME/.config/changed-link ]] &&
    [[ $(cat "$REAL_HOME/.config/changed-link") == new ]] &&
    [[ $(cat "$work/target") == old ]]; then
    pass "a changed symlink is replaced, not written through"
else
    fail "changed symlink: $(ls -l "$REAL_HOME/.config/changed-link" 2>&1) / $(cat "$work/target")"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
