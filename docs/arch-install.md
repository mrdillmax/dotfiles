# Arch Linux install guide

This guide installs Arch Linux and then applies these dotfiles. It assumes
a UEFI system with GRUB; the dotfiles themselves are bootloader-neutral.

The repository never edits live files on its own. Every step is explicit;
the installer backs up anything it replaces.

## 1. Install Arch Linux

Boot the Arch ISO and follow the [official installation guide](https://wiki.archlinux.org/title/Installation_guide). Recommended settings:

- UEFI boot, GPT, btrfs or ext4 root partition
- A swap file or zram (this repo ships an optional zram preset)
- Locale `en_US.UTF-8`, optionally `uk_UA.UTF-8`
- A regular user in the `wheel` group
- `NetworkManager` for networking
- GRUB as bootloader, `linux-lts` as fallback kernel

After the first boot, log in as your user and update the system:

```bash
sudo pacman -Syu --needed git base-devel
```

## 2. Install an AUR helper

The installer supports `yay` and `paru`. Choose one:

```bash
# Option A: yay
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay && makepkg -si

# Option B: paru
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si
```

## 3. Clone and inspect

```bash
git clone <your-repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh --dry-run
```

The first screen shows the detected host (desktop / laptop), GPU profile,
monitor count and CPU level. You can change any of them before proceeding.
Every action returns to the menu, and the top entry toggles `--dry-run`
for the whole session.

## 4. Run the installer

```bash
./install.sh
```

The menu walks you through:

1. **Profile** — confirm host (`desktop` / `laptop`) and GPU profile
2. **Modules** — select which config modules to install (all selected by default)
3. **Packages** — choose categories and individual packages
4. **System** — opt-in /etc files (requires sudo): DNS, zram, services, etc.
5. **Kernel** — detect CPU level and install a matching kernel

Each step is confirmed individually. Files are backed up before replacement.

If you prefer non-interactive mode:

```bash
./install.sh --all --gpu nvidia --host desktop --yes
```

## 5. Configure monitors

```bash
./install.sh --monitors
```

This detects your connected displays and writes the layout to
`hosts/<host>/monitors.lua`. The file is rendered into
`~/.config/hypr/monitors.lua` on install.

## 6. Finish fish setup

```bash
fish -c 'fisher update'
```

This installs the tide prompt plugins. You may need to restart your
terminal for the changes to take effect.

## 7. Set wallpaper and theme

```bash
./install.sh --wallpaper ~/Pictures/wallpaper.jpg
./install.sh --theme
```

This generates colours from the wallpaper using matugen and applies
them to GTK, Qt, waybar, rofi, dunst, and hyprlock.

## 8. Optional: system configuration

```bash
sudo ./install.sh --system
```

This installs /etc files one at a time, each confirmed separately:

- **DNS** — Pi-hole + unbound (ad-blocking DNS)
- **zram** — compressed swap device
- **Services** — irqbalance, ananicy-cpp, cpupower
- **GRUB / mkinitcpio** — boot configuration (NVIDIA/hybrid only)
- **Autologin** — getty autologin drop-in
- **UFW** — firewall with a minimal policy

Without `--system`, no /etc files are touched.

## Verification

```bash
./install.sh --doctor    # read-only health check
./install.sh --dns-check # DNS chain check
```

## Troubleshooting

**Waybar doesn't start:** check that the `waybar` module is installed
and that `~/.config/waybar/config.jsonc` exists. Run `waybar` directly
to see error output.

**No sound:** ensure `pipewire-pulse` and `pavucontrol` are installed,
then run `pavucontrol` to set the default device.

**GPU profile wrong:** run `./install.sh` and reselect the profile in
the menu. The installer updates `~/.config/uwsm/env` and
`~/.config/uwsm/env-hyprland`.

**Packages missing:** run `./install.sh --only-packages` and select
the needed category. Or check `packages/catalog.tsv` for the package
name.

## Uninstall

```bash
./install.sh --uninstall              # remove all installed files
./install.sh --uninstall --modules hypr  # remove specific module
sudo ./install.sh --uninstall --system # remove /etc files
```
