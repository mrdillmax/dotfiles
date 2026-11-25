# AGENTS.md — dotfiles repository

Personal Arch Linux + Hyprland dotfiles. The repo is the source of truth; the
installer links and renders files into `$HOME`.

Allowed without asking: reading files, `./install.sh --dry-run`, `--doctor`,
`make test`, `make lint`. Forbidden: `sudo`, `install.sh` without `--dry-run`,
and any change to live files outside the repo.

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
  `*.token`, `*.pem`, `*.key`, `*.kdbx`, `*.ovpn`, `id_*` (SSH).
- **Generated output excluded:** matugen colors, rendered configs. Only templates
  are committed.
- **`/etc` only with `--system`.** One file at a time, with diff + confirmation.
- **Pre-commit blocks:** secret paths, secret patterns, shellcheck errors,
  matugen generated output, hardcoded `/home/<user>` paths, disk UUIDs.

## Module system

Each module owns its packages, services, and config files:

```bash
DESCRIPTION="..."
PACKAGES=(pkg1 pkg2 ...)
SERVICES=(service1.service ...)
REQUIRES=(module1 module2)
```

Files under `home/` are installed via `link_path` (symlink) or `copy_file`
(copy with mode). Both call `backup_path` which lazily creates the backup dir
and writes to `manifest.tsv` only when something is actually backed up.

### How to add a module or package

1. Create `modules/<name>/module.conf` + `home/…` files.
2. Add menu entry to `lib/menu.sh` / `dotfiles-control-center` if needed.
3. Add packages to `packages/catalog.tsv`; write `tests/<name>.sh`.

## Testing

```bash
make test           # runs ./tests/run.sh
make lint           # bash -n + shellcheck -x on all .sh files
make check          # lint + test + audit + doctor (all read-only)
./tests/run.sh [pattern]  # run a subset
./tests/run.sh --list     # list all test files
```

Tests use a temporary HOME, stub system tools, and never touch live files.

## Process rules

- Commits are allowed. Never run `git push`.
- Write code/comments in English. Respond in Ukrainian when the user does.
- Repo changes reach live machines only through `install.sh`.
- Executable helpers live in `~/.local/bin`. Config stays in `~/.config`.


## UX invariants

- **`SUPER + V`** must remain the clipboard bind.
- **`SUPER + L`** is the lock bind.
- **Brightness** never below 5% (clamped in `brightness-adjust.sh`).
- **Idle dims before locking** (15% dim), not powers off the panel.
- **Night light** in Menu with Enable/Disable toggle; schedule in
  Configuration → Night light (off/times/sun).
- **Sound** opens `pavucontrol`, never `hyprpwcenter`.
- **Lid/lock:** opening lid must not flash hyprlock and black the screen.
- **Four-finger horizontal gesture** moves the active window to another
  workspace.
- **Wallpaper picker** must fit on screen (240x135 cards, 190px icon).
- **Waybar** uses managed `config.jsonc` + `style.css`. Legacy `config`/
  `config.json` are removed during install.

## Hyprland / hypridle technical notes

- **Hyprland Lua config:** `misc.*` keys (not `general.*`) for DPMS wake
  options (verified on Hyprland 0.57). DPMS dispatcher requires table
  actions: `hl.dsp.dpms({ action = "on" })`. A bare string `"on"` used to
  toggle the panel off instead of on.
- **hypridle** idle config uses `condition_cmd`; `lock-screen.sh` has a
  fallback guard for hypridle builds that ignore it.
  `before_sleep_cmd = loginctl lock-session`,
  `after_sleep_cmd = lock-screen.sh resume`.
