# dotfiles

Особисті dotfiles для Arch Linux + Hyprland + uwsm на десктопі й ноутбуці.
Перед встановленням виконайте `./install.sh --dry-run` — він покаже кожну дію,
нічого не змінюючи.

- **Композитор:** Hyprland (Lua-конфіг)
- **Сесія:** uwsm
- **Оболонка:** fish, **Термінал:** kitty
- **Панель / лаунчер / сповіщення:** waybar, rofi, dunst
- **Браузер:** Firefox
- **Тема:** Inter + JetBrainsMono Nerd Font, кольори через matugen
- **Пакети:** 280+ у 21 категорії (pacman + AUR-помічник)
- **Перевірки:** shell-тести в `tests/`

[English README](README.md) · [Посібник встановлення Arch](docs/arch-install.uk.md)

<!-- screenshot: сесія Hyprland з waybar, лаунчером rofi та кількома вікнами -->

## Що ви отримаєте

Повноцінне робоче середовище: тайловий композитор, власна панель, лаунчер rofi
зі центром керування, оболонка fish з prompt tide, термінал kitty, Firefox
з українською локаллю, монітор системи btop, менеджер буфера обміну (cliphist),
інструмент знімків екрана (grim + swappy), сповіщення dunst, і опційно —
DNS Pi-hole, Syncthing, брандмауер UFW та ігрові утиліти (Steam, MangoHud,
gamescope).

## Швидкий старт

```bash
git clone https://github.com/<user>/dotfiles ~/Projects/dotfiles
cd ~/Projects/dotfiles

./install.sh --dry-run          # спершу переглянути все
./install.sh                    # інтерактивне меню
./install.sh --monitors         # виявити розкладку моніторів
fish -c 'fisher update'         # встановити плагіни tide
./install.sh --wallpaper ~/шлях/до/стінки.jpg
./install.sh --theme            # згенерувати кольори зі стінки
```

На новій машині спершу виконайте `./bootstrap.sh` (встановлює base-devel, git,
jq, gum та AUR-помічник). Кожна дія меню відповідає прапорцю — меню це обгортка
навколо `./install.sh`.

## Щоденне використання

| Дія | Клавіша | Утиліта |
|-----|---------|---------|
| Лаунчер | `SUPER + R` | rofi |
| Центр керування | `SUPER + SHIFT + R` | меню install.sh |
| Термінал | `SUPER + T` | kitty |
| Файли | `SUPER + E` | dolphin |
| Історія буфера | `SUPER + V` | меню cliphist |
| Знімок екрана | `SUPER + S` | grimblast → буфер |
| Знімок + редагування | `SUPER + SHIFT + S` | swappy |
| Блокування | `SUPER + L` | lock-screen.sh |
| Меню виходу | `SUPER + Escape` | rofi |
| Піпетка кольору | `SUPER + P` | hyprpicker |
| Калькулятор | `SUPER + C` | qalculate-gtk |
| Закрити вікно | `SUPER + Q` | hyprctl kill |
| Перемикнути float | `SUPER + Z` | — |
| Розділити макет | `SUPER + J` | toggplitsplit |
| Робочий стіл 1-10 | `SUPER + 1…0` | — |
| Пересунути вікно | `SUPER + SHIFT + 1…0` | — |
| Фокус напряму | `SUPER + стрілка` | — |
| Перемкнути стіл | `SUPER + колесо миші` | — |
| Перетягнути / змінити | `SUPER + drag / right` | — |

Яскравість (скрол або клавіші) та гучність (клавіші) обслуговуються модулем
`osd`. Яскравість обмежена 5 % і 100 %.

## Налаштування

### Профіль GPU

Шість профілів: `nvidia`, `amd`, `intel`, `hybrid`, `vm`, `software`.
Кожен встановлює правильні `LIBVA_DRIVER_NAME` та vendor-змінні. Вкажіть у
меню розділі **Profile** або через `--gpu`. На системах NVIDIA також можна
вибрати стек драйвера (open, 580xx-dkms, legacy).

### Стінка та тема

```bash
./install.sh --wallpaper ~/шлях/до/зображення.jpg
./install.sh --theme            # генерація кольорів matugen
./install.sh --theme-menu       # вибір стінки, режиму, схеми
```

Кольори генеруються з поточної стінки та застосовуються до GTK, Qt, waybar,
rofi, dunst і шаблонів hyprlock. Згенеровані файли живуть у
`~/.config/matugen/` і не комітяться.

### Миша і тачпад

```bash
./install.sh --mouse
```

Інтерактивний тюнер: чутливість, профіль прискорення, натуральна прокрутка,
тап для кліку, налаштування для кожного пристрою, жести трьома і чотирма
пальцями для перемикання робочих столів. Збереження пишеться в
`hosts/<host>/input.lua`.

### Ядро

```bash
./install.sh --kernel
```

Визначає рівень CPU x86-64 (v1–v4) і пропонує сумісна ядра:
`linux-lts` (резервне), `linux`, `linux-zen`, `xanmod` (десктоп).
Рівень вище CPU вимагає підтвердження `I UNDERSTAND`.

### Система (/etc)

```bash
sudo ./install.sh --system
```

Один файл за раз, з підтвердженням. Опції: DNS (Pi-hole + unbound), zram,
cpupower, irqbalance/ananicy-cpp, GRUB, mkinitcpio, автологін getty,
брандмауер UFW. Кожен файл резервується перед заміною.

### Пакети

```bash
./install.sh --only-packages --category Games    # встановити категорію
./install.sh --pkg-sync status                   # перевірити розбіжності
./install.sh --pkg-sync pull --yes               # додати неперелічені пакети
```

Каталог пакетів — `packages/catalog.tsv`. `--all` встановлює рядки з
`default=yes` з усіх категорій. `local.tsv` зберігає вручну встановлені
пакети, виявлені `pkg-sync`.

## Часті запитання

**П: Чи підійде це для ноутбука?**
В: Так. Хост `laptop` вмикає попередження батареї, обробку кришки та
інтеграцію power-profiles-daemon. Оберіть у меню або `--host laptop`.

**П: Чи працює без інтернету?**
В: Інсталятору потрібен доступ до pacman і AUR для пакетів. Конфіги
закомічені й не вимагають мережі. Більшість функцій працюють офлайн.

**П: Як повернути оболонку за замовчуванням?**
В: Виконайте `chsh -s /bin/bash` (або `/bin/zsh`). Конфіг fish — лише в
`~/.config/fish/` та `~/.local/share/fish/`.

**П: Чи безпечно запускати з sudo?**
В: Системні файли встановлюються по одному, з підтвердженням. Кожен
замінений файл резервується в `~/.dotfiles-backup/<timestamp>/`. Служби
не перезапускаються і завантажувач не оновлюється.

## Структура репозиторію

```
install.sh          Інсталятор (меню + прапорці)
bootstrap.sh        Передумови нової машини → install.sh
lib/                Спільні функції: common, tui, menu, packages, …
modules/<name>/     Кожен модуль: module.conf + home/… конфіги
hosts/<host>/       Хост-специфічні: монітори, вхід, перевизначення
profiles/gpu/       Шаблони GPU-профілів (nvidia, amd, …)
system/             Опційні /etc-файли (--system)
packages/catalog.tsv  280+ пакетів, 21 категорія
migrations/         Скрипти оновлення версії (NNN-name.sh)
tests/              Набір shell-тестів
assets/             Теми курсорів, графіка
```

## Посилання

- [Посібник встановлення Arch](docs/arch-install.uk.md)
- [Довідник модулів](docs/modules.md)
- [Конфігурація системи](system/README.md)
- [Треті ліцензії](THIRD_PARTY.md)
- [Баг-репорт / обговорення](https://github.com/<user>/dotfiles)

Ліцензія MIT. Див. [LICENSE](LICENSE).
