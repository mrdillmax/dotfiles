# Встановлення Arch Linux

Цей посібник встановлює Arch Linux і застосовує ці dotfiles. Передбачається
UEFI-система з GRUB; самі dotfiles не залежать від завантажувача.

Репозиторій ніколи не змінює живі файли сам по собі. Кожен крок — явний;
інсталятор зберігає резервні копії всього, що замінює.

## 1. Встановіть Arch Linux

Завантажте Arch ISO і дотримуйтесь [офіційного посібника](https://wiki.archlinux.org/title/Installation_guide). Рекомендовані налаштування:

- UEFI завантаження, GPT, btrfs або ext4 кореневий розділ
- Swap-файл або zram (у репозиторії є опційний preset zram)
- Локаль `en_US.UTF-8`, за потреби `uk_UA.UTF-8`
- Звичайний користувач у групі `wheel`
- `NetworkManager` для мережі
- GRUB як завантажувач, `linux-lts` як резервне ядро

Після першого завантаження увійдіть як звичайний користувач і оновіть систему:

```bash
sudo pacman -Syu --needed git base-devel
```

## 2. Встановіть AUR-помічник

Інсталятор підтримує `yay` і `paru`. Оберіть один:

```bash
# Варіант A: yay
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay && makepkg -si

# Варіант B: paru
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si
```

## 3. Клонуйте і перевірте

```bash
git clone <url-вашого-репо> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh --dry-run
```

Перший екран показує визначений хост (desktop / laptop), профіль GPU,
кількість моніторів і рівень CPU. Ви можете змінити будь-яке значення
перед продовженням. Після кожної дії меню повертається, а верхній пункт
перемикає `--dry-run` для всієї сесії.

## 4. Запустіть інсталятор

```bash
./install.sh
```

Меню проведе вас через:

1. **Profile** — підтвердити хост (`desktop` / `laptop`) і профіль GPU
2. **Modules** — обрати конфіг-модулі (усі обрані за замовчуванням)
3. **Packages** — вибрати категорії й окремі пакети
4. **System** — опційні /etc-файли (потрібен sudo): DNS, zram, служби тощо
5. **Kernel** — визначити рівень CPU і встановити сумісне ядро

Кожен крок підтверджується окремо. Файли резервуються перед заміною.

Якщо потрібен неінтерактивний режим:

```bash
./install.sh --all --gpu nvidia --host desktop --yes
```

## 5. Налаштуйте монітори

```bash
./install.sh --monitors
```

Це виявить підключені дисплеї і запише розкладку в
`hosts/<host>/monitors.lua`. Файл рендериться в
`~/.config/hypr/monitors.lua` під час встановлення.

## 6. Завершіть налаштування fish

```bash
fish -c 'fisher update'
```

Це встановить плагіни tide prompt. Можливо, потрібно перезапустити
термінал.

## 7. Встановіть стінку і тему

```bash
./install.sh --wallpaper ~/Pictures/wallpaper.jpg
./install.sh --theme
```

Це згенерує кольори зі стінки через matugen і застосує їх до GTK, Qt,
waybar, rofi, dunst і hyprlock.

## 8. Опційно: конфігурація системи

```bash
sudo ./install.sh --system
```

Встановлює /etc-файли по одному, кожен з підтвердженням:

- **DNS** — Pi-hole + unbound (блокування реклами)
- **zram** — стиснутий swap-пристрій
- **Служби** — irqbalance, ananicy-cpp, cpupower
- **GRUB / mkinitcpio** — конфігурація завантаження (тільки NVIDIA/hybrid)
- **Автологін** — drop-in getty autologin
- **UFW** — брандмауер з мінімальною політикою

Без `--system` /etc-файли не змінюються.

## Перевірка

```bash
./install.sh --doctor    # перевірка стану (тільки читання)
./install.sh --dns-check # перевірка DNS-ланцюжка
```

## Усунення проблем

**Waybar не запускається:** переконайтеся, що модуль `waybar` встановлено
і файл `~/.config/waybar/config.jsonc` існує. Запустіть `waybar` напряму,
щоб побачити вивід помилок.

**Немає звуку:** переконайтеся, що `pipewire-pulse` і `pavucontrol`
встановлено, потім запустіть `pavucontrol` для вибору пристрою за замовчуванням.

**Неправильний профіль GPU:** запустіть `./install.sh` і знову оберіть
профіль у меню. Інсталятор оновить `~/.config/uwsm/env` і
`~/.config/uwsm/env-hyprland`.

**Пакети відсутні:** виконайте `./install.sh --only-packages` і оберіть
потрібну категорію. Або перевірте `packages/catalog.tsv` для назви пакета.

## Видалення

```bash
./install.sh --uninstall              # видалити всі встановлені файли
./install.sh --uninstall --modules hypr  # видалити конкретний модуль
sudo ./install.sh --uninstall --system # видалити /etc-файли
```
