# Guided First-Run Setup and Catalogue Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the installer a clear packages → configuration → `/etc` → kernel sequence, stop silent package no-ops, gate services on installed units, refresh pacman mirrors from the Control Center, and apply the requested catalogue changes.

**Architecture:** A new `--setup` flow runs the existing stages in order inside `install.sh`; the interactive menu gets a `First-time setup` entry and numbered steps. Package installation moves before module file installation. Service selection and autostart filter on installed units/commands. The Control Center gains a reflector action.

**Tech Stack:** Bash, gum/whiptail/plain TUI, pacman/yay, systemd, rofi, reflector.

**Spec:** `docs/superpowers/specs/2026-11-19-guided-setup-catalog-design.md`

## Global Constraints

- No live package installation, no `/etc` writes, no sudo prompts during tests.
- `--all` keeps its current meaning: modules + default packages, no system, no kernel.
- All new tests use temporary HOME/XDG and stub tools.
- Response and user-facing docs stay in English and Ukrainian where the file is bilingual.
- `profile-sync-daemon` moves to `System`.
- `networkmanager` moves to `bootstrap.sh` prerequisites.

## Review Focus

- `--only-packages` with no selector and no TTY must fail with a readable error.
- A package install that did not produce the requested packages must fail, not print success.
- A missing service unit must never be offered or enabled.
- An autostart entry whose command is missing must not be launched.
- The guided flow must not run `/etc` or kernel stages without confirmation.

---

### Task 1: Catalogue and bootstrap changes

**Files:**
- Modify: `packages/catalog.tsv`
- Modify: `bootstrap.sh`
- Modify: `tests/app-picker.sh`
- Modify: `tests/bootstrap.sh`

**Interfaces:**
- Produces: `catalog_lines` output used by all later tasks; `BASE_PACKAGES` includes `networkmanager`.

- [ ] **Step 1: Write failing catalogue assertions**

Add to `tests/app-picker.sh` after the existing removed-package check:

```bash
for removed in base base-devel efibootmgr git gitleaks tcpdump cups-pdf \
    fbida smath networkmanager clang cmake jdk17-openjdk lld llvm uv rustup \
    jpegoptim oxipng; do
    if catalog_lines | cut -f1 | grep -qx "$removed"; then
        fail "$removed should have been removed from the catalog"
    fi
done
pass "requested removals are gone from the catalog"

for optional in inotify-tools snap-pac cpu-x gsmartcontrol hardinfo2 \
    kdiskmark pdfcraft-bin s-tui docker docker-compose libvirt qemu-base \
    qemu-desktop swtpm virt-manager; do
    if ! catalog_lines | awk -F'\t' -v p="$optional" '$1 == p && $4 == "no" { found = 1 } END { exit !found }'; then
        fail "$optional should be optional (default=no)"
    fi
done
pass "requested optional packages default to no"

if catalog_lines | awk -F'\t' '$1 == "profile-sync-daemon" && $2 == "System" { found = 1 } END { exit !found }'; then
    pass "profile-sync-daemon moved to System"
else
    fail "profile-sync-daemon is not in System"
fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/app-picker.sh`
Expected: FAIL for removed rows and defaults.

- [ ] **Step 3: Edit `packages/catalog.tsv`**

Delete these rows entirely: `base`, `base-devel`, `efibootmgr`, `git`,
`gitleaks`, `tcpdump`, `cups-pdf`, `fbida`, `smath`, `networkmanager`,
`clang`, `cmake`, `jdk17-openjdk`, `lld`, `llvm`, `uv`, `rustup`,
`jpegoptim`, `oxipng`.

Set column 4 to `no` for: `inotify-tools`, `snap-pac`, `cpu-x`,
`gsmartcontrol`, `hardinfo2`, `kdiskmark`, `pdfcraft-bin`, `s-tui`,
`docker`, `docker-compose`, `libvirt`, `qemu-base`, `qemu-desktop`, `swtpm`,
`virt-manager`.

Change `profile-sync-daemon` category from `Session` to `System`.

- [ ] **Step 4: Add NetworkManager to bootstrap**

In `bootstrap.sh`, change:

```bash
BASE_PACKAGES=(base-devel git curl jq gum)
```

to:

```bash
BASE_PACKAGES=(base-devel git curl jq gum networkmanager)
```

Update the usage text that lists bootstrap packages.

- [ ] **Step 5: Update bootstrap test expectations**

In `tests/bootstrap.sh`, replace the expected pacman line with:

```bash
-S --needed --noconfirm base-devel git jq gum networkmanager
```

and add `networkmanager` to the tool loop where the package stubs are created.

- [ ] **Step 6: Run tests**

Run: `bash tests/app-picker.sh && bash tests/bootstrap.sh`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add packages/catalog.tsv bootstrap.sh tests/app-picker.sh tests/bootstrap.sh
git commit -m "chore(packages): apply the requested catalogue removals and defaults"
```

---

### Task 2: Robust `--only-packages`

**Files:**
- Modify: `install.sh`
- Modify: `lib/packages.sh`
- Test: `tests/app-picker.sh`

**Interfaces:**
- Produces: `install_packages` returns non-zero when a requested package is still missing after installation.

- [ ] **Step 1: Write the failing test**

Add to `tests/app-picker.sh`:

```bash
# 13. --only-packages without a selector cannot silently do nothing.
if (cd "$ROOT" && timeout 20 ./install.sh --dry-run --yes --only-packages) >/tmp/op-only-packages.log 2>&1; then
    fail "--only-packages without a selector succeeded"
else
    if grep -q 'needs --packages, --category or --apps' /tmp/op-only-packages.log; then
        pass "--only-packages without a selector fails loudly"
    else
        fail "--only-packages failed without a clear message"
    fi
fi
```

Use a temporary file under the test's temp dir instead of `/tmp` if the suite
has one; otherwise keep the literal path and remove it at the end.

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/app-picker.sh`
Expected: FAIL (the command currently exits 0).

- [ ] **Step 3: Add the guard in `install.sh`**

After the `ONLY_PACKAGES` block:

```bash
if (( ONLY_PACKAGES )) \
    && [[ -z $PACKAGES_ARG && -z $CATEGORY_ARG && -z $APPS_ARG ]] \
    && { (( ASSUME_YES )) || [[ ! -t 0 ]]; }; then
    die "--only-packages needs --packages, --category or --apps"
fi
```

- [ ] **Step 4: Add install verification in `lib/packages.sh`**

Before the package-manager case:

```bash
if [[ $manager == pacman ]] && (( EUID != 0 )) && ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required to install packages"
fi
```

After the case block, re-read installed packages and fail when any requested
package is still missing:

```bash
unset PACKAGE_INSTALLED
declare -gA PACKAGE_INSTALLED=()
package_installed_map
local -a not_installed=()
for pkg in "${manager_packages[@]}"; do
    [[ -n ${PACKAGE_INSTALLED[$pkg]:-} ]] || not_installed+=("$pkg")
done
if ((${#not_installed[@]})); then
    warn "not installed: ${not_installed[*]}"
    return 1
fi
ok "installed ${#manager_packages[@]} package(s)"
```

- [ ] **Step 5: Run tests**

Run: `bash tests/app-picker.sh`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add install.sh lib/packages.sh tests/app-picker.sh
git commit -m "fix(install): fail loudly when package installation installs nothing"
```

---

### Task 3: Service and autostart gating

**Files:**
- Modify: `install.sh`
- Modify: `modules/autostart/home/.local/bin/autostart.sh`
- Test: `tests/autostart.sh`
- Test: `tests/menu.sh`

**Interfaces:**
- Produces: `user_unit_exists UNIT` in `install.sh`; `entry_command_available CMD` in `autostart.sh`.

- [ ] **Step 1: Write the autostart failure test**

Add to `tests/autostart.sh`:

```bash
# 14. run skips entries whose command does not exist.
{
    printf '1\tmissing\tdefinitely-not-a-real-command --flag\n'
} >"$state_file"
missing_out="$(run_auto run 2>&1)"
if grep -q 'skip missing: command not found' <<<"$missing_out" \
    && ! grep -q 'start missing:' <<<"$missing_out"; then
    pass "run skips an autostart entry with a missing command"
else
    fail "run launched a missing autostart entry"
    printf '%s\n' "$missing_out"
fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/autostart.sh`
Expected: FAIL.

- [ ] **Step 3: Implement command detection in `autostart.sh`**

Add before `launch`:

```bash
entry_command_available() {
    local cmd="$1" first
    if [[ $cmd == "uwsm app -- "* ]]; then
        cmd="${cmd#uwsm app -- }"
    fi
    read -r first _ <<<"$cmd"
    first="${first%\"}"
    first="${first#\"}"
    first="${first%\'}"
    first="${first#\'}"
    if [[ $first == /* ]]; then
        [[ -x $first ]]
    else
        command -v -- "$first" >/dev/null 2>&1
    fi
}
```

In `run_entries`, before launching (and in the dry-run branch), skip entries
where `entry_command_available "$cmd"` is false and log
`skip $name: command not found`. Count them separately and report
`started N enabled entries (M skipped)`.

In `show_list` and `pick_entries`, append ` (not installed)` when the command
is unavailable.

- [ ] **Step 4: Implement unit gating in `install.sh`**

Add near `enable_services`:

```bash
user_unit_exists() {
    local unit="$1"
    if systemctl --user list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .; then
        return 0
    fi
    [[ -f "/usr/lib/systemd/user/$unit" || -f "/etc/systemd/user/$unit" \
        || -f "$REAL_HOME/.config/systemd/user/$unit" ]]
}
```

Filter the service labels before the checklist. Warn once per skipped unit:

```bash
if ! user_unit_exists "$service"; then
    warn "service not installed, skipping: $service"
    continue
fi
```

- [ ] **Step 5: Update tests**

In `tests/autostart.sh`, update the dry-run and run fixtures to create stubs
for every command they expect to start. For example, add executable stubs in
`$bin` named `waybar`, `dunst`, `awww-daemon`, etc. Change the expected count
line to the new `(M skipped)` form.

In `tests/menu.sh`, add an assertion that `install.sh` defines
`user_unit_exists` and that `enable_services` calls it:

```bash
if grep -q '^user_unit_exists()' "$ROOT/install.sh" \
    && grep -q 'user_unit_exists "$service"' "$ROOT/install.sh"; then
    pass "services are gated on installed units"
else
    fail "services are not gated on installed units"
fi
```

- [ ] **Step 6: Run tests**

Run: `bash tests/autostart.sh && bash tests/menu.sh`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add install.sh modules/autostart/home/.local/bin/autostart.sh tests/autostart.sh tests/menu.sh
git commit -m "fix(services): never offer or start units and apps that are not installed"
```

---

### Task 4: Guided setup and ordered flow

**Files:**
- Modify: `install.sh`
- Modify: `lib/menu.sh`
- Test: `tests/menu.sh`
- Test: `tests/help-flags.sh`

**Interfaces:**
- Produces: `SETUP=1` flag; `run_setup_stage`; menu entry `setup`.

- [ ] **Step 1: Write the failing menu test**

Add to `tests/menu.sh`:

```bash
# 7. The main menu presents the setup order.
main_items="$(menu_items_for main)"
if grep -q '^setup|' <<<"$main_items" \
    && grep -q '^apps|1\. Packages' <<<"$main_items" \
    && grep -q '^modules|2\. Configuration files' <<<"$main_items" \
    && grep -q '^menu:system|3\. System configuration' <<<"$main_items" \
    && grep -q '^menu:kernel|4\. Kernel' <<<"$main_items"; then
    pass "the main menu shows the packages -> configs -> system -> kernel order"
else
    fail "the main menu does not show the setup order"
    printf '%s\n' "$main_items"
fi

if grep -q -- '--setup' <<<"$(cd "$ROOT" && ./install.sh --help)"; then
    pass "--setup is documented"
else
    fail "--setup is missing from --help"
fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/menu.sh`
Expected: FAIL.

- [ ] **Step 3: Add `--setup` parsing and validation**

Add near the other flags:

```bash
SETUP=0
...
--setup) SETUP=1; HAS_ACTION=1 ;;
```

After option checks:

```bash
if (( SETUP )); then
    (( !DRY_RUN )) && [[ ! -t 0 ]] && die "--setup needs an interactive terminal"
    (( ASSUME_YES )) && die "--setup is interactive; do not combine it with --yes"
fi
```

- [ ] **Step 4: Add the guided runner**

Run each stage as a child `install.sh` process so every stage keeps its own
privileges and prompts. Add before the `ONLY_PACKAGES` branch:

```bash
setup_stage() {
    local label="$1"
    shift
    if ! tui_confirm "$label" yes; then
        info "step skipped"
        return 0
    fi
    "$@" || {
        local rc=$?
        warn "setup stopped after: $label"
        return "$rc"
    }
}

run_setup() {
    local -a common=(--host "$HOST_NAME" --gpu "$GPU_PROFILE")
    (( DRY_RUN )) && common+=(--dry-run)

    setup_stage "Step 1/4: packages?" \
        bash "$DOTFILES_DIR/install.sh" --only-packages "${common[@]}" || return $?
    setup_stage "Step 2/4: configuration files and their packages?" \
        bash "$DOTFILES_DIR/install.sh" --module-packages "${common[@]}" || return $?

    local -a system_cmd=(--system)
    (( DRY_RUN )) && system_cmd+=(--dry-run)
    system_cmd+=(--host "$HOST_NAME" --gpu "$GPU_PROFILE")
    if (( DRY_RUN || EUID == 0 )); then
        setup_stage "Step 3/4: system configuration?" \
            bash "$DOTFILES_DIR/install.sh" "${system_cmd[@]}" || return $?
    else
        setup_stage "Step 3/4: system configuration (sudo)?" \
            sudo bash "$DOTFILES_DIR/install.sh" "${system_cmd[@]}" || return $?
    fi

    setup_stage "Step 4/4: kernel?" \
        bash "$DOTFILES_DIR/install.sh" --kernel "${common[@]}" || return $?
}

if (( SETUP )); then
    if run_setup; then
        exit 0
    else
        exit $?
    fi
fi
```

`--module-packages` selects modules and installs their package requirements
before linking files, without opening the catalogue picker. This leaves the
normal flag flow untouched. `--setup` is rejected with `--yes`, without a TTY,
or together with `--only-packages`/`--no-packages`.

- [ ] **Step 6: Reorder `lib/menu.sh`**

Main menu items become:

```text
setup|First-time setup|packages -> configuration -> system -> kernel
profile|Profile|host and GPU profile
apps|1. Packages|choose categories and applications
modules|2. Configuration files|link dotfiles and enable services
menu:system|3. System configuration|/etc files, sudo required
menu:kernel|4. Kernel|CPU-level aware kernel selection
menu:maintenance|Maintenance|doctor, DNS, restore, sync, hooks
dryrun|Dry run|toggle for every action
exit|Exit|leave without doing anything
```

Add `MENU_FLAG[setup]="--setup"`, `menu_action setup) menu_run --setup ;;`,
and remove the now-unused `install` submenu from `menu_items_for` and
`menu_menu_names`.

- [ ] **Step 7: Run tests**

Run: `bash tests/menu.sh && bash tests/help-flags.sh`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add install.sh lib/menu.sh tests/menu.sh tests/help-flags.sh
git commit -m "feat(setup): guide first-time installs through packages, configs, system and kernel"
```

---

### Task 5: Mirror refresh in the Control Center

**Files:**
- Modify: `modules/control-center/home/.local/bin/dotfiles-control-center`
- Test: `tests/control-center.sh`

**Interfaces:**
- Produces: System page entry `Update — repository mirrors (reflector)`.

- [ ] **Step 1: Write the failing test**

In `tests/control-center.sh`, extend the System page check:

```bash
if grep -q 'Update — repository mirrors (reflector)' "$CC" \
    && grep -q 'reflector --latest 20 --protocol https --sort rate' "$CC" \
    && grep -q 'mirrorlist.bak' "$CC"; then
    pass "mirror refresh is wired to reflector with a backup"
else
    fail "mirror refresh is missing"
fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/control-center.sh`
Expected: FAIL.

- [ ] **Step 3: Implement the action**

Add the menu entry after the update entries and a case:

```bash
"Update — repository mirrors (reflector)")
    if have reflector; then
        local backup="/etc/pacman.d/mirrorlist.bak.$(date +%Y%m%d-%H%M%S)"
        run_terminal "sudo cp -a /etc/pacman.d/mirrorlist $(printf '%q' "$backup") && sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist"
    else
        notify "reflector is not installed"
    fi
    ;;
```

- [ ] **Step 4: Run tests**

Run: `bash tests/control-center.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add modules/control-center/home/.local/bin/dotfiles-control-center tests/control-center.sh
git commit -m "feat(control-center): refresh pacman mirrors with reflector"
```

---

### Task 6: Documentation and full verification

**Files:**
- Modify: `README.md`, `README.uk.md`
- Modify: `docs/arch-install.md`, `docs/arch-install.uk.md`

- [ ] **Step 1: Document the guided order**

Add a short section to both READMEs: first run, menu order, what each stage
does, that `--all` stays packages + modules only, and that `--setup` is
interactive. Document `--only-packages` requiring a selector when there is no
TTY. Document the mirror refresh and the new bootstrap package list.

- [ ] **Step 2: Document the catalogue changes**

Update the package-management section with the removed rows, the new optional
defaults, and the `profile-sync-daemon` move to System.

- [ ] **Step 3: Run the full check**

Run: `make check`
Expected: tests, shellcheck and audit pass; no new warnings.

- [ ] **Step 4: Commit**

```bash
git add README.md README.uk.md docs/arch-install.md docs/arch-install.uk.md docs/superpowers/specs docs/superpowers/plans
git commit -m "docs: describe the guided setup, catalogue changes and mirror refresh"
```
