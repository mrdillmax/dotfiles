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
- [Де що лежить](#де-що-лежить)
- [Інсталятор](#інсталятор)
- [Модулі](#модулі)
- [Профілі хоста](#профілі-хоста)
- [GPU-профілі](#gpu-профілі)
- [Монітори](#монітори)
- [Помічники робочого столу](#помічники-робочого-столу)
- [Control Center](#control-center)
- [Тюнер мишки й тачпада](#тюнер-мишки-й-тачпада)
- [Каталог пакетів](#каталог-пакетів)
- [Дрейф пакетів](#дрейф-пакетів)
- [RAM-кеш](#ram-кеш)
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
laptop, AMD, Intel, hybrid, `vm` і `software`, обробник `lid` та логіка
dock/monitor-profiles покриті лише синтетичними тестами. На відповідному
обладнанні їх не запускали. Idle і блокування екрана доступні й на десктопі та
є опційними.

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
- Для idle і блокування екрана: `hypridle`, `hyprlock` (опційні пакети Session; десктоп використовує AC-профіль)
- Для профілів док-станції: `socat`
- Для GPU-профілів: відповідні драйвери (категорія Drivers у
  `packages/catalog.tsv`, Mesa для AMD/Intel тощо)

## Швидкий старт

Спершу виконайте `./install.sh --dry-run`: він показує кожну дію в тому ж меню
й нічого не змінює. Прочитайте цей вивід перед першим реальним встановленням.

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

./install.sh              # головне меню
./install.sh --dry-run    # те саме меню, кожна дія лише друкується
```

Перший екран показує визначені host, GPU, кількість моніторів і рівень CPU.
Їх можна змінити там же. Після кожної дії меню повертається, а верхній пункт
перемикає dry-run для всієї сесії.

Прапорці лишаються для автоматизації:

```bash
./install.sh --dry-run --all
./install.sh --modules hypr,uwsm,waybar,rofi,kitty,fish
./install.sh --monitors
```

На машині, де ще немає передумов:

```bash
./bootstrap.sh            # base-devel/git/curl, далі ./install.sh
./bootstrap.sh --dry-run  # спершу показати всі команди
```

Типовий перший запуск:

```bash
./install.sh --host desktop --gpu nvidia --modules hypr,uwsm,waybar,rofi,kitty,fish
./install.sh --monitors   # виявити й записати розкладку моніторів
fish -c 'fisher update'   # встановити плагіни tide
./install.sh --wallpaper ~/Pictures/wallpaper.jpg
./install.sh --theme      # згенерувати кольори matugen зі шпалер
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
├── install.sh                 інсталятор із меню, єдина точка входу для користувача
├── bootstrap.sh               передумови нової машини, далі install.sh
├── lib/                       common, TUI, меню, монітори, пакети, система, секрети
├── profiles/gpu/              nvidia, amd, intel, hybrid, vm, software
├── hosts/
│   ├── desktop/               monitors.conf.sh, input.lua, env хоста
│   └── laptop/                дефолти батареї/яскравості/тачпада/кришки
├── modules/<name>/home/...    файли, які лінкуються або рендеряться в $HOME
├── system/                    опційні /etc файли (--system)
├── packages/                  каталог пакетів + локальні доповнення
├── scripts/                   audit, doctor, sync, pkg-sync, DNS-перевірка
├── tests/                     shell-тести + локальний run.sh
├── .github/workflows/ci.yml   lint + тести в Arch-контейнері
├── personal/                  приватні файли, gitignored
├── docs/                      посібник зі встановлення Arch (EN/UK)
├── Makefile
├── LICENSE / THIRD_PARTY.md
└── README.md / README.uk.md
```

## Де що лежить

| Шлях | Призначення |
|------|-------------|
| `install.sh` | єдина точка входу для користувача: меню, прапорці й одноразові дії |
| `Makefile` | лише розробницькі задачі: `lint`, `test`, `check`, `audit`, `doctor`, `hooks` |
| `scripts/` | внутрішні помічники для інсталятора, CI і pre-commit hook |
| `lib/` | спільний shell-код: TUI, меню, пакети, монітори, системні файли |
| `modules/`, `hosts/`, `profiles/` | конфігурації, які лінкуються або рендеряться |
| `bootstrap.sh` | єдиний виняток: перший запуск на чистій системі, до `install.sh` |

`bootstrap.sh` навмисно лишається окремим файлом. Він запускається до того, як
з'являться `gum`, `jq` та інші залежності інсталятора, тому використовує лише
bash і не потребує `lib/`. Якщо `install.sh` не знаходить `gum`, `jq` чи `git`,
він підказує спершу запустити `./bootstrap.sh`.

## Інсталятор

```bash
./install.sh        # головне меню (потрібен термінал)
./install.sh --help # згрупована довідка прапорців
```

Меню охоплює:

- **Встановлення** — модулі конфігів, програми, профіль host/GPU
- **Система (/etc)** — DNS (Pi-hole/Unbound), zram, cpupower, сервіси,
  pacman/makepkg, GRUB/mkinitcpio, sysctl для RAM-кешу
- **Ядро** — звіт про рівень CPU і вибір ядра
- **Обслуговування** — doctor, DNS-перевірка, restore, sync, дрейф пакетів, hooks

Щоденні налаштування живуть у rofi Control Center, а не в цьому меню. Натисни
`SUPER + Space` або відкрий **Control Center** з rofi.

Пункти, які не працюють на цій машині, лишаються видимими, але сірими, з
причиною (лише ноутбук, лише NVIDIA, немає `sudo`). Без термінала інсталятор
поводиться як раніше.

### Прапорці для автоматизації

| Область | Прапорці |
|---------|----------|
| Встановлення | `--all`, `--modules a,b`, `--category a,b`, `--apps a,b`, `--packages a,b`, `--no-packages`, `--only-packages`, `--host`, `--gpu`, `--spicetify` |
| Налаштування | `--monitors`, `--dock-layout L`, `--mouse`, `--cursor`, `--cursor-archive`, `--cursor-theme`, `--cursor-size`, `--wallpaper`, `--theme`, `--theme-menu`, `--binds [plain\|rofi\|json]`, `--monitor-profiles ACTION`, `--autostart ACTION`, `--gamemode ACTION`, `--idle ACTION`, `--lid ACTION` |
| Система | `--system`, `--system-components a,b` (включно з `ram`), `--iface`, `--autologin-user` |
| Ядро | `--kernel`, `--kernel-level v1..v4` |
| Обслуговування | `--doctor`, `--dns-check`, `--json`, `--restore [date]`, `--sync COMMAND`, `--pkg-sync ACTION`, `--hooks` |
| Загальні | `--dry-run`, `--yes`, `--list`, `--help` |

Кожен пункт меню відповідає одному з цих прапорців. `tests/menu.sh` і
`tests/help-flags.sh` падають, якщо меню й `--help` розійдуться.

`--all` означає **модулі + типові пакети**, а не `/etc`. Усі модулі вибрані
типово, крім `ram-cache` і `workspaces-split`; `lid` пропускається на десктопі.
`idle` ставить пакети, але стартує вимкненим, доки його не увімкнути.
Системні файли завжди опційні й ставляться лише через `--system`.

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
| `idle` | профілі hypridle/hyprlock; AC на десктопі, батарея/AC на ноутбуці; вимкнений до увімкнення |
| `lid` | обробник кришки (лише ноутбук; потребує idle для екрана блокування) |
| `monitor-profiles` | профілі гарячого підключення док-станції/зовнішнього дисплея |
| `theme-menu` | rofi-меню для шпалер, режиму matugen і схеми кольорів |
| `uwsm` | `~/.config/uwsm/env` (common + GPU-профіль) і `env-hyprland` |
| `waybar` | конфіг статус-бару, стиль і скрипти |
| `rofi` | лаунчер, меню живлення й скрипти історії dunst |
| `kitty` | конфіг термінала |
| `fish` | конфіг fish, аліаси й список плагінів tide |
| `dunst` | демон сповіщень (кольори генерує matugen) |
| `matugen` | шаблони й `config.toml` (без згенерованих кольорів) |
| `theming` | єдиний вигляд GTK/Qt/KDE, шрифти, іконки й portal |
| `cursor` | тема/розмір курсора в uwsm, GTK3/4, Qt, xsettingsd і Hyprland |
| `apps` | btop, micro, spicetify, vesktop, Firefox chrome, dolphinrc |
| `control-center` | rofi-хаб щоденних налаштувань (`SUPER + Space`) |
| `ram-cache` | опційний прогрів page cache і tmpfs для профілю браузера |
| `workspaces-split` | слоти воркспейсів на монітор; лише коли є 2+ монітори |
| `mouse-sensitivity` | інтерактивний тюнер вказівника й overlay вводу |

Spicetify CLI — вибраний Music-пункт, який ставить upstream-скрипт, а не pacman. `./install.sh --spicetify` запускає той самий інсталятор.

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

### Покоління драйвера NVIDIA

Категорія Drivers перелічує всі стеки й лишає їх опційними. Вибери той, що
відповідає карті. Став один стек, ніколи два.

| Покоління GPU | Драйвер |
|---------------|---------|
| Blackwell (GBXXX) і новіші | `nvidia-open`, `nvidia-open-lts` або `nvidia-open-dkms` |
| Ada Lovelace, Ampere, Turing | рекомендовано `nvidia-open*`; пропрієтарний `nvidia-580xx-dkms` також підтримується |
| Volta (NV140/GV100), Pascal (NV130/GPXXX), Maxwell (NV110/GMXXX) | `nvidia-580xx-dkms` (legacy, підтримується) |
| Kepler (NVE0/GKXXX) | `nvidia-470xx-dkms` |
| Fermi (NVC0/GF1XX) | `nvidia-390xx-dkms` |
| Tesla (NV50/G80-90-GT2XX) | `nvidia-340xx-dkms` |
| Curie (NV40/G70) і старіші | більше не пакуються |

Профілі `nvidia` і `hybrid` вибирають лише середовище. Сам пакет драйвера
береться з категорії Drivers, тож Pascal або Maxwell лишає `nvidia-580xx-dkms`,
а Turing або новіший може вибрати варіант `nvidia-open`.

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
./install.sh --monitor-profiles status
./install.sh --monitor-profiles apply --dry-run
./install.sh --monitor-profiles watch
```

`watch` слухає сокет подій Hyprland (`socket2`) через `socat` і дебаунсить
сплески, тож док-станція, яка реєструє кілька виходів одразу, запускає один
прохід розкладки. `apply` змінює лише поточну сесію; він ніколи не переписує
конфігураційні файли Hyprland. Перед застосуванням зберігає поточний
`hyprctl monitors -j` у `~/.local/state/dotfiles/monitor-profiles/`. `ask`
ніколи не змінює монітори.

> **На реальному обладнанні док-станції не перевірено.** Спершу запустіть
> `apply` з `--dry-run` і збережіть знімок моніторів. Якщо після реального
> запуску розкладка неправильна, поверніть попередні файли через
> `./install.sh --restore`.

## Помічники робочого столу

У цих модулів одне правило: стан живе в `~/.local/state/dotfiles/`, а не в
конфігу композитора.

Після встановлення відповідного модуля ті самі інструменти доступні як
команди в `~/.local/bin`: `autostart.sh`, `idle-tune.sh` і
`monitor-profiles.sh`.

### Меню теми

```bash
./install.sh --theme-menu       # меню rofi/gum/whiptail/dialog/plain
./install.sh --theme-menu --dry-run
```

Вибір шпалер, режиму matugen (`dark`/`light`) і схеми кольорів. Вибір
зберігається в `~/.local/state/dotfiles/theme.conf`; `./install.sh --theme`
може його перевикористати.

### Шпаргалка клавіш

```bash
./install.sh --binds            # вирівняна таблиця
./install.sh --binds rofi       # меню rofi
./install.sh --binds json       # JSON для скриптів
~/.local/bin/binds-cheatsheet.sh --duplicates
```

Шпаргалка парсить Lua-конфіг, бо Hyprland 0.57 з Lua-диспетчерами показує
непрозорі числові аргументи в `hyprctl binds -j`.

### Gamemode

```bash
./install.sh --gamemode toggle
./install.sh --gamemode status
./install.sh --gamemode on --dry-run
```

Увімкнення вимикає анімації, blur, тіні й округлення. Значення, активні до
першого ввімкнення, читаються через `hyprctl getoption` і зберігаються в
`~/.local/state/dotfiles/gamemode.conf`, тож повторне ввімкнення не перезапише
оригінали, а `off` завжди їх відновлює.

### Idle і блокування

Модуль `idle` рендерить `~/.config/hypr/hypridle.conf` і ставить
`hyprlock.conf`. Він працює на десктопі й ноутбуці; десктоп без батареї
використовує AC-профіль. Модуль вибраний типово, але idle стартує вимкненим,
щоб не спрацьовувати несподівано:

```bash
./install.sh --modules idle
./install.sh --idle enable
```

| Профіль | Dim | Lock | Екран off | Suspend |
|---------|-----|------|-----------|---------|
| battery | 150 | 300 | 330 | 900 |
| AC | 300 | 600 | 660 | 1800 |

`0` вимикає стадію; увімкнені стадії мають задовольняти
`dim < lock <= off < suspend`. Налаштування живуть у
`~/.local/state/dotfiles/idle.conf`.

```bash
./install.sh --idle status
~/.local/bin/idle-tune.sh apply --profile battery
./install.sh --idle configure              # запитує всі вісім значень
./install.sh --idle watch                  # перезастосувати при зміні AC/батареї
./install.sh --idle toggle                 # увімкнути або вимкнути idle
```

`SUPER + SHIFT + I` перемикає idle у сесії. Вимкнений стан зберігається в
`idle.conf`, тож autostart не запускає `hypridle` під час наступного входу.
Попередній `hypridle.conf` бекапиться перед заміною. Модуль `lid` лишається
лише для ноутбука й залежить від `idle` для спільного екрана блокування.

### Кришка ноутбука

```bash
./install.sh --lid status
./install.sh --lid closed
./install.sh --lid closed --dry-run
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
./install.sh --autostart list
~/.local/bin/autostart.sh disable vesktop
~/.local/bin/autostart.sh add notes obsidian
./install.sh --autostart pick          # rofi/gum/whiptail/dialog/plain
```

Записи живуть у `~/.local/state/dotfiles/autostart.tsv` і при першому
використанні наповнюються вбудованими застосунками. `hyprland.lua` викликає
`autostart.sh run`; вимкнений запис лишається вимкненим після наступного
входу без редагування Lua-конфігу. `SUPER+SHIFT+A` відкриває вибір.

## Control Center

Щоденні налаштування живуть у rofi Control Center, а не в `install.sh`.

```bash
dotfiles-control-center
```

Натисни `SUPER + Space` або відкрий **Control Center** з rofi. Сторінки:

- **Вигляд**: шпалери з мініатюрами magick, dark/light/smart, схеми matugen,
  статус шрифтів, іконок і курсора
- **Робочий стіл**: статус моніторів, збережена розкладка, док-профіль
- **Ввід**: тюнер мишки/тачпада, шпаргалка біндів
- **Сесія**: автозапуск, idle, кришка, game mode
- **Музика**: Spicetify update, backup/apply і restore
- **Система**: doctor, DNS, дрейф пакетів, sync і restore
- **Встановлення й оновлення**: відкриває `install.sh` у kitty

Меню використовує палітру matugen (`colors.rasi`), Inter і
`JetBrainsMono Nerd Font`, без окремої теми. Воно викликає помічники напряму.
`install.sh` лишається для встановлення, оновлення й рідкісних одноразових дій.

Бінд живе в `hosts/<host>/control-center.conf` і рендериться в опційний
`~/.config/hypr/control-center.lua`.

## Тюнер мишки й тачпада

```bash
./install.sh --mouse
~/.local/bin/mouse-tune.sh          # після встановлення
mouse-tune.sh --show                # read-only поточні значення
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

## Каталог пакетів

`packages/catalog.tsv` — джерело істини. Кожен рядок містить пакет, категорію,
роль, прапорець default, host, список GPU і короткий опис. Інсталятор показує
вкладки категорій і checklist усередині кожної, тож одну програму можна
прибрати без редагування списків.

- ★ основна: конфіг у репозиторії, вибрана типово
- ○ аналог: лише пакет, не вибраний типово
- • пакет: звичайний пакет
- ✓ вже встановлено

`--all` ставить рядки з `default=yes`. Офісні, engineering- і CAD-програми
видимі, але опційні. `cuda`, `virtio-win`, `hypridle`, `hyprlock`,
`profile-sync-daemon`, `vmtouch` і `preload` також видимі, але опційні.

Категорії: System, Desktop, Hyprland, Audio, Network, Development, Games,
Virtualization, Fonts, Drivers, Terminal, Launcher, Bar, Notifications,
Browser, Files, Editor, Music, System Monitor, Session, Media. Офіс, CAD і
EasyEDA живуть у Desktop або Development.

Вибір без інтерактиву:

```bash
./install.sh --only-packages --category Terminal,Development
./install.sh --only-packages --category Terminal --apps foot
./install.sh --only-packages --packages foot,kitty
```

`packages/local.tsv` зберігає пакети, додані через `pkg-sync pull`. Він є
частиною каталогу, але не частиною типових наборів.

### Дрейф пакетів

```bash
./install.sh --pkg-sync status       # лише звіт
./install.sh --pkg-sync check        # exit 1, коли каталог розійшовся
./install.sh --pkg-sync pull --dry-run
./install.sh --pkg-sync pull --yes   # дописати в local.tsv, ніколи не видаляти
```

`pkg-sync` порівнює явно встановлені пакети з каталогом. Опційні рядки не
вважаються відсутніми, але встановлений опційний пакет рахується як внесений.
`pull` лише дописує встановлені, але не внесені пакети в `packages/local.tsv`;
він ніколи не видаляє запис і нічого не встановлює. Рядки конкретного хоста
порівнюються лише на відповідному хості.

З `--system` репозиторій ставить pacman hook, який оновлює
`/var/lib/dotfiles/pkg-sync.stamp` після кожної транзакції пакетів. `status`
попереджає, коли штамп новіший за останній огляд, тож зміни пакетів можна
розібрати пізніше, а не під час транзакції.

### RAM-кеш

Опційний модуль `ram-cache` призначений для десктопів із великим обсягом RAM.
Він не входить у `--all` і не пропонується на ноутбуках або при малому обсязі
памʼяті.

```bash
./install.sh --modules ram-cache
ramcache status
ramcache warm ~/Games/SomeGame
ramcache run -- ~/Games/SomeGame/start.sh
```

`ramcache` рахує ліміт від `MemAvailable` (типово 50%, до 80%) і прогріває
page cache через `vmtouch`. Page cache вивільняється системою і не містить
єдиної копії даних, тому раптове вимкнення не втрачає файли ігор чи програм.

Профілі браузера окремо обробляє `profile-sync-daemon`: переносить профіль у
tmpfs, синхронізує при stop і suspend та зберігає crash-recovery бекапи.
Ризикують лише несинхронізовані записи tmpfs після останнього resync.
`preload` опційно кешує бінарники.

Модуль ставить `~/.config/dotfiles/ram-cache.conf`,
`~/.config/psd/psd.conf` і `~/.local/bin/ramcache`. Sysctl ставиться лише
через:

```bash
sudo ./install.sh --system --system-components ram
```

Fstab, sudoers і NOPASSWD не змінюються.

## Тема

Кольори генеруються matugen зі шпалер:

```bash
./install.sh --wallpaper ~/Pictures/wallpaper.jpg
./install.sh --theme
```

Без `--wallpaper` `./install.sh --theme` спершу читає
`~/.config/hypr/wallpaper.path` (пише `./install.sh --wallpaper`), а далі поле
`image` у `~/.config/hypr/colors.lua`. Сам файл зображення ніколи не
комітиться. Згенеровані файли ігноруються git:

- `~/.config/hypr/colors.lua`
- кольори waybar/rofi/kitty/dunst
- схеми кольорів GTK/Qt
- вивід btop/micro/spicetify/vesktop
- Firefox `colors.css`

Комітяться лише `matugen/config.toml` і шаблони в
`modules/matugen/home/.config/matugen/templates/`. Модуль `theming` рендерить
GTK3/4, GTK2, xsettingsd, Qt5ct, Qt6ct і kdeglobals з
`hosts/<host>/appearance.conf`. Шрифти — Inter і `JetBrainsMono Nerd Font`,
іконки — `breeze-dark`, Qt використовує Fusion, Dolphin читає схему Matugen.
GTK4 stylesheet явно імпортує `colors.css` і вибрану тему libadwaita.

Portal закріплює Hyprland для screenshot/screencast і GTK для Settings та
файлових діалогів. `theme-menu` і hook matugen разом оновлюють
`org.freedesktop.appearance color-scheme` і GTK-тему. Програми, які не можуть
автоматично слідувати палітрі, перелічені в розділі «Поза єдиною темою»:
SMath, Steam/Wine та власний chrome Spotify, Obsidian і Vesktop.

### Поза єдиною темою

- SMath: застосунок Java/Mono з власним виглядом; палітри GTK і Qt не читає.
- Steam і Wine: власні рендерери та ігрові UI.
- Spotify, Obsidian і Vesktop: кольори з генерованого CSS, але внутрішній
  chrome і шрифти належать застосунку. Після зміни режиму їх треба перезапустити.
- `imv`, `swappy` і `fastfetch` поки не мають генерованого конфігу;
  вони використовують GTK-тему або палітру термінала.

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
| `system/ram-cache/99-ram-cache.conf` | `/etc/sysctl.d/99-ram-cache.conf` (лише компонент ram) |
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
./install.sh --restore 2026-11-16_120000 --modules hypr --dry-run
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
./install.sh --sync status          # файли, що відрізняються
./install.sh --sync diff hypr       # unified diff
./install.sh --sync pull --dry-run  # перегляд
./install.sh --sync pull --yes      # записати назад (diff + скан секретів)
./install.sh --sync packages        # порівняти встановлені пакети
```

Pull зворотно рендерить `@HOME@`, `@FIREFOX_PROFILE_DIR@` і `@OBSIDIAN_VAULT@`,
пропускає згенерований matugen-вивід, `personal/` і шляхи секретів, а перед
записом запускає сканер секретів. Копія кожного файлу репозиторію до pull
зберігається в `~/.local/state/dotfiles/sync-backup/<timestamp>/` з
`manifest.tsv`.

## Перевірки, тести й CI

```bash
make lint       # bash -n + shellcheck
make test       # shell-тести; тимчасовий HOME, живі файли не чіпаються
make audit      # read-only аудит живої системи й репозиторію
make doctor     # CPU/ядро, вигляд, RAM-кеш, курсор, шпалери, symlink-и
make check      # lint + test + audit + doctor
make hooks      # встановити pre-commit hook репозиторію
```

Makefile — інструмент розробника. Користувацькі перевірки:
`./install.sh --doctor`, `./install.sh --dns-check` і
`./install.sh --pkg-sync check`.

Аудит перевіряє помилки конфігу Hyprland, дублікати біндів, переносимість
моніторів, захардкожені домашні шляхи, systemd-юніти, синтаксис Unbound,
файли `.pacnew`, секрети, згенеровані файли й рівень CPU проти встановленого
ядра. Він нічого не редагує й не потребує root.

`./install.sh --doctor` — та сама read-only перевірка з доступним `--json`.
Вона покриває portal color scheme, доступність шрифтів GTK/Qt, імпорт кольорів
GTK4, portal-бекенди й опційний RAM-кеш (psd, preload, ramcache).
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
