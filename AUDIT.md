# AUDIT — поточний стан конфігурації

Дата: 2026-11-16  
Система: Arch Linux, Hyprland 0.57.2 (Lua-конфіг), uwsm 0.27.2, NVIDIA 580xx  
Метод: лише читання (`hyprctl`, `unbound-checkconf`, `systemd-analyze verify`, `grep`, `git`).
Живі файли під час аудиту не редагувалися, не переміщалися і не видалялися.

Єдиний вплив на сесію — дозволений no-op тест рантайм-застосування: `input:sensitivity`
на мить встановлювалась у `-0.31`, потім повернута до поточного `-0.3`. Інші
input-параметри до і після тесту збігаються. Нічого не збережено і не перезавантажено.

## Підсумок

| ID | Серйозність | Проблема |
|----|-------------|----------|
| A-01 | середня | Дубльований бінд `SUPER + H` |
| A-02 | середня | Зайва `GB_ALLOCATOR=minigbm` у uwsm env |
| A-03 | висока (гігієна) | Копія `pihole.toml` у корені репо, права `777 root:root` |
| A-04 | середня | Незамержені `.pacnew` (unbound, mirrorlist) |
| A-05 | середня | `enp9s0` захардкожено в dnsmasq і wait-iface |
| A-06 | низька | Pi-hole rate limit збільшено до 5000/60 |
| A-07 | середня | Імена моніторів захардкожені в живих конфігах |
| A-08 | інфо | Поточні input-налаштування та тачпад |
| A-09 | низька | Абсолютні `/home/dill` шляхи в живих конфігах |
| A-10 | низька | `rustup` і `spicetify` поза pacman |
| A-11 | низька | Старий згенерований `chrome/firefox-colors.css` |
| A-12 | інфо | Порожні `~/.config/mpv`, `~/.config/fastfetch` |
| A-13 | інфо | GRUB: `mitigations=off`, TPM blacklist, `nowatchdog` |
| A-14 | інфо | `zirochka-invite` слухає порт 80 як користувач |
| A-15 | інфо | Зайві `XDG_*` у uwsm env |

Позитивні результати:

- `hyprctl configerrors` — без помилок.
- `unbound-checkconf /etc/unbound/unbound.conf` — без помилок.
- `systemd-analyze verify` для юнітів репозиторію — без помилок.
- `switch_ws.sh` працює у власника, перевірено; **не є багом і не потребує змін**.
- GTK4 імпорти, які виглядають «відсутніми», насправді резолвляться через
  symlink-и на `adw-gtk3-dark`; це не помилка.

## Деталі

### A-01. Дубльований `SUPER + H`

`~/.config/hypr/hyprland.lua:199-200`:

```lua
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd(history))
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd('dunstctl history-pop'))
```

`hyprctl binds -j` підтверджує два бінди з `modmask=64`, `key=H`.
Практично працює лише один із них. Рекомендація: залишити один —
або `rofi-dunst-history.sh`, або `dunstctl history-pop`.

### A-02. `GB_ALLOCATOR=minigbm`

`~/.config/uwsm/env` містить `export GB_ALLOCATOR=minigbm`. Для NVIDIA-сесії
це не потрібно і може конфліктувати з `GBM_BACKEND=nvidia-drm`. У репозиторії
`profiles/gpu/nvidia/env` цю змінну не відтворено. Рекомендація: прибрати з
живого env після підтвердження.

### A-03. Копія `pihole.toml` у корені репозиторію

`/home/dill/Projects/dotfiles/pihole.toml`:

- права `777`, власник `root:root`;
- файл уже доданий у `.gitignore` до першого коміту і не відстежується git;
- містить робочу конфігурацію Pi-hole (`cli_pw = true`, порожні `pwhash`,
  `totp_secret`, `app_pwhash`).

Це не частина репозиторію. Рекомендація: видалити копію вручну після перевірки
`sanitized` версії `system/pihole/pihole.toml.example`. Оригінал
`/etc/pihole/pihole.toml` має права `640 pihole:pihole` і не чіпався.

### A-04. `.pacnew`

- `/etc/unbound/unbound.conf.pacnew`
- `/etc/pacman.d/mirrorlist.pacnew`

Для unbound **не можна** просто замінити конфіг на `.pacnew`: живий файл містить
кастомні `interface: 127.0.0.1` і `port: 5335`, а `.pacnew` — шаблонні
закоментовані значення. Потрібне ручне злиття з збереженням цих двох рядків.

### A-05. Захардкожений `enp9s0`

- `/etc/pihole/dnsmasq.conf`: `interface=enp9s0`, `bind-interfaces`.
- `/usr/local/bin/wait-iface.sh`: перевіряє `/sys/class/net/enp9s0`.
- `/etc/systemd/system/pihole-FTL.service.d/wait-net.conf`:
  `Wants/After=sys-subsystem-net-devices-enp9s0.device`.

У репозиторії ці файли вже узагальнено: `wait-iface.sh` визначає інтерфейс
default-route або перший non-loopback, а drop-in більше не згадує `enp9s0`.
Живі файли не змінювалися.

### A-06. Pi-hole rate limit

У робочій копії `pihole.toml`:

```toml
[dns.rateLimit]
count = 5000      # default = 1000
interval = 60
```

Це не помилка, але варто зафіксувати навмисність: 5000 запитів/60 с на клієнта.

### A-07. Імена моніторів у живих конфігах

| Файл | Рядки | Що саме |
|------|-------|---------|
| `~/.config/hypr/hyprland.lua` | 7, 14 | `hl.monitor` для `HDMI-A-2`, `DP-1` |
| `~/.config/hypr/hyprland.lua` | 230-231 | `mon0`, `mon1` для workspace rules |
| `~/.config/hypr/hyprland.lua` | 240, 244 | абсолютний шлях до `switch_ws.sh` |
| `~/.config/sunshine/apps.json` | 5, 13 | `hl.dsp.focus({ monitor="DP-1" })` |
| `~/.config/sunshine/sunshine.conf` | 6 | `output_name = HEADLESS-1` |

У репозиторії:

- `hosts/<host>/monitors.conf.sh` — єдине джерело істини;
- `install.sh` рендерить `~/.config/hypr/monitors.lua` і `monitors.conf.sh`;
- `hyprland.lua` підключає їх через `pcall(dofile, ...)` з fallback
  `preferred,auto,1`;
- `switch_ws.sh` читає імена/діапазони з `monitors.conf.sh`;
- app-workspace правила параметризовані (`app_workspaces`).

Sunshine поки не входить до репозиторію; якщо додавати — `output_name` і
`monitor="DP-1"` треба винести в змінні/шаблон.

### A-08. Поточні input-налаштування

| Параметр | Значення |
|----------|----------|
| `input:sensitivity` | `-0.300000` (`set: true`, задано в `hyprland.lua:179`) |
| `input:accel_profile` | не задано (порожньо) |
| `input:force_no_accel` | `false` |
| `input:scroll_factor` | `1.000000` |
| `input:touchpad:natural_scroll` | `false` |
| `input:touchpad:tap-to-click` | `true` |
| `input:touchpad:disable_while_typing` | `true` |

Інших згадок `sensitivity`, `accel_profile`, `force_no_accel`, `scroll_factor`,
`natural_scroll`, `tap-to-click`, `disable_while_typing` або `device:` у
`~/.config/hypr` і `~/.config/uwsm` немає. Тачпада на цьому хості немає.

### A-09. Абсолютні `/home/dill` у живих конфігах

| Файл | Рядок | Приклад |
|------|-------|---------|
| `~/.config/fish/config.fish` | 93 | `fish_add_path /home/dill/.spicetify` |
| `~/.config/btop/btop.conf` | 5 | `color_theme = "/home/dill/..."` |
| `~/.config/qt5ct/qt5ct.conf` | 2 | `color_scheme_path=/home/dill/...` |
| `~/.config/qt6ct/qt6ct.conf` | 2 | `color_scheme_path=/home/dill/...` |
| `~/.gtkrc-2.0` | 4 | `include "/home/dill/.gtkrc-2.0.mine"` |
| `~/.config/spicetify/config-xpui.ini` | 14, 17 | `prefs_path`, `spotify_path` |
| `~/.config/matugen/config.toml` | 9 | Firefox profile path |
| `~/.config/systemd/user/rclone-sync.service` | 6 | `ExecStart=... /home/dill/...` |
| `~/.config/systemd/user/zirochka-invite.service` | 3, 7, 8 | `Documentation`, `WorkingDirectory`, `ExecStart` |
| `~/.config/hypr/hyprland.lua` | 240, 244 | шлях до `switch_ws.sh` |
| `~/.config/hypr/colors.lua` | — | wallpaper `image = "/home/dill/Картинки/..."` |

У репозиторії статичні шляхи замінені на `$HOME`/`%h`, а шаблони `.in`
рендеряться з `@HOME@`, `@FIREFOX_PROFILE_DIR@`, `@OBSIDIAN_VAULT@`.

### A-10. `rustup` і `spicetify` поза pacman

`rustup` встановлений через `rustup-init` (`~/.cargo/bin/rustup`), `spicetify` —
у `~/.spicetify/spicetify`. Обидва додані в `packages/dev.txt` і
`packages/aur.txt` (`spicetify-cli`), але на чистій системі може знадобитися
ручний bootstrap. Це не помилка поточної системи.

### A-11. Старий згенерований файл Firefox

`~/.config/mozilla/firefox/famcgdw2.default-release/chrome/` містить
`colors.css` (актуальний вихід matugen) і `firefox-colors.css` (старий, 230 B).
Репозиторій зберігає лише шаблон `firefox-colors.css` і не комітить згенеровані
`colors.css`. Рекомендація: видалити застарілий файл вручну.

### A-12. Порожні каталоги

`~/.config/mpv/` і `~/.config/fastfetch/` порожні. У репозиторій не включені.

### A-13. GRUB

`GRUB_CMDLINE_LINUX_DEFAULT` містить:

```
quiet loglevel=2 nvidia_drm.modeset=1 nvidia_drm.fbdev=1
module_blacklist=tpm,tpm_tis,tpm_tis_core mitigations=off nowatchdog psi=1
```

`mitigations=off` і blacklist TPM — свідомий компроміс продуктивності/сумісності.
Варто залишити як є, але пам'ятати про це при оновленні системи.

### A-14. `zirochka-invite` і порт 80

User-сервіс слухає `0.0.0.0:80`. Це працює завдяки
`/etc/sysctl.d/99-invite-port80.conf` (`net.ipv4.ip_unprivileged_port_start=80`).
Сервіс увімкнений і активний. Змін не потрібно.

### A-15. Зайві `XDG_*` у uwsm env

`~/.config/uwsm/env` явно задає `XDG_DATA_HOME` і `XDG_DATA_DIRS`. uwsm/systemd
і так формують типові значення; явне дублювання ускладнює підтримку. У
репозиторії `modules/uwsm/home/.config/uwsm/env.common` ці рядки залишені лише
тому, що вони є в поточній робочій конфігурації; їх можна прибрати окремим
комітом після підтвердження.

## Що вже зроблено в репозиторії (без змін живих файлів)

- `.gitignore` створено до першого коміту; `pihole.toml` ігнорується.
- `install.sh` + `lib/` з бекапами, `--dry-run`, `--all`, `--system`, `--mouse`,
  `--monitors`, `--list`.
- GPU-профілі: `nvidia`, `amd`, `intel`, `hybrid`, `vm`, `software`.
- Host-профілі: `desktop`, `laptop`.
- Модулі: `hypr`, `uwsm`, `waybar`, `rofi`, `kitty`, `fish`, `dunst`, `matugen`,
  `theming`, `scripts`, `systemd-user`, `apps`, `workspaces-split`,
  `mouse-sensitivity`.
- `monitors.conf.sh` як єдине джерело; `monitors.lua` генерується; пресет
  `dill-desktop` збережено.
- `switch_ws.sh` переписано config-driven; живий файл не змінювався.
- `mouse-tune.sh`: інтерактивний TUI, live-застосування через
  `hyprctl eval 'hl.config(...)'`, збереження лише у `hosts/<host>/input.lua`
  після diff + backup + підтвердження.
- Пакети згруповано за категоріями; `alternatives.txt` розділяє
  `[main, config]` і `[package only]`.
- `system/pihole/pihole.toml.example` без хешів/TOTP/app_pwhash; `cli_pw=false`.
- `wait-iface.sh` і `pi-hole` drop-in узагальнено для будь-якого NIC.
- `scripts/audit.sh`, `lib/secrets.sh`, `Makefile` (`lint`, `audit`, `check`,
  `theme`, `mouse`, `monitors`).

## Що НЕ змінено у живих конфігах

Не редагувалися:

- `~/.config/hypr/hyprland.lua`, `switch_ws.sh`, `colors.lua`;
- `~/.config/uwsm/env`, `env-hyprland`;
- `~/.config/{waybar,rofi,kitty,fish,dunst,matugen,theming,apps,systemd/user}`;
- `/etc/unbound`, `/etc/pihole`, `/etc/default/grub`, `/etc/mkinitcpio.conf`,
  `/etc/modprobe.d`, `/etc/sysctl.d`, `/etc/systemd/system`;
- `pihole.toml` (жодна копія не видалялася).

## Рекомендовані наступні кроки (потрібен дозвіл)

1. Прибрати дубль `SUPER + H` у живому `hyprland.lua`.
2. Прибрати `GB_ALLOCATOR=minigbm` з `~/.config/uwsm/env`.
3. Вручну видалити `~/Projects/dotfiles/pihole.toml` після перевірки example.
4. Злити `unbound.conf.pacnew` вручну, зберігши `interface: 127.0.0.1` і
   `port: 5335`.
5. Замінити `enp9s0` у dnsmasq/wait-iface на універсальне визначення (версії
   вже є в репозиторії).
6. За бажанням: додати Sunshine-конфіг у репозиторій з параметризованим
   `output_name`/`monitor`.
7. За бажанням: прибрати зайві `XDG_*` з uwsm env.

Кожен пункт — окремий коміт після явного підтвердження. Цей файл нічого не
виправляє автоматично.
