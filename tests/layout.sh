#!/usr/bin/env bash
# Repository layout: executables belong in ~/.local/bin, declarative files in
# ~/.config. Reference paths must follow the move.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

while IFS= read -r file; do
    if [[ -x $file ]]; then
        fail "executable in .config: ${file#"$ROOT"/}"
    fi
done < <(find "$ROOT/modules" -path '*/.config/*' -type f)

for name in powermenu.sh dunst-history.sh switch-workspace.sh; do
    found=0
    for candidate in "$ROOT"/modules/*/home/.local/bin/"$name"; do
        [[ -x $candidate ]] && found=1
    done
    if ((found)); then
        pass "$name lives in .local/bin"
    else
        fail "$name is not in .local/bin"
    fi
done

if grep -q 'rofi/scripts/powermenu.sh' "$ROOT/modules/hypr/home/.config/hypr/hyprland.lua"; then
    fail "hyprland.lua still points at the old powermenu path"
else
    pass "hyprland.lua uses the new helper paths"
fi

if grep -q 'waybar/scripts/dunst.sh' "$ROOT/modules/waybar/home/.config/waybar/config.jsonc"; then
    fail "waybar config still points at the old dunst path"
else
    pass "waybar config inlines dunst state check"
fi

if grep -q 'uwsm check may-start' "$ROOT/modules/fish/home/.config/fish/config.fish"; then
    pass "fish autologin uses uwsm check may-start"
else
    fail "fish autologin is outdated"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
