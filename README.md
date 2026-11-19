# dotfiles

Personal Arch Linux + Hyprland + uwsm dotfiles for a desktop and a laptop.
These are personal dotfiles: run `./install.sh --dry-run` and read the output
before you install anything.

The repository is the source of truth. The installer renders machine-specific
values and links the rest into `$HOME`.

- **Compositor:** Hyprland 0.57 with the Lua configuration API
- **Session:** uwsm
- **Shell:** fish
- **Bar / launcher / notifications:** waybar, rofi, dunst
- **Theming:** matugen templates (generated colors are never committed)
- **Packages:** pacman + an AUR helper (`yay` or `paru`)
- **Checks:** shell test suite under `tests/`, run in CI on an Arch container

Ukrainian documentation: [README.uk.md](README.uk.md).  
Install guide: [docs/arch-install.md](docs/arch-install.md).

## Contents

- [Status](#status)
- [Safety model](#safety-model)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Bootstrap a fresh machine](#bootstrap-a-fresh-machine)
- [Repository layout](#repository-layout)
- [Where is what](#where-is-what)
- [Installer](#installer)
- [Modules](#modules)
- [Host profiles](#host-profiles)
- [GPU profiles](#gpu-profiles)
- [Monitors](#monitors)
- [Desktop helpers](#desktop-helpers)
- [Control center](#control-center)
- [Mouse and touchpad tuner](#mouse-and-touchpad-tuner)
- [Package catalog](#package-catalog)
- [Package drift](#package-drift)
- [RAM cache](#ram-cache)
- [Kernel and CPU level](#kernel-and-cpu-level)
- [Theming](#theming)
- [System configuration (`--system`)](#system-configuration---system)
- [Backups and restore](#backups-and-restore)
- [Syncing live changes back](#syncing-live-changes-back)
- [Checks, tests and CI](#checks-tests-and-ci)
- [Secrets](#secrets)
- [License](#license)

## Status

Tested on one desktop: Arch Linux, Hyprland 0.57, NVIDIA GPU. The laptop, AMD,
Intel, hybrid, `vm` and `software` profiles, the `lid` handler and the
dock/monitor-profile logic are covered only by synthetic tests. They have not
been run on that hardware. Idle and screen locking are available on desktops
and are optional.

## Safety model

- The repository never edits live configuration files on its own.
- The installer backs up every file it replaces to
  `~/.dotfiles-backup/<YYYY-MM-DD_HHMMSS>/` and writes a `manifest.tsv`.
- `--dry-run` prints every action and changes nothing.
- The installer writes `/etc` files only with `--system`, one file at a time.
- GRUB, mkinitcpio and `modprobe/nvidia.conf` are installed only for the
  `nvidia` and `hybrid` GPU profiles. GRUB and mkinitcpio need an extra
  confirmation; other profiles keep their boot and initramfs configuration.
- The default GRUB template does not disable CPU mitigations or the TPM. The
  file contains a commented block that explains both options.
- The installer never runs `grub-mkconfig` or `mkinitcpio`.
- No service is started or restarted automatically.
- Secrets are excluded from git: `pihole.toml`, rclone, RustDesk and OpenCode
  configs, `.env`, keys and the whole `personal/` directory.
- Generated matugen output is excluded; only templates and
  `matugen/config.toml` are tracked.

## Requirements

- Arch Linux (or an Arch-based distribution) with `pacman`
- `git`, `jq`, `bash` 5.x
- Optional but recommended: `gum` (TUI), `shellcheck` (lint), `yay`/`paru` (AUR)
- For idle and screen locking: `hypridle`, `hyprlock` (optional Session packages; desktops use the AC profile)
- For dock hotplug profiles: `socat`
- For GPU profiles: the matching driver packages (the Drivers category in
  `packages/catalog.tsv`, Mesa for AMD/Intel, etc.)

## Quick start

Run the dry-run first: `./install.sh --dry-run` shows every action in the same
menu and changes nothing. Read that output before the first real install.

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

./install.sh              # main menu
./install.sh --dry-run    # same menu, every action only prints
```

The first screen shows the detected host, GPU, monitor count and CPU level.
You can change them there. Every action returns to the menu, and the top entry
toggles dry-run for the whole session.

Flags stay for automation:

```bash
./install.sh --dry-run --all
./install.sh --modules hypr,uwsm,waybar,rofi,kitty,fish
./install.sh --monitors
```

On a machine that does not have the prerequisites yet:

```bash
./bootstrap.sh            # base-devel/git/curl/jq/gum + yay-bin, then ./install.sh
./bootstrap.sh --dry-run  # show every command first
```

A typical first run:

```bash
./install.sh --host desktop --gpu nvidia --modules hypr,uwsm,waybar,rofi,kitty,fish
./install.sh --monitors   # detect and write the monitor layout
fish -c 'fisher update'   # install the tide prompt plugins
./install.sh --wallpaper ~/Pictures/wallpaper.jpg
./install.sh --theme      # generate matugen colours from that wallpaper
```

## Bootstrap a fresh machine

```bash
./bootstrap.sh --dry-run
./bootstrap.sh
./bootstrap.sh --yes -- --host laptop --gpu intel
```

Bootstrap installs the tools the installer needs (`base-devel`, `git`, `curl`,
`jq`, `gum`, `networkmanager`), checks network reachability and builds `yay-bin`
when no AUR
helper exists. Use `--no-aur` to keep the old report-only behaviour. It then
runs `install.sh` (with `--all --yes` when `--yes` is given) and finishes with a
read-only `--doctor` pass. Everything after `--` is forwarded to `install.sh`.

## Repository layout

```text
.
├── install.sh                 menu-first installer, the only user entry point
├── bootstrap.sh               fresh-machine prerequisites, then install.sh
├── lib/                       common, TUI, menu, monitors, packages, system, secrets
├── profiles/gpu/              nvidia, amd, intel, hybrid, vm, software
├── hosts/
│   ├── desktop/               monitors.conf.sh, input.lua, host env
│   └── laptop/                battery/brightness/touchpad/lid defaults
├── modules/<name>/home/...    files linked or rendered into $HOME
├── system/                    opt-in /etc files (--system)
├── packages/                  package catalog + local additions
├── scripts/                   audit, doctor, sync, pkg-sync, DNS check
├── tests/                     shell tests + run.sh local runner
├── .github/workflows/ci.yml   lint + tests on an Arch container
├── personal/                  private files, gitignored
├── docs/                      Arch install guide (EN/UK)
├── Makefile
├── LICENSE / THIRD_PARTY.md
└── README.md / README.uk.md
```

## Where is what

| Path | Purpose |
|------|---------|
| `install.sh` | the only user entry point: main menu, flags and one-off actions |
| `Makefile` | developer tasks only: `lint`, `test`, `check`, `audit`, `doctor`, `hooks` |
| `scripts/` | internal helpers called by the installer, CI and the pre-commit hook |
| `lib/` | shared shell code: TUI, menu, packages, monitors, system files |
| `modules/`, `hosts/`, `profiles/` | the configuration content that gets linked or rendered |
| `bootstrap.sh` | the single exception: first run on a clean system, before `install.sh` |

`bootstrap.sh` stays a separate file on purpose. It runs before `gum`, `jq` and
the rest of the installer dependencies exist, so it uses only bash and no
`lib/`. When `install.sh` misses `gum`, `jq` or `git`, it tells you to run
`./bootstrap.sh` first.

## Installer

```bash
./install.sh        # main menu (needs a terminal)
./install.sh --help # grouped flag reference
```

The main menu follows the order of a first install:

1. **First-time setup** — walks through packages, configuration files, `/etc`
   files (with `sudo`) and the kernel, with an explanation and a confirmation
   between steps.
2. **Profile** — host and GPU profile.
3. **1. Packages**, **2. Configuration files**, **3. System configuration**,
   **4. Kernel** — the same stages for repeat runs.
4. **Maintenance** — doctor, DNS check, restore, sync, package drift, hooks.

The wizard stops at the first failed stage and returns to the menu. `--setup`
runs it non-interactively; it is not meant for scripts.

Daily settings live in the rofi control center, not in this menu. Press
`SUPER + Space` or launch **Control Center** from rofi.

Entries that cannot work on this machine stay visible but greyed, with the
reason (laptop-only, NVIDIA-only, missing `sudo`). Without a terminal the
installer keeps the previous non-interactive behaviour.

### Flags for automation

| Area | Flags |
|------|-------|
| Installation | `--setup`, `--all`, `--modules a,b`, `--category a,b`, `--apps a,b`, `--packages a,b`, `--no-packages`, `--only-packages`, `--host`, `--gpu`, `--spicetify` |
| Settings | `--monitors`, `--dock-layout L`, `--mouse`, `--cursor`, `--cursor-archive`, `--cursor-theme`, `--cursor-size`, `--wallpaper`, `--theme`, `--theme-menu`, `--binds [plain\|rofi\|json]`, `--monitor-profiles ACTION`, `--autostart ACTION`, `--gamemode ACTION`, `--idle ACTION`, `--lid ACTION` |
| System | `--system`, `--system-components a,b` (includes `ram`), `--iface`, `--autologin-user` |
| Kernel | `--kernel`, `--kernel-level v1..v4` |
| Maintenance | `--doctor`, `--dns-check`, `--json`, `--restore [date]`, `--sync COMMAND`, `--pkg-sync ACTION`, `--hooks` |
| General | `--dry-run`, `--yes`, `--list`, `--help` |

Every menu entry maps to one of these flags. `tests/menu.sh` and
`tests/help-flags.sh` fail when the menu and `--help` drift apart.

`--all` means **modules + default packages**, not `/etc`. Every module is
selected by default except `ram-cache` and `workspaces-split`; `lid` is skipped
on desktops and `idle` is enabled when installed. System files are always opt-in
through `--system`.

`--only-packages` without `--packages`, `--category` or `--apps` exits with an
error when there is no terminal to show the picker. After installation the
installer re-reads the package database and fails when a requested package is
still missing, so a silent no-op cannot pass as success.

The installer detects the host type from `/sys/class/power_supply/BAT*` and the
DMI chassis type, and the GPU profile from `lspci`/`systemd-detect-virt`. You
can override both. With `gum`, selection is an interactive checklist; without
it, a plain numbered prompt is used.

### Modules

| Module | What it installs |
|--------|------------------|
| `hypr` | Hyprland Lua config, binds, autostart hook, window rules, generated monitors |
| `autostart` | login-application state manager (`autostart.sh`, `SUPER+SHIFT+A` picker) |
| `binds-cheatsheet` | Hyprland keybind cheatsheet (plain, markdown, JSON, rofi) |
| `gamemode` | toggle animations, blur, shadows and rounding for gaming |
| `idle` | hypridle/hyprlock profiles; AC on desktops, battery/AC on laptops |
| `lid` | lid-switch safety handler (laptop only; requires idle for the lock screen) |
| `monitor-profiles` | dock/external-display hotplug profiles |
| `theme-menu` | rofi menu for wallpaper, matugen mode and colour scheme |
| `uwsm` | `~/.config/uwsm/env` (common + GPU profile) and `env-hyprland` |
| `waybar` | status bar config, style and scripts |
| `rofi` | launcher, power menu and dunst history scripts |
| `kitty` | terminal config |
| `fish` | fish config, aliases and tide plugin list |
| `dunst` | notification daemon (colors generated by matugen) |
| `matugen` | templates and `config.toml` (no generated colors) |
| `theming` | unified GTK/Qt/KDE appearance, fonts, icons and portal settings |
| `cursor` | cursor theme/size rendered into uwsm, GTK3/4, Qt, xsettingsd and Hyprland |
| `apps` | btop, micro, spicetify, vesktop, Firefox chrome, dolphinrc |
| `control-center` | rofi daily settings hub (`SUPER + Space`) |
| `ram-cache` | optional page-cache warming and browser-profile tmpfs |
| `workspaces-split` | per-monitor workspace slots; offered only with 2+ monitors |
| `mouse-sensitivity` | interactive pointer tuner and the input overlay |

Spicetify CLI is a selected Music entry and is installed by the upstream script, not pacman. `./install.sh --spicetify` runs the same installer.

### Host profiles

| Host | Detection | Specifics |
|------|-----------|-----------|
| `desktop` | no battery | two-monitor example preset available |
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

The selected profile is appended to
`modules/uwsm/home/.config/uwsm/env.common` and rendered to
`~/.config/uwsm/env`. `env-hyprland` is separate because `HYPR*`/`AQ_*`
variables must not leak into other sessions.

### NVIDIA driver generation

The Drivers category lists every stack and keeps them opt-in. Choose the one
that matches the card. Install one stack, never two.

| GPU generation | Driver |
|----------------|--------|
| Blackwell (GBXXX) and newer | `nvidia-open`, `nvidia-open-lts` or `nvidia-open-dkms` |
| Ada Lovelace, Ampere, Turing | `nvidia-open*` recommended; `nvidia-580xx-dkms` proprietary also supported |
| Volta (NV140/GV100), Pascal (NV130/GPXXX), Maxwell (NV110/GMXXX) | `nvidia-580xx-dkms` (legacy, supported) |
| Kepler (NVE0/GKXXX) | `nvidia-470xx-dkms` |
| Fermi (NVC0/GF1XX) | `nvidia-390xx-dkms` |
| Tesla (NV50/G80-90-GT2XX) | `nvidia-340xx-dkms` |
| Curie (NV40/G70) and older | no longer packaged |

The `nvidia` and `hybrid` GPU profiles only select the environment. The driver
package itself comes from the Drivers category, so a Pascal or Maxwell machine
keeps `nvidia-580xx-dkms` while a Turing or newer machine can select an
`nvidia-open` variant.

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
4. the `dill-desktop` example preset (`HDMI-A-2` left, `DP-1` right, both
   1920x1080@60, workspaces 1–10 and 11–20);
5. manual editing of `hosts/<host>/monitors.conf.sh`.

For a laptop, the generated layout supports fractional scale and any `eDP-*`
panel; lid and external-monitor behaviour belongs to the laptop host profile.

The `workspaces-split` module is offered only when two or more monitors are
detected. It installs `~/.config/hypr/switch_ws.sh`, which reads monitor names
and workspace ranges from the generated `monitors.conf.sh` — nothing is
hardcoded. Without the module, `SUPER+1..0` uses Hyprland's native workspace
dispatchers.

### Dock and hotplug profiles

The optional `monitor-profiles` module handles a laptop docked to an external
display. The preference lives in `~/.config/hypr/monitor-profiles.conf`:

```bash
DOCK_LAYOUT=right      # right|left|mirror|ask
```

Store it through the installer or change it directly:

```bash
./install.sh --dock-layout right
./install.sh --monitor-profiles status
./install.sh --monitor-profiles apply --dry-run
./install.sh --monitor-profiles watch
```

`watch` listens on the Hyprland event socket (`socket2`) with `socat` and
debounces bursts, so a dock that registers several outputs at once triggers one
layout pass. `apply` changes the running session only; it never rewrites
Hyprland configuration files. Before applying it saves the current
`hyprctl monitors -j` under `~/.local/state/dotfiles/monitor-profiles/`.
`ask` never changes monitors.

> **Not verified on real dock hardware.** Run `apply` with `--dry-run` first and
> keep the saved monitor snapshot. If the layout is wrong after a real run, use
> `./install.sh --restore` to put the previous files back.

## Desktop helpers

These modules share one rule: state lives under
`~/.local/state/dotfiles/`, never in the compositor config.

After the matching module is installed, the same tools are also commands in
`~/.local/bin`: `autostart.sh`, `idle-tune.sh` and `monitor-profiles.sh`.

### Theme menu

```bash
./install.sh --theme-menu       # rofi/gum/whiptail/dialog/plain menu
./install.sh --theme-menu --dry-run
```

Choose a wallpaper, matugen mode (`dark`/`light`) and colour scheme. The choice
is stored in `~/.local/state/dotfiles/theme.conf`; `./install.sh --theme` can
then reuse it.

### Keybind cheatsheet

```bash
./install.sh --binds            # aligned table
./install.sh --binds rofi       # rofi menu
./install.sh --binds json       # JSON for scripts
~/.local/bin/binds-cheatsheet.sh --duplicates
```

The cheatsheet parses the Lua configuration, because Hyprland 0.57 with Lua
dispatchers reports opaque numeric arguments in `hyprctl binds -j`.

### Gamemode

```bash
./install.sh --gamemode toggle
./install.sh --gamemode status
./install.sh --gamemode on --dry-run
```

Enabling disables animations, blur, shadows and rounding. The values that were
active before the first enable are read with `hyprctl getoption` and stored in
`~/.local/state/dotfiles/gamemode.conf`, so enabling twice cannot overwrite the
originals and `off` always restores them.

### Idle and lock

The `idle` module renders `~/.config/hypr/hypridle.conf` and installs
`hyprlock.conf`. It works on desktops and laptops; a desktop with no battery
uses the AC profile. The module is selected by default and idle starts enabled:

```bash
./install.sh --modules idle
./install.sh --idle status
~/.local/bin/idle-tune.sh apply --profile battery
./install.sh --idle configure              # prompts for all eight values
./install.sh --idle watch                  # re-apply on AC/battery changes
./install.sh --idle toggle                 # enable or disable idle
```

`SUPER + SHIFT + I` toggles idle from the session. A disabled idle is remembered
in `idle.conf`, so autostart does not start `hypridle` at the next login.

| Profile | Dim | Lock | Screen off | Suspend |
|---------|-----|------|------------|---------|
| battery | 150 | 300 | 330 | 900 |
| AC | 300 | 600 | 660 | 1800 |

`0` disables a stage; enabled stages must satisfy `dim < lock <= off < suspend`.
Settings live in `~/.local/state/dotfiles/idle.conf`. The previous
`hypridle.conf` is backed up before it is replaced. The `lid` module is laptop
only and depends on `idle` for the shared lock screen.

### Lid switch

```bash
./install.sh --lid status
./install.sh --lid closed
./install.sh --lid closed --dry-run
```

On close, the handler reads `hyprctl monitors -j` immediately before acting:
if another active monitor exists it disables every `eDP-*`/`LVDS`/`DSI` output
and remembers mode, position and scale in `~/.local/state/dotfiles/lid.conf`;
otherwise it suspends through `systemctl`. Opening the lid always restores the
internal panel. logind configuration is never modified. The decision logic is
covered by synthetic tests only, not by physical lid hardware.

### Autostart

```bash
./install.sh --autostart list
~/.local/bin/autostart.sh disable vesktop
~/.local/bin/autostart.sh add notes obsidian
./install.sh --autostart pick          # rofi/gum/whiptail/dialog/plain
```

Entries live in `~/.local/state/dotfiles/autostart.tsv` and are seeded from the
built-in applications on first use. `hyprland.lua` calls `autostart.sh run`;
disabling an entry keeps it off at the next login without editing the Lua
config. `SUPER+SHIFT+A` opens the picker.

## Control center

Daily settings live in the rofi control center, not in `install.sh`.

```bash
dotfiles-control-center
```

Press `SUPER + Space` or launch **Control Center** from rofi. Pages cover:

- **Appearance**: wallpapers with magick thumbnails, dark/light/smart mode,
  matugen colour schemes, fonts/icons/cursor status
- **Desktop**: monitor status, saved layout, dock preference
- **Input**: mouse/touchpad tuner, searchable keybind cheatsheet
- **Session**: autostart, idle, lid, game mode
- **Music**: Spicetify update, backup/apply and restore
- **System**: updates, repository mirror refresh (reflector), package
  search/install/remove, doctor, DNS check, package drift, sync and restore
- **Install and update**: opens `install.sh` in kitty

The menu uses the matugen palette (`colors.rasi`), Inter and
`JetBrainsMono Nerd Font`, with no separate theme to keep in sync. It calls the
feature helpers directly. `install.sh` stays for installing, updating and rare
one-shot actions.

The bind is stored in `hosts/<host>/control-center.conf` and rendered into the
optional `~/.config/hypr/control-center.lua`.

## Mouse and touchpad tuner

```bash
./install.sh --mouse
~/.local/bin/mouse-tune.sh          # after installation
mouse-tune.sh --show                # read-only current values
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
fine step, `r` resets to the session value, `Enter`/`q` finishes. Values are
parsed and printed with a dot regardless of the system locale, so the saved Lua
file stays valid under a comma-decimal locale.

> **Important:** older Hyprland versions have no `scroll_factor` option for a
> mouse. The tuner offers it where `hyprctl getoption` reports it; otherwise it
> is not shown.

Saving writes only to `hosts/<host>/input.lua` in the repository (or to
`~/.config/hypr/input.lua` when no repository is found). It shows a unified
diff, asks for confirmation and creates a backup. The live `hyprland.lua` is
never edited. The overlay is loaded with:

```lua
pcall(dofile, HOME .. "/.config/hypr/input.lua")
```

so a missing file is safe.

## Package catalog

`packages/catalog.tsv` is the source of truth. Each row carries the package,
category, role, default flag, host, GPU list and a short description. The
installer shows category tabs and a checklist inside each category, so you can
drop one package without editing a list.

- ★ main: config in this repo, selected by default
- ○ alternative: package only, not selected by default
- • package: regular package
- ✓ already installed

`--all` installs rows with `default=yes`. The office and CAD apps are visible
but opt-in. `cuda`, `virtio-win`, `hypridle`, `hyprlock`,
`profile-sync-daemon`, `vmtouch` and `preload` also stay visible but opt-in.
Base-system packages (`base`, `base-devel`, `git`, `networkmanager`, compilers
and similar) are not in the catalog; bootstrap owns them. Virtualization, Docker
and hardware-inspection tools are opt-in.

Categories: System, Desktop, Hyprland, Audio, Network, Development, Games,
Virtualization, Fonts, Drivers, Terminal, Launcher, Bar, Notifications,
Browser, Files, Editor, Music, System Monitor, Session, Media. Office, CAD and
EasyEDA live in Desktop or Development.

Non-interactive selection:

```bash
./install.sh --only-packages --category Terminal,Development
./install.sh --only-packages --category Terminal --apps foot
./install.sh --only-packages --packages foot,kitty
```

`packages/local.tsv` holds packages added by `pkg-sync pull`. It is part of the
catalog but not part of the curated defaults.

### Package drift

```bash
./install.sh --pkg-sync status       # report only
./install.sh --pkg-sync check        # exit 1 when the catalog drifts
./install.sh --pkg-sync pull --dry-run
./install.sh --pkg-sync pull --yes   # append to local.tsv, never remove
```

`pkg-sync` compares explicitly installed packages with the catalog. Optional
rows are not reported as missing, but an installed optional package counts as
listed. `pull` only appends installed-but-unlisted packages to
`packages/local.tsv`; it never removes an entry and never installs anything.
Host-specific rows are compared only on the matching host.

With `--system`, the repository installs a pacman hook that touches
`/var/lib/dotfiles/pkg-sync.stamp` after every package transaction. `status`
warns when the stamp is newer than the last review, so package changes can be
triaged later instead of during the transaction.

### RAM cache

The optional `ram-cache` module is for desktops with plenty of RAM. It is
excluded from `--all` and does not appear on laptops or small-RAM hosts.

```bash
./install.sh --modules ram-cache
ramcache status
ramcache warm ~/Games/SomeGame
ramcache run -- ~/Games/SomeGame/start.sh
```

`ramcache` computes its limit from `MemAvailable` (50% by default, configurable
up to 80%) and uses `vmtouch` to warm the page cache. Page cache is reclaimable
and holds no unique data, so an unexpected power loss loses no game or
application files.

Browser profiles are handled separately by `profile-sync-daemon`: it moves the
profile to tmpfs, syncs on stop and on suspend, and keeps crash-recovery
backups. Unsynced tmpfs writes since the last resync are the only data at risk.
`preload` is optional and caches frequently used binaries.

The module installs `~/.config/dotfiles/ram-cache.conf`,
`~/.config/psd/psd.conf` and `~/.local/bin/ramcache`. The sysctl file is
installed only with:

```bash
sudo ./install.sh --system --system-components ram
```

No fstab entry, no sudoers rule and no NOPASSWD rule is created.

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
`mkinitcpio`/`grub-mkconfig` commands and never runs them.
`./install.sh --doctor` compares the CPU level with the installed kernel level.

yay 13 accepts `--pgpfetch=false` but never reads it: with `--noconfirm` it
imports every key from `validpgpkeys` that is missing from the user keyring.
Some kernel build keys are not served by the default keyserver, so the
installer points gpg at `keyserver.ubuntu.com` and `pgp.surf.nl`. The import
happens once; later installs reuse the keyring. Source files are still checked
against `sha256sums`; signatures are never skipped.

## Theming

Colours are generated with matugen from a wallpaper:

```bash
./install.sh --wallpaper ~/Pictures/wallpaper.jpg
./install.sh --theme
```

Without `--wallpaper`, `./install.sh --theme` first reads
`~/.config/hypr/wallpaper.path` (written by `./install.sh --wallpaper`) and
falls back to the `image` field in `~/.config/hypr/colors.lua`. The image itself
is never committed. The generated files are ignored by git:

- `~/.config/hypr/colors.lua`
- waybar/rofi/kitty/dunst colours
- GTK/Qt colour schemes
- btop/micro/spicetify/vesktop outputs
- Firefox `colors.css`

Only `matugen/config.toml` and the templates in
`modules/matugen/home/.config/matugen/templates/` are tracked. The theming
module renders GTK3/4, GTK2, xsettingsd, Qt5ct, Qt6ct and kdeglobals from
`hosts/<host>/appearance.conf`. Fonts are Inter and `JetBrainsMono Nerd Font`,
icons are `breeze-dark`, Qt uses Fusion, and Dolphin reads the Matugen KDE
scheme. The GTK4 user stylesheet imports `colors.css` and the selected
libadwaita theme explicitly.

The portal pins Hyprland for screenshots and screencasts and GTK for Settings
and file dialogs. `theme-menu` and the matugen hook update
`org.freedesktop.appearance color-scheme` together with the GTK theme. Apps that
cannot follow the palette automatically are listed in "Outside the unified
theme": SMath, Steam/Wine, and application-owned chrome inside Spotify, Obsidian
and Vesktop.

### Outside the unified theme

- SMath: Java/Mono application with its own look; it does not read GTK or Qt palettes.
- Steam and Wine applications: their own renderers and game UIs.
- Spotify, Obsidian and Vesktop: colors come from the generated CSS, but the
  internal chrome and fonts stay application-owned. Restart them after a mode
  change.
- `imv`, `swappy` and `fastfetch` have no generated config yet; they use the
  GTK theme or the terminal palette.

## System configuration (`--system`)

Run with root:

```bash
sudo ./install.sh --system --iface eno1
sudo ./install.sh --system --autologin-user "$USER"
```

Only this mode writes `/etc`, one file at a time, after a backup. `@IFACE@` is
rendered from `--iface`, then the default-route interface, then an interactive
prompt. If none is available the file is skipped with an error; a fixed
interface name is never substituted in universal templates.

`@USER@` in the getty drop-in is rendered from `--autologin-user`, then
`SUDO_USER`, then the invoking login, and finally an interactive prompt. The
drop-in always needs a separate confirmation.

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
| `system/ram-cache/99-ram-cache.conf` | `/etc/sysctl.d/99-ram-cache.conf` (ram component only) |
| `system/grub/default-grub` | `/etc/default/grub` (nvidia/hybrid only; extra confirmation) |
| `system/mkinitcpio/mkinitcpio.conf` | `/etc/mkinitcpio.conf` (nvidia/hybrid only; extra confirmation) |
| `system/modprobe/nvidia.conf` | `/etc/modprobe.d/nvidia.conf` (nvidia/hybrid only) |
| `system/modprobe/*` | `/etc/modprobe.d/*` (other modprobe files) |

> **Pi-hole password reset.** `system/pihole/pihole.toml.example` is copied
> over `/etc/pihole/pihole.toml` and has an empty `pwhash`. Installing it
> **resets the Pi-hole admin password**. Run `pihole setpassword` afterwards.

`pihole.toml` itself is excluded. The example also has empty `totp_secret` and
`app_pwhash`, and sets `cli_pw = false`; review it and copy secrets yourself.

`pacman.conf` and `makepkg.conf` are merged, not copied: the installer shows a
diff, asks for confirmation and creates a backup. The merge is skipped with
`--yes`. Optional services are enabled with `systemctl enable` only, never
started or restarted.

### NVIDIA boot files

The GRUB, mkinitcpio and `modprobe/nvidia.conf` files are specific to the
proprietary NVIDIA driver. The installer maps them only when the selected GPU
profile is `nvidia` or `hybrid`. Other profiles do not touch `/etc/default/grub`,
`/etc/mkinitcpio.conf` or `/etc/modprobe.d/nvidia.conf`.

The default GRUB template does **not** include `mitigations=off` or
`module_blacklist=tpm,tpm_tis,tpm_tis_core`. Both options are in a commented
block with a warning: they weaken CPU vulnerability mitigations and break
TPM-based measured boot or disk unlocking. Add them only if you accept that
tradeoff.

The installer never runs `grub-mkconfig` or `mkinitcpio -P`; it prints the
commands to review manually. Kernel work belongs to `./install.sh --kernel`;
`--system` only reports CPU/kernel drift.

UFW is documentation only. The repository does not change firewall state or
rules; see `system/ufw/README.md` for general guidance.

Not managed by this repository: `/etc/fstab`, NetworkManager connection
profiles, snapper configuration.

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
./install.sh --restore 2026-11-16_120000 --modules hypr --dry-run
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
./install.sh --sync status          # files that differ
./install.sh --sync diff hypr       # unified diffs
./install.sh --sync pull --dry-run  # preview
./install.sh --sync pull --yes      # write back (diff + secret scan)
./install.sh --sync packages        # compare installed packages
```

Pull reverse-renders `@HOME@`, `@FIREFOX_PROFILE_DIR@` and `@OBSIDIAN_VAULT@`,
skips generated matugen output, `personal/` and secret paths, and runs the
secret scanner before writing. A pre-pull copy of every repository file is
stored under `~/.local/state/dotfiles/sync-backup/<timestamp>/` with a
`manifest.tsv`.

## Checks, tests and CI

```bash
make lint       # bash -n + shellcheck
make test       # shell tests; temporary HOME, live files untouched
make audit      # read-only live + repository audit
make doctor     # CPU/kernel, appearance, RAM cache, cursor, wallpaper, symlinks
make check      # lint + test + audit + doctor
make hooks      # install the repository pre-commit hook
```

The Makefile is a developer tool only. User-facing checks are
`./install.sh --doctor`, `./install.sh --dns-check` and
`./install.sh --pkg-sync check`.

The audit checks Hyprland config errors, duplicate binds, monitor portability,
hardcoded home paths, systemd units, Unbound syntax, `.pacnew` files, secrets,
generated files, and the CPU level versus the installed kernel level. It never
edits anything and never requires root.

`./install.sh --doctor` is the same read-only check with `--json` available.
It covers the portal color scheme, GTK/Qt font availability, GTK4 colour import,
portal backends, and the optional RAM cache (psd, preload, ramcache).
`./install.sh --dns-check` verifies the DNS chain and warns that a configuration
needs a working Pi-hole/Unbound pair before `--system` changes resolver files.

Every test uses a temporary `$HOME`/`XDG_STATE_HOME` and stub system tools, so
the live configuration, package database and monitors are never touched.
Restore and sync tests additionally verify that live files stay unchanged and
that a backup is created. `tests/run.sh [pattern] [-v] [--list]` runs one or all
files and never runs itself. CI (`.github/workflows/ci.yml`) runs `make lint`
and the suite in an `archlinux:latest` container.

## Secrets

The repository does not contain credentials. Excluded from git: `pihole.toml`,
rclone, RustDesk and OpenCode configs, `.env` files, SSH and GPG keys, and the
whole `personal/` directory. Committed `.example` files contain placeholders
only.

If you copied this repository from a private working tree, rotate any token
that was ever stored in a tracked file.

## License

MIT. See [LICENSE](LICENSE).

Third-party configuration examples and themes keep their upstream licenses.
See [THIRD_PARTY.md](THIRD_PARTY.md).
