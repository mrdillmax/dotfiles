# First-run Session, Services, Theme and Control Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a fresh install boot into Hyprland with fish/Tide, start selected services, generate matugen colours, and clean up the Control Center.

**Architecture:** Small, focused changes in the existing installer pipeline: the configuration step prepares user-level pieces (Tide, default wallpaper, matugen), the system step performs privileged actions (chsh, services, grub, mkinitcpio), and the Control Center loses redundant navigation and gains one Spicetify action.

**Tech Stack:** Bash 5, systemd, fish/fisher, matugen, rofi, existing test suite.

**Spec:** `docs/superpowers/specs/2026-11-19-first-run-session-services-theme-design.md`

## Global Constraints

- `--dry-run` prints and changes nothing, including no `sudo` and no service calls.
- Privileged actions stay inside `--system` behind the existing confirmations.
- A failure in a non-critical extra step warns and does not abort the run.
- Repo assets are public and redistributable; never add `personal/`.
- Code and tests in English; report to the user in Ukrainian.

## Review Focus

- Login shell already fish: no chsh prompt, no failure.
- Fish or fisher missing: Tide step warns, setup continues.
- `--system-components` subset: grub/mkinitcpio/services only run for selected components.
- Dry-run with services, grub, chsh, matugen, Tide: no side effects.
- Control Center on Esc: every page returns without a dead loop.

---

### Task 1: Session — cargo guard, fish login shell, Tide

**Files:**
- Modify: `modules/fish/home/.config/fish/conf.d/rustup.fish`
- Modify: `lib/system.sh` (`set_login_shell_fish`)
- Modify: `install.sh` (`run_user_hooks`, system step call)
- Test: `tests/fish.sh` (create), `tests/system-files.sh`

**Interfaces:**
- Produces: `set_login_shell_fish [user]` — returns 0 when the login shell is already fish or was changed; 1 when fish is missing or the user declined.
- Produces: `run_user_hooks()` — runs Tide after module files are installed.

- [ ] **Step 1: Write the failing tests**
  - `tests/fish.sh`: the rustup conf contains no unconditional `source`; a fake `HOME` without `.cargo/env.fish` produces no source line when evaluated (grep-based).
  - `tests/system-files.sh`: `set_login_shell_fish` exists and `install.sh` calls it in the system step; with a stub `fish` and `chsh` it is a no-op when `$SHELL` is already fish.
- [ ] **Step 2: Run to verify RED.**
- [ ] **Step 3: Implement.**
  - Guard: `if test -f "$HOME/.cargo/env.fish"; source ...; end`.
  - `set_login_shell_fish`: target `SUDO_USER` or invoking user, shell path `command -v fish`; if `getent passwd` shell equals it, return 0; otherwise confirm (unless `ASSUME_YES`) and `run chsh -s "$shell" "$user"`.
  - In `install_system_configs`, after files: if `system_component_wanted services` and fish exists, call it.
  - After `install_selected_modules`, when `fish` is selected: `if command -v fish && command -v fisher; then run fish -c 'fisher update' || warn ...; fi` (skip in dry-run).
- [ ] **Step 4: Run tests and the full suite.**
- [ ] **Step 5: Commit.**

---

### Task 2: Services and system follow-ups

**Files:**
- Modify: `lib/system.sh` (`enable_system_services`, follow-up block)
- Test: `tests/services.sh` (create)

**Interfaces:**
- Consumes: `run`, `system_component_wanted`.
- Produces: `enable_system_services` uses `systemctl enable --now`.

- [ ] **Step 1: Write the failing tests**
  - A stub `systemctl` records arguments; selecting a service calls `enable --now <unit>`.
  - The follow-up block contains no `Not run automatically` text.
  - `grub-mkconfig` and `mkinitcpio -P` are invoked only when `system_component_wanted grub` and the boot files were installed.
- [ ] **Step 2: Run RED.**
- [ ] **Step 3: Implement.**
  - Services: `run systemctl enable --now "$service"` and keep the unit-exists check.
  - Track `boot_changed=1` when `/etc/default/grub` or `/etc/mkinitcpio.conf` was written.
  - Replace the manual list with: `daemon-reload`; `systemctl start systemd-zram-setup@zram0.service` when zram; `enable --now cpupower` when cpupower; restarts for NetworkManager/unbound/pihole when DNS files were installed; `grub-mkconfig -o /boot/grub/grub.cfg` and `mkinitcpio -P` when `boot_changed`. Each with `warn` on failure, never aborting.
- [ ] **Step 4: Run tests and suite.**
- [ ] **Step 5: Commit.**

---

### Task 3: Assets — cursor theme and default wallpaper

**Files:**
- Create: `assets/cursors/win11_concept_cursos/` (copy of `/usr/share/icons/win11_concept_cursos`)
- Create: `assets/wallpapers/example.jpg` (the approved wallpaper, renamed)
- Modify: `lib/cursor.sh` (repo theme preferred)
- Modify: `install.sh` (install default wallpaper when the hypr/wallpaper module is selected)
- Test: `tests/assets.sh` (create)

**Interfaces:**
- Produces: `cursor_repo_theme_dir` — prints `assets/cursors/<theme>` when present.
- Produces: `install_default_wallpaper()` — copies the repo image to `$HOME/.local/share/wallpapers/dotfiles/example.jpg` and records it only when no wallpaper is recorded yet.

- [ ] **Step 1: Copy the assets, write the failing tests** (asset exists; wallpaper state empty → state points to installed copy; existing state is preserved; cursor install uses the repo directory without an archive).
- [ ] **Step 2: Run RED.**
- [ ] **Step 3: Implement.**
  - `cursor_install` prefers `assets/cursors/$CURSOR_THEME`; copies to `~/.local/share/icons` (no sudo); archive flow stays as fallback.
  - `install_default_wallpaper` runs in the configuration step after modules; then matugen generation happens in Task 4.
- [ ] **Step 4: Run tests and suite.**
- [ ] **Step 5: Commit.**

---

### Task 4: Theme — matugen everywhere, rofi rows, hyprlock, kitty default

**Files:**
- Modify: `install.sh` (`render_template` terminal keys, generate after config), `lib/theme.sh`
- Modify: `modules/theming/home/.config/kdeglobals.in`
- Modify: `modules/control-center/home/.config/rofi/control-center.rasi`
- Modify: `modules/idle/home/.config/hypr/hyprlock.conf`
- Test: `tests/theming.sh`, `tests/theme-menu.sh`, `tests/idle.sh`

**Interfaces:**
- Produces: `TERMINAL_APP`, `TERMINAL_SERVICE` rendered into `kdeglobals`.
- Produces: `generate_theme_if_possible()` — runs matugen when wallpaper, `matugen` and its config exist; warns otherwise.

- [ ] **Step 1: Write the failing tests:** kdeglobals contains `TerminalApplication=@TERMINAL_APP@` and `TerminalService=@TERMINAL_SERVICE@`; the control-center rasi sets an explicit `@surface` for `element normal.normal`; hyprlock label does not contain `$HOST`; `render_template` substitutes the terminal pair.
- [ ] **Step 2: Run RED.**
- [ ] **Step 3: Implement.**
  - Detect terminal: kitty if its module/command exists, else foot, ghostty, alacritty, wezterm.
  - Render keys into kdeglobals.
  - After the configuration step and the default wallpaper, call `generate_theme_if_possible`.
  - Theme-menu already regenerates on `--apply`; keep and test.
  - Rofi rows: `element normal.normal { background-color: @surface; text-color: @on-surface; }`.
  - Hyprlock label: `text = $USER`.
- [ ] **Step 4: Run tests and suite.**
- [ ] **Step 5: Commit.**

---

### Task 5: Control Center and terminal window

**Files:**
- Modify: `modules/control-center/home/.local/bin/dotfiles-control-center`
- Test: `tests/control-center.sh`

**Interfaces:**
- Consumes: `spicetify`, `rofi`.

- [ ] **Step 1: Write the failing tests:** main menu has no `Close`; no page contains `Back`; Music page gone; updates page contains `Spicetify — backup and apply`; the action is `spicetify backup apply`; `run_terminal` has no `--hold` and waits for a key (`read -rsn1`).
- [ ] **Step 2: Run RED.**
- [ ] **Step 3: Implement:** remove Back/Close, remove `music_page` and its main entry, add the Spicetify button to `install_page`, rewrite `run_terminal` to wait for one key press.
- [ ] **Step 4: Run tests and suite.**
- [ ] **Step 5: Commit.**

---

### Task 6: Autostart — add a program

**Files:**
- Modify: `modules/autostart/home/.local/bin/autostart.sh`
- Test: `tests/autostart.sh`

**Interfaces:**
- Consumes: `add_entry NAME COMMAND`, `choose_line`.
- Produces: `ask_line PROMPT` — rofi `-dmenu -l 0`, gum input, or plain read.

- [ ] **Step 1: Write the failing tests:** the pick menu source contains `Add a program`; a scripted run with `AUTOSTART_INPUT` (name, command) adds the entry and it survives a `list`.
- [ ] **Step 2: Run RED.**
- [ ] **Step 3: Implement:** add the menu item; prompt for name and command; validate with `valid_command`; call `add_entry`.
- [ ] **Step 4: Run tests and suite.**
- [ ] **Step 5: Commit.**
