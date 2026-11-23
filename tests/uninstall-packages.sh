#!/usr/bin/env bash
# Removing module packages is explicit, respects shared packages and dry-run.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/modules/demo" "$work/repo/modules/other" "$work/bin"
printf 'DESCRIPTION="demo"\nPACKAGES=(demo-pkg shared-pkg)\nSERVICES=()\nREQUIRES=()\n' \
    >"$work/repo/modules/demo/module.conf"
printf 'DESCRIPTION="other"\nPACKAGES=(shared-pkg)\nSERVICES=()\nREQUIRES=()\n' \
    >"$work/repo/modules/other/module.conf"

printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/pacman.log"\nexit 0\n' "$work" >"$work/bin/pacman"
printf '#!/bin/sh\nexec "$@"\n' >"$work/bin/sudo"
chmod +x "$work/bin/pacman" "$work/bin/sudo"
PATH="$work/bin:$PATH"
DOTFILES_DIR="$work/repo"
REAL_HOME="$work/home"
STATE_DIR="$work/state"
BACKUP_DIR="$work/backup"
mkdir -p "$REAL_HOME" "$STATE_DIR" "$BACKUP_DIR"
SUDO_BIN="$work/bin/sudo"
export PATH DOTFILES_DIR REAL_HOME STATE_DIR BACKUP_DIR SUDO_BIN

# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/uninstall.sh"

export ASSUME_YES=1 DRY_RUN=0
uninstall_remove_packages "demo" >/dev/null 2>&1
if grep -q -- '-Rns -- demo-pkg' "$work/pacman.log"; then
    pass "an unselected module's package is removed explicitly"
else
    fail "demo-pkg was not removed: $(cat "$work/pacman.log" 2>/dev/null)"
fi
if grep -q "shared-pkg" "$work/pacman.log"; then
    fail "a shared package was removed"
else
    pass "a package used by another module is kept"
fi

: >"$work/pacman.log"
export DRY_RUN=1; uninstall_remove_packages "demo" >/dev/null 2>&1
if ! grep -q -- '-Rns' "$work/pacman.log"; then
    pass "dry-run removes no packages"
else
    fail "dry-run ran pacman -Rns: $(cat "$work/pacman.log")"
fi

if uninstall_remove_packages "" >/dev/null 2>&1; then
    fail "package removal without --modules was allowed"
else
    pass "package removal requires an explicit module"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
