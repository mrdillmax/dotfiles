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
- **Перевірки:** набір shell-тестів у `tests/`, запускається в CI на Arch-контейнері

Англійська документація: [README.md](README.md).  
Посібник зі встановлення: [docs/arch-install.uk.md](docs/arch-install.uk.md).

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
- Для ноутбука: `hypridle`, `hyprlock` (обидва в `packages/laptop.txt`)
- Для профілів док-станції: `socat`
- Для GPU-профілів — відповідні драйвери (`packages/nvidia.txt`, Mesa для
  AMD/Intel тощо)

## Швидкий старт

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

make lint                 # bash -n + shellcheck
./tests/run.sh            # shell-тести; тимчасовий HOME, живі файли не чіпаються
make dry-run              # повний прев'ю-інстал, нічого не змінює
./install.sh              # інтерактивний інсталятор
```

На машині, де ще немає передумов:

```bash
./bootstrap.sh            # base-devel/git/curl, далі інсталятор
./bootstrap.sh --dry-run  # спершу показати всі команди
```

Типовий перший запуск:

```bash
./install.sh --host desktop --gpu nvidia --modules hypr,uwsm,waybar,rofi,kitty,fish
./install.sh --monitors   # визначити й записати розкладку моніторів
fish -c 'fisher update'   # встановити плагіни tide
make theme WALLPAPER=~/Pictures/wallpaper.jpg
```

## Bootstrap на чистій машині

```bash
./bootstrap.sh --dry-run
./bootstrap.sh
./bootstrap.sh --yes -- --host laptop --gpu intel
```

Bootstrap встановлює лише те, що потрібно інсталятору (`base-devel`, `git`,
`curl`), перевіряє доступність мережі й повідомляє про відсутній AUR-хелпер —
сам його не збирає. Далі запускає `install.sh` (з `--all --yes`, якщо дано
`--yes`) і завершує read-only проходом `--doctor`. Усе після `--`
передається в `install.sh`.

## Структура

```text
.
├── install.sh                 інсталятор і точка входу
├── bootstrap.sh               передумови для чистої машини, далі install.sh
├── lib/                       common, TUI, monitors, packages, system, secrets
├── profiles/gpu/              nvidia, amd, intel, hybrid, vm, software
├── hosts/
│   ├── desktop/               monitors.conf.sh, input.lua, env хоста
│   └── laptop/                батарея/яскравість/тачпад/кришка
├── modules/<name>/home/...    файли, що лінкуються або рендеряться в $HOME
├── system/                    опційні /etc-файли (--system)
├── packages/                  групи пакетів + реєстр альтернатив
├── scripts/                   audit, doctor, sync, pkg-sync, DNS-перевірка
├── tests/                     shell-тести + локальний запуск run.sh
├── .github/workflows/ci.yml   lint + тести в Arch-контейнері
├── personal/                  приватні файли, gitignored
├── docs/                      посібник зі встановлення Arch (EN/UK)
├── Makefile
└── README.md / README.uk.md
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
  --dock-layout LAYOUT  зберегти right|left|mirror|ask для зовнішніх моніторів
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
  --hooks               встановити pre-commit hook репозиторію й вийти
  --doctor              read-only перевірка й вихід (ніколи не потребує sudo)
  --json                машинозчитуваний вивід (з --doctor/--dns-check)
  --dns-check           read-only перевірка DNS-ланцюжка й вихід
  --restore [date]      показати бекапи й відновити один (разом з --modules a,b;
                        для /etc також потрібен --system)
  --sync COMMAND        status|diff|pull|packages
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
| `hypr` | Lua-конфіг Hyprland, бінди, хук автозапуску, правила вікон, згенеровані монітори |
| `autostart` | менеджер стану програм входу (`autostart.sh`, вибір `SUPER+SHIFT+A`) |
| `binds-cheatsheet` | шпаргалка біндів Hyprland (plain, markdown, JSON, rofi) |
| `gamemode` | перемикання анімацій, blur, тіней і заокруглень для ігор |
| `idle` | профілі hypridle для батареї/мережі й хелпер перезавантаження |
| `lid` | безпечна обробка кришки й hyprlock |
| `monitor-profiles` | профілі гарячого підключення док-станції/зовнішнього екрана |
| `theme-menu` | rofi-меню шпалер, режиму matugen і схеми кольорів |
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

### Док-станція й гаряче підключення

Опційний модуль `monitor-profiles` обробляє ноутбук із зовнішнім екраном.
Налаштування зберігається в `~/.config/hypr/monitor-profiles.conf`:

```bash
DOCK_LAYOUT=right      # right|left|mirror|ask
```

Записати через інсталятор або змінити напряму:

```bash
./install.sh --dock-layout right
make monitor-profiles ACTION=status
make monitor-profiles ACTION=apply DRY_RUN=1
make monitor-profiles ACTION=watch
```

`watch` слухає сокет подій Hyprland (`socket2`) через `socat` і об'єднує
сплески, тому док, який реєструє кілька виходів одразу, викликає один прохід
розкладки. `apply` змінює лише поточну сесію й ніколи не переписує конфіги
Hyprland. Перед застосуванням зберігає поточний `hyprctl monitors -j` у
`~/.local/state/dotfiles/monitor-profiles/`. `ask` ніколи не змінює монітори.

> **Не перевірено на реальному док-обладнанні.** Спершу запустіть
> `apply --dry-run` і збережіть знімок моніторів. Якщо реальна розкладка
> виявиться хибною, скористайтеся `./install.sh --restore`.

## Помічники робочого столу

Усі вони дотримуються одного правила: стан живе в
`~/.local/state/dotfiles/`, а не в конфізі композитора.

### Меню теми

```bash
make theme-menu                 # меню rofi/gum/whiptail/dialog/plain
make theme-menu DRY_RUN=1
```

Вибір шпалер, режиму matugen (`dark`/`light`) і схеми кольорів зберігається в
`~/.local/state/dotfiles/theme.conf`; `make theme` може його використати.

### Шпаргалка біндів

```bash
make binds                      # вирівняна таблиця
make binds ROFI=1               # меню rofi
make binds JSON=1               # JSON для скриптів
~/.local/bin/binds-cheatsheet.sh --duplicates
```

Шпаргалка читає Lua-конфіг, бо Hyprland 0.57 з Lua-диспетчерами повертає
непрозорі числові аргументи в `hyprctl binds -j`.

### Gamemode

```bash
make gamemode ACTION=toggle
make gamemode ACTION=status
make gamemode ACTION=on DRY_RUN=1
```

Увімкнення вимикає анімації, blur, тіні й заокруглення. Значення, активні до
першого ввімкнення, читаються через `hyprctl getoption` і зберігаються в
`~/.local/state/dotfiles/gamemode.conf`, тому повторне ввімкнення не перезапише
оригінали, а `off` завжди їх відновлює.

### Idle і блокування

Модуль `idle` рендерить `~/.config/hypr/hypridle.conf` з двох профілів:

| Профіль | Затемнення | Блокування | Екран off | Suspend |
|---------|------------|------------|-----------|---------|
| батарея | 150 | 300 | 330 | 900 |
| мережа | 300 | 600 | 660 | 1800 |

`0` вимикає стадію; увімкнені стадії мають задовольняти
`dim < lock <= off < suspend`. Налаштування — в
`~/.local/state/dotfiles/idle.conf`.

```bash
make idle ACTION=status
make idle ACTION=apply PROFILE=battery
make idle ACTION=configure              # запитує всі вісім значень
make idle ACTION=watch                  # перезастосовує при зміні живлення
```

Попередній `hypridle.conf` бекапиться перед заміною. `hypridle` і `hyprlock`
належать до групи пакетів ноутбука, а не до base.

### Кришка

```bash
make lid ACTION=status
make lid ACTION=closed
make lid ACTION=closed DRY_RUN=1
```

Під час закриття обробник безпосередньо перед дією читає `hyprctl monitors -j`:
якщо є інший активний монітор — вимикає всі виходи `eDP-*`/`LVDS`/`DSI` і
запам'ятовує режим, позицію та масштаб у `~/.local/state/dotfiles/lid.conf`;
інакше засинає через `systemctl`. Відкриття кришки завжди відновлює внутрішню
панель. Конфіг logind не змінюється. Логіку покривають лише синтетичні тести,
не фізичне залізо.

### Автозапуск

```bash
make autostart                        # список
make autostart ACTION=disable NAME=vesktop
make autostart ACTION=add NAME=notes CMD=obsidian
make autostart ACTION=pick            # rofi/gum/whiptail/dialog/plain
```

Записи живуть у `~/.local/state/dotfiles/autostart.tsv` і створюються з 17
вбудованих програм при першому використанні. `hyprland.lua` викликає
`autostart.sh run`; вимкнений запис не стартує наступного входу без редагування
Lua-конфігу. `SUPER+SHIFT+A` відкриває вибір.

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
| `laptop.txt` | hypridle, hyprlock (лише ноутбучні сесії) |
| `aur.txt` | лише AUR-пакети |

`install.sh --no-packages` повністю пропускає цей крок.

### Дрейф пакетів

```bash
make pkg-sync                        # лише звіт
make pkg-sync ACTION=check           # код 1, якщо списки різняться
make pkg-sync ACTION=pull DRY_RUN=1
make pkg-sync ACTION=pull YES=1      # лише додає, ніколи не видаляє
```

`pkg-sync` порівнює явно встановлені пакети зі `packages/*.txt`. `pull` лише
дописує встановлені, але не внесені пакети в `packages/extra-installed.txt`;
він ніколи не видаляє записи й нічого не встановлює. Файли конкретного хоста
порівнюються лише на відповідному хості.

З `--system` репозиторій встановлює pacman-hook, який після кожної транзакції
пакетів оновлює `/var/lib/dotfiles/pkg-sync.stamp`. `status` попереджає, коли
штамп новіший за останній огляд, тож зміни можна розібрати пізніше, а не під
час транзакції.

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

Відновлення вручну:

```bash
cp -a ~/.dotfiles-backup/2026-11-16_120000/.config/hypr/hyprland.lua \
      ~/.config/hypr/hyprland.lua
```

Або через вбудований режим:

```bash
./install.sh --restore                       # список бекапів із кількістю файлів
./install.sh --restore 2026-11-16_120000
make restore RESTORE_DATE=2026-11-16_120000
make restore RESTORE_DATE=2026-11-16_120000 MODULES=hypr DRY_RUN=1
```

Restore читає `manifest.tsv`, показує diff, питає підтвердження й бекапить
поточний стан перед записом. Файли `/etc` відновлюються лише з `--system` і
окремим підтвердженням. Якщо є конфігурація snapper, пропонується знімок перед
відновленням.

Керовані шляхи записуються в
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/managed.tsv`. Нічого не
видаляється автоматично. Інші файли стану в цьому каталозі: `theme.conf`,
`gamemode.conf`, `idle.conf`, `autostart.tsv`, `lid.conf`,
`monitor-profiles/` і `sync-backup/`.

## Синхронізація живих змін назад

Напрямок завжди **жива система → репозиторій**. Під `$HOME` нічого не
записується.

```bash
make sync-status                    # файли, що різняться
make sync-diff SYNC_TARGET=hypr     # unified diff
make sync-pull DRY_RUN=1            # попередній перегляд
make sync-pull YES=1                # записати (diff + скан секретів)
./scripts/sync.sh packages          # порівняти встановлені пакети
```

Pull зворотно рендерить `@HOME@`, `@FIREFOX_PROFILE_DIR@` і
`@OBSIDIAN_VAULT@`, пропускає згенеровані matugen-файли, `personal/` і шляхи
секретів, а перед записом запускає сканер секретів. Копія кожного файла
репозиторію до pull зберігається в
`~/.local/state/dotfiles/sync-backup/<timestamp>/` з `manifest.tsv`.

## Перевірки, тести й CI

```bash
make lint       # bash -n + shellcheck
make audit      # read-only аудит живої системи й репозиторію
make doctor     # рівень CPU/ядра, курсор, шпалери, керовані symlink-и
make dns-check  # resolv.conf -> Pi-hole -> unbound
make check      # lint + audit + doctor
./tests/run.sh  # повний набір shell-тестів
make hooks      # встановити pre-commit hook репозиторію
```

Аудит перевіряє помилки конфігу Hyprland, дублі біндів, переносимість
моніторів, захардкожені home-шляхи, systemd-юніти, синтаксис Unbound,
`.pacnew`, секрети, згенеровані файли та відповідність рівня CPU рівню
встановленого ядра. Він нічого не редагує й не потребує root.

`./install.sh --doctor` — та сама read-only перевірка з доступним `--json`;
`./install.sh --dns-check` перевіряє DNS-ланцюжок і попереджає, що для зміни
resolver-файлів через `--system` потрібна робоча пара Pi-hole/Unbound.

Кожен тест використовує тимчасовий `$HOME`/`XDG_STATE_HOME` і заглушки
системних утиліт, тому живі конфіги, база пакетів і монітори не чіпаються.
Тести restore і sync додатково перевіряють, що живі файли не змінилися, а
бекап створено. `tests/run.sh [pattern] [-v] [--list]` запускає один або всі
файли й ніколи не запускає себе. CI (`.github/workflows/ci.yml`) виконує
`make lint` і набір тестів у контейнері `archlinux:latest`.

## Секрети, які треба ротувати

Під час міграції були видні такі дані; вважайте їх скомпрометованими й
замініть вручну:

- API-ключ/пароль OpenCode;
- токен rclone (`~/.config/rclone/rclone.conf`);
- дані RustDesk.

Вони навмисно не входять до репозиторію. Комітяться лише `.example`-шаблони.

## Ліцензія

Файл ліцензії ще не додано. Додайте його перед публікацією репозиторію.
