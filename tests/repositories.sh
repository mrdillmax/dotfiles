#!/usr/bin/env bash
# Repository preparation: multilib detection and the --repositories action.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

check_enabled() {
    local file="$1" expected="$2" label="$3" actual
    if DOTFILES_DIR="$ROOT" bash -c '
        source "$DOTFILES_DIR/lib/system.sh"
        multilib_enabled "$1"
    ' _ "$file"; then
        actual=0
    else
        actual=1
    fi
    if [[ $actual == "$expected" ]]; then pass "$label"; else fail "$label"; fi
}

tmp="$(mktemp)"
printf '[options]\nColor\n' >"$tmp"
check_enabled "$tmp" 1 "missing [multilib] counts as disabled"
printf '[options]\nColor\n#[multilib]\n#Include = /etc/pacman.d/mirrorlist\n' >"$tmp"
check_enabled "$tmp" 1 "commented [multilib] counts as disabled"
printf '[options]\nColor\n\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >"$tmp"
check_enabled "$tmp" 0 "active [multilib] counts as enabled"
rm -f -- "$tmp"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
