#!/usr/bin/env bash
# Control center: module wiring, non-interactive entry points and bind config.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="$ROOT/modules/control-center/home/.local/bin/dotfiles-control-center"
RASI="$ROOT/modules/control-center/home/.config/rofi/control-center.rasi"
DESKTOP="$ROOT/modules/control-center/home/.local/share/applications/dotfiles-control-center.desktop"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# 1. The entry point is executable and usable without a display.
if [[ -x $CC ]]; then
    pass "control center is executable"
else
    fail "control center is not executable"
fi

if "$CC" --help | grep -q 'Installation and updates'; then
    pass "--help explains the scope"
else
    fail "--help does not explain the scope"
fi

actions="$("$CC" --list-actions)"
for action in Appearance Desktop Input Session Music System "Install and update"; do
    if grep -qx "$action" <<<"$actions"; then
        pass "action listed: $action"
    else
        fail "action missing: $action"
    fi
done

# 2. The desktop entry launches the same command.
if grep -qx 'Exec=dotfiles-control-center' "$DESKTOP"; then
    pass "desktop entry uses the control center command"
else
    fail "desktop entry has the wrong Exec"
fi

# 3. The theme uses matugen colors and the installed fonts.
if grep -q '@import "colors.rasi"' "$RASI" \
    && grep -q 'Inter' "$RASI" \
    && grep -q '@primary' "$RASI"; then
    pass "rofi theme uses matugen colors and Inter"
else
    fail "rofi theme is not wired to colors.rasi"
fi

# 4. The bind is configurable per host and rendered through a separate Lua file.
for host in desktop laptop; do
    if grep -q 'CONTROL_CENTER_BIND="SUPER + Space"' "$ROOT/hosts/$host/control-center.conf"; then
        pass "$host control center bind is set"
    else
        fail "$host control center bind is missing"
    fi
done

if grep -q 'control-center.lua' "$ROOT/modules/hypr/home/.config/hypr/hyprland.lua"; then
    pass "hyprland.lua loads the optional control center bind"
else
    fail "hyprland.lua does not load the control center bind"
fi

if grep -q '@CONTROL_CENTER_BIND@' "$ROOT/modules/control-center/home/.config/hypr/control-center.lua.in" \
    && grep -q '@HOME@/.local/bin/dotfiles-control-center' "$ROOT/modules/control-center/home/.config/hypr/control-center.lua.in"; then
    pass "control center Lua template is renderable"
else
    fail "control center Lua template is incomplete"
fi

# 5. System page covers updates, package search and removal.
if grep -q 'Update — repository packages' "$CC" \
    && grep -q 'Packages — search and install' "$CC" \
    && grep -q 'Packages — remove' "$CC" \
    && grep -q 'sudo pacman -Syu' "$CC"; then
    pass "system updates and package management are wired"
else
    fail "system package management is incomplete"
fi

# 6. Daily actions call helpers directly, not the installer menu.
if grep -q 'autostart.sh pick' "$CC" \
    && grep -q 'gamemode.sh toggle' "$CC" \
    && grep -q 'idle-tune.sh' "$CC" \
    && grep -q 'monitor-profiles.sh' "$CC"; then
    pass "daily actions use the per-feature helpers"
else
    fail "a daily action is not wired to its helper"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
