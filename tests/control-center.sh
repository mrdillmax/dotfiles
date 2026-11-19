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

if "$CC" --help | grep -q 'apps, docs, menu toggles'; then
    pass "--help explains the scope"
else
    fail "--help does not explain the scope"
fi

actions="$("$CC" --list-actions)"
for action in Apps Docs Menu Style Configuration Install Uninstall Update Power; do
    if grep -qx "$action" <<<"$actions"; then
        pass "action listed: $action"
    else
        fail "action missing: $action"
    fi
done

# 1b. Every top-level entry has an icon. The glyphs are real characters, not
# the literal "\uf..." escapes rofi would show.
main_block="$(awk '/^main_menu\(\)/,/^}/' "$CC")"
icons_ok=1
for code in f009 f02d f0c9 f1fc f013 f019 f1f8 f021 f011; do
    grep -qF "$(printf '%b' "\\u$code")" <<<"$main_block" || icons_ok=0
done
if ((icons_ok)); then
    pass "the main menu has nine real icon glyphs"
else
    fail "the main menu shows literal escapes or misses icons"
fi
if grep -q -- '-markup-rows' "$CC" \
    && grep -q "font='JetBrainsMono Nerd Font 13'" "$CC" \
    && grep -q -- '-format i' "$CC"; then
    pass "icons render through a Nerd Font span"
else
    fail "icons still depend on the UI font fallback"
fi
if ! grep -qE '^ +"\\uf[0-9a-f]+' "$CC"; then
    pass "no menu row contains a literal escape"
else
    fail "a menu row still contains a literal escape"
fi

# 1c. Esc is the only way out; no Back or Close entries and no Music page.
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

# 1d. Spicetify lives in the update page as one button.
update_block="$(awk '/^update_page\(\)/,/^}/' "$CC")"
if grep -q 'Spicetify' <<<"$update_block" \
    && grep -q 'backup apply' <<<"$update_block" \
    && ! grep -q 'spicetify update' <<<"$update_block"; then
    pass "Spicetify update is a single action inside updates"
else
    fail "Spicetify update is not a single action inside updates"
fi

# 1e. A terminal opened by the control center waits for a key press.
if ! grep -q -- '--hold' "$CC" && grep -q 'read -rsn1' "$CC"; then
    pass "the action terminal waits for a key press and closes"
else
    fail "the action terminal closes immediately or stays forever"
fi

# 1f. Host-specific entries are gated: no dock layout on a desktop, no lid
# entry without a laptop chassis.
config_block="$(awk '/^configuration_page\(\)/,/^}/' "$CC")"
if grep -q 'host_is_laptop' <<<"$config_block"; then
    pass "touchpad wording follows the host type"
else
    fail "touchpad wording ignores the host type"
fi
menu_block="$(awk '/^menu_page\(\)/,/^}/' "$CC")"
if grep -q 'host_is_laptop && have lid-handler.sh' <<<"$menu_block"; then
    pass "the lid entry is laptop-only"
else
    fail "the lid entry is not gated by host"
fi
monitor_block="$(awk '/^monitors_page\(\)/,/^}/' "$CC")"
if grep -q 'host_is_laptop && specs+=' <<<"$monitor_block"; then
    pass "dock layout is only offered on laptops"
else
    fail "desktop still offers laptop-only dock entries"
fi

# 2. The desktop entry launches the same command.
if grep -qx 'Exec=dotfiles-control-center' "$DESKTOP"; then
    pass "desktop entry uses the control center command"
else
    fail "desktop entry has the wrong Exec"
fi

# 3. The theme uses matugen colors, the installed font and flat rows.
if grep -q '@import "colors.rasi"' "$RASI" \
    && grep -q 'Inter 13' "$RASI" \
    && grep -q '@primary' "$RASI"; then
    pass "rofi theme uses matugen colors and Inter 13"
else
    fail "rofi theme is not wired to colors.rasi"
fi

if grep -A4 'element normal.normal' "$RASI" | grep -q 'background-color: *transparent' \
    && grep -A4 'element alternate.normal' "$RASI" | grep -q 'background-color: *transparent'; then
    pass "rows are flat like the other rofi menus"
else
    fail "rows still draw their own fill"
fi

# 3b. Rofi 2.x paints element-text white unless the theme overrides it, so every
# themed menu needs an explicit transparent background.
for theme in \
    "$ROOT/modules/rofi/home/.config/rofi/launcher.rasi" \
    "$ROOT/modules/rofi/home/.config/rofi/powermenu.rasi" \
    "$RASI"; do
    if awk '/^element-text *\{/,/^\}/' "$theme" | grep -q 'background-color: *transparent'; then
        pass "$(basename "$theme") keeps element-text transparent"
    else
        fail "$(basename "$theme") leaves element-text white"
    fi
done

# 3c. Message and history popups reuse the same palette.
# shellcheck disable=SC2016 # literal shell text is being checked
if grep -q 'args=(-theme "$THEME"' "$CC"; then
    pass "info messages use the control center theme"
else
    fail "info messages fall back to the default white theme"
fi
if grep -q 'launcher.rasi' "$ROOT/modules/rofi/home/.config/rofi/scripts/rofi-dunst-history.sh" \
    && grep -q 'launcher.rasi' "$ROOT/modules/rofi/home/.local/bin/clipboard-menu.sh"; then
    pass "history and clipboard menus use the launcher theme"
else
    fail "history or clipboard menus fall back to the default theme"
fi

# 3d. Rofi windows shrink to their contents.
if grep -q -- '-no-fixed-num-lines' "$CC" \
    && grep -q 'fixed-height: *false' "$RASI" \
    && grep -q 'max \* 9 + 140' "$CC"; then
    pass "rofi windows size to their contents"
else
    fail "rofi windows keep a fixed size"
fi
if grep -q 'prompt { enabled: false; }' "$CC" \
    && grep -q 'entry { placeholder:' "$CC"; then
    pass "page names live inside the search field"
else
    fail "page names still draw a separate label"
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

# 5. Docs and configuration expose real data instead of empty pages.
docs_block="$(awk '/^docs_page\(\)/,/^}/' "$CC")"
if grep -q '"Versions"' <<<"$docs_block" \
    && grep -q '"Links"' <<<"$docs_block" \
    && grep -q 'hyprctl version' "$CC" \
    && grep -q 'fish --version' "$CC"; then
    pass "docs cover versions, keybinds and links"
else
    fail "docs are incomplete"
fi

if grep -q '"Config files"' "$CC" \
    && grep -q '"Hyprland"' "$CC" \
    && grep -q '"Fish"' "$CC" \
    && grep -q '"Waybar layout"' "$CC"; then
    pass "configuration exposes the main text configs"
else
    fail "configuration does not expose the main configs"
fi

if grep -q 'tide configure' "$CC"; then
    pass "Tide is configured on the machine"
else
    fail "Tide configuration is missing"
fi

# 5a. Menu wording and the leaf actions that should close the panel.
menu_block="$(awk '/^menu_page\(\)/,/^}/' "$CC")"
if grep -q 'Toggle notifications' <<<"$menu_block" \
    && ! grep -q 'Apply idle' <<<"$menu_block" \
    && ! grep -q 'Game mode status' <<<"$menu_block" \
    && grep -q 'Autostart") run_terminal' <<<"$menu_block"; then
    pass "menu entries are toggles and autostart uses a terminal"
else
    fail "menu wording is stale"
fi

# 5b. Info pages are normal, readable rows instead of a plain rofi -e block.
if grep -q '^show_info()' "$CC" \
    && grep -q 'show_info "Versions"' "$CC" \
    && grep -q 'show_info "Fonts and icons"' "$CC"; then
    pass "versions and font details render as readable rows"
else
    fail "info pages still use an unreadable message block"
fi

# 5c. The colour-scheme menu is curated and labelled with icons.
scheme_block="$(awk '/^theme_scheme_page\(\)/,/^}/' "$CC")"
if grep -q 'Tonal spot' <<<"$scheme_block" \
    && grep -q 'Vibrant' <<<"$scheme_block" \
    && grep -q 'Monochrome' <<<"$scheme_block" \
    && ! grep -q 'scheme-rainbow' <<<"$scheme_block"; then
    pass "the colour scheme menu is curated"
else
    fail "the colour scheme menu still lists every scheme"
fi

# 5d. Wallpapers use large cards with the name under the photo.
if grep -q '^make_wallpaper_card()' "$CC" \
    && grep -q 'caption:' "$CC" \
    && grep -q 'element-icon { size: 300px; }' "$CC"; then
    pass "wallpapers use large named cards"
else
    fail "wallpapers still use small icons"
fi

# 5e. The large menu keeps every entry on screen.
if grep -q 'lines: *20;' "$RASI"; then
    pass "the menu can show twenty rows"
else
    fail "the menu still scrolls for a normal page"
fi

# 6. Install and uninstall use fzf when it is available.
if grep -q 'pacman -Slq | fzf' "$CC" \
    && grep -q -- '-Slq | fzf' "$CC" \
    && grep -q 'pacman -Qqe | fzf' "$CC" \
    && grep -q 'pacman -Qq | fzf' "$CC" \
    && grep -q 'lazydocker' "$CC"; then
    pass "repo, AUR, removal and inspection use fzf"
else
    fail "fzf install, removal or inspection is missing"
fi

# 7. The update page covers repos, AUR, mirrors, dotfiles and Spicetify.
if grep -q '"Repositories"' <<<"$update_block" \
    && grep -q '"Repositories and AUR"' <<<"$update_block" \
    && grep -q '"Apply configs"' <<<"$update_block" \
    && grep -q 'sudo pacman -Syu' <<<"$update_block" \
    && grep -q 'keyserver hkps://pgp.surf.nl' "$CC"; then
    pass "system and dotfiles updates are wired"
else
    fail "system or dotfiles updates are incomplete"
fi

if grep -q 'Mirrors' <<<"$update_block" \
    && grep -q 'reflector --latest 20 --protocol https --sort rate' <<<"$update_block" \
    && grep -q 'mirrorlist.bak' <<<"$update_block"; then
    pass "mirror refresh is wired to reflector with a backup"
else
    fail "mirror refresh is missing"
fi

# 8. Daily actions call helpers directly, not the installer menu.
if grep -q 'autostart.sh pick' "$CC" \
    && grep -q 'gamemode.sh toggle' "$CC" \
    && grep -q 'idle-tune.sh' "$CC" \
    && grep -q 'monitor-profiles.sh' "$CC" \
    && grep -q 'powermenu.sh' "$CC"; then
    pass "daily actions use the per-feature helpers"
else
    fail "a daily action is not wired to its helper"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
