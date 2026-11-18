# dotfiles

Особисті dotfiles для Arch Linux + Hyprland + uwsm на десктопі й ноутбуці.
Це особисті dotfiles: перед встановленням виконайте `./install.sh --dry-run` і
прочитайте вивід.

Репозиторій є джерелом істини. Інсталятор рендерить машинно-специфічні
значення, а решту лінкує в `$HOME`.

- **Композитор:** Hyprland 0.57 з Lua-API конфігурації
- **Сесія:** uwsm
- **Оболонка:** fish
- **Панель / лаунчер / сповіщення:** waybar, rofi, dunst
- **Тема:** шаблони matugen (згенеровані кольори не комітяться)
- **Пакети:** pacman + AUR-помічник (`yay` або `paru`)
- **Перевірки:** набір shell-тестів у `tests/`, запускається в CI на Arch-контейнері

Англійська документація: [README.md](README.md).  
Посібник зі встановлення: [docs/arch-install.uk.md](docs/arch-install.uk.md).

## Зміст

- [Статус](#статус)
- [Модель безпеки](#модель-безпеки)
- [Вимоги](#вимоги)
- [Швидкий старт](#швидкий-старт)
- [Bootstrap нової машини](#bootstrap-нової-машини)
- [Структура репозиторію](#структура-репозиторію)
- [Інсталятор](#інсталятор)
- [Модулі](#модулі)
- [Профілі хоста](#профілі-хоста)
- [GPU-профілі](#gpu-профілі)
- [Монітори](#монітори)
- [Помічники робочого столу](#помічники-робочого-столу)
- [Тюнер мишки й тачпада](#тюнер-мишки-й-тачпада)
- [Категорії застосунків](#категорії-застосунків)
- [Дрейф пакетів](#дрейф-пакетів)
- [Ядро й рівень CPU](#ядро-й-рівень-cpu)
- [Тема](#тема)
- [Системні конфіги (`--system`)](#системні-конфіги---system)
- [Бекапи й відновлення](#бекапи-й-відновлення)
- [Синхронізація живих змін назад](#синхронізація-живих-змін-назад)
- [Перевірки, тести й CI](#перевірки-тести-й-ci)
- [Секрети](#секрети)
- [Ліцензія](#ліцензія)

## Статус

Перевірено на одному десктопі: Arch Linux, Hyprland 0.57, GPU NVIDIA. Профілі
laptop, AMD, Intel, hybrid, `vm` і `software`, а також логіка `lid`, `idle` та
dock/monitor-profiles покриті лише синтетичними тестами. На відповідному
обладнанні їх не запускали.

## Модель безпеки

- Репозиторій сам ніколи не змінює живі конфігураційні файли.
- Інсталятор робить бекап кожного заміненого файлу в
  `~/.dotfiles-backup/<YYYY-MM-DD_HHMMSS>/` і пише `manifest.tsv`.
- `--dry-run` друкує кожну дію й нічого не змінює.
- Файли `/etc` інсталятор пише лише з `--system`, по одному за раз.
- GRUB, mkinitcpio і `modprobe/nvidia.conf` ставляться лише для GPU-профілів
  `nvidia` і `hybrid`. GRUB і mkinitcpio потребують додаткового підтвердження;
  інші профілі не чіпають завантаження та initramfs.
- Стандартний шаблон GRUB не вимикає мітигації CPU і TPM. У файлі є
  закоментований блок із поясненням обох опцій.
- Інсталятор ніколи не запускає `grub-mkconfig` чи `mkinitcpio`.
- Жоден сервіс не запускається й не перезапускається автоматично.
- Секрети виключені з git: `pihole.toml`, конфіги rclone, RustDesk та OpenCode,
  `.env`, ключі та весь каталог `personal/`.
- Згенеровані matugen-файли виключені; комітяться лише шаблони й
  `matugen/config.toml`.

## Вимоги

- Arch Linux (або Arch-based дистрибутив) з `pacman`
- `git`, `jq`, `bash` 5.x
- Необов'язково, але бажано: `gum` (TUI), `shellcheck` (lint), `yay`/`paru` (AUR)
- Для ноутбучних інструментів: `hypridle`, `hyprlock` (обидва в `packages/laptop.txt`)
- Для профілів док-станції: `socat`
- Для GPU-профілів: відповідні драйвери (`packages/nvidia.txt`,
  Mesa для AMD/Intel тощо)

## Швидкий старт

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

make lint                 # bash -n + shellcheck
./tests/run.sh            # shell-набір; тимчасовий HOME, живі файли не чіпаються
make dry-run              # повний перегляд встановлення, нічого не змінює
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
./install.sh --monitors   # виявити й записати розкладку моніторів
fish -c 'fisher update'   # встановити плагіни tide
make theme WALLPAPER=~/Pictures/wallpaper.jpg
```

## Bootstrap нової машини

```bash
./bootstrap.sh --dry-run
./bootstrap.sh
./bootstrap.sh --yes -- --host laptop --gpu intel
```

Bootstrap ставить лише інструменти, потрібні інсталятору (`base-devel`, `git`,
`curl`), перевіряє доступність мережі й повідомляє про відсутній AUR-помічник.
Він ніколи не збирає AUR-помічник. Далі запускає `install.sh` (з `--all --yes`,
якщо передано `--yes`) і завершує read-only проходом `--doctor`. Усе після `--`
передається в `install.sh`.

## Структура репозиторію

```text
.
├── install.sh                 інтерактивний інсталятор і точка входу
├── bootstrap.sh               передумови нової машини, далі install.sh
├── lib/                       common, TUI, монітори, пакети, система, секрети
├── profiles/gpu/              nvidia, amd, intel, hybrid, vm, software
├── hosts/
│   ├── desktop/               monitors.conf.sh, input.lua, env хоста
│   └── laptop/                дефолти батареї/яскравості/тачпада/кришки
├── modules/<name>/home/...    файли, які лінкуються або рендеряться в $HOME
├── system/                    опційні /etc файли (--system)
├── packages/                  групи пакетів + реєстр альтернатив
├── scripts/                   audit, doctor, sync, pkg-sync, DNS-перевірка
├── tests/                     shell-тести + локальний run.sh
├── .github/workflows/ci.yml   lint + тести в Arch-контейнері
├── personal/                  приватні файли, gitignored
├── docs/                      посібник зі встановлення Arch (EN/UK)
├── Makefile
├── LICENSE / THIRD_PARTY.md
└── README.md / README.uk.md
```

## Інсталятор

```text
./install.sh [options]

  --all                 вибрати всі модулі й групи пакетів
  --dry-run             показати дії, нічого не змінювати
  --yes, -y             відповідати "yes" на підтвердження
  --modules a,b,c       встановити лише ці модулі
  --no-packages         пропустити встановлення пакетів
  --host desktop|laptop перевизначити визначення хоста
  --gpu PROFILE         nvidia|amd|intel|hybrid|vm|software
  --monitors            переналаштувати розкладку моніторів і вийти
  --dock-layout LAYOUT  зберегти right|left|mirror|ask для зовнішніх моніторів
  --mouse               запустити тюнер мишки/тачпада
  --cursor              встановити/налаштувати тему курсора і вийти
  --cursor-archive PATH встановити тему курсора з локального архіву (не комітиться)
  --cursor-theme NAME   назва теми курсора (типово: cursor.conf хоста)
  --cursor-size N       розмір курсора 16..128 (типово: 24)
  --wallpaper PATH      зберегти шлях шпалер і за потреби застосувати
  --system              встановити опційні /etc файли (запускати через sudo)
  --iface IFACE         мережевий інтерфейс для Pi-hole (рендер @IFACE@)
  --autologin-user USER користувач для getty autologin drop-in (з --system)
  --kernel              визначити рівень CPU і встановити відповідне ядро
  --kernel-level LEVEL  перевизначити рівень ядра: v1..v4
  --hooks               встановити pre-commit hook репозиторію і вийти
  --doctor              read-only перевірка здоров'я і вихід (без sudo)
  --json                machine-readable вивід (з --doctor/--dns-check)
  --dns-check           read-only перевірка DNS-ланцюжка і вихід
  --restore [date]      показати бекапи й відновити один (з --modules a,b;
                        /etc також потребує --system)
  --sync COMMAND        status|diff|pull|packages
  --list                показати модулі, GPU-профілі й групи пакетів
  -h, --help            довідка
```

`--all` означає **модулі + пакети**, а не `/etc`. Системні файли завжди
опційні й ставляться лише через `--system`.

Інсталятор визначає тип хоста за `/sys/class/power_supply/BAT*` і DMI chassis
type, а GPU-профіль — за `lspci`/`systemd-detect-virt`. Обидва можна
перевизначити. З `gum` вибір — інтерактивний checklist; без нього —
звичайний нумерований запит.

### Модулі

| Модуль | Що встановлює |
|--------|----------------|
| `hypr` | Lua-конфіг Hyprland, бінди, autostart hook, правила вікон, згенеровані монітори |
| `autostart` | менеджер стану застосунків автозапуску (`autostart.sh`, вибір на `SUPER+SHIFT+A`) |
| `binds-cheatsheet` | шпаргалка біндових клавіш Hyprland (plain, markdown, JSON, rofi) |
| `gamemode` | вимкнення анімацій, blur, тіней і округлення для ігор |
| `idle` | профілі hypridle для батареї/AC і helper перезавантаження |
| `lid` | обробник кришки ноутбука й hyprlock |
| `monitor-profiles` | профілі гарячого підключення док-станції/зовнішнього дисплея |
| `theme-menu` | rofi-меню для шпалер, режиму matugen і схеми кольорів |
| `uwsm` | `~/.config/uwsm/env` (common + GPU-профіль) і `env-hyprland` |
| `waybar` | конфіг статус-бару, стиль і скрипти |
| `rofi` | лаунчер, меню живлення й скрипти історії dunst |
| `kitty` | конфіг термінала |
| `fish` | конфіг fish, аліаси й список плагінів tide |
| `dunst` | демон сповіщень (кольори генерує matugen) |
| `matugen` | шаблони й `config.toml` (без згенерованих кольорів) |
| `theming` | налаштування GTK/Qt/KDE і symlink-и adw-gtk3 |
| `cursor` | тема/розмір курсора в uwsm, GTK3/4, Qt, xsettingsd і Hyprland |
| `apps` | btop, micro, spicetify, vesktop, Firefox chrome, dolphinrc |
| `workspaces-split` | слоти воркспейсів на монітор; лише коли є 2+ монітори |
| `mouse-sensitivity` | інтерактивний тюнер вказівника й overlay вводу |

### Профілі хоста

| Хост | Визначення | Особливості |
|------|------------|-------------|
| `desktop` | немає батареї | доступний приклад двомоніторного пресета |
| `laptop` | є батарея | батарея, яскравість, тачпад, кришка/suspend, power-profiles-daemon, `eDP-*` |

### GPU-профілі

| Профіль | Середовище |
|---------|------------|
| `nvidia` | `LIBVA_DRIVER_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `NVD_BACKEND=direct` |
| `amd` | `LIBVA_DRIVER_NAME=radeonsi` |
| `intel` | `LIBVA_DRIVER_NAME=iHD` (або `i965` для старішого обладнання) |
| `hybrid` | змінні NVIDIA + `__NV_PRIME_RENDER_OFFLOAD=1`, `__VK_LAYER_NV_optimus=NVIDIA_only`; `AQ_DRM_DEVICES` задається для хоста |
| `vm` | без vendor-змінних; опційно `AQ_NO_KMS_REQUIREMENT=1` |
| `software` | `LIBGL_ALWAYS_SOFTWARE=1` |

Вибраний профіль дописується до
`modules/uwsm/home/.config/uwsm/env.common` і рендериться в
`~/.config/uwsm/env`. `env-hyprland` окремий, бо `HYPR*`/`AQ_*` не мають
потрапляти в інші сесії.

## Монітори

Єдине джерело істини — `hosts/<host>/monitors.conf.sh`. Інсталятор рендерить з
нього два файли:

- `~/.config/hypr/monitors.lua` — викликає `hl.monitor()` і
  `hl.workspace_rule()` та повертає список моніторів;
- `~/.config/hypr/monitors.conf.sh` — копію, яку читає `switch_ws.sh`.

`hyprland.lua` завантажує `monitors.lua` через `pcall(dofile, ...)`. Якщо файл
відсутній або невалідний, використовується `preferred,auto,1`, тож свіже
встановлення все одно стартує.

`./install.sh --monitors` визначає підключені виходи (`hyprctl monitors`, далі
`/sys/class/drm`) і пропонує:

1. один монітор;
2. два або більше моніторів із вибором порядку зліва направо й позицій;
3. auto (`preferred`, автоматичні позиції);
4. приклад пресета `dill-desktop` (`HDMI-A-2` ліворуч, `DP-1` праворуч, обидва
   1920x1080@60, воркспейси 1–10 і 11–20);
5. ручне редагування `hosts/<host>/monitors.conf.sh`.

Для ноутбука згенерована розкладка підтримує дробовий масштаб і будь-яку
панель `eDP-*`; поведінка кришки й зовнішніх моніторів належить профілю хоста
laptop.

Модуль `workspaces-split` пропонується лише коли знайдено 2+ монітори. Він
встановлює `~/.config/hypr/switch_ws.sh`, який читає імена моніторів і
діапазони воркспейсів зі згенерованого `monitors.conf.sh` — нічого не
захардкожено. Без модуля `SUPER+1..0` використовує рідні диспетчери Hyprland.

### Профілі док-станції й гарячого підключення

Опційний модуль `monitor-profiles` обробляє ноутбук, підключений до
зовнішнього дисплея. Налаштування живе в
`~/.config/hypr/monitor-profiles.conf`:

```bash
DOCK_LAYOUT=right      # right|left|mirror|ask
```

Зберегти через інсталятор або змінити напряму:

```bash
./install.sh --dock-layout right
make monitor-profiles ACTION=status
make monitor-profiles ACTION=apply DRY_RUN=1
make monitor-profiles ACTION=watch
```

`watch` слухає сокет подій Hyprland (`socket2`) через `socat` і дебаунсить
сплески, тож док-станція, яка реєструє кілька виходів одразу, запускає один
прохід розкладки. `apply` змінює лише поточну сесію; він ніколи не переписує
конфігураційні файли Hyprland. Перед застосуванням зберігає поточний
`hyprctl monitors -j` у `~/.local/state/dotfiles/monitor-profiles/`. `ask`
ніколи не змінює монітори.

> **На реальному обладнанні док-станції не перевірено.** Спершу запустіть
> `apply` з `DRY_RUN=1` і збережіть знімок моніторів. Якщо після реального
> запуску розкладка неправильна, поверніть попередні файли через
> `./install.sh --restore`.

## Помічники робочого столу

У цих модулів одне правило: стан живе в `~/.local/state/dotfiles/`, а не в
конфігу композитора.

### Меню теми

```bash
make theme-menu                 # меню rofi/gum/whiptail/dialog/plain
make theme-menu DRY_RUN=1
```

Вибір шпалер, режиму matugen (`dark`/`light`) і схеми кольорів. Вибір
зберігається в `~/.local/state/dotfiles/theme.conf`; `make theme` може його
перевикористати.

### Шпаргалка клавіш

```bash
make binds                      # вирівняна таблиця
make binds ROFI=1               # меню rofi
make binds JSON=1               # JSON для скриптів
~/.local/bin/binds-cheatsheet.sh --duplicates
```

Шпаргалка парсить Lua-конфіг, бо Hyprland 0.57 з Lua-диспетчерами показує
непрозорі числові аргументи в `hyprctl binds -j`.

### Gamemode

```bash
make gamemode ACTION=toggle
make gamemode ACTION=status
make gamemode ACTION=on DRY_RUN=1
```

Увімкнення вимикає анімації, blur, тіні й округлення. Значення, активні до
першого ввімкнення, читаються через `hyprctl getoption` і зберігаються в
`~/.local/state/dotfiles/gamemode.conf`, тож повторне ввімкнення не перезапише
оригінали, а `off` завжди їх відновлює.

### Idle і блокування

Модуль `idle` рендерить `~/.config/hypr/hypridle.conf` з двох профілів:

| Профіль | Dim | Lock | Екран off | Suspend |
|---------|-----|------|-----------|---------|
| battery | 150 | 300 | 330 | 900 |
| AC | 300 | 600 | 660 | 1800 |

`0` вимикає стадію; увімкнені стадії мають задовольняти
`dim < lock <= off < suspend`. Налаштування живуть у
`~/.local/state/dotfiles/idle.conf`.

```bash
make idle ACTION=status
make idle ACTION=apply PROFILE=battery
make idle ACTION=configure              # запитує всі вісім значень
make idle ACTION=watch                  # перезастосувати при зміні AC/батареї
```

Попередній `hypridle.conf` бекапиться перед заміною. `hypridle` і `hyprlock`
належать до ноутбучної групи пакетів, не до базової.

### Кришка ноутбука

```bash
make lid ACTION=status
make lid ACTION=closed
make lid ACTION=closed DRY_RUN=1
```

Під час закриття обробник читає `hyprctl monitors -j` безпосередньо перед дією:
якщо є інший активний монітор, він вимикає кожен вихід `eDP-*`/`LVDS`/`DSI` і
запам'ятовує режим, позицію та масштаб у
`~/.local/state/dotfiles/lid.conf`; інакше засинає через `systemctl`.
Відкриття кришки завжди повертає внутрішню панель. Конфіг logind не
змінюється. Логіка рішень покрита лише синтетичними тестами, не фізичною
кришкою.

### Автозапуск

```bash
make autostart                        # список
make autostart ACTION=disable NAME=vesktop
make autostart ACTION=add NAME=notes CMD=obsidian
make autostart ACTION=pick            # rofi/gum/whiptail/dialog/plain
```

Записи живуть у `~/.local/state/dotfiles/autostart.tsv` і при першому
використанні наповнюються вбудованими застосунками. `hyprland.lua` викликає
`autostart.sh run`; вимкнений запис лишається вимкненим після наступного
входу без редагування Lua-конфігу. `SUPER+SHIFT+A` відкриває вибір.

## Тюнер мишки й тачпада

```bash
make mouse
./install.sh --mouse
~/.local/bin/mouse-tune.sh          # після встановлення
./scripts/mouse-tune.sh --show      # read-only поточні значення
```

Тюнер потребує запущеної сесії Hyprland і використовує Lua runtime API:

```bash
hyprctl eval 'hl.config({ input = { sensitivity = -0.3 } })'
hyprctl eval 'hl.device({ name = "...", sensitivity = -0.2 })'
```

Що можна змінити наживо:

- `input:sensitivity` у `-1.0…1.0`, крок `0.05`, дрібний крок `0.01` (`f`);
- `input:accel_profile` (`flat` / `adaptive` / default);
- `input:force_no_accel`;
- `input:scroll_factor`;
- перевизначення для пристрою з `hyprctl devices` (sensitivity, acceleration,
  scroll factor);
- тачпад ноутбука: `natural_scroll`, `tap_to_click`,
  `disable_while_typing`.

Клавіші живого слайдера: `←`/`→` або `-`/`+` змінюють значення, `f` перемикає
дрібний крок, `r` повертає значення сесії, `Enter`/`q` завершує. Значення
парсяться й друкуються з точкою незалежно від локалі системи, тож збережений
Lua-файл лишається валідним і за коми-десяткової локалі.

> **Важливо:** у старіших версіях Hyprland немає опції `scroll_factor` для
> мишки. Тюнер пропонує її там, де `hyprctl getoption` її показує; інакше вона
> просто не відображається.

Збереження пише лише в `hosts/<host>/input.lua` у репозиторії (або в
`~/.config/hypr/input.lua`, якщо репозиторій не знайдено). Показує unified diff,
питає підтвердження й створює бекап. Живий `hyprland.lua` ніколи не
редагується. Overlay завантажується так:

```lua
pcall(dofile, HOME .. "/.config/hypr/input.lua")
```

тож відсутній файл безпечний.

## Категорії застосунків

Групи пакетів живуть у `packages/<category>.txt`. Інсталятор дає вибрати
групи й позначає альтернативи як `[main, config]` (конфіг цього застосунку є в
репозиторії) або `[package only]` (конфігу тут немає).

| Категорія | Основна (конфіг включено) | Альтернативи (лише пакет) |
|-----------|---------------------------|---------------------------|
| термінал | kitty | foot, alacritty, wezterm, ghostty |
| лаунчер | rofi | fuzzel, wofi, anyrun |
| статус-бар | waybar | hyprpanel, ags |
| сповіщення | dunst | mako, swaync |
| браузер | firefox | chromium, brave-bin, librewolf |
| файловий менеджер | dolphin | nautilus, thunar, yazi |
| системний монітор | btop | htop, bottom |
| редактор | micro | neovim, kate |
| музика | spotify-launcher | amberol, elisa |
| ядро | керується `--kernel` | linux, linux-lts, linux-zen, linux-hardened |

Огляд груп:

| Група | Вміст |
|-------|-------|
| `base.txt` | завантаження, сховище, CLI-інструменти, база без шрифтів |
| `hyprland.txt` | композитор, портали, Wayland-утиліти, теми |
| `shell.txt` | fish + fisher |
| `audio.txt` | PipeWire, Carla, Guitarix, REAPER |
| `desktop.txt` | щоденні GUI-застосунки |
| `media.txt` | CLI-інструменти для зображень/мініатюр |
| `dev.txt` | компілятори, SDK, редактори |
| `network.txt` | NetworkManager, Pi-hole, Unbound, rclone, ZeroTier |
| `virtualization.txt` | Docker, libvirt/QEMU, Steam, Wine, Waydroid |
| `nvidia.txt` | стек NVIDIA 580xx і моніторинг |
| `tuning.txt` | тюнінг CPU/IO й stress-інструменти |
| `fonts.txt` | шрифти й підтримка української |
| `laptop.txt` | hypridle, hyprlock (лише ноутбучні сесії) |
| `aur.txt` | пакети лише з AUR |

`install.sh --no-packages` повністю пропускає цей крок.

### Дрейф пакетів

```bash
make pkg-sync                        # лише звіт
make pkg-sync ACTION=check           # exit 1, коли списки розійшлися
make pkg-sync ACTION=pull DRY_RUN=1
make pkg-sync ACTION=pull YES=1      # дописати, ніколи не видаляти
```

`pkg-sync` порівнює явно встановлені пакети з `packages/*.txt`. `pull` лише
дописує встановлені, але не внесені пакети в
`packages/extra-installed.txt`; він ніколи не видаляє запис і нічого не
встановлює. Файли конкретного хоста порівнюються лише на відповідному хості.

З `--system` репозиторій ставить pacman hook, який оновлює
`/var/lib/dotfiles/pkg-sync.stamp` після кожної транзакції пакетів. `status`
попереджає, коли штамп новіший за останній огляд, тож зміни пакетів можна
розібрати пізніше, а не під час транзакції.

### Ядро й рівень CPU

```bash
./install.sh --kernel
```

Інсталятор визначає рівень CPU x86-64 (`v1`..`v4`) і пропонує ядра на цьому
рівні або нижче: `linux-lts` (fallback), `linux`, `linux-zen` і відповідний
xanmod на десктопах. Ноутбуки трактуються консервативно. Рівень вище за CPU
вимагає червоного попередження й введення `I UNDERSTAND`; неінтерактивний
режим відмовляє. Запущене ядро й fallback-ядро ніколи не видаляються.

NVIDIA DKMS завжди отримує відповідні headers. Інсталятор друкує команди
`mkinitcpio`/`grub-mkconfig` і ніколи їх не запускає. `make doctor` порівнює
рівень CPU з рівнем встановленого ядра.

## Тема

Кольори генеруються matugen зі шпалер:

```bash
make theme WALLPAPER=~/Pictures/wallpaper.jpg
```

Без `WALLPAPER` `make theme` спершу читає `~/.config/hypr/wallpaper.path`
(пише `./install.sh --wallpaper`), а далі поле `image` у
`~/.config/hypr/colors.lua`. Сам файл зображення ніколи не комітиться.
Згенеровані файли ігноруються git:

- `~/.config/hypr/colors.lua`
- кольори waybar/rofi/kitty/dunst
- схеми кольорів GTK/Qt
- вивід btop/micro/spicetify/vesktop
- Firefox `colors.css`

Комітяться лише `matugen/config.toml` і шаблони в
`modules/matugen/home/.config/matugen/templates/`. Записи GTK4 `gtk.css`,
`gtk-dark.css` і `assets` — symlink-и на
`/usr/share/themes/adw-gtk3-dark/gtk-4.0/`; модуль `theming` їх відтворює.

## Системні конфіги (`--system`)

Запускати з root:

```bash
sudo ./install.sh --system --iface eno1
sudo ./install.sh --system --autologin-user "$USER"
```

Лише цей режим пише в `/etc`, по одному файлу, після бекапу. `@IFACE@`
рендериться з `--iface`, далі з інтерфейсу default-route, далі з інтерактивного
запиту. Якщо жодного немає, файл пропускається з помилкою; фіксована назва
інтерфейсу ніколи не підставляється в універсальних шаблонах.

`@USER@` у getty drop-in рендериться з `--autologin-user`, далі з `SUDO_USER`,
далі з логіну, що викликав інсталятор, і врешті з інтерактивного запиту.
Drop-in завжди потребує окремого підтвердження.

Маніфест:

| Джерело | Призначення |
|---------|-------------|
| `system/zram/zram-generator.conf` | `/etc/systemd/zram-generator.conf` |
| `system/cpupower/cpupower` | `/etc/default/cpupower` |
| `system/networkmanager/dns.conf` | `/etc/NetworkManager/conf.d/dns.conf` (лише з Pi-hole + Unbound) |
| `system/networkmanager/rc-manager.conf` | `/etc/NetworkManager/conf.d/rc-manager.conf` (лише з Pi-hole + Unbound) |
| `system/unbound/unbound.conf` | `/etc/unbound/unbound.conf` |
| `system/pihole/dnsmasq.conf` | `/etc/pihole/dnsmasq.conf` |
| `system/pihole/pihole.toml.example` | `/etc/pihole/pihole.toml` (лише після огляду) |
| `system/wait-iface/wait-iface.sh` | `/usr/local/bin/wait-iface.sh` |
| `system/systemd/...` | `/etc/systemd/system/...` |
| `system/grub/default-grub` | `/etc/default/grub` (лише nvidia/hybrid; додаткове підтвердження) |
| `system/mkinitcpio/mkinitcpio.conf` | `/etc/mkinitcpio.conf` (лише nvidia/hybrid; додаткове підтвердження) |
| `system/modprobe/nvidia.conf` | `/etc/modprobe.d/nvidia.conf` (лише nvidia/hybrid) |
| `system/modprobe/*` | `/etc/modprobe.d/*` (інші modprobe-файли) |

> **Скидання пароля Pi-hole.** `system/pihole/pihole.toml.example` копіюється
> поверх `/etc/pihole/pihole.toml` і має порожній `pwhash`. Встановлення
> **скидає пароль адміністратора Pi-hole**. Після нього виконайте
> `pihole setpassword`.

Сам `pihole.toml` виключений. Приклад також має порожні `totp_secret` і
`app_pwhash` та `cli_pw = false`; огляньте його й додайте секрети самостійно.

`pacman.conf` і `makepkg.conf` зливаються, а не копіюються: інсталятор показує
diff, питає підтвердження й робить бекап. Злиття пропускається з `--yes`.
Опційні сервіси вмикаються лише через `systemctl enable`, без запуску чи
перезапуску.

### Завантажувальні файли NVIDIA

Файли GRUB, mkinitcpio і `modprobe/nvidia.conf` специфічні для пропрієтарного
драйвера NVIDIA. Інсталятор мапить їх лише коли вибраний GPU-профіль — `nvidia`
або `hybrid`. Інші профілі не чіпають `/etc/default/grub`,
`/etc/mkinitcpio.conf` і `/etc/modprobe.d/nvidia.conf`.

Стандартний шаблон GRUB **не** містить `mitigations=off` чи
`module_blacklist=tpm,tpm_tis,tpm_tis_core`. Обидві опції є в закоментованому
блоці з попередженням: вони послаблюють мітигації вразливостей CPU і ламають
TPM-based measured boot або розблокування диска. Додавайте їх лише якщо
приймаєте цей компроміс.

Інсталятор ніколи не запускає `grub-mkconfig` чи `mkinitcpio -P`; він друкує
команди для ручного огляду. Робота з ядром належить `./install.sh --kernel`;
`--system` лише повідомляє про дрейф CPU/ядра.

UFW — лише документація. Репозиторій не змінює стан фаєрвола чи правила; див.
`system/ufw/README.md` із загальними рекомендаціями.

Не керується цим репозиторієм: `/etc/fstab`, з'єднання NetworkManager,
конфігурація snapper.

## Бекапи й відновлення

Кожен замінений файл копіюється в:

```text
~/.dotfiles-backup/<YYYY-MM-DD_HHMMSS>/<шлях відносно $HOME>
~/.dotfiles-backup/<YYYY-MM-DD_HHMMSS>/manifest.tsv
```

Щоб відновити файл вручну:

```bash
cp -a ~/.dotfiles-backup/2026-11-16_120000/.config/hypr/hyprland.lua \
      ~/.config/hypr/hyprland.lua
```

Або скористайтеся вбудованим відновленням:

```bash
./install.sh --restore                       # список бекапів із кількістю файлів
./install.sh --restore 2026-11-16_120000
make restore RESTORE_DATE=2026-11-16_120000
make restore RESTORE_DATE=2026-11-16_120000 MODULES=hypr DRY_RUN=1
```

Відновлення читає `manifest.tsv`, показує diff, питає підтвердження й бекапить
поточний стан перед записом. Файли `/etc` відновлюються лише з `--system` і
окремим підтвердженням. Якщо є конфігурація snapper, пропонується знімок перед
відновленням.

Інсталятор записує керовані шляхи в
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/managed.tsv`. Нічого не видаляється
автоматично. Інші файли стану в тому ж каталозі: `theme.conf`,
`gamemode.conf`, `idle.conf`, `autostart.tsv`, `lid.conf`,
`monitor-profiles/` і `sync-backup/`.

## Синхронізація живих змін назад

Напрямок завжди **жива система → репозиторій**. Під `$HOME` нічого не
записується.

```bash
make sync-status                    # файли, що відрізняються
make sync-diff SYNC_TARGET=hypr     # unified diff
make sync-pull DRY_RUN=1            # перегляд
make sync-pull YES=1                # записати назад (diff + скан секретів)
./scripts/sync.sh packages          # порівняти встановлені пакети
```

Pull зворотно рендерить `@HOME@`, `@FIREFOX_PROFILE_DIR@` і `@OBSIDIAN_VAULT@`,
пропускає згенерований matugen-вивід, `personal/` і шляхи секретів, а перед
записом запускає сканер секретів. Копія кожного файлу репозиторію до pull
зберігається в `~/.local/state/dotfiles/sync-backup/<timestamp>/` з
`manifest.tsv`.

## Перевірки, тести й CI

```bash
make lint       # bash -n + shellcheck
make audit      # read-only аудит живої системи й репозиторію
make doctor     # рівень CPU/ядра, курсор, шпалери, керовані symlink-и
make dns-check  # resolv.conf -> Pi-hole -> unbound
make check      # lint + audit + doctor
./tests/run.sh  # повний shell-набір
make hooks      # встановити pre-commit hook репозиторію
```

Аудит перевіряє помилки конфігу Hyprland, дублікати біндів, переносимість
моніторів, захардкожені домашні шляхи, systemd-юніти, синтаксис Unbound,
файли `.pacnew`, секрети, згенеровані файли й рівень CPU проти встановленого
ядра. Він нічого не редагує й не потребує root.

`./install.sh --doctor` — та сама read-only перевірка з доступним `--json`;
`./install.sh --dns-check` перевіряє DNS-ланцюжок і попереджає, що конфігурації
потрібна робоча пара Pi-hole/Unbound, перш ніж `--system` змінить файли
резолвера.

Кожен тест використовує тимчасовий `$HOME`/`XDG_STATE_HOME` і stub-інструменти
системи, тож живий конфіг, база пакетів і монітори не чіпаються. Тести restore
і sync додатково перевіряють, що живі файли не змінилися й що бекап створено.
`tests/run.sh [pattern] [-v] [--list]` запускає один або всі файли й ніколи не
запускає себе. CI (`.github/workflows/ci.yml`) виконує `make lint` і набір у
контейнері `archlinux:latest`.

## Секрети

Репозиторій не містить облікових даних. З git виключені: `pihole.toml`,
конфіги rclone, RustDesk та OpenCode, `.env`-файли, SSH- і GPG-ключі та весь
каталог `personal/`. Комічені `.example`-файли містять лише placeholder-и.

Якщо ви скопіювали репозиторій із приватного робочого дерева, відкличте
(rotate) кожен токен, який колись лежав у відстежуваному файлі.

## Ліцензія

MIT. Див. [LICENSE](LICENSE).

Сторонні приклади конфігурацій і теми зберігають свої ліцензії.
Див. [THIRD_PARTY.md](THIRD_PARTY.md).
