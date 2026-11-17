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
- **Checks:** shell test suite under `tests/`, run in CI on an Arch container

Ukrainian documentation: [README.uk.md](README.uk.md).  
Install guide: [docs/arch-install.md](docs/arch-install.md).

## Safety model

- Live configuration files are never modified by this repository on their own.
- The installer **backs up every file it replaces** to
  `~/.dotfiles-backup/<YYYY-MM-DD_HHMMSS>/` and writes a `manifest.tsv`.
- `--dry-run` prints every action and changes nothing.
- `/etc` files are installed **only** with `--system`, one file at a time.
- `grub`, `mkinitcpio` and getty autologin require an extra explicit
  confirmation. The installer never runs `grub-mkconfig` or `mkinitcpio`.
- No service is started or restarted automatically.
- Secrets are excluded from git: `pihole.toml`, rclone, RustDesk and OpenCode
  configs, `.env`, keys and the whole `personal/` directory.
- Generated matugen output is excluded; only templates and
  `matugen/config.toml` are tracked.

## Requirements

- Arch Linux (or an Arch-based distribution) with `pacman`
- `git`, `jq`, `bash` 5.x
- Optional but recommended: `gum` (TUI), `shellcheck` (lint), `yay`/`paru` (AUR)
- For the laptop tools: `hypridle`, `hyprlock` (both in `packages/laptop.txt`)
- For dock hotplug profiles: `socat`
- For GPU profiles: the matching driver packages (`packages/nvidia.txt`,
  Mesa for AMD/Intel, etc.)

## Quick start

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

make lint                 # bash -n + shellcheck
./tests/run.sh            # shell suite; temporary HOME, live files untouched
make dry-run              # full install preview, changes nothing
./install.sh              # interactive installer
```

On a machine that does not have the prerequisites yet:

```bash
./bootstrap.sh            # base-devel/git/curl, then the installer
./bootstrap.sh --dry-run  # show every command first
```

A typical first run:

```bash
./install.sh --host desktop --gpu nvidia --modules hypr,uwsm,waybar,rofi,kitty,fish
./install.sh --monitors   # detect and write the monitor layout
fish -c 'fisher update'   # install the tide prompt plugins
make theme WALLPAPER=~/Pictures/wallpaper.jpg
```

## Bootstrap a fresh machine

```bash
./bootstrap.sh --dry-run
./bootstrap.sh
./bootstrap.sh --yes -- --host laptop --gpu intel
```

Bootstrap installs only the tools the installer needs (`base-devel`, `git`,
`curl`), checks network reachability and reports a missing AUR helper — it
never builds one. It then runs `install.sh` (with `--all --yes` when `--yes` is
given) and finishes with a read-only `--doctor` pass. Everything after `--` is
forwarded to `install.sh`.

## Repository layout

```text
.
├── install.sh                 interactive installer and entry point
├── bootstrap.sh               fresh-machine prerequisites, then install.sh
├── lib/                       common, TUI, monitors, packages, system, secrets
├── profiles/gpu/              nvidia, amd, intel, hybrid, vm, software
├── hosts/
│   ├── desktop/               monitors.conf.sh, input.lua, host env
│   └── laptop/                battery/brightness/touchpad/lid defaults
├── modules/<name>/home/...    files linked or rendered into $HOME
├── system/                    opt-in /etc files (--system)
├── packages/                  package groups + alternatives registry
├── scripts/                   audit, doctor, sync, pkg-sync, DNS check
├── tests/                     shell tests + run.sh local runner
├── .github/workflows/ci.yml   lint + tests on an Arch container
├── personal/                  private files, gitignored
├── docs/                      Arch install guide (EN/UK)
├── Makefile
└── README.md / README.uk.md
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
  --dock-layout LAYOUT  store right|left|mirror|ask for external monitors
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
  --hooks               install the repository pre-commit hook and exit
  --doctor              read-only health check and exit (never needs sudo)
  --json                machine-readable output (with --doctor/--dns-check)
  --dns-check           read-only DNS chain check and exit
  --restore [date]      list backups and restore one (with --modules a,b;
                        /etc also needs --system)
  --sync COMMAND        status|diff|pull|packages
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
| `hypr` | Hyprland Lua config, binds, autostart hook, window rules, generated monitors |
| `autostart` | login-application state manager (`autostart.sh`, `SUPER+SHIFT+A` picker) |
| `binds-cheatsheet` | Hyprland keybind cheatsheet (plain, markdown, JSON, rofi) |
| `gamemode` | toggle animations, blur, shadows and rounding for gaming |
| `idle` | hypridle battery/AC profiles and reload helper |
| `lid` | lid-switch safety handler and hyprlock |
| `monitor-profiles` | dock/external-display hotplug profiles |
| `theme-menu` | rofi menu for wallpaper, matugen mode and colour scheme |
| `uwsm` | `~/.config/uwsm/env` (common + GPU profile) and `env-hyprland` |
| `waybar` | status bar config, style and scripts |
| `rofi` | launcher, power menu and dunst history scripts |
| `kitty` | terminal config |
| `fish` | fish config, aliases and tide plugin list |
| `dunst` | notification daemon (colors generated by matugen) |
| `matugen` | templates and `config.toml` (no generated colors) |
| `theming` | GTK/Qt/KDE settings and the adw-gtk3 symlinks |
| `cursor` | cursor theme/size rendered into uwsm, GTK3/4, Qt, xsettingsd and Hyprland |
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
dispatchers. The `dill-desktop` example preset covers a two-monitor setup.

### Dock and hotplug profiles

The optional `monitor-profiles` module handles a laptop docked to an external
display. The preference lives in `~/.config/hypr/monitor-profiles.conf`:

```bash
DOCK_LAYOUT=right      # right|left|mirror|ask
```

Store it through the installer or change it directly:

```bash
./install.sh --dock-layout right
make monitor-profiles ACTION=status
make monitor-profiles ACTION=apply DRY_RUN=1
make monitor-profiles ACTION=watch
```

`watch` listens on the Hyprland event socket (`socket2`) with `socat` and
debounces bursts, so a dock that registers several outputs at once triggers one
layout pass. `apply` changes the running session only; it never rewrites
Hyprland configuration files. Before applying it saves the current
`hyprctl monitors -j` under `~/.local/state/dotfiles/monitor-profiles/`.
`ask` never changes monitors.

> **Not verified on real dock hardware.** Run `apply --dry-run` first and keep
> the saved monitor snapshot. A first real run should be followed by
> `./install.sh --restore` if the layout is wrong.

## Desktop helpers

These small modules share one rule: state lives under
`~/.local/state/dotfiles/`, never in the compositor config.

### Theme menu

```bash
make theme-menu                 # rofi/gum/whiptail/dialog/plain menu
make theme-menu DRY_RUN=1
```

Choose a wallpaper, matugen mode (`dark`/`light`) and colour scheme. The choice
is stored in `~/.local/state/dotfiles/theme.conf`; `make theme` can then reuse
it.

### Keybind cheatsheet

```bash
make binds                      # aligned table
make binds ROFI=1               # rofi menu
make binds JSON=1               # JSON for scripts
~/.local/bin/binds-cheatsheet.sh --duplicates
```

The cheatsheet parses the Lua configuration, because Hyprland 0.57 with Lua
dispatchers reports opaque numeric arguments in `hyprctl binds -j`.

### Gamemode

```bash
make gamemode ACTION=toggle
make gamemode ACTION=status
make gamemode ACTION=on DRY_RUN=1
```

Enabling disables animations, blur, shadows and rounding. The values that were
active before the first enable are read with `hyprctl getoption` and stored in
`~/.local/state/dotfiles/gamemode.conf`, so enabling twice cannot overwrite the
originals and `off` always restores them.

### Idle and lock

The `idle` module renders `~/.config/hypr/hypridle.conf` from two profiles:

| Profile | Dim | Lock | Screen off | Suspend |
|---------|-----|------|------------|---------|
| battery | 150 | 300 | 330 | 900 |
| AC | 300 | 600 | 660 | 1800 |

`0` disables a stage; enabled stages must satisfy `dim < lock <= off < suspend`.
Settings live in `~/.local/state/dotfiles/idle.conf`.

```bash
make idle ACTION=status
make idle ACTION=apply PROFILE=battery
make idle ACTION=configure              # prompts for all eight values
make idle ACTION=watch                  # re-apply on AC/battery changes
```

The previous `hypridle.conf` is backed up before it is replaced. `hypridle` and
`hyprlock` belong to the laptop package group, not to the base group.

### Lid switch

```bash
make lid ACTION=status
make lid ACTION=closed
make lid ACTION=closed DRY_RUN=1
```

On close, the handler reads `hyprctl monitors -j` immediately before acting:
if another active monitor exists it disables every `eDP-*`/`LVDS`/`DSI` output
and remembers mode, position and scale in `~/.local/state/dotfiles/lid.conf`;
otherwise it suspends through `systemctl`. Opening the lid always restores the
internal panel. logind configuration is never modified. The decision logic is
covered by synthetic tests only, not by physical lid hardware.

### Autostart

```bash
make autostart                        # list
make autostart ACTION=disable NAME=vesktop
make autostart ACTION=add NAME=notes CMD=obsidian
make autostart ACTION=pick            # rofi/gum/whiptail/dialog/plain
```

Entries live in `~/.local/state/dotfiles/autostart.tsv` and are seeded from the
17 built-in applications on first use. `hyprland.lua` calls
`autostart.sh run`; disabling an entry keeps it off at the next login without
editing the Lua config. `SUPER+SHIFT+A` opens the picker.

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
groups, and marks alternatives as `[main, config]` (this repository contains
its config) or `[package only]` (no config here).

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
| `laptop.txt` | hypridle, hyprlock (laptop sessions only) |
| `aur.txt` | AUR-only packages |

`install.sh --no-packages` skips this step entirely.

### Package drift

```bash
make pkg-sync                        # report only
make pkg-sync ACTION=check           # exit 1 when lists drift
make pkg-sync ACTION=pull DRY_RUN=1
make pkg-sync ACTION=pull YES=1      # append, never remove
```

`pkg-sync` compares explicitly installed packages with `packages/*.txt`.
`pull` only appends installed-but-unlisted packages to
`packages/extra-installed.txt`; it never removes an entry and never installs
anything. Host-specific files are compared only on the matching host.

With `--system`, the repository installs a pacman hook that touches
`/var/lib/dotfiles/pkg-sync.stamp` after every package transaction. `status`
warns when the stamp is newer than the last review, so package changes can be
triaged later instead of during the transaction.

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
prompt. If none is available the file is skipped with an error; a fixed
interface name is never substituted in universal templates.

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

`pacman.conf` and `makepkg.conf` are merged, not copied: the installer shows a
diff, asks for confirmation and creates a backup. The merge is skipped with
`--yes`. Optional services are enabled with `systemctl enable` only, never
started or restarted.

UFW is documentation only. The repository does not change firewall state or
rules; see `system/ufw/README.md` for general guidance.

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

To restore a file manually:

```bash
cp -a ~/.dotfiles-backup/2026-11-16_120000/.config/hypr/hyprland.lua \
      ~/.config/hypr/hyprland.lua
```

Or use the built-in restore flow:

```bash
./install.sh --restore                       # list backups with file counts
./install.sh --restore 2026-11-16_120000
make restore RESTORE_DATE=2026-11-16_120000
make restore RESTORE_DATE=2026-11-16_120000 MODULES=hypr DRY_RUN=1
```

Restore reads `manifest.tsv`, shows a diff, asks for confirmation and backs up
the current state before writing. `/etc` files are restored only with
`--system` and a separate confirmation. If a snapper configuration exists, a
pre-restore snapshot is offered.

The installer records managed paths in
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/managed.tsv`. Nothing is deleted
automatically. Other state files in the same directory: `theme.conf`,
`gamemode.conf`, `idle.conf`, `autostart.tsv`, `lid.conf`,
`monitor-profiles/` and `sync-backup/`.

## Syncing live changes back

The direction is always **live system → repository**. Nothing under `$HOME` is
written.

```bash
make sync-status                    # files that differ
make sync-diff SYNC_TARGET=hypr     # unified diffs
make sync-pull DRY_RUN=1            # preview
make sync-pull YES=1                # write back (diff + secret scan)
./scripts/sync.sh packages          # compare installed packages
```

Pull reverse-renders `@HOME@`, `@FIREFOX_PROFILE_DIR@` and `@OBSIDIAN_VAULT@`,
skips generated matugen output, `personal/` and secret paths, and runs the
secret scanner before writing. A pre-pull copy of every repository file is
stored under `~/.local/state/dotfiles/sync-backup/<timestamp>/` with a
`manifest.tsv`.

## Checks, tests and CI

```bash
make lint       # bash -n + shellcheck
make audit      # read-only live + repository audit
make doctor     # CPU/kernel level, cursor, wallpaper, managed symlinks
make dns-check  # resolv.conf -> Pi-hole -> unbound
make check      # lint + audit + doctor
./tests/run.sh  # full shell suite
make hooks      # install the repository pre-commit hook
```

The audit checks Hyprland config errors, duplicate binds, monitor portability,
hardcoded home paths, systemd units, Unbound syntax, `.pacnew` files, secrets,
generated files, and the CPU level versus the installed kernel level. It never
edits anything and never requires root.

`./install.sh --doctor` is the same read-only check with `--json` available;
`./install.sh --dns-check` verifies the DNS chain and warns that a configuration
needs a working Pi-hole/Unbound pair before `--system` changes resolver files.

Every test uses a temporary `$HOME`/`XDG_STATE_HOME` and stub system tools, so
the live configuration, package database and monitors are never touched.
Restore and sync tests additionally verify that live files stay unchanged and
that a backup is created. `tests/run.sh [pattern] [-v] [--list]` runs one or all
files and never runs itself. CI (`.github/workflows/ci.yml`) runs `make lint`
and the suite in an `archlinux:latest` container.

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
