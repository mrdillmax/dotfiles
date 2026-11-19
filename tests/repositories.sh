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

# 2. The action reports its plan under --dry-run and needs root otherwise.
log="$(mktemp)"
if (cd "$ROOT" && ./install.sh --repositories --dry-run) >"$log" 2>&1; then
    if grep -Eq 'multilib is already enabled|\[dry-run\].*merge pacman.conf' "$log"; then
        pass "--repositories --dry-run reports its plan"
    else
        fail "--repositories --dry-run printed no plan"
    fi
else
    fail "--repositories --dry-run failed"
fi
rm -f -- "$log"

if ((EUID != 0)); then
    log="$(mktemp)"
    if (cd "$ROOT" && ./install.sh --repositories) >"$log" 2>&1; then
        fail "--repositories ran without root"
    elif grep -q 'repositories require root' "$log"; then
        pass "--repositories needs root"
    else
        fail "--repositories failed without a root message"
    fi
    rm -f -- "$log"
fi

if ./install.sh --help 2>&1 | grep -q -- '--repositories'; then
    pass "--repositories is documented in --help"
else
    fail "--repositories is missing from --help"
fi

# 3. Guided setup prepares repositories before it installs packages.
repo_line="$(grep -n -- '--repositories' "$ROOT/install.sh" | grep -v 'die ' | tail -1 | cut -d: -f1)"
packages_line="$(grep -n -- '--only-packages' "$ROOT/install.sh" | grep 'run_setup\|setup_stage\|install.sh"' | tail -1 | cut -d: -f1)"
setup_start="$(grep -n '^run_setup()' "$ROOT/install.sh" | cut -d: -f1)"
if [[ -n $repo_line && -n $packages_line ]] && ((repo_line > setup_start && repo_line < packages_line)); then
    pass "setup prepares repositories before packages"
else
    fail "setup order is repositories ($repo_line) then packages ($packages_line)"
fi

# 4. The root guard must not create state or backup directories on failure.
guard_line="$(grep -nF 'repositories require root' "$ROOT/install.sh" | cut -d: -f1)"
# shellcheck disable=SC2016 # literal shell text in install.sh is being checked
mkdir_line="$(grep -nF 'mkdir -p "$STATE_DIR"' "$ROOT/install.sh" | cut -d: -f1)"
if [[ -n $guard_line && -n $mkdir_line ]] && ((guard_line < mkdir_line)); then
    pass "the root guard runs before state directories are created"
else
    fail "the root guard runs after state directories (guard $guard_line, mkdir $mkdir_line)"
fi

# 5. prepare_repositories leaves a clean signal and never upgrades when the
# merge did not happen.
run_prepare() {
    local conf="$1" dry="$2"
    DOTFILES_DIR="$ROOT" DRY_RUN="$dry" bash -c '
        source "$DOTFILES_DIR/lib/common.sh"
        source "$DOTFILES_DIR/lib/tui.sh"
        source "$DOTFILES_DIR/lib/system.sh"
        pacman() { printf "PACMAN CALLED\n"; }
        prepare_repositories "$1"
    ' _ "$conf" 2>&1
}

tmp="$(mktemp)"
printf '[options]\nColor\n' >"$tmp"

out="$(run_prepare "$tmp" 0)"
if [[ $? -ne 0 && $out != *'PACMAN CALLED'* ]]; then
    pass "a skipped merge does not upgrade the system"
else
    fail "a skipped merge still reached pacman"
fi

out="$(run_prepare "$tmp" 1)"
if [[ $? -eq 0 && $out == *'pacman -Syu'* ]]; then
    pass "--dry-run plans pacman -Syu without running it"
else
    fail "--dry-run did not plan pacman -Syu"
fi

printf '[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >"$tmp"
out="$(run_prepare "$tmp" 0)"
if [[ $? -eq 0 && $out == *'already enabled'* && $out != *'PACMAN CALLED'* ]]; then
    pass "an enabled multilib skips the upgrade"
else
    fail "an enabled multilib still reached pacman"
fi
rm -f -- "$tmp"

# 6. A missing pacman.conf is reported, not an awk crash under set -e.
log="$(mktemp)"
DOTFILES_DIR="$ROOT" bash -c 'set -e
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/system.sh"
    merge_pacman_conf /tmp/dotfiles-no-such-pacman.conf' >"$log" 2>&1
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'not found, skipping pacman.conf' "$log"; then
    pass "a missing pacman.conf is reported"
else
    fail "a missing pacman.conf crashes (rc $rc)"
fi
rm -f -- "$log"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
