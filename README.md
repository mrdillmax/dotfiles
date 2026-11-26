# dotfiles

Arch Linux + Hyprland + uwsm dotfiles for a desktop and a laptop.
Run `./install.sh --dry-run` before installing anything — it shows every
action without changing files.

- **Compositor:** Hyprland (Lua config)
- **Session:** uwsm
- **Shell:** fish, **Terminal:** kitty
- **Bar / launcher / notifications:** waybar, rofi, dunst
- **Browser:** Firefox
- **Theme:** Inter + JetBrainsMono Nerd Font, matugen colour generation
- **Packages:** 280+ across 21 categories (pacman + AUR helper)
- **Checks:** shell test suite under `tests/`

[README українською](README.uk.md) · [Arch install guide](docs/arch-install.md)

<!-- screenshot: Hyprland session showing waybar, rofi launcher, and a few windows -->

## What you get

A complete desktop environment: tiling compositor, custom bar, rofi launcher
with a control center, fish shell with tide prompt, kitty terminal, Firefox
with Ukrainian locale, btop system monitor, clipboard manager (cliphist),
screenshot tool (grim + swappy), dunst notifications, and optional Pi-hole
DNS, Syncthing, UFW firewall, and game tools (Steam, MangoHud, gamescope).

## Quick start

```bash
git clone https://github.com/<user>/dotfiles ~/Projects/dotfiles
cd ~/Projects/dotfiles

./install.sh --dry-run          # inspect everything first
./install.sh                    # interactive menu
./install.sh --monitors         # detect monitor layout
fish -c 'fisher update'         # install tide prompt plugins
./install.sh --wallpaper ~/path/to/wall.jpg
./install.sh --theme            # generate colours from wallpaper
```

On a fresh machine run `./bootstrap.sh` first (installs base-devel, git, jq,
gum, and an AUR helper). Every menu action maps to a flag — the menu is just
a wrapper around `./install.sh`.

## Daily use

| Action | Key | Tool |
|--------|-----|------|
| Launcher | `SUPER + R` | rofi |
| Control Center | `SUPER + SHIFT + R` | install.sh menu |
| Terminal | `SUPER + T` | kitty |
| Files | `SUPER + E` | dolphin |
| Clipboard history | `SUPER + V` | cliphist menu |
| Screenshot (area) | `SUPER + S` | grimblast → clipboard |
| Screenshot + edit | `SUPER + SHIFT + S` | swappy |
| Lock screen | `SUPER + L` | lock-screen.sh |
| Power menu | `SUPER + Escape` | rofi |
| Colour picker | `SUPER + P` | hyprpicker |
| Calculator | `SUPER + C` | qalculate-gtk |
| Window close | `SUPER + Q` | hyprctl kill |
| Toggle float | `SUPER + Z` | — |
| Split layout | `SUPER + J` | toggplitsplit |
| Workspace 1-10 | `SUPER + 1…0` | — |
| Move window to ws | `SUPER + SHIFT + 1…0` | — |
| Focus direction | `SUPER + arrow` | — |
| Switch workspace | `SUPER + mouse scroll` | — |
| Drag / resize | `SUPER + mouse drag / right` | — |

Brightness (scroll or keys) and volume (keys) are handled by the `osd` module.
Brightness clamps at 5 % and 100 %.

## Settings

### GPU profile

Six profiles: `nvidia`, `amd`, `intel`, `hybrid`, `vm`, `software`.
Each sets the right `LIBVA_DRIVER_NAME` and vendor variables. Set it in the
menu under **Profile** or with `--gpu`. NVIDIA hosts also offer driver-stack
selection (open, 580xx-dkms, legacy).

### Wallpaper & theme

```bash
./install.sh --wallpaper ~/path/to/image.jpg
./install.sh --theme          # matugen colour generation
./install.sh --theme-menu     # pick wallpaper, mode, scheme
```

Colours are generated from the current wallpaper and applied to GTK, Qt,
waybar, rofi, dunst, and hyprlock templates. Generated files live in
`~/.config/matugen/` and are never committed.

### Mouse & touchpad

```bash
./install.sh --mouse
```

Interactive tuner: sensitivity, acceleration profile, natural scroll,
tap-to-click, per-device overrides, three- and four-finger workspace
gestures. Settings are saved to `hosts/<host>/input.lua`.

### Kernel

```bash
./install.sh --kernel
```

Detects CPU x86-64 level (v1–v4) and offers matching kernels:
`linux-lts` (fallback), `linux`, `linux-zen`, `xanmod` (desktop).
Above-CPU level requires `I UNDERSTAND`.

### System (/etc)

```bash
sudo ./install.sh --system
```

One file at a time, confirmed individually. Options: DNS (Pi-hole + unbound),
zram, cpupower, irqbalance/ananicy-cpp, GRUB, mkinitcpio, getty autologin,
UFW firewall. Each file is backed up before replacing.

### Package management

```bash
./install.sh --only-packages --category Games    # install a category
./install.sh --pkg-sync status                   # check for drift
./install.sh --pkg-sync pull --yes               # add unlisted packages
```

The package catalog lives in `packages/catalog.tsv`. `--all` installs
default=yes rows across all categories. `local.tsv` tracks manually
installed packages detected by `pkg-sync`.

## FAQ

**Q: Can I use this on a laptop?**
A: Yes. The `laptop` host enables battery warnings, lid handling, and
power-profiles-daemon integration. Select it in the menu or with
`--host laptop`.

**Q: Does it work without internet?**
A: The installer needs pacman + AUR access for packages. Config files
are committed and don't require network. After install, most features
work offline.

**Q: How do I switch back to the default shell?**
A: Run `chsh -s /bin/bash` (or `/bin/zsh`). The fish config is only
in `~/.config/fish/` and `~/.local/share/fish/`.

**Q: Is this safe to run with sudo?**
A: System files are installed one at a time with confirmation. Every
replaced file is backed up under `~/.dotfiles-backup/<timestamp>/`.
No service is restarted and no bootloader is regenerated.

## Repository structure

```
install.sh          Interactive installer (menu + flags)
bootstrap.sh        Fresh machine prerequisites → install.sh
lib/                Shared functions: common, tui, menu, packages, …
modules/<name>/     Each module: module.conf + home/… config files
hosts/<host>/       Host-specific: monitors, input, env overrides
profiles/gpu/       GPU profile templates (nvidia, amd, …)
system/             Opt-in /etc files (--system)
packages/catalog.tsv  280+ packages, 21 categories
migrations/         Version-upgrade scripts (NNN-name.sh)
tests/              Shell test suite
assets/             Cursor themes, artwork
```

## Links

- [Arch install guide](docs/arch-install.md)
- [Module reference](docs/modules.md)
- [System config](system/README.md)
- [Third-party licenses](THIRD_PARTY.md)
- [Bug report / discussion](https://github.com/<user>/dotfiles)

MIT License. See [LICENSE](LICENSE).
