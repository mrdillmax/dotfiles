# AGENTS.md — dotfiles repository

## Repo type

Personal Arch Linux + Hyprland dotfiles. The repo is the source of truth; the
installer links and renders files into `$HOME`. Never run live commands — the
user controls packages, services, and pushes.

## Entry points

| File | Purpose |
|------|---------|
| `install.sh` | Only user-facing entry: main menu + flags for everything |
| `bootstrap.sh` | Fresh-machine prerequisites, then runs `install.sh` |
| `Makefile` | Developer tasks only: `lint`, `test`, `check`, `audit`, `doctor`, `hooks` |

## Structure at a glance

```
install.sh           # main menu, flags, one-off actions
bootstrap.sh         # first-run: base-devel, git, jq, gum, yay-bin → install.sh
lib/                 # shared code: common, tui, menu, packages, monitors, system, secrets, migrate, uninstall, restore
modules/<name>/      # each module: module.conf + home/… files
  module.conf        # DESCRIPTION, PACKAGES[], SERVICES[], REQUIRES[]
  home/…             # files linked (link_path) or copied (copy_file) into $HOME
hosts/<host>/        # desktop/ laptop/ — monitors, input, env overrides
profiles/gpu/        # nvidia, amd, intel, hybrid, vm, software
system/              # opt-in /etc files (only with --system)
packages/            # catalog.tsv (TSV: package, category, role, default, host, gpu, description)
migrations/          # numbered .sh scripts run when repo version advances
scripts/             # audit, doctor, sync, pkg-sync, DNS, mouse-tune, hooks installer
tests/               # shell tests; ./tests/run.sh or make test
```

## Safety rules (never break)

- **`--dry-run` changes nothing.** Never call `sudo` or mutate live state.
- **Live files only through `install.sh`.** No direct writes to `~/.config` or
  `~/.local`.
- **Secrets excluded:** `personal/`, `pihole.toml`, `.env`, `*.secret`,
  `*.token`, `*.pem`, `*.key`, `*.kdbx`, `*.ovpn`, `*.p12`, `id_*` (SSH),
  `.gnupg/`, `*.age`.
- **Generated output excluded:** matugen colors, rendered configs. Only templates
  are committed.
- **`/etc` only with `--system`.** One file at a time, with diff + confirmation.
- **Pre-commit blocks:** secret paths, secret patterns, shellcheck errors,
  matugen generated output, hardcoded `/home/<user>` paths, disk UUIDs.
  Bypass with `--no-verify` only if you know what you're doing.

## Module system

Each module owns its packages, services, and config files:

```bash
# module.conf format:
DESCRIPTION="..."
PACKAGES=(pkg1 pkg2 ...)
SERVICES=(service1.service ...)
REQUIRES=(module1 module2)
```

Files under `home/` are installed via two helpers:

| Helper | What it does |
|--------|-------------|
| `link_path <repo-src> <home-dst>` | Symlinks repo file into `$HOME`, backs up existing |
| `copy_file <repo-src> <home-dst> [mode] [recorded-source]` | Copies with mode, backs up existing, records digest |

Both call `backup_path` which lazily creates the backup dir and writes to
`manifest.tsv` only when something is actually backed up.

Modules can declare dependencies in `REQUIRES[]`; the installer respects them
during install and uninstall.

### How to add a new module

1. Create `modules/<name>/module.conf` with `DESCRIPTION`, `PACKAGES[]`,
   `SERVICES[]`, `REQUIRES[]`.
2. Add `home/…` files under the right paths (they will be linked/copied).
3. If the module needs a menu entry, add to `MENU_FLAG` and the menu page in
   `lib/menu.sh` and/or `dotfiles-control-center`.
4. If it installs packages, add them to `packages/catalog.tsv` (TSV with
   category, role, default, host, gpu, description).
5. Write a test in `tests/<name>.sh` if the module has behavior worth
   verifying (use a temp HOME, stub binaries, never touch live files).
6. Run `make lint` and `./tests/run.sh` before committing.

### How to add a package to catalog.tsv

- Add a line: `name\tcategory\trole\tdefault\thost\tgpu\tdescription`
- `role`: `main` (config in repo), `alt` (package only), `pkg` (regular)
- `default`: `yes` or `no`
- `host`: `any` or comma-separated list
- `gpu`: `any` or comma-separated list (nvidia, amd, intel, hybrid, vm, software)
- Run `./tests/catalog.sh` to verify format.

## Installer flags (automation)

```
Selection: --all, --modules a,b, --category a,b, --apps a,b,
           --packages a,b, --no-packages, --only-packages, --module-packages
Host/GPU:  --host desktop|laptop, --gpu nvidia|amd|intel|hybrid|vm|software
System:    --system, --system-components dns,zram,...
Maintenance: --doctor, --restore [date], --uninstall [--modules a,b]
             [--remove-packages], --sync COMMAND, --hooks
One-offs:  --monitors, --wallpaper PATH, --theme, --theme-menu,
           --binds [plain|rofi|json], --idle ACTION, --lid ACTION,
           --gamemode ACTION, --autostart ACTION, --cursor, --mouse,
           --spicetify
General:   --dry-run, --verbose, --force, --yes, --list, --help
```

## Testing

```bash
make test           # runs ./tests/run.sh
make lint           # bash -n + shellcheck -x on all .sh files
make check          # lint + test + audit + doctor (all read-only)
./tests/run.sh [pattern]  # run a subset
./tests/run.sh --list     # list all test files
```

Tests use a temporary HOME, stub system tools, and never touch live files.
Each test file prints `N passed, M failed`. A test exits non-zero on any
failure.

## Backup and restore

- Backups go to `~/.dotfiles-backup/<YYYY-MM-DD_HHMMSS>/` with a
  `manifest.tsv` listing `target<TAB>backup`.
- Backup dirs are created lazily (only when something is actually backed up).
- `prune_empty_backups()` removes dirs that contain only `manifest.tsv` — this
  catches leftover empty directories from interrupted or failed runs where no
  file was actually replaced.
- `managed.tsv` (`~/.local/state/dotfiles/managed.tsv`) records every
  installed path with kind, source, digest, and original backup location.
- `--uninstall` reads `managed.tsv`, restores originals, and removes its own
  entries. Never removes packages unless `--remove-packages`.
- `--restore <date>` lists backups, shows diffs, backs up current state, then
  restores from the selected snapshot.

## Migrations

Versioned migrations live in `migrations/<NNN>-<name>.sh`. The installer
reads `VERSION` and `~/.local/state/dotfiles/version`, runs all pending
migrations (with confirmation), then updates the version. Dry-run lists
pending migrations without executing them.

When a change affects installed files in a way that existing installs need
to adapt (new config format, renamed paths, etc.), bump `VERSION` and add a
migration script.

## Commit style

Conventional commits: `fix(scope): description`, `feat(scope): description`,
`refactor(scope): description`. Scope is the module or area. Keep subjects
under 72 chars. Multi-line bodies explain the why, not the how.

## TUI chain

All interactive prompts follow: `gum` → `whiptail` → `dialog` → plain `read`.
The installer checks for each in order. Non-UTF-8 terminals get ASCII fallback
symbols.

## CI

GitHub Actions on `ubuntu-latest` with `archlinux:latest` container:
1. `make lint` (bash -n + shellcheck)
2. `./tests/run.sh`
3. `./install.sh --doctor` (read-only, non-fatal)

## Read-only investigation commands

These are safe to run without live-machine access:

```bash
make test           # run tests in temp HOME
make lint           # syntax + shellcheck
make audit          # secret scanner (read-only)
make doctor         # system snapshot (read-only)
./install.sh --dry-run --all   # shows every action, changes nothing
./install.sh --doctor          # read-only system info
cat ~/.local/state/dotfiles/managed.tsv   # what's installed
ls -la ~/.dotfiles-backup/            # backup snapshots
```

Anything that writes to `~/.config`, `~/.local`, `/etc`, or runs `sudo`
must go through `install.sh` or be explicitly approved by the user.

## Process rules

- **Write code/comments in English.** Respond in Ukrainian when the user
  communicates in Ukrainian.
- **Repo changes reach live machines only through `install.sh`.** Live files
  only through `link_path` or `copy_file` (which handle backup).
- **Never push/commit secrets or `personal/` paths.**
- **Executable helpers live in `~/.local/bin`.** Config stays in `~/.config`.

## UX invariants

- **`SUPER + V`** must remain the clipboard bind.
- **`SUPER + L`** is the lock bind.
- **Brightness never below 5%** (clamped in `brightness-adjust.sh`).
- **Idle dims before locking** (15% dim), not powers off the panel.
- **Night light** in Menu with Enable/Disable toggle; schedule in
  Configuration → Night light (off/times/sun).
- **Sound** opens `pavucontrol`, never `hyprpwcenter`.
- **Lid/lock:** opening lid must not flash hyprlock and black the screen.
  Unlock must not leave a black panel.
- **Four-finger horizontal gesture** moves the active window to another
  workspace.
- **Wallpaper picker** must fit on screen (240x135 cards, 190px icon).
- **Waybar** uses managed `config.jsonc` + `style.css`. Legacy `config`/
  `config.json` files are removed during install.

## Hyprland / hypridle technical notes

- **`set -uo pipefail`** (without `-e`) is the convention for standalone
  scripts — it avoids aborting on expected failures in conditionals.
  `install.sh` and `bootstrap.sh` use `set -euo pipefail` for flow control.
  `lib/*.sh` have no `set -` because they are sourced and inherit the caller's
  settings.
- **hypridle** uses `condition_cmd` (hypridle ≥ 0.42.0) with a
  `lock-screen.sh can-*` guard as a fallback for older builds. The guard
  also lives in the `on-timeout` action itself so a build that ignores
  `condition_cmd` cannot power the panel off right after resume.
  `before_sleep_cmd = loginctl lock-session`,
  `after_sleep_cmd = lock-screen.sh resume`.
- **Hyprland Lua config:** `misc.*` keys (not `general.*`) for DPMS wake
  options (verified on Hyprland 0.57). DPMS dispatcher requires table
  actions: `hl.dsp.dpms({ action = "on" })`. A bare string `"on"` used to
  toggle the panel off instead of on.
- **Night light** daemon lifecycle owned by `nightlight.sh`;
  `nightlight.lua` only calls `restore` and `watch`.

## File conventions

- Module configs: `.in` templates rendered by `install.sh` (e.g.
  `hypridle.conf.in` → `hypridle.conf`).
- Package catalog: `packages/catalog.tsv` — tab-separated, comments start
  with `#`.
- State files: `~/.local/state/dotfiles/` — `managed.tsv`, `idle.conf`,
  `nightlight.conf`, `theme.conf`.
