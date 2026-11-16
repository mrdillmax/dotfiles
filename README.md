# dotfiles

Personal Arch Linux + Hyprland (Lua config) + uwsm dotfiles for a desktop and a
laptop. The repository is the source of truth; the installer renders
machine-specific values and links the rest into `$HOME`.

- **Compositor:** Hyprland 0.57 with the Lua configuration API
- **Session:** uwsm
- **Shell:** fish
- **Bar / launcher / notifications:** waybar, rofi, dunst
- **Theming:** matugen templates (generated colors are never committed)
- **Packages:** pacman + an AUR helper (`yay` or `paru`)

Ukrainian documentation: [README.uk.md](README.uk.md).  
Install guide: [docs/arch-install.md](docs/arch-install.md).  
Read-only findings and pending fixes: [AUDIT.md](AUDIT.md).

## Safety model

- Live configuration files are never modified by this repository on their own.
- The installer **backs up every file it replaces** to
  `~/.dotfiles-backup/<YYYY-MM-DD_HHMMSS>/` and writes a `manifest.tsv`.
- `--dry-run` prints every action and changes nothing.
- `/etc` files are installed **only** with `--system`, one file at a time.
- `grub`, `mkinitcpio` and getty autologin require an extra explicit
  confirmation. The installer never runs `grub-mkconfig` or `mkinitcpio`.
- No service is started or restarted automatically.
- Secrets are excluded from git: `pihole.toml`, rclone/rustdesk/opencode/
  omniroute configs, `.env`, keys and the whole `personal/` directory.
- Generated matugen output is excluded; only templates and
  `matugen/config.toml` are tracked.

## Requirements

- Arch Linux (or an Arch-based distribution) with `pacman`
- `git`, `jq`, `bash` 5.x
- Optional but recommended: `gum` (TUI), `shellcheck` (lint), `yay`/`paru` (AUR)
- For GPU profiles: the matching driver packages (`packages/nvidia.txt`,
  Mesa for AMD/Intel, etc.)

## Quick start

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

make lint                 # bash -n + shellcheck
make dry-run              # full install preview, changes nothing
./install.sh              # interactive installer
```

A typical first run:

```bash
./install.sh --host desktop --gpu nvidia --modules hypr,uwsm,waybar,rofi,kitty,fish
./install.sh --monitors   # detect and write the monitor layout
fish -c 'fisher update'   # install the tide prompt plugins
make theme WALLPAPER=~/Pictures/wallpaper.jpg
```

## Repository layout

```text
.
├── install.sh                 interactive installer and entry point
├── lib/                       common, TUI, monitors, packages, system, secrets
├── profiles/gpu/              nvidia, amd, intel, hybrid, vm, software
├── hosts/
│   ├── desktop/               monitors.conf.sh, input.lua, host env
│   └── laptop/                battery/brightness/touchpad/lid defaults
├── modules/<name>/home/...    files linked or rendered into $HOME
├── system/                    opt-in /etc files (--system)
├── packages/                  package groups + alternatives registry
├── scripts/                   audit, mouse tuner wrapper
├── personal/                  private files, gitignored
├── docs/                      Arch install guide (EN/UK)
├── Makefile
├── README.md / README.uk.md
└── AUDIT.md
```

## Installer

```text
./install.sh [options]

  --all                 select every module and package group
  --dry-run             show actions, change nothing
  --yes, -y             answer "yes" to confirmations
  --modules a,b,c       install only these modules
  --no-packages         skip package installation
  --host desktop|laptop override host detection
  --gpu PROFILE         nvidia|amd|intel|hybrid|vm|software
  --monitors            reconfigure the monitor layout and exit
  --mouse               run the mouse/touchpad tuner
  --cursor              install/configure the cursor theme and exit
  --cursor-archive PATH install a cursor theme from a local archive (not committed)
  --cursor-theme NAME   cursor theme name (default: host cursor.conf)
  --cursor-size N       cursor size 16..128 (default: 24)
  --wallpaper PATH      store the wallpaper path and optionally apply it
  --system              install opt-in /etc files (run with sudo)
  --iface IFACE         network interface for Pi-hole (@IFACE@ rendering)
  --kernel              detect the CPU level and install a matching kernel
  --kernel-level LEVEL  override the kernel level: v1..v4
  --list                list modules, GPU profiles and package groups
  -h, --help            help
```

`--all` means **modules + packages**, not `/etc`. System files are always
opt-in through `--system`.

The installer detects the host type from `/sys/class/power_supply/BAT*` and the
DMI chassis type, and the GPU profile from `lspci`/`systemd-detect-virt`. Both
can be overridden. With `gum`, selection is an interactive checklist; without
it, a plain numbered prompt is used.

### Modules

| Module | What it installs |
|--------|------------------|
| `hypr` | Hyprland Lua config, binds, autostart, window rules, generated monitors |
| `uwsm` | `~/.config/uwsm/env` (common + GPU profile) and `env-hyprland` |
| `waybar` | status bar config, style and scripts |
| `rofi` | launcher, power menu and dunst history scripts |
| `kitty` | terminal config |
| `fish` | fish config, aliases and tide plugin list |
| `dunst` | notification daemon (colors generated by matugen) |
| `matugen` | templates and `config.toml` (no generated colors) |
| `theming` | GTK/Qt/KDE settings and the adw-gtk3 symlinks |
| `cursor` | cursor theme/size rendered into uwsm, GTK3/4, Qt, xsettingsd and Hyprland |
| `scripts` | helper scripts in `~/.local/bin` |
| `systemd-user` | rclone sync, omniroute backup and invite-site units |
| `apps` | btop, micro, spicetify, vesktop, Firefox chrome, dolphinrc |
| `workspaces-split` | per-monitor workspace slots; offered only with 2+ monitors |
| `mouse-sensitivity` | interactive pointer tuner and the input overlay |

### Host profiles

| Host | Detection | Specifics |
|------|-----------|-----------|
| `desktop` | no battery | NVIDIA profile, two-monitor preset available |
| `laptop` | battery present | battery, brightness, touchpad, lid/suspend, power-profiles-daemon, `eDP-*` |

### GPU profiles

| Profile | Environment |
|---------|-------------|
| `nvidia` | `LIBVA_DRIVER_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `NVD_BACKEND=direct` |
| `amd` | `LIBVA_DRIVER_NAME=radeonsi` |
| `intel` | `LIBVA_DRIVER_NAME=iHD` (or `i965` for older hardware) |
| `hybrid` | NVIDIA variables + `__NV_PRIME_RENDER_OFFLOAD=1`, `__VK_LAYER_NV_optimus=NVIDIA_only`; `AQ_DRM_DEVICES` is set per host |
| `vm` | no vendor variables; optional `AQ_NO_KMS_REQUIREMENT=1` |
| `software` | `LIBGL_ALWAYS_SOFTWARE=1` |

The selected profile is appended to `modules/uwsm/home/.config/uwsm/env.common`
and rendered to `~/.config/uwsm/env`. `env-hyprland` is separate because
`HYPR*`/`AQ_*` variables must not leak into other sessions.

## Monitors

The single source of truth is `hosts/<host>/monitors.conf.sh`. The installer
renders two files from it:

- `~/.config/hypr/monitors.lua` — calls `hl.monitor()` and
  `hl.workspace_rule()`, and returns the monitor list;
- `~/.config/hypr/monitors.conf.sh` — the copy read by `switch_ws.sh`.

`hyprland.lua` loads `monitors.lua` with `pcall(dofile, ...)`. If the file is
missing or invalid, it falls back to `preferred,auto,1`, so a fresh install
still starts.

`./install.sh --monitors` detects connected outputs (`hyprctl monitors`, then
`/sys/class/drm`) and offers:

1. single monitor;
2. two or more monitors, choosing left-to-right order and positions;
3. auto (`preferred`, automatic positions);
4. the `dill-desktop` preset (`HDMI-A-2` left, `DP-1` right, both
   1920x1080@60, workspaces 1–10 and 11–20);
5. manual editing of `hosts/<host>/monitors.conf.sh`.

For a laptop, the generated layout supports fractional scale and any `eDP-*`
panel; lid and external-monitor behaviour belongs to the laptop host profile.

The `workspaces-split` module is offered only when two or more monitors are
detected. It installs `~/.config/hypr/switch_ws.sh`, which reads monitor names
and workspace ranges from the generated `monitors.conf.sh` — nothing is
hardcoded. Without the module, `SUPER+1..0` uses Hyprland's native workspace
dispatchers. The owner's two-monitor behaviour is preserved as the
`dill-desktop` preset. The live `switch_ws.sh` works and is verified; it is not
a bug.

## Mouse and touchpad tuner

```bash
make mouse
./install.sh --mouse
~/.local/bin/mouse-tune.sh          # after installation
./scripts/mouse-tune.sh --show      # read-only current values
```

The tuner requires a running Hyprland session and uses the Lua runtime API:

```bash
hyprctl eval 'hl.config({ input = { sensitivity = -0.3 } })'
hyprctl eval 'hl.device({ name = "...", sensitivity = -0.2 })'
```

What it can change live:

- `input:sensitivity` in `-1.0…1.0`, step `0.05`, fine step `0.01` (`f`);
- `input:accel_profile` (`flat` / `adaptive` / default);
- `input:force_no_accel`;
- `input:scroll_factor`;
- per-device overrides from `hyprctl devices` (sensitivity, acceleration,
  scroll factor);
- laptop touchpad: `natural_scroll`, `tap_to_click`,
  `disable_while_typing`.

Keys in the live slider: `←`/`→` or `-`/`+` change the value, `f` toggles the
fine step, `r` resets to the session value, `Enter`/`q` finishes.

> **Important:** there is no `scroll_factor` option for a mouse in older
> Hyprland versions. The tuner offers it where `hyprctl getoption` reports it;
> otherwise it is simply not shown.

Saving writes only to `hosts/<host>/input.lua` in the repository (or to
`~/.config/hypr/input.lua` when no repository is found). It shows a unified
diff, asks for confirmation and creates a backup. The live `hyprland.lua` is
never edited. The overlay is loaded with:

```lua
pcall(dofile, HOME .. "/.config/hypr/input.lua")
```

so a missing file is safe.

## Packages

Package groups live in `packages/<category>.txt`. The installer lets you pick
groups, and marks alternatives as `[main, config]` (the owner uses it and this
repository contains its config) or `[package only]` (no config here).

| Category | Main (config included) | Alternatives (package only) |
|----------|------------------------|-----------------------------|
| terminal | kitty | foot, alacritty, wezterm, ghostty |
| launcher | rofi | fuzzel, wofi, anyrun |
| status bar | waybar | hyprpanel, ags |
| notifications | dunst | mako, swaync |
| browser | firefox | chromium, brave-bin, librewolf |
| file manager | dolphin | nautilus, thunar, yazi |
| system monitor | btop | htop, bottom |
| editor | micro | neovim, kate |
| music | spotify-launcher | amberol, elisa |
| kernel | managed by `--kernel` | linux, linux-lts, linux-zen, linux-hardened |

Group overview:

| Group | Contents |
|-------|----------|
| `base.txt` | boot, storage, CLI tools, fonts-independent basics |
| `hyprland.txt` | compositor, portals, Wayland utilities, theming |
| `shell.txt` | fish + fisher |
| `audio.txt` | PipeWire, Carla, Guitarix, REAPER |
| `desktop.txt` | everyday GUI applications |
| `media.txt` | image/thumbnail CLI tools |
| `dev.txt` | compilers, SDKs, editors |
| `network.txt` | NetworkManager, Pi-hole, Unbound, rclone, ZeroTier |
| `virtualization.txt` | Docker, libvirt/QEMU, Steam, Wine, Waydroid |
| `nvidia.txt` | NVIDIA 580xx stack and monitoring |
| `tuning.txt` | CPU/IO tuning and stress tools |
| `fonts.txt` | fonts and Ukrainian language support |
| `aur.txt` | AUR-only packages |

`install.sh --no-packages` skips this step entirely.

### Kernel and CPU level

```bash
./install.sh --kernel
```

The installer detects the CPU x86-64 level (`v1`..`v4`) and offers kernels at
or below it: `linux-lts` (fallback), `linux`, `linux-zen`, and a matching
xanmod level on desktops. Laptops are treated conservatively. An above-CPU
level requires a red warning and typing `I UNDERSTAND`; non-interactive mode
refuses it. The running kernel and the fallback kernel are never removed.

NVIDIA DKMS always gets matching headers. The installer prints
`mkinitcpio`/`grub-mkconfig` commands and never runs them. `make doctor`
compares the CPU level with the installed kernel level.

## Theming

Colours are generated with matugen from a wallpaper:

```bash
make theme WALLPAPER=~/Pictures/wallpaper.jpg
```

Without `WALLPAPER`, `make theme` first reads
`~/.config/hypr/wallpaper.path` (written by `./install.sh --wallpaper`) and
falls back to the `image` field in `~/.config/hypr/colors.lua`. The image itself
is never committed. The generated files are ignored by git:

- `~/.config/hypr/colors.lua`
- waybar/rofi/kitty/dunst colours
- GTK/Qt colour schemes
- btop/micro/spicetify/vesktop outputs
- Firefox `colors.css`

Only `matugen/config.toml` and the templates in
`modules/matugen/home/.config/matugen/templates/` are tracked. The GTK4
`gtk.css`, `gtk-dark.css` and `assets` entries are symlinks to
`/usr/share/themes/adw-gtk3-dark/gtk-4.0/`; the `theming` module recreates them.

## System configuration (`--system`)

Run with root:

```bash
sudo ./install.sh --system --iface eno1
```

Only this mode writes `/etc`, one file at a time, after a backup. `@IFACE@` is
rendered from `--iface`, then the default-route interface, then an interactive
prompt. If none is available the file is skipped with an error; `enp9s0` is
never substituted in universal templates.

Manifest:

| Source | Destination |
|--------|-------------|
| `system/zram/zram-generator.conf` | `/etc/systemd/zram-generator.conf` |
| `system/cpupower/cpupower` | `/etc/default/cpupower` |
| `system/networkmanager/dns.conf` | `/etc/NetworkManager/conf.d/dns.conf` (Pi-hole + Unbound only) |
| `system/networkmanager/rc-manager.conf` | `/etc/NetworkManager/conf.d/rc-manager.conf` (Pi-hole + Unbound only) |
| `system/unbound/unbound.conf` | `/etc/unbound/unbound.conf` |
| `system/pihole/dnsmasq.conf` | `/etc/pihole/dnsmasq.conf` |
| `system/pihole/pihole.toml.example` | `/etc/pihole/pihole.toml` (only after review) |
| `system/wait-iface/wait-iface.sh` | `/usr/local/bin/wait-iface.sh` |
| `system/systemd/...` | `/etc/systemd/system/...` |
| `system/grub/default-grub` | `/etc/default/grub` (extra confirmation) |
| `system/mkinitcpio/mkinitcpio.conf` | `/etc/mkinitcpio.conf` (extra confirmation) |
| `system/modprobe/*` | `/etc/modprobe.d/*` |
| `system/sysctl/*` | `/etc/sysctl.d/*` |

`pacman.conf` and `makepkg.conf` are merged, not copied: the installer shows a
diff, asks for confirmation and creates a backup. The merge is skipped with
`--yes`. Optional services are enabled with `systemctl enable` only, never
started or restarted.

UFW is documentation only. The repository does not change firewall state or
rules; see `system/ufw/README.md` for the recorded live state.

Not managed by this repository: `/etc/fstab`, NetworkManager connection
profiles, snapper configuration. The installer never runs `grub-mkconfig` or
`mkinitcpio -P`; it prints the commands to review manually. Kernel work belongs
to `./install.sh --kernel`; `--system` only reports CPU/kernel drift.

`pihole.toml` itself is excluded. The example has empty `pwhash`,
`totp_secret`, `app_pwhash` and `cli_pw = false`; review it and copy secrets
yourself.

## Backups and restore

Every replaced file is copied to:

```text
~/.dotfiles-backup/<YYYY-MM-DD_HHMMSS>/<path relative to $HOME>
~/.dotfiles-backup/<YYYY-MM-DD_HHMMSS>/manifest.tsv
```

To restore a file:

```bash
cp -a ~/.dotfiles-backup/2026-11-16_120000/.config/hypr/hyprland.lua \
      ~/.config/hypr/hyprland.lua
```

The installer records managed paths in
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/managed.tsv`. Nothing is deleted
automatically.

## Audit and lint

```bash
make lint     # bash -n + shellcheck
make audit    # read-only live + repository audit
make doctor   # CPU/kernel level, cursor, wallpaper, managed symlinks
make check    # lint + audit + doctor
```

The audit checks Hyprland config errors, duplicate binds, monitor portability,
hardcoded home paths, systemd units, Unbound syntax, `.pacnew` files, secrets,
generated files, and the CPU level versus the installed kernel level. It never
edits anything and never requires root.

## Secrets that must be rotated

The following were visible during the migration work and should be considered
compromised; rotate them manually:

- OpenCode API key/password;
- rclone token (`~/.config/rclone/rclone.conf`);
- RustDesk credentials.

They are intentionally not part of this repository. `.example` templates are the
only placeholders that may be committed.

## License

No license file is included yet. Add one before publishing the repository.
