# Guided first-run setup and package catalogue cleanup

Date: 2026-11-19

## Intent

The installer works on the main machine, but a first run on a fresh VM is
opaque. The Applications action prints `packages only; configuration modules
are skipped` and appears to do nothing. The main menu has no visible order, so
a new user cannot tell that packages come before configuration files, which
come before `/etc`, which come before the kernel. The same installer also
offers user services from modules whose packages are not installed, and the
autostart runner launches applications that do not exist. The Control Center
has no mirror refresh.

This change makes the order explicit, makes a no-op package run fail loudly,
gates services on installed units, and adds a reflector action.

## Approved decisions

- Use a guided `First-time setup` entry: packages, configuration files,
  system configuration (`sudo`), kernel, with an explanation and confirmation
  between steps. Keep separate menu entries for repeat runs.
- Keep NetworkManager available on a fresh machine by installing it in
  `bootstrap.sh`; remove it from the package catalogue.
- Mirror refresh uses reflector with `--latest 20 --protocol https
  --sort rate`, backs up the old mirror list, and needs sudo.

## Goals

- The main menu reads as a sequence: profile, 1 packages, 2 configuration,
  3 system, 4 kernel, maintenance.
- `--only-packages` never silently installs nothing.
- A service is offered or started only when its unit/command exists.
- The Control Center can refresh `/etc/pacman.d/mirrorlist`.
- The catalogue matches the requested removals and default changes.
- `--all` keeps its current meaning so bootstrap and scripting do not start
  touching `/etc` or kernels.

## Non-goals

- No change to the backup, diff or per-file confirmation rules.
- No automatic `mkinitcpio`, GRUB regeneration or service restart.
- No automatic `/etc` edits outside `--system`.
- No package removal from the live system.

## Findings

- `--only-packages --packages foot` works. With no selector and no TTY the
  current code selects nothing and prints only the `packages only` line. That
  is the observed VM symptom unless the VM checkout is stale.
- `enable_services` offers every `SERVICES` entry from selected modules. For
  example `ram-cache` offers `psd.service` even when
  `profile-sync-daemon` is absent.
- `autostart.sh run` starts the seeded defaults (`vesktop`, `firefox`,
  `steam`, `kopia-ui`) without checking that the command exists.
- The Control Center System page has updates, package management, doctor,
  DNS, drift, sync and restore, but no mirror refresh.

## Design

### 1. Guided setup

`menu_main` becomes:

```text
First-time setup — packages -> configs -> system -> kernel
Profile — host and GPU
1. Packages — categories and applications
2. Configuration files — dotfiles and user services
3. System configuration — /etc files, sudo
4. Kernel — CPU-level aware selection
Maintenance — doctor, DNS, restore, sync, hooks
Dry run
Exit
```

`menu_action_setup` runs child processes so each stage keeps its own
privileges and prompts:

1. `install.sh --only-packages` (interactive package picker).
2. `install.sh --no-packages` (module picker, file install, service
   selection).
3. `sudo install.sh --system` through `menu_system_run`.
4. `install.sh --kernel`.

Each step prints what it is about to do and asks to continue. A failed step
stops the wizard and returns to the menu. `--all` stays packages + modules
only. The guided wizard lives only in the interactive menu.

### 2. `--only-packages` robustness

- If `--only-packages` is used without `--packages`, `--apps` or
  `--category` and there is no TTY (or `--yes` is set), exit with a clear
  error naming the missing selector.
- Preselect every category that has default packages, so accepting the
  category picker does not silently select nothing.
- Log the exact package list before installing.
- Check `sudo` (when not root) and the package manager before mutating.
- After install, re-read `pacman -Qq` and report any requested package that
  is still missing. Exit non-zero instead of reporting success.
- This makes the VM failure visible without guessing.

### 3. Service and autostart gating

- `enable_services` filters each unit with `systemctl --user
  list-unit-files --no-legend <unit>`, falling back to unit-file paths. Units
  that do not exist are listed as skipped, never offered and never enabled.
- `autostart.sh` resolves the executable of each entry:
  - skip the `uwsm app --` prefix;
  - absolute path: require `-x`;
  - otherwise: `command -v`.
  `run` skips missing commands and logs why. `pick` marks them
  `(not installed)` and refuses to enable them. `list` marks them too.

### 4. Mirror refresh

Add `Update — repository mirrors (reflector)` to the Control Center System
page. It runs in the terminal:

```bash
sudo cp -a /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak.<timestamp>
sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
```

If reflector is missing, show a notification instead of running the command.

### 5. Catalogue changes

Delete rows: `base`, `base-devel`, `efibootmgr`, `git`, `gitleaks`,
`tcpdump`, `cups-pdf`, `fbida`, `smath`, `networkmanager`, `clang`, `cmake`,
`jdk17-openjdk`, `lld`, `llvm`, `uv`, `rustup`, `jpegoptim`, `oxipng`.

Set `default=no`: `inotify-tools`, `snap-pac`, `cpu-x`, `gsmartcontrol`,
`hardinfo2`, `kdiskmark`, `pdfcraft-bin`, `s-tui`, `docker`,
`docker-compose`, `libvirt`, `qemu-base`, `qemu-desktop`, `swtpm`,
`virt-manager`.

`ayugram-desktop-bin` is already `main` + `yes`; no change.

`profile-sync-daemon` moves from `Session` to `System` (it is a background
daemon, not a session/idle component). The `ram-cache` module keeps using it.

`bootstrap.sh` adds `networkmanager` to its prerequisites so a fresh machine
has a network manager even though the catalogue no longer carries it.

### 6. Documentation and tests

- README and README.uk.md: guided order, `--only-packages` behaviour, mirror
  refresh, bootstrap package list.
- Tests: menu order and wizard wiring, `--only-packages` error path,
  skipped services, autostart missing commands, mirror action, catalogue
  removals/defaults, bootstrap package list.

## Verification

- `make check` (tests, shellcheck, audit) stays green.
- `./install.sh --dry-run --only-packages` without a selector fails with a
  readable error.
- `./install.sh --dry-run --only-packages --packages foot` still shows foot.
- The menu test asserts the stage order.
- The autostart test puts a missing command in the state file and asserts it
  is not launched.
- The catalogue test asserts removed rows are absent and optional rows are
  `no`.
