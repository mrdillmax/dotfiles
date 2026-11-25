# Optimize Progress

## High priority (waybar modules, idle, brightness — викликаються часто)
| # | Скрипт | Статус | Примітки |
|---|--------|--------|----------|
| 1 | waybar-battery.sh | ✅ | `cat` → `$(<file)` (1 підпроцес менше) |
| 2 | waybar-brightness.sh | ⏭ skip | вже оптимізований |
| 3 | waybar-network.sh | ⏭ skip | nmcli+ip не об'єднати |
| 4 | waybar-update.sh | ✅ | 2 sed → 1 sed |
| 5 | waybar-units.sh | ✅ | json_escape $() → inline |
| 6 | waybar-dunst.sh | ⬜ | |
| 7 | idle-dim.sh | ⬜ | |
| 8 | idle-tune.sh | ⬜ | |
| 9 | nightlight.sh | ⬜ | |
| 10 | brightness-adjust.sh | ⬜ | |
| 11 | lock-screen.sh | ⬜ | |
| 12 | switch-workspace.sh | ⬜ | |
| 13 | clipboard-menu.sh | ⬜ | |

## Medium priority (викликаються рідше)
| # | Скрипт | Статус | Примітки |
|---|--------|--------|----------|
| 14 | battery-alert.sh | ⬜ | |
| 15 | autostart.sh | ⬜ | |
| 16 | binds-cheatsheet.sh | ⬜ | |
| 17 | lid-handler.sh | ⬜ | |
| 18 | monitor-profiles.sh | ⬜ | |
| 19 | mouse-tune.sh | ⬜ | |
| 20 | theme-menu.sh | ⬜ | |
| 21 | record.sh | ⬜ | |
| 22 | powermenu.sh | ⬜ | |
| 23 | greeter.sh | ⬜ | |

## Low priority (scripts/, lib/ — install-time або рідкісні)
| # | Скрипт | Статус | Примітки |
|---|--------|--------|----------|
| 24 | scripts/audit.sh | ⬜ | |
| 25 | scripts/doctor.sh | ⬜ | |
| 26 | scripts/sync.sh | ⬜ | |
| 27 | scripts/pkg-sync.sh | ⬜ | |
| 28 | lib/common.sh | ⬜ | |
| 29 | lib/menu.sh | ⬜ | |
| 30 | lib/packages.sh | ⬜ | |

## Перевірки
- База: 487 passed, 0 failed
- Last check: N/A
