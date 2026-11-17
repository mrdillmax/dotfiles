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
./tests/run.sh        # temporary HOME; live files are never touched
make dry-run          # full preview, changes nothing
make doctor           # read-only health check
```

`make dry-run` selects every module and package group but never touches `/etc`.

If the machine lacks the prerequisites (`base-devel`, `git`, `curl`), bootstrap
can install them and then start the installer:

```bash
./bootstrap.sh --dry-run
./bootstrap.sh --yes -- --host laptop --gpu intel
```

Bootstrap never builds an AUR helper; it only reports a missing `yay`/`paru`.
Everything after `--` is passed to `install.sh`.

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

### State and daily helpers

Small runtime tools keep their state under `~/.local/state/dotfiles/`, not in
the compositor config:

```bash
make autostart                         # list login applications
make autostart ACTION=pick             # SUPER+SHIFT+A picker
make theme-menu                        # wallpaper, mode, colour scheme
make binds ROFI=1                      # keybind cheatsheet
make gamemode ACTION=toggle            # animations, blur, shadows, rounding
make idle ACTION=status                # battery/AC idle profiles
make lid ACTION=status                 # lid-switch behaviour
```

`idle` renders `~/.config/hypr/hypridle.conf` and backs up the previous file.
`hypridle`/`hyprlock` come from `packages/laptop.txt`, not from `base.txt`.
`autostart.sh` replaces the static login list in `hyprland.lua`.

## 4. Monitors and input

```bash
./install.sh --monitors
./install.sh --mouse
```

Monitor names live in `hosts/<host>/monitors.conf.sh`; the installer renders
`~/.config/hypr/monitors.lua` and never hardcodes a monitor layout into
universal templates.

For a laptop with a dock or an external display, install the optional hotplug
module and choose a layout:

```bash
./install.sh --modules monitor-profiles --dock-layout right
make monitor-profiles ACTION=apply DRY_RUN=1
make monitor-profiles ACTION=watch
```

`watch` listens on the Hyprland event socket with `socat`. The monitor-profile
code is **not verified on real dock hardware**: run a dry run first, keep the
saved `hyprctl monitors -j` snapshot, and use `./install.sh --restore` if the
result is wrong. `DOCK_LAYOUT=ask` never changes monitors.

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

- zram swap, `cpupower` governor and modprobe files
- systemd units and drop-ins, including optional getty autologin
- GRUB, mkinitcpio and `modprobe/nvidia.conf` only for the `nvidia` and
  `hybrid` GPU profiles
- Pi-hole + Unbound configs (render `@IFACE@` from `--iface` or the default
  route; a fixed interface name is never substituted automatically)
- NetworkManager `dns=none` / `rc-manager=unmanaged` (only when Pi-hole and
  Unbound already exist; keep a DNS safety net)
- pacman/makepkg merge proposals (diff, confirmation, backup; skipped with
  `--yes`)
- optional service enablement with `systemctl enable` only, never `start`

UFW is documentation only. This repository never changes firewall state or
rules; see `system/ufw/README.md` for general guidance.

The same mode installs a pacman hook that touches
`/var/lib/dotfiles/pkg-sync.stamp` after a package transaction. Review package
drift later with `make pkg-sync`; `make pkg-sync ACTION=pull YES=1` only
appends missing packages to `packages/extra-installed.txt`.

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
make dns-check  # resolv.conf -> Pi-hole -> unbound
make check      # lint + audit + doctor
./tests/run.sh  # full shell suite
```

`make doctor` exits non-zero only on failures (above-CPU kernel, broken
managed links, missing repository files). Warnings are informational.
`./install.sh --doctor --json` gives the same result in machine-readable form;
`./install.sh --dns-check` fails when the resolver chain cannot work.

The tests use a temporary `$HOME` and stub system tools. Restore and sync tests
also verify that live files stay unchanged and that a backup is created.
`tests/run.sh [pattern]` runs selected files and excludes itself. CI runs lint
and the suite inside an `archlinux:latest` container.

## 9. Secrets

Never commit:

- `pihole.toml`, DNS/API secrets
- rclone, RustDesk and OpenCode configs
- `.env`, SSH/GPG keys
- the whole `personal/` directory
- cursor theme archives and wallpapers

`sanitized` Pi-hole examples live in `system/pihole/`. Rotate any credential
that was ever stored in a tracked file.

## 10. Notes

- `--all` means modules + packages only; `/etc` requires `--system`.
- Every replaced file is backed up under `~/.dotfiles-backup/<timestamp>/`.
- Restore with `./install.sh --restore [date]` (or `make restore`): it shows a
  diff, confirms, and backs up the current state first. `/etc` needs `--system`.
- Copy live changes back with `make sync-status`, `make sync-diff`,
  `make sync-pull` — direction is always system → repository.
- Pre-commit safety checks: `make hooks` installs them into this repository
  only; `git commit --no-verify` is the only bypass.
- The lid handler and monitor profiles are covered by synthetic tests only.
  Verify them on the real laptop/dock with `--dry-run` first.
- Live configuration is never modified without an explicit installer step.
- `make audit` lists unmerged `.pacnew` files and other live drift.
