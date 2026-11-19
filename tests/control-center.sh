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
for action in Appearance Desktop Input Session System "Install and update"; do
    if grep -qx "$action" <<<"$actions"; then
        pass "action listed: $action"
    else
        fail "action missing: $action"
    fi
done

# 1b. Esc is the only way out; no Back or Close entries and no Music page.
if grep -Eq '"(Back|Close)"|Back\|"")' "$CC"; then
    fail "control center still has Back or Close entries"
else
    pass "control center closes with Esc only"
fi
if grep -q 'music_page' "$CC"; then
    fail "the Music page still exists"
else
    pass "the Music page is gone"
fi

# 1c. Spicetify update is one button in the updates page.
if grep -q 'Spicetify — backup and apply' "$CC" \
    && grep -q 'spicetify backup apply' "$CC" \
    && ! grep -q 'spicetify update' "$CC"; then
    pass "Spicetify update is a single backup-and-apply action"
else
    fail "Spicetify update is not a single action"
fi

# 1d. A terminal opened by the control center waits for a key press.
if ! grep -q -- '--hold' "$CC" && grep -q 'read -rsn1' "$CC"; then
    pass "the action terminal waits for a key press and closes"
else
    fail "the action terminal closes immediately or stays forever"
fi

# 1e. Host-specific entries are gated: no dock layout on a desktop, no lid
# entry without a laptop chassis.
desktop_block="$(awk '/^desktop_page\(\)/,/^input_page\(\)/' "$CC")"
if grep -q 'if host_is_laptop; then' <<<"$desktop_block" \
    && grep -q 'Dock layout' <<<"$desktop_block"; then
    pass "dock layout is only offered on laptops"
else
    fail "desktop still offers laptop-only dock entries"
fi
session_block="$(awk '/^session_page\(\)/,/^music_page|^package_search/' "$CC")"
if grep -q 'host_is_laptop && have lid-handler.sh' <<<"$session_block"; then
    pass "the lid entry is laptop-only"
else
    fail "the lid entry is not gated by host"
fi

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

# 3b. Rows use an explicit surface colour, not "transparent", which some rofi
# versions render as white.
if grep -A4 'element normal.normal' "$RASI" | grep -q 'background-color: *@surface'; then
    pass "rofi rows use an explicit surface colour"
else
    fail "rofi rows still rely on transparent"
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
    && grep -q 'sudo pacman -Syu' "$CC" \
    && grep -q 'keyserver hkps://pgp.surf.nl' "$CC"; then
    pass "system updates and package management are wired"
else
    fail "system package management is incomplete"
fi

if grep -q 'Update — repository mirrors (reflector)' "$CC" \
    && grep -q 'reflector --latest 20 --protocol https --sort rate' "$CC" \
    && grep -q 'mirrorlist.bak' "$CC"; then
    pass "mirror refresh is wired to reflector with a backup"
else
    fail "mirror refresh is missing"
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
