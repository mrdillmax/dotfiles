# dotfiles

Особисті dotfiles для Arch Linux + Hyprland (Lua-конфіг) + uwsm — для
стаціонарного ПК та ноутбука. Репозиторій є джерелом істини; інсталятор
рендерить машинозалежні значення, а решту файлів лінкує в `$HOME`.

- **Композитор:** Hyprland 0.57 з Lua-конфігурацією
- **Сесія:** uwsm
- **Оболонка:** fish
- **Панель / лаунчер / сповіщення:** waybar, rofi, dunst
- **Темізація:** шаблони matugen (згенеровані кольори не комітяться)
- **Пакети:** pacman + AUR-хелпер (`yay` або `paru`)

Англійська документація: [README.md](README.md).  
Посібник зі встановлення: [docs/arch-install.uk.md](docs/arch-install.uk.md).  
Результати аудиту та відкладені виправлення: [AUDIT.md](AUDIT.md).

## Безпека

- Живі конфіги не змінюються самим репозиторієм.
- Інсталятор **бекапить кожен замінений файл** у
  `~/.dotfiles-backup/<РРРР-ММ-ДД_ГГХХСС>/` і пише `manifest.tsv`.
- `--dry-run` лише показує дії й нічого не змінює.
- Файли `/etc` встановлюються **тільки** з `--system`, по одному.
- `grub`, `mkinitcpio` і autologin getty вимагають додаткового явного
  підтвердження. Інсталятор ніколи не запускає `grub-mkconfig` чи `mkinitcpio`.
- Сервіси не запускаються й не перезапускаються автоматично.
- Секрети виключені з git: `pihole.toml`, конфіги rclone/rustdesk/opencode/
  omniroute, `.env`, ключі та весь каталог `personal/`.
- Згенеровані matugen-файли виключені; комітяться лише шаблони й
  `matugen/config.toml`.

## Вимоги

- Arch Linux (або Arch-based) з `pacman`
- `git`, `jq`, `bash` 5.x
- Бажано: `gum` (TUI), `shellcheck` (lint), `yay`/`paru` (AUR)
- Для GPU-профілів — відповідні драйвери (`packages/nvidia.txt`, Mesa для
  AMD/Intel тощо)

## Швидкий старт

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

make lint                 # bash -n + shellcheck
make dry-run              # повний прев'ю-інстал, нічого не змінює
./install.sh              # інтерактивний інсталятор
```

Типовий перший запуск:

```bash
./install.sh --host desktop --gpu nvidia --modules hypr,uwsm,waybar,rofi,kitty,fish
./install.sh --monitors   # визначити й записати розкладку моніторів
fish -c 'fisher update'   # встановити плагіни tide
make theme WALLPAPER=~/Pictures/wallpaper.jpg
```

## Структура

```text
.
├── install.sh                 інсталятор і точка входу
├── lib/                       common, TUI, monitors, packages, system, secrets
├── profiles/gpu/              nvidia, amd, intel, hybrid, vm, software
├── hosts/
│   ├── desktop/               monitors.conf.sh, input.lua, env хоста
│   └── laptop/                батарея/яскравість/тачпад/кришка
├── modules/<name>/home/...    файли, що лінкуються або рендеряться в $HOME
├── system/                    опційні /etc-файли (--system)
├── packages/                  групи пакетів + реєстр альтернатив
├── scripts/                   audit, обгортка mouse-tune
├── personal/                  приватні файли, gitignored
├── docs/                      посібник зі встановлення Arch (EN/UK)
├── Makefile
├── README.md / README.uk.md
└── AUDIT.md
```

## Інсталятор

```text
./install.sh [опції]

  --all                 усі модулі й групи пакетів
  --dry-run             показати дії, нічого не змінювати
  --yes, -y             відповідати "так" на підтвердження
  --modules a,b,c       лише ці модулі
  --no-packages         пропустити встановлення пакетів
  --host desktop|laptop перевизначити тип хоста
  --gpu PROFILE         nvidia|amd|intel|hybrid|vm|software
  --monitors            переналаштувати монітори й вийти
  --mouse               запустити тюнер миші/тачпада
  --cursor              встановити/налаштувати тему курсора й вийти
  --cursor-archive PATH встановити тему курсора з локального архіву (не комітиться)
  --cursor-theme NAME   назва теми курсора (типово: host cursor.conf)
  --cursor-size N       розмір курсора 16..128 (типово: 24)
  --wallpaper PATH      записати шлях до шпалер і за бажанням застосувати
  --system              встановити /etc-файли (запускати через sudo)
  --iface IFACE         мережевий інтерфейс для Pi-hole (рендер @IFACE@)
  --kernel              визначити рівень CPU і встановити відповідне ядро
  --kernel-level LEVEL  перевизначити рівень ядра: v1..v4
  --list                список модулів, GPU-профілів і груп пакетів
  -h, --help            довідка
```

`--all` — це **модулі + пакети**, без `/etc`. Системні файли завжди окремо,
через `--system`.

Тип хоста визначається за `/sys/class/power_supply/BAT*` і DMI chassis type,
GPU-профіль — через `lspci`/`systemd-detect-virt`. Обидва можна перевизначити.
З `gum` вибір інтерактивний, без нього — звичайні нумеровані пункти.

### Модулі

| Модуль | Що встановлює |
|--------|----------------|
| `hypr` | Lua-конфіг Hyprland, бінди, автозапуск, правила вікон, згенеровані монітори |
| `uwsm` | `~/.config/uwsm/env` (common + GPU-профіль) і `env-hyprland` |
| `waybar` | конфіг, стиль і скрипти панелі |
| `rofi` | лаунчер, power menu, історія dunst |
| `kitty` | конфіг термінала |
| `fish` | конфіг fish, аліаси, список плгінів tide |
| `dunst` | демон сповіщень (кольори генерує matugen) |
| `matugen` | шаблони й `config.toml` (без згенерованих кольорів) |
| `theming` | GTK/Qt/KDE налаштування і symlink-и adw-gtk3 |
| `cursor` | тема/розмір курсора в uwsm, GTK3/4, Qt, xsettingsd і Hyprland |
| `scripts` | допоміжні скрипти в `~/.local/bin` |
| `systemd-user` | rclone sync, бекап omniroute, сервіс invite-site |
| `apps` | btop, micro, spicetify, vesktop, Firefox chrome, dolphinrc |
| `workspaces-split` | воркспейси на монітор; пропонується лише за 2+ моніторів |
| `mouse-sensitivity` | інтерактивний тюнер і overlay для input |

### Профілі хостів

| Хост | Визначення | Особливості |
|------|------------|-------------|
| `desktop` | немає батареї | NVIDIA-профіль, доступний двомоніторний пресет |
| `laptop` | є батарея | батарея, яскравість, тачпад, кришка/suspend, power-profiles-daemon, `eDP-*` |

### GPU-профілі

| Профіль | Середовище |
|---------|------------|
| `nvidia` | `LIBVA_DRIVER_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `NVD_BACKEND=direct` |
| `amd` | `LIBVA_DRIVER_NAME=radeonsi` |
| `intel` | `LIBVA_DRIVER_NAME=iHD` (або `i965` для старого заліза) |
| `hybrid` | NVIDIA-змінні + `__NV_PRIME_RENDER_OFFLOAD=1`, `__VK_LAYER_NV_optimus=NVIDIA_only`; `AQ_DRM_DEVICES` задається на хості |
| `vm` | без vendor-змінних; опційно `AQ_NO_KMS_REQUIREMENT=1` |
| `software` | `LIBGL_ALWAYS_SOFTWARE=1` |

Вибраний профіль додається до `modules/uwsm/home/.config/uwsm/env.common` і
рендериться в `~/.config/uwsm/env`. `env-hyprland` окремий, щоб `HYPR*`/`AQ_*`
не потрапляли в інші сесії.

## Монітори

Єдине джерело істини — `hosts/<host>/monitors.conf.sh`. З нього інсталятор
рендерить:

- `~/.config/hypr/monitors.lua` — викликає `hl.monitor()` і
  `hl.workspace_rule()` та повертає список моніторів;
- `~/.config/hypr/monitors.conf.sh` — копію, яку читає `switch_ws.sh`.

`hyprland.lua` підключає `monitors.lua` через `pcall(dofile, ...)`. Якщо файла
немає або він невалідний, використовується fallback `preferred,auto,1`, тому
свіжа інсталяція все одно стартує.

`./install.sh --monitors` визначає підключені виходи (`hyprctl monitors`, далі
`/sys/class/drm`) і пропонує:

1. один монітор;
2. два й більше — вибір порядку зліва направо та позицій;
3. авто (`preferred`, автоматичні позиції);
4. пресет `dill-desktop` (`HDMI-A-2` ліворуч, `DP-1` праворуч, обидва
   1920x1080@60, воркспейси 1–10 і 11–20);
5. ручне редагування `hosts/<host>/monitors.conf.sh`.

Для ноутбука підтримується fractional scale і будь-яка панель `eDP-*`;
поведінка кришки й зовнішнього монітора — у профілі `laptop`.

Модуль `workspaces-split` пропонується лише коли знайдено 2+ монітори. Він
встановлює `~/.config/hypr/switch_ws.sh`, який читає імена моніторів і
діапазони воркспейсів зі згенерованого `monitors.conf.sh` — нічого не
захардкожено. Без модуля `SUPER+1..0` використовує рідні диспетчери Hyprland.
Поточна двомоніторна логіка власника збережена як пресет `dill-desktop`.
Живий `switch_ws.sh` працює, перевірено; це не баг.

## Тюнер миші й тачпада

```bash
make mouse
./install.sh --mouse
~/.local/bin/mouse-tune.sh          # після інсталяції
./scripts/mouse-tune.sh --show      # лише читання поточних значень
```

Тюнер потребує запущеного Hyprland і використовує Lua runtime API:

```bash
hyprctl eval 'hl.config({ input = { sensitivity = -0.3 } })'
hyprctl eval 'hl.device({ name = "...", sensitivity = -0.2 })'
```

Що можна змінити на льоту:

- `input:sensitivity` у `-1.0…1.0`, крок `0.05`, дрібний `0.01` (`f`);
- `input:accel_profile` (`flat` / `adaptive` / default);
- `input:force_no_accel`;
- `input:scroll_factor`;
- окремі налаштування для пристрою з `hyprctl devices` (чутливість,
  прискорення, скрол);
- тачпад ноутбука: `natural_scroll`, `tap_to_click`,
  `disable_while_typing`.

Клавіші в live-слайдері: `←`/`→` або `-`/`+` змінюють значення, `f` перемикає
дрібний крок, `r` повертає значення сесії, `Enter`/`q` завершує.

> **Важливо:** у старих версіях Hyprland `scroll_factor` для миші може бути
> відсутній. Тюнер показує його лише тоді, коли `hyprctl getoption` його
> повертає.

«Зберегти» пише лише в `hosts/<host>/input.lua` у репозиторії (або в
`~/.config/hypr/input.lua`, якщо репозиторій не знайдено). Перед записом
показується unified diff, запитується підтвердження і створюється бекап.
Живий `hyprland.lua` не редагується. Overlay підключається так:

```lua
pcall(dofile, HOME .. "/.config/hypr/input.lua")
```

тому відсутній файл безпечний.

## Пакети

Групи лежать у `packages/<category>.txt`. Інсталятор дає вибрати групи й
позначає альтернативи:

- `[main, config]` — власник реально користується, і конфіг є в репозиторії;
- `[package only]` — лише пакет, конфігу в репозиторії немає.

| Категорія         | Основна (конфіг є)   | Аналоги (лише пакет)                        |
| ----------------- | -------------------- | ------------------------------------------- |
| термінал          | kitty                | foot, alacritty, wezterm, ghostty           |
| лаунчер           | rofi                 | fuzzel, wofi, anyrun                        |
| статус-бар        | waybar               | hyprpanel, ags                              |
| сповіщення        | dunst                | mako, swaync                                |
| браузер           | firefox              | chromium, brave-bin, librewolf              |
| файловий менеджер | dolphin              | nautilus, thunar, yazi                      |
| системний монітор | btop                 | htop, bottom                                |
| редактор          | micro                | neovim, kate                                |
| музика            | spotify-launcher     | amberol, elisa                              |
| ядро              | керується `--kernel` | linux, linux-lts, linux-zen, linux-hardened |

Огляд груп:

| Група | Вміст |
|-------|-------|
| `base.txt` | завантаження, диски, CLI-інструменти |
| `hyprland.txt` | композитор, портали, Wayland-утиліти, темізація |
| `shell.txt` | fish + fisher |
| `audio.txt` | PipeWire, Carla, Guitarix, REAPER |
| `desktop.txt` | щоденні GUI-програми |
| `media.txt` | CLI-інструменти для зображень/прев'ю |
| `dev.txt` | компілятори, SDK, редактори |
| `network.txt` | NetworkManager, Pi-hole, Unbound, rclone, ZeroTier |
| `virtualization.txt` | Docker, libvirt/QEMU, Steam, Wine, Waydroid |
| `nvidia.txt` | NVIDIA 580xx і моніторинг |
| `tuning.txt` | CPU/IO-тюнінг і стрес-тести |
| `fonts.txt` | шрифти й українська локалізація |
| `aur.txt` | лише AUR-пакети |

`install.sh --no-packages` повністю пропускає цей крок.

### Ядро за рівнем CPU

```bash
./install.sh --kernel
```

Інсталятор визначає рівень x86-64 (`v1`..`v4`) і пропонує ядра не вище нього:
`linux-lts` (резервне), `linux`, `linux-zen` і відповідний xanmod на десктопах.
Ноутбуки трактуються консервативно. Рівень вище CPU вимагає червоного
попередження й введення `I UNDERSTAND`; неінтерактивний режим його відхиляє.
Поточне й резервне ядра ніколи не видаляються.

NVIDIA DKMS завжди отримує відповідні headers. Інсталятор друкує команди
`mkinitcpio`/`grub-mkconfig` і ніколи їх не запускає. `make doctor` порівнює
рівень CPU з рівнем встановленого ядра.

## Темізація

Кольори генеруються matugen з шпалер:

```bash
make theme WALLPAPER=~/Pictures/wallpaper.jpg
```

Без `WALLPAPER` `make theme` спершу читає
`~/.config/hypr/wallpaper.path` (його пише `./install.sh --wallpaper`), а потім
поле `image` з `~/.config/hypr/colors.lua`. Сам файл зображення не комітиться.
Згенеровані файли ігноруються git:

- `~/.config/hypr/colors.lua`
- кольори waybar/rofi/kitty/dunst
- схеми GTK/Qt
- виводи btop/micro/spicetify/vesktop
- Firefox `colors.css`

Комітяться лише `matugen/config.toml` і шаблони в
`modules/matugen/home/.config/matugen/templates/`. GTK4 `gtk.css`,
`gtk-dark.css` і `assets` — це symlink-и на
`/usr/share/themes/adw-gtk3-dark/gtk-4.0/`; модуль `theming` їх відтворює.

## Системні конфіги (`--system`)

Запускати від root:

```bash
sudo ./install.sh --system --iface eno1
```

Лише цей режим пише `/etc`, по одному файлу, після бекапу. `@IFACE@`
рендериться з `--iface`, далі з інтерфейсу default-route, далі з інтерактивного
запиту. Якщо жодного немає — файл пропускається з помилкою; `enp9s0` ніколи не
підставляється в універсальні шаблони.

Маніфест:

| Джерело | Призначення |
|---------|-------------|
| `system/zram/zram-generator.conf` | `/etc/systemd/zram-generator.conf` |
| `system/cpupower/cpupower` | `/etc/default/cpupower` |
| `system/networkmanager/dns.conf` | `/etc/NetworkManager/conf.d/dns.conf` (лише з Pi-hole + Unbound) |
| `system/networkmanager/rc-manager.conf` | `/etc/NetworkManager/conf.d/rc-manager.conf` (лише з Pi-hole + Unbound) |
| `system/unbound/unbound.conf` | `/etc/unbound/unbound.conf` |
| `system/pihole/dnsmasq.conf` | `/etc/pihole/dnsmasq.conf` |
| `system/pihole/pihole.toml.example` | `/etc/pihole/pihole.toml` (лише після перевірки) |
| `system/wait-iface/wait-iface.sh` | `/usr/local/bin/wait-iface.sh` |
| `system/systemd/...` | `/etc/systemd/system/...` |
| `system/grub/default-grub` | `/etc/default/grub` (додаткове підтвердження) |
| `system/mkinitcpio/mkinitcpio.conf` | `/etc/mkinitcpio.conf` (додаткове підтвердження) |
| `system/modprobe/*` | `/etc/modprobe.d/*` |
| `system/sysctl/*` | `/etc/sysctl.d/*` |

`pacman.conf` і `makepkg.conf` не копіюються, а зливаються: інсталятор показує
diff, питає підтвердження і створює бекап. З `--yes` злиття пропускається.
Опційні сервіси лише вмикаються через `systemctl enable`, без `start` чи
`restart`.

UFW — лише документація. Репозиторій не змінює стан фаєрвола чи правила; див.
`system/ufw/README.md` із зафіксованим живим станом.

Поза репозиторієм: `/etc/fstab`, профілі NetworkManager, конфігурація snapper.
Інсталятор ніколи не запускає `grub-mkconfig` чи `mkinitcpio -P`; він лише
друкує команди для ручної перевірки. Робота з ядром — окремо через
`./install.sh --kernel`; `--system` лише звітує про drift CPU/ядра.

Сам `pihole.toml` виключений. У прикладі порожні `pwhash`, `totp_secret`,
`app_pwhash` і `cli_pw = false`; перегляньте його і додайте секрети самі.

## Бекапи й відновлення

Кожен замінений файл копіюється в:

```text
~/.dotfiles-backup/<РРРР-ММ-ДД_ГГХХСС>/<шлях відносно $HOME>
~/.dotfiles-backup/<РРРР-ММ-ДД_ГГХХСС>/manifest.tsv
```

Відновлення:

```bash
cp -a ~/.dotfiles-backup/2026-11-16_120000/.config/hypr/hyprland.lua \
      ~/.config/hypr/hyprland.lua
```

Керовані шляхи записуються в
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/managed.tsv`. Нічого не видаляється
автоматично.

## Аудит і lint

```bash
make lint     # bash -n + shellcheck
make audit    # read-only аудит живої системи й репозиторію
make doctor   # рівень CPU/ядра, курсор, шпалери, керовані symlink-и
make check    # lint + audit + doctor
```

Аудит перевіряє помилки конфігу Hyprland, дублі біндів, переносимість
моніторів, захардкожені home-шляхи, systemd-юніти, синтаксис Unbound,
`.pacnew`, секрети, згенеровані файли та відповідність рівня CPU рівню
встановленого ядра. Він нічого не редагує й не потребує root.

## Секрети, які треба ротувати

Під час міграції були видні такі дані; вважайте їх скомпрометованими й
замініть вручну:

- API-ключ/пароль OpenCode;
- токен rclone (`~/.config/rclone/rclone.conf`);
- дані RustDesk.

Вони навмисно не входять до репозиторію. Комітяться лише `.example`-шаблони.

## Ліцензія

Файл ліцензії ще не додано. Додайте його перед публікацією репозиторію.
