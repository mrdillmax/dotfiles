#!/usr/bin/env bash
# Unified appearance: source values, generated templates and toolkit wiring.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME="$ROOT/modules/theming"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# 1. One source for the appearance values.
for host in desktop laptop; do
    file="$ROOT/hosts/$host/appearance.conf"
    if grep -q '^UI_FONT="Inter"' "$file" \
        && grep -q '^MONO_FONT="JetBrainsMono Nerd Font"' "$file" \
        && grep -q '^ICON_THEME="breeze-dark"' "$file"; then
        pass "$host appearance values are set"
    else
        fail "$host appearance values are incomplete"
    fi
done

# 2. GTK templates use the shared values and import matugen colors.
if grep -q '@GTK_THEME@' "$THEME/home/.config/gtk-3.0/settings.ini.in" \
    && grep -q '@ICON_THEME@' "$THEME/home/.config/gtk-3.0/settings.ini.in" \
    && grep -q '@UI_FONT@ @UI_SIZE@' "$THEME/home/.config/gtk-4.0/settings.ini.in"; then
    pass "GTK settings are rendered from appearance.conf"
else
    fail "GTK settings still hardcode a theme, icon set or font"
fi

if grep -q 'colors.css' "$THEME/home/.config/gtk-4.0/gtk.css.in" \
    && grep -q '/usr/share/themes/@GTK_THEME@/gtk-4.0/libadwaita.css' "$THEME/home/.config/gtk-4.0/gtk.css.in"; then
    pass "GTK4 stylesheet imports colors and the selected theme"
else
    fail "GTK4 stylesheet is incomplete"
fi

# 3. Qt uses Fusion, the same fonts and the Matugen palette.
for qt in qt5ct qt6ct; do
    file="$THEME/home/.config/$qt/$qt.conf.in"
    if grep -q '^style=Fusion' "$file" \
        && grep -q '^icon_theme=@ICON_THEME@' "$file" \
        && grep -q 'color_scheme_path=@HOME@/.local/share/color-schemes/Matugen.colors' "$file" \
        && grep -q '@QT_UI_FONT' "$file"; then
        pass "$qt uses Fusion and the Matugen palette"
    else
        fail "$qt is not wired to the shared appearance"
    fi
done

if grep -q '^ColorScheme=Matugen' "$THEME/home/.config/kdeglobals.in" \
    && grep -q '^widgetStyle=Fusion' "$THEME/home/.config/kdeglobals.in" \
    && grep -q '^Theme=@ICON_THEME@' "$THEME/home/.config/kdeglobals.in"; then
    pass "KDE applications use the Matugen scheme and Fusion"
else
    fail "kdeglobals is not unified"
fi

if grep -q '^TerminalApplication=@TERMINAL_APP@' "$THEME/home/.config/kdeglobals.in" \
    && grep -q '^TerminalService=@TERMINAL_SERVICE@' "$THEME/home/.config/kdeglobals.in"; then
    pass "kdeglobals records the default terminal"
else
    fail "kdeglobals does not record the default terminal"
fi

# 4. Portal backends are explicit.
portal="$THEME/home/.config/xdg-desktop-portal/portals.conf.in"
if grep -q '^default=hyprland;gtk' "$portal" \
    && grep -q 'FileChooser=gtk' "$portal" \
    && grep -q 'Settings=gtk' "$portal" \
    && grep -q 'ScreenCast=hyprland' "$portal" \
    && grep -q 'Screenshot=hyprland' "$portal"; then
    pass "portal backends are explicit"
else
    fail "portal backends are incomplete"
fi

# 5. Fonts and Qt5 wrapper.
if grep -q 'sans-serif' "$THEME/home/.config/fontconfig/fonts.conf.in" \
    && grep -q '@UI_FONT@' "$THEME/home/.config/fontconfig/fonts.conf.in" \
    && grep -q 'QT_QPA_PLATFORMTHEME=qt5ct' "$THEME/home/.local/bin/qt5-app"; then
    pass "fontconfig aliases and the Qt5 wrapper are present"
else
    fail "fontconfig or the Qt5 wrapper is missing"
fi

# 6. No old hardcoded font or icon names in the generated configs.
if grep -RIn 'JetBrains Mono NerdFont\|JetBrains Mono Regular\|icon_theme = Papirus' "$ROOT/modules" >/dev/null; then
    fail "an old font or icon name is still hardcoded"
else
    pass "old font and icon names are gone"
fi

# 7. The session PATH contains the user bin directory.
# shellcheck disable=SC2016 # literal shell text in the rendered file
if grep -q 'export PATH="\$HOME/.spicetify:\$HOME/.local/bin:\$PATH"' "$ROOT/modules/uwsm/env.common" \
    && grep -q 'fish_add_path \$HOME/.local/bin' "$ROOT/modules/fish/home/.config/fish/config.fish"; then
    pass "the user bin directory is on the session PATH"
else
    fail "the user bin directory is not on the session PATH"
fi

# 7. One UI font everywhere; the mono face stays in terminals and editors.
if grep -q '^font=@QT_UI_FONT5@' "$THEME/home/.config/kdeglobals.in"; then
    pass "KDE applications inherit the shared UI font"
else
    fail "kdeglobals has no shared font"
fi
for file in \
    "$ROOT/modules/rofi/home/.config/rofi/launcher.rasi" \
    "$ROOT/modules/rofi/home/.config/rofi/powermenu.rasi" \
    "$ROOT/modules/control-center/home/.config/rofi/control-center.rasi"; do
    if grep -q '"Inter' "$file"; then
        pass "$(basename "$file") uses Inter"
    else
        fail "$(basename "$file") uses a different font"
    fi
done
if grep -q '"Inter", "JetBrainsMono Nerd Font"' "$ROOT/modules/waybar/home/.config/waybar/style.css"; then
    pass "waybar uses Inter with Nerd Font glyphs"
else
    fail "waybar does not use the UI font"
fi
if grep -q '^    font = Inter 11' "$ROOT/modules/matugen/home/.config/matugen/templates/dunstrc"; then
    pass "notifications use the UI font"
else
    fail "notifications use a different font"
fi
if grep -q 'font_family = Inter' "$ROOT/modules/idle/home/.config/hypr/hyprlock.conf"; then
    pass "the lock screen uses the UI font"
else
    fail "the lock screen does not use the UI font"
fi
for script in \
    "$ROOT/modules/theme-menu/home/.local/bin/theme-menu.sh" \
    "$ROOT/modules/autostart/home/.local/bin/autostart.sh" \
    "$ROOT/modules/binds-cheatsheet/home/.local/bin/binds-cheatsheet.sh"; do
    if grep -q 'rofi/launcher.rasi' "$script"; then
        pass "$(basename "$script") menus use the shared rofi theme"
    else
        fail "$(basename "$script") menus use the default rofi font"
    fi
done

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
