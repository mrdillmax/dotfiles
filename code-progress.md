# Code Refactor Progress

## Baseline

- Tests: 491 passed, 0 failed
- Lint: ok
- Dry-run saved: dryrun-before.txt

## Files

| # | File | Status | Commit |
|---|------|--------|--------|
| 1 | lib/common.sh | reviewed (clean) | — |
| 2 | lib/tui.sh | reviewed (clean) | — |
| 3 | lib/menu.sh | done | e5dd11c |
| 4 | lib/packages.sh | reviewed (clean) | — |
| 5 | lib/monitors.sh | done | cb573da |
| 6 | lib/kernel.sh | reviewed (clean) | — |
| 7 | lib/system.sh | reviewed (clean) | — |
| 8 | lib/services.sh | reviewed (clean) | — |
| 9 | lib/cursor.sh | done | 25c4d95 |
| 10 | lib/wallpaper.sh | reviewed (clean) | — |
| 11 | lib/theme.sh | reviewed (clean) | — |
| 12 | lib/desktop.sh | reviewed (clean) | — |
| 13 | lib/firefox.sh | reviewed (clean) | — |
| 14 | lib/dock.sh | reviewed (clean) | — |
| 15 | lib/restore.sh | reviewed (clean) | — |
| 16 | lib/uninstall.sh | reviewed (clean) | — |
| 17 | lib/secrets.sh | reviewed (clean) | — |
| 18 | lib/migrate.sh | reviewed (clean) | — |
| 19 | lib/firewall.sh | reviewed (clean) | — |
| 20 | install.sh | reviewed (clean) | — |
| 21 | bootstrap.sh | reviewed (clean) | — |
| 22 | scripts/doctor.sh | reviewed (clean) | — |
| 23 | scripts/pkg-sync.sh | reviewed (clean) | — |
| 24 | scripts/sync.sh | reviewed (clean) | — |
| 25 | scripts/audit.sh | reviewed (clean) | — |
| 26 | scripts/modules-doc.sh | reviewed (clean) | — |
| 27 | scripts/install-hooks.sh | reviewed (clean) | — |
| 28 | scripts/install-spicetify.sh | reviewed (clean) | — |
| 29 | scripts/diagnose-picker.sh | reviewed (clean) | — |
| 30 | scripts/dns-check.sh | reviewed (clean) | — |
| 31 | modules/hypr/home/.local/bin/lock-screen.sh | reviewed (clean) | — |
| 32 | modules/hypr/home/.local/bin/brightness-adjust.sh | reviewed (clean) | — |
| 33 | modules/idle/home/.local/bin/idle-tune.sh | reviewed (clean) | — |
| 34 | modules/idle/home/.local/bin/greeter.sh | reviewed (clean) | — |
| 35 | modules/idle/home/.local/bin/idle-dim.sh | reviewed (clean) | — |
| 36 | modules/battery/home/.local/bin/battery-alert.sh | reviewed (clean) | — |
| 37 | modules/autostart/home/.local/bin/autostart.sh | reviewed (clean) | — |
| 38 | modules/rofi/home/.local/bin/clipboard-menu.sh | reviewed (clean) | — |
| 39 | modules/rofi/home/.local/bin/powermenu.sh | reviewed (clean) | — |
| 40 | modules/rofi/home/.local/bin/dunst-history.sh | reviewed (clean) | — |
| 41 | modules/waybar/home/.local/bin/waybar-units.sh | reviewed (clean) | — |
| 42 | modules/waybar/home/.local/bin/waybar-update.sh | reviewed (clean) | — |
| 43 | modules/waybar/home/.local/bin/waybar-battery.sh | done | a9001c2 |
| 44 | modules/waybar/home/.local/bin/waybar-brightness.sh | done | 3b0af32 |
| 45 | modules/waybar/home/.local/bin/waybar-network.sh | reviewed (clean) | — |
| 46 | modules/mouse-sensitivity/home/.local/bin/mouse-tune.sh | reviewed (clean) | — |
| 47 | modules/theme-menu/home/.local/bin/theme-menu.sh | reviewed (clean) | — |
| 48 | modules/binds-cheatsheet/home/.local/bin/binds-cheatsheet.sh | reviewed (clean) | — |
| 49 | modules/gamemode/home/.local/bin/gamemode.sh | reviewed (clean) | — |
| 50 | modules/monitor-profiles/home/.local/bin/monitor-profiles.sh | reviewed (clean) | — |
| 51 | modules/lid/home/.local/bin/lid-handler.sh | reviewed (clean) | — |
| 52 | modules/nightlight/home/.local/bin/nightlight.sh | done | 11cdbea |
| 53 | modules/recorder/home/.local/bin/record.sh | reviewed (clean) | — |
| 54 | modules/hypr/home/.config/hypr/hyprland.lua | reviewed (clean) | — |
| 55 | modules/control-center/home/.local/bin/dotfiles-control-center | reviewed (clean) | — |
| 56 | modules/control-center/home/.local/bin/dotfiles-update-check.sh | reviewed (clean) | — |
| 57 | modules/ram-cache/home/.local/bin/ramcache | done | b85490f |

## Summary

- **Done (refactored):** 6 files
- **Reviewed (clean, no changes needed):** 51 files
- **Total scanned:** 57 files

## Not touching (public interface)

- modules/*/module.conf — module declaration format
- hosts/<host>/ — host-specific configs
- profiles/gpu/ — GPU profile templates
- system/ — /etc files
- migrations/ — explicitly excluded
- packages/catalog.tsv — data file
- tests/*.sh — test assertions
- .github/ — CI config
