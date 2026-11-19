#!/usr/bin/env bash
# Hyprland defaults: single-monitor workspaces, one SUPER+H bind, language click.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

lua="$ROOT/modules/hypr/home/.config/hypr/hyprland.lua"
if [[ $(grep -c 'mainMod .. " + H"' "$lua") -eq 1 ]]; then
    pass "SUPER+H has one binding"
else
    fail "SUPER+H is bound more than once"
fi

if grep -q '^MON_COUNT=0' "$ROOT/hosts/desktop/monitors.conf.sh"; then
    pass "the desktop default lets Hyprland detect monitors"
else
    fail "the desktop default hardcodes monitors"
fi

if grep -q 'app_workspace("obsidian", 5)' "$lua" \
    && grep -q 'app_workspace("vesktop", 6)' "$lua"; then
    pass "apps default to workspaces inside the single-monitor range"
else
    fail "apps still default to dual-monitor workspaces"
fi

if grep -q 'switchxkblayout all next' "$ROOT/modules/waybar/home/.config/waybar/config.jsonc"; then
    pass "clicking the waybar language switches the layout"
else
    fail "the waybar language is not clickable"
fi

clipboard="$ROOT/modules/rofi/home/.local/bin/clipboard-menu.sh"
if grep -q 'clipboard-menu.sh' "$lua" \
    && [[ -x $clipboard ]] \
    && grep -q 'launcher.rasi' "$clipboard"; then
    pass "SUPER+V opens the themed clipboard picker"
else
    fail "SUPER+V does not use the clipboard picker"
fi

if grep -q '"tooltip-format": "{desc}"' "$ROOT/modules/waybar/home/.config/waybar/config.jsonc"; then
    pass "the microphone tooltip uses the device description"
else
    fail "the microphone tooltip is hardcoded"
fi

bar_config="$ROOT/modules/waybar/home/.config/waybar/config.jsonc"
if grep -q '"{icon}   {volume}%"' "$bar_config" \
    && grep -q '{usage}%' "$bar_config"; then
    pass "waybar leaves space between icons and values"
else
    fail "waybar values collide with their icons"
fi

if grep -q 'nwg-look-float' "$lua"; then
    pass "the appearance editor floats in the centre"
else
    fail "the appearance editor tiles"
fi

if grep -q 'dotfiles-control-center-float' "$lua" \
    && grep -q 'pavucontrol-float' "$lua" \
    && grep -q 'center = true' "$lua"; then
    pass "helper terminals and pavucontrol float in the centre"
else
    fail "helper terminals or pavucontrol still tile"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
