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
./tests/run.sh        # тимчасовий HOME; живі файли не чіпаються
make dry-run          # повний попередній перегляд, нічого не змінює
make doctor           # перевірка стану лише читанням
```

`make dry-run` вибирає всі модулі й групи пакетів, але не торкається `/etc`.

Якщо на машині бракує передумов (`base-devel`, `git`, `curl`), bootstrap
встановить їх і запустить інсталятор:

```bash
./bootstrap.sh --dry-run
./bootstrap.sh --yes -- --host laptop --gpu intel
```

Bootstrap ніколи не збирає AUR-хелпер; він лише повідомляє про відсутній
`yay`/`paru`. Усе після `--` передається в `install.sh`.

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

### Стан і щоденні помічники

Малі runtime-інструменти тримають стан у `~/.local/state/dotfiles/`, а не в
конфізі композитора:

```bash
make autostart                         # список програм входу
make autostart ACTION=pick             # вибір SUPER+SHIFT+A
make theme-menu                        # шпалери, режим, схема кольорів
make binds ROFI=1                      # шпаргалка біндів
make gamemode ACTION=toggle            # анімації, blur, тіні, заокруглення
make idle ACTION=status                # профілі idle для батареї/мережі
make lid ACTION=status                 # поведінка кришки
```

`idle` рендерить `~/.config/hypr/hypridle.conf` і бекапить попередній файл.
`hypridle`/`hyprlock` постачаються з `packages/laptop.txt`, не з `base.txt`.
`autostart.sh` замінює статичний список автозапуску в `hyprland.lua`.

## 4. Монітори й введення

```bash
./install.sh --monitors
./install.sh --mouse
```

Назви моніторів зберігаються в `hosts/<host>/monitors.conf.sh`; інсталятор
рендерить `~/.config/hypr/monitors.lua` і не вшиває розкладку власника в
універсальні шаблони.

Для ноутбука з док-станцією або зовнішнім екраном встановіть опційний модуль
гарячого підключення й виберіть розкладку:

```bash
./install.sh --modules monitor-profiles --dock-layout right
make monitor-profiles ACTION=apply DRY_RUN=1
make monitor-profiles ACTION=watch
```

`watch` слухає сокет подій Hyprland через `socat`. Код профілів моніторів
**не перевірено на реальному док-обладнанні**: спершу зробіть dry run,
збережіть знімок `hyprctl monitors -j`, а в разі хибного результату
скористайтеся `./install.sh --restore`. `DOCK_LAYOUT=ask` ніколи не змінює
монітори.

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

- zram swap, governor `cpupower` і modprobe
- systemd-юніти та drop-in-и, включно з необов'язковим getty autologin
- GRUB, mkinitcpio і `modprobe/nvidia.conf` лише для GPU-профілів `nvidia`
  і `hybrid`
- конфіги Pi-hole + Unbound (рендерять `@IFACE@` з `--iface` або default-route;
  `enp9s0` ніколи не підставляється автоматично)
- NetworkManager `dns=none` / `rc-manager=unmanaged` (лише коли Pi-hole і
  Unbound вже існують; заздалегідь підготуйте DNS-запас)
- пропозиції злиття pacman/makepkg (diff, підтвердження, бекап; з `--yes`
  пропускається)
- опційне вмикання сервісів лише через `systemctl enable`, без `start`

UFW — тільки документація. Репозиторій не змінює стан фаєрвола чи правила;
фактичний стан записано в `system/ufw/README.md`.

Цей самий режим встановлює pacman-hook, який після транзакції пакетів оновлює
`/var/lib/dotfiles/pkg-sync.stamp`. Переглядайте дрейф пізніше через
`make pkg-sync`; `make pkg-sync ACTION=pull YES=1` лише дописує відсутні
пакети в `packages/extra-installed.txt`.

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
make dns-check  # resolv.conf -> Pi-hole -> unbound
make check      # lint + audit + doctor
./tests/run.sh  # повний набір shell-тестів
```

`make doctor` завершується з помилкою лише за наявності failures (ядро вище
CPU, зламані керовані посилання, відсутні файли репозиторію). Попередження —
інформаційні. `./install.sh --doctor --json` дає той самий результат у
машинозчитуваному вигляді; `./install.sh --dns-check` падає, якщо ланцюжок
резолвера не може працювати.

Тести використовують тимчасовий `$HOME` і заглушки системних утиліт. Тести
restore і sync додатково перевіряють, що живі файли не змінилися, а бекап
створено. `tests/run.sh [pattern]` запускає вибрані файли й виключає себе. CI
виконує lint і набір тестів у контейнері `archlinux:latest`.

## 9. Секрети

Ніколи не комітьте:

- `pihole.toml`, DNS/API-секрети
- конфіги rclone, RustDesk та OpenCode
- `.env`, SSH/GPG-ключі
- весь каталог `personal/`
- архіви тем курсора й шпалери

`sanitized` приклади Pi-hole лежать у `system/pihole/`. Ротуйте будь-який
секрет, який колись потрапляв у відстежуваний файл.

## 10. Примітки

- `--all` означає лише модулі + пакети; `/etc` потребує `--system`.
- Кожен замінений файл зберігається в `~/.dotfiles-backup/<timestamp>/`.
- Відновлення: `./install.sh --restore [date]` (або `make restore`) — показує
  diff, питає підтвердження й спершу бекапить поточний стан. Для `/etc`
  потрібен `--system`.
- Копіювання живих змін назад: `make sync-status`, `make sync-diff`,
  `make sync-pull` — напрямок завжди система → репозиторій.
- Перевірки pre-commit: `make hooks` встановлює їх лише в цей репозиторій;
  єдиний обхід — `git commit --no-verify`.
- Обробник кришки й профілі моніторів покриті лише синтетичними тестами.
  Перевіряйте їх на реальному ноутбуці/док-станції спершу з `--dry-run`.
- Жива конфігурація не змінюється без явного кроку інсталятора.
- `make audit` перелічує незамержені `.pacnew` та інший живий drift.
