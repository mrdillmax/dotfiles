#!/usr/bin/env bash
# Package command builders: the terminal must stay attached to pacman so its
# confirmation prompt works. xargs redirects stdin from /dev/null, which is the
# bug these checks pin down.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="$ROOT/modules/control-center/home/.local/bin/dotfiles-control-center"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# shellcheck source=/dev/null
source "$CC"

repo_cmd="$(package_install_command repo "" kitty firefox)"
if [[ $repo_cmd == *'pacman -S --needed'* && $repo_cmd == *kitty* && $repo_cmd == *firefox* ]]; then
    pass "repo install keeps every selected package"
else
    fail "repo install lost packages: $repo_cmd"
fi

if [[ $repo_cmd != *--noconfirm* ]]; then
    pass "repo install keeps the confirmation prompt"
else
    fail "repo install skips the confirmation prompt"
fi

aur_cmd="$(package_install_command aur paru kitty)"
if [[ $aur_cmd == *'paru -S --needed'* && $aur_cmd == *kitty* ]]; then
    pass "AUR install uses the detected helper"
else
    fail "AUR install is wrong: $aur_cmd"
fi

remove_cmd="$(package_remove_command "" kitty)"
if [[ $remove_cmd == *'pacman -Rns'* && $remove_cmd == *kitty* ]]; then
    pass "remove builds a direct pacman command"
else
    fail "remove command is wrong: $remove_cmd"
fi

repo_script="$(fzf_install_script repo "")"
if [[ $repo_script != *xargs* && $repo_script == *mapfile* ]]; then
    pass "fzf install feeds pacman without xargs"
else
    fail "fzf install still uses xargs or drops stdin"
fi

aur_script="$(fzf_install_script aur paru)"
if [[ $aur_script != *xargs* && $aur_script == *paru* ]]; then
    pass "fzf AUR install feeds the helper without xargs"
else
    fail "fzf AUR install still uses xargs"
fi

remove_script="$(fzf_remove_script "")"
if [[ $remove_script != *xargs* && $remove_script == *'pacman -Rns'* ]]; then
    pass "fzf removal feeds pacman without xargs"
else
    fail "fzf removal still uses xargs"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
