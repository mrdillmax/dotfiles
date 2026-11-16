# Arch Linux install guide

This guide installs Arch Linux and then applies these dotfiles. It is written
for a UEFI system with GRUB, but the dotfiles themselves are bootloader-neutral.

The repository never edits live files on its own. Every step below is explicit;
the installer backs up anything it replaces.

## 1. Base system

Boot the Arch ISO and follow the official installation guide, or use
`archinstall` with:

- UEFI boot, GPT, a btrfs or ext4 root
- a swap file or zram (this repository ships an optional zram preset)
- locale `en_US.UTF-8` plus `uk_UA.UTF-8` if you want Ukrainian
- a regular user in the `wheel` group
- `NetworkManager` for networking
- GRUB (or another bootloader) and `linux-lts` as the fallback kernel

After the first boot:

```bash
sudo pacman -Syu --needed git base-devel
```

Install an AUR helper (the installer supports `yay` and `paru`):

```bash
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay && makepkg -si
```

## 2. Clone and inspect

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

make lint
make dry-run          # full preview, changes nothing
make doctor           # read-only health check
```

`make dry-run` selects every module and package group but never touches `/etc`.

## 3. Interactive install

```bash
./install.sh
```

Useful non-interactive variants:

```bash
./install.sh --host desktop --gpu nvidia --modules hypr,uwsm,waybar,rofi,kitty,fish
./install.sh --all --yes          # modules + packages, no /etc
./install.sh --modules cursor --cursor-archive ~/Downloads/theme.7z
```

The host (`desktop` or `laptop`) and GPU profile are detected automatically and
can be overridden with `--host` and `--gpu`.

### Cursor theme

Cursor theme files are never committed. The repository stores only the theme
name and size in `hosts/<host>/cursor.conf`, then renders them into uwsm, GTK3,
GTK4, Qt, xsettingsd and (optionally) applies them with `hyprctl setcursor`.

```bash
./install.sh --cursor --cursor-archive /path/to/theme.7z
./install.sh --cursor --cursor-theme Bibata-Modern-Ice --cursor-size 24
```

Without an archive the installer offers package-only themes (`breeze`,
`capitaine-cursors`, `bibata-cursor-theme`). A live `hyprctl setcursor` is only
run after an explicit confirmation.

### Wallpaper

The image is not copied into the repository. Its absolute path is written to
`~/.config/hypr/wallpaper.path`, and `make theme` prefers that file:

```bash
./install.sh --wallpaper ~/Pictures/wallpaper.jpg
make theme
```

## 4. Monitors and input

```bash
./install.sh --monitors
./install.sh --mouse
```

Monitor names live in `hosts/<host>/monitors.conf.sh`; the installer renders
`~/.config/hypr/monitors.lua` and never hardcodes the owner's layout into
universal templates.

## 5. Kernel by CPU level

Pick a kernel that matches the CPU x86-64 microarchitecture level:

```bash
./install.sh --kernel
```

The installer detects the highest level supported by the CPU (`v1`..`v4`) and
offers kernels at or below that level:

- `linux-lts` + headers — fallback, always recommended
- `linux` + headers, `linux-zen` + headers — desktops only
- xanmod `vN` + headers — only at or below the detected level, desktops only

Rules enforced by the installer:

- it never removes the running kernel or the fallback kernel;
- laptops are treated conservatively (no xanmod and no `linux-zen` offer);
- NVIDIA DKMS always gets the matching headers, and a warning is printed if
  DKMS support for a bin kernel is uncertain;
- an above-CPU level requires a red warning **and** typing `I UNDERSTAND`;
- non-interactive mode refuses above-CPU levels.

After installation the installer prints, but never runs:

```bash
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg   # GRUB only
```

Install headers for every kernel used by DKMS. `make doctor` and `make audit`
compare the CPU level with the installed kernel level and report missing
headers.

## 6. Opt-in system files

```bash
sudo ./install.sh --system --iface eno1
```

Only this mode writes `/etc`, one file at a time, with a backup. It never runs
`grub-mkconfig`, `mkinitcpio -P`, and never starts or restarts a service.

What is included:

- zram swap, `cpupower` governor, sysctl and modprobe files
- systemd units and drop-ins
- Pi-hole + Unbound configs (render `@IFACE@` from `--iface` or the default
  route; `enp9s0` is never substituted automatically)
- NetworkManager `dns=none` / `rc-manager=unmanaged` (only when Pi-hole and
  Unbound already exist; keep a DNS safety net)
- pacman/makepkg merge proposals (diff, confirmation, backup; skipped with
  `--yes`)
- optional service enablement with `systemctl enable` only, never `start`

UFW is documentation only. This repository never changes firewall state or
rules; see `system/ufw/README.md` for the recorded live state.

## 7. Theming

```bash
make theme WALLPAPER=~/Pictures/wallpaper.jpg
```

matugen templates regenerate colors for Hyprland, waybar, dunst, GTK, Qt and
Firefox. Generated color files are never committed.

## 8. Verification

```bash
make lint       # bash -n + shellcheck
make audit      # read-only configuration audit
make doctor     # CPU/kernel, cursor, wallpaper, managed symlinks
make check      # lint + audit + doctor
```

`make doctor` exits non-zero only on failures (above-CPU kernel, broken
managed links, missing repository files). Warnings are informational.

## 9. Secrets

Never commit:

- `pihole.toml`, DNS/API secrets
- rclone, RustDesk, OpenCode, Omniroute configs
- `.env`, SSH/GPG keys
- the whole `personal/` directory
- cursor theme archives and wallpapers

`sanitized` Pi-hole examples live in `system/pihole/`. Rotate any credential
that was ever stored in a tracked file.

## 10. Notes

- `--all` means modules + packages only; `/etc` requires `--system`.
- Every replaced file is backed up under `~/.dotfiles-backup/<timestamp>/`.
- Live configuration is never modified without an explicit installer step.
- Unmerged `.pacnew` files and other live drift are listed in `AUDIT.md`.
