# Встановлення Arch Linux

Посібник описує встановлення Arch Linux і застосування цих dotfiles. Орієнтований
на UEFI-систему з GRUB, але самі dotfiles не залежать від завантажувача.

Репозиторій ніколи не змінює живі файли сам по собі. Кожен крок нижче —
явний; інсталятор зберігає резервні копії всього, що замінює.

## 1. Базова система

Завантажте Arch ISO і дотримуйтесь офіційного посібника, або використайте
`archinstall` з такими параметрами:

- UEFI, GPT, btrfs або ext4 для кореня
- swap-файл або zram (у репозиторії є опційний preset zram)
- локаль `en_US.UTF-8`, за потреби також `uk_UA.UTF-8`
- звичайний користувач у групі `wheel`
- `NetworkManager` для мережі
- GRUB (або інший завантажувач) і `linux-lts` як резервне ядро

Після першого завантаження:

```bash
sudo pacman -Syu --needed git base-devel
```

Встановіть AUR-хелпер (інсталятор підтримує `yay` і `paru`):

```bash
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay && makepkg -si
```

## 2. Клонування й перевірка

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

make lint
make dry-run          # повний попередній перегляд, нічого не змінює
make doctor           # перевірка стану лише читанням
```

`make dry-run` вибирає всі модулі й групи пакетів, але не торкається `/etc`.

## 3. Інтерактивне встановлення

```bash
./install.sh
```

Корисні неінтерактивні варіанти:

```bash
./install.sh --host desktop --gpu nvidia --modules hypr,uwsm,waybar,rofi,kitty,fish
./install.sh --all --yes          # модулі + пакети, без /etc
./install.sh --modules cursor --cursor-archive ~/Downloads/theme.7z
```

Тип хоста (`desktop` або `laptop`) і GPU-профіль визначаються автоматично;
їх можна перевизначити через `--host` і `--gpu`.

### Тема курсора

Файли теми курсора ніколи не комітяться. Репозиторій зберігає лише назву теми
й розмір у `hosts/<host>/cursor.conf`, а потім рендерить їх у uwsm, GTK3, GTK4,
Qt, xsettingsd і (за бажанням) застосовує через `hyprctl setcursor`.

```bash
./install.sh --cursor --cursor-archive /path/to/theme.7z
./install.sh --cursor --cursor-theme Bibata-Modern-Ice --cursor-size 24
```

Без архіву інсталятор пропонує теми лише як пакети (`breeze`,
`capitaine-cursors`, `bibata-cursor-theme`). Живий `hyprctl setcursor`
виконується тільки після явного підтвердження.

### Шпалери

Зображення не копіюється в репозиторій. Його абсолютний шлях записується в
`~/.config/hypr/wallpaper.path`, і `make theme` надає перевагу цьому файлу:

```bash
./install.sh --wallpaper ~/Pictures/wallpaper.jpg
make theme
```

## 4. Монітори й введення

```bash
./install.sh --monitors
./install.sh --mouse
```

Назви моніторів зберігаються в `hosts/<host>/monitors.conf.sh`; інсталятор
рендерить `~/.config/hypr/monitors.lua` і не вшиває розкладку власника в
універсальні шаблони.

## 5. Ядро за рівнем CPU

Виберіть ядро, що відповідає рівню мікроархітектури x86-64 вашого CPU:

```bash
./install.sh --kernel
```

Інсталятор визначає найвищий підтримуваний рівень (`v1`..`v4`) і пропонує
ядра не вище нього:

- `linux-lts` + headers — резервне, рекомендоване завжди
- `linux` + headers, `linux-zen` + headers — лише для десктопів
- xanmod `vN` + headers — лише на рівні не вище визначеного, лише десктопи

Правила, які забезпечує інсталятор:

- ніколи не видаляє поточне ядро чи резервне;
- ноутбуки трактує консервативно (не пропонує xanmod і `linux-zen`);
- NVIDIA DKMS завжди отримує відповідні headers; якщо підтримка DKMS для
  бінарного ядра непевна — попереджає;
- рівень вище CPU вимагає червоного попередження **і** введення `I UNDERSTAND`;
- у неінтерактивному режимі рівень вище CPU відхиляється.

Після встановлення інсталятор друкує, але **не виконує**:

```bash
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg   # лише GRUB
```

Встановлюйте headers для кожного ядра, яке використовує DKMS. `make doctor` і
`make audit` порівнюють рівень CPU з рівнем встановленого ядра і повідомляють
про відсутні headers.

## 6. Опційні системні файли

```bash
sudo ./install.sh --system --iface eno1
```

Лише цей режим пише в `/etc`, по одному файлу, з резервною копією. Він не
виконує `grub-mkconfig`, `mkinitcpio -P` і не запускає та не перезапускає
сервіси.

Що входить:

- zram swap, governor `cpupower`, sysctl і modprobe
- systemd-юніти та drop-in-и
- конфіги Pi-hole + Unbound (рендерять `@IFACE@` з `--iface` або default-route;
  `enp9s0` ніколи не підставляється автоматично)
- NetworkManager `dns=none` / `rc-manager=unmanaged` (лише коли Pi-hole і
  Unbound вже існують; заздалегідь підготуйте DNS-запас)
- пропозиції злиття pacman/makepkg (diff, підтвердження, бекап; з `--yes`
  пропускається)
- опційне вмикання сервісів лише через `systemctl enable`, без `start`

UFW — тільки документація. Репозиторій не змінює стан фаєрвола чи правила;
фактичний стан записано в `system/ufw/README.md`.

## 7. Темізація

```bash
make theme WALLPAPER=~/Pictures/wallpaper.jpg
```

Шаблони matugen перегенеровують кольори для Hyprland, waybar, dunst, GTK, Qt і
Firefox. Згенеровані файли кольорів ніколи не комітяться.

## 8. Перевірка

```bash
make lint       # bash -n + shellcheck
make audit      # аудит конфігурації лише читанням
make doctor     # CPU/ядро, курсор, шпалери, керовані symlink-и
make check      # lint + audit + doctor
```

`make doctor` завершується з помилкою лише за наявності failures (ядро вище
CPU, зламані керовані посилання, відсутні файли репозиторію). Попередження —
інформаційні.

## 9. Секрети

Ніколи не комітьте:

- `pihole.toml`, DNS/API-секрети
- конфіги rclone, RustDesk, OpenCode, Omniroute
- `.env`, SSH/GPG-ключі
- весь каталог `personal/`
- архіви тем курсора й шпалери

`sanitized` приклади Pi-hole лежать у `system/pihole/`. Ротуйте будь-який
секрет, який колись потрапляв у відстежуваний файл.

## 10. Примітки

- `--all` означає лише модулі + пакети; `/etc` потребує `--system`.
- Кожен замінений файл зберігається в `~/.dotfiles-backup/<timestamp>/`.
- Жива конфігурація не змінюється без явного кроку інсталятора.
- Незамержені `.pacnew` та інший живий drift перелічені в `AUDIT.md`.
