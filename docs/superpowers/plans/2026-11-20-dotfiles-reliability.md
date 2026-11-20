# Dotfiles reliability pass — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the documented install/update, theming, DNS, firewall and Control Center flows work on a real machine, and replace source-grep tests with a small behavior suite.

**Architecture:** Each broken flow gets one small, sourceable helper (`lib/firefox.sh`, `lib/dns_config.sh`, `lib/firewall.sh`) that prints or applies its work, so a bash test can run it against stubs and a temporary HOME. The Control Center keeps its current structure but gains a source guard and pure command builders. System files move to `conf.d` drop-ins wherever the daemon supports them.

**Tech Stack:** Bash, rofi, matugen, Pi-hole FTL v6, unbound, ufw, systemd user units, ImageMagick.

**Spec:** `docs/superpowers/specs/2026-11-20-dotfiles-reliability-design.md`

## Global Constraints

- All repo changes reach the machine through `install.sh`; never edit live files during implementation.
- `--dry-run` changes nothing and never calls sudo.
- No `--noconfirm` for pacman or AUR helpers; the user must be able to decline.
- No new packages installed during implementation.
- Do not touch the working-tree edit in `modules/hypr/home/.config/hypr/hyprland.lua` (clipboard bind) or the Waybar spacing in `modules/waybar/home/.config/waybar/config.jsonc` / `style.css`.
- Comments and code are English; UI strings stay as they are unless the task says otherwise.

## Review Focus

- A machine with no Firefox profile: installer must warn and skip, not create a bogus profile path.
- A machine with DNS already broken: install must repair it instead of refusing to touch DNS files.
- Pi-hole TOML edited by hand: merge must not drop unrelated keys or comments.
- ufw enabled twice or rules already present: must be idempotent.
- rofi with one wallpaper or 100 wallpapers: picker must fit and still mark the current one.

---

### Task 1: Disable legacy tests and make the Control Center sourceable

**Files:**
- Move: `tests/*.sh` (except `tests/run.sh`) → `tests/legacy/`
- Modify: `tests/run.sh:33-58` (candidate glob)
- Modify: `.gitignore`
- Modify: `Makefile:31-32` (test target comment only if needed)
- Modify: `modules/control-center/home/.local/bin/dotfiles-control-center:1400-1450`

**Interfaces:**
- Produces: `tests/*.sh` contains only behavior tests; `tests/legacy/` is ignored and untracked.
- Produces: sourcing the Control Center with `BASH_SOURCE[0] != $0` defines functions without running the menu.

- [ ] **Step 1: Move the legacy tests**

```bash
mkdir -p tests/legacy
git mv tests/app-picker.sh tests/assets.sh tests/autologin.sh tests/autostart.sh \
  tests/binds-cheatsheet.sh tests/bootstrap.sh tests/control-center.sh tests/dns.sh \
  tests/doctor.sh tests/fish.sh tests/gamemode.sh tests/help-flags.sh tests/hook.sh \
  tests/hypr.sh tests/idle.sh tests/kernel.sh tests/lid.sh tests/menu.sh \
  tests/monitor-profiles.sh tests/mouse.sh tests/pkg-sync.sh tests/ram-cache.sh \
  tests/repositories.sh tests/restore.sh tests/services.sh tests/spicetify.sh \
  tests/sync.sh tests/system-files.sh tests/theme-menu.sh tests/theming.sh tests/legacy/
```

- [ ] **Step 2: Ignore the legacy directory and untrack it**

Append to `.gitignore`:

```gitignore
# ── Disabled grep-only tests (kept locally, not part of the suite) ─────────
tests/legacy/
```

Then:

```bash
git rm -r --cached tests/legacy >/dev/null
```

- [ ] **Step 3: Point the runner at the behavior suite**

`tests/run.sh` keeps `candidates=(tests/*.sh)`; no change needed because the glob no longer matches `tests/legacy/`. Verify:

```bash
./tests/run.sh --list
```

Expected: no `legacy/` paths, and it does not fail with an empty suite (a behavior test arrives in Task 2).

- [ ] **Step 4: Add the source guard**

At the end of `dotfiles-control-center`, wrap the dispatch:

```bash
control_center_main() {
    case "${1:-}" in
        ...existing case body...
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    control_center_main "$@"
fi
```

- [ ] **Step 5: Verify sourcing has no side effects**

```bash
bash -c 'source modules/control-center/home/.local/bin/dotfiles-control-center; declare -F package_search_install >/dev/null && echo sourced-ok'
```

Expected: `sourced-ok`, no rofi window.

- [ ] **Step 6: Commit**

```bash
git add .gitignore tests modules/control-center/home/.local/bin/dotfiles-control-center
git commit -m "test: retire grep-only suite and make the control center sourceable"
```

---

### Task 2: Package install and removal keep the terminal attached

**Files:**
- Modify: `modules/control-center/home/.local/bin/dotfiles-control-center:1110-1188` (`package_search_install`, `fzf_install`)
- Modify: `modules/control-center/home/.local/bin/dotfiles-control-center:1291-1305` (`fzf_remove`)
- Modify: `modules/control-center/home/.local/bin/dotfiles-control-center:1264-1290` (`package_remove`)
- Test: `tests/packages.sh`

**Interfaces:**
- Produces: `package_install_command KIND HELPER PKG...` prints one shell command string for `run_terminal`.
- Produces: `package_remove_command HELPER PKG` prints one shell command string.
- Produces: `fzf_install_script KIND HELPER` prints the script run in the terminal; it must use `mapfile` + direct invocation, never `xargs`.

- [ ] **Step 1: Write the failing test**

`tests/packages.sh` (follow the `pass`/`fail` pattern from any current test):

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="$ROOT/modules/control-center/home/.local/bin/dotfiles-control-center"
# shellcheck source=/dev/null
source "$CC"

check() { [[ $1 == *"$2"* ]]; }

if check "$(package_install_command repo "" kitty firefox)" "pacman -S --needed kitty firefox"; then
    pass "repo install keeps all selected packages"
else
    fail "repo install lost packages"
fi
if ! check "$(fzf_install_script repo "")" "xargs"; then
    pass "fzf install does not use xargs"
else
    fail "fzf install still uses xargs (stdin is /dev/null)"
fi
if check "$(package_remove_command "" kitty)" "pacman -Rns kitty"; then
    pass "remove builds a direct pacman command"
else
    fail "remove command is wrong"
fi
if check "$(package_install_command aur paru kitty)" "paru -S --needed kitty"; then
    pass "AUR install uses the detected helper"
else
    fail "AUR install is wrong"
fi
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash tests/packages.sh`
Expected: FAIL — functions do not exist.

- [ ] **Step 3: Implement the builders**

Implement in the Control Center:

```bash
package_install_command() {   # kind helper pkg...
    local kind="$1" helper="$2"
    shift 2
    case "$kind" in
        repo) printf 'sudo pacman -S --needed %s' "$(printf '%q ' "$@")" ;;
        aur)  printf '%s -S --needed %s' "$helper" "$(printf '%q ' "$@")" ;;
    esac
}

package_remove_command() {    # helper pkg
    local helper="$1" pkg="$2"
    if [[ -n $helper ]]; then
        printf '%s -Rns %q' "$helper" "$pkg"
    else
        printf 'sudo pacman -Rns %q' "$pkg"
    fi
}
```

`fzf_install_script` returns a heredoc that reads selection with `mapfile -t sel < <(...)` and then runs the command with `"${sel[@]}"`. No `xargs`, no `--noconfirm`.

- [ ] **Step 4: Re-run the test**

Run: `bash tests/packages.sh`
Expected: PASS on all four checks.

- [ ] **Step 5: Commit**

```bash
git add tests/packages.sh modules/control-center/home/.local/bin/dotfiles-control-center
git commit -m "fix(control-center): keep package prompts interactive"
```

---

### Task 3: Firefox profile discovery and CSS install

**Files:**
- Create: `lib/firefox.sh`
- Modify: `install.sh:634-644` (replace local helper with `lib/firefox.sh`)
- Create: `modules/apps/home/.config/mozilla/firefox/@FIREFOX_PROFILE_DIR@/user.js`
- Modify: `modules/matugen/home/.config/matugen/config.toml.in:7-9`
- Test: `tests/firefox.sh`

**Interfaces:**
- Produces: `firefox_profile_dir` returns the profile directory *name* or fails with status 1 when none exists.
- Produces: `firefox_profile_root` returns the directory containing profiles.
- Consumes: `REAL_HOME` from `lib/common.sh`.

- [ ] **Step 1: Write the failing test**

```bash
# tests/firefox.sh
home="$(mktemp -d)"
mkdir -p "$home/.config/mozilla/firefox/abc.default-release"
REAL_HOME="$home" source "$ROOT/lib/firefox.sh"
[[ $(firefox_profile_dir) == abc.default-release ]] && pass "finds the XDG layout" || fail "XDG layout missed"

home2="$(mktemp -d)"
mkdir -p "$home2/.mozilla/firefox/xyz.default"
REAL_HOME="$home2" source "$ROOT/lib/firefox.sh"
[[ $(firefox_profile_dir) == xyz.default ]] && pass "finds the classic layout" || fail "classic layout missed"

home3="$(mktemp -d)"
REAL_HOME="$home3" source "$ROOT/lib/firefox.sh"
firefox_profile_dir >/dev/null && fail "invented a profile" || pass "warns when there is no profile"
```

- [ ] **Step 2: Run it**

Run: `bash tests/firefox.sh`
Expected: FAIL — `lib/firefox.sh` missing.

- [ ] **Step 3: Implement `lib/firefox.sh`**

Search in this order and stop at the first match:

1. `$REAL_HOME/.config/mozilla/firefox/*.default*`
2. `$REAL_HOME/.mozilla/firefox/*.default*`
3. `$REAL_HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/*.default*`

Return `basename`; return 1 when nothing is found.

- [ ] **Step 4: Install `user.js` and tolerate a missing profile**

`user.js`:

```js
// Managed by dotfiles: allow chrome/userContent.css to load.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
```

In `install.sh`, when `firefox_profile_dir` fails, skip the `@FIREFOX_PROFILE_DIR@`
files with `warn "Firefox profile not found; start Firefox once and re-run"`, and
render `config.toml` with the detected profile only when one exists.

- [ ] **Step 5: Verify with the repo install in dry-run**

Run: `./install.sh --all --no-packages --dry-run | grep -i firefox`
Expected: with a profile present, paths contain the real profile; the run succeeds.

- [ ] **Step 6: Commit**

```bash
git add lib/firefox.sh install.sh modules/apps tests/firefox.sh
git commit -m "fix(firefox): install chrome files into the real profile"
```

---

### Task 4: Wallpaper picker and current marker

**Files:**
- Modify: `lib/wallpaper.sh` (add state reader)
- Modify: `modules/theme-menu/home/.local/bin/theme-menu.sh` (write `wallpaper.path` on apply)
- Modify: `modules/control-center/home/.local/bin/dotfiles-control-center:580-680`
- Test: `tests/wallpaper.sh`

**Interfaces:**
- Produces: `wallpaper_current_image` prints the absolute path from `theme.conf`, falling back to `wallpaper.path`, else fails.
- Produces: `wallpaper_card_key LABEL PATH` prints a cache key that includes the label.

- [ ] **Step 1: Write the failing test**

```bash
home="$(mktemp -d)"
state="$home/.local/state/dotfiles"
mkdir -p "$state" "$home/.config/hypr"
printf 'wallpaper=/a/one.jpg\n' >"$state/theme.conf"
printf '/b/two.jpg\n' >"$home/.config/hypr/wallpaper.path"
REAL_HOME="$home" source "$ROOT/lib/wallpaper.sh"
[[ $(wallpaper_current_image) == /a/one.jpg ]] && pass "theme state wins over wallpaper.path" || fail "wrong precedence"

key1="$(wallpaper_card_key photo /a/one.jpg)"
key2="$(wallpaper_card_key 'photo (current)' /a/one.jpg)"
[[ $key1 != "$key2" ]] && pass "current marker changes the cache key" || fail "stale card cache"
```

- [ ] **Step 2: Run it**

Run: `bash tests/wallpaper.sh`
Expected: FAIL.

- [ ] **Step 3: Implement the two helpers and the picker**

- `theme-menu.sh` writes `wallpaper.path` (via `set_wallpaper` from `lib/wallpaper.sh`
  semantics) whenever a wallpaper is applied.
- The picker uses a single-column list: `window { width: 380px; } listview { lines: 6; }`,
  `element-icon { size: 340px; }`, caption under the photo.
- Cache file name = `sha1(wallpaper_card_key "$label" "$path")`.

- [ ] **Step 4: Re-run**

Run: `bash tests/wallpaper.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/wallpaper.sh modules/theme-menu modules/control-center tests/wallpaper.sh
git commit -m "fix(wallpaper): single-column picker and a live current marker"
```

---

### Task 5: Lua keybind creation writes valid inserts

**Files:**
- Modify: `modules/binds-cheatsheet/home/.local/bin/binds-cheatsheet.sh:261-315`
- Test: `tests/binds.sh`

**Interfaces:**
- Produces: `add_bind SUFFIX COMMAND` appends after the last `hl.bind(` line and prints `<file>:<line>`.
- Produces: comments start with `--` (Lua), never `#`.

- [ ] **Step 1: Write the failing test**

Fixture from a temp copy of `modules/hypr/home/.config/hypr/hyprland.lua`.
Assertions:

- the last non-empty line before the new bind is `hl.bind(`-based
- the inserted comment matches `^-- Added by binds-cheatsheet`
- no line in the file starts with `#`

- [ ] **Step 2: Run it**

Run: `bash tests/binds.sh`
Expected: FAIL on `#` and on insertion point.

- [ ] **Step 3: Implement**

Find the last line number containing `hl.bind(`; insert a blank line, the `--` comment,
and the bind after it. Leave window rules below untouched.

- [ ] **Step 4: Verify**

Run: `bash tests/binds.sh && hyprctl configerrors` (skip if Hyprland absent)
Expected: PASS and no config errors.

- [ ] **Step 5: Commit**

```bash
git add modules/binds-cheatsheet tests/binds.sh
git commit -m "fix(binds): valid Lua comments and insertion among the binds"
```

---

### Task 6: Control Center cleanup and hardware gating

**Files:**
- Modify: `modules/control-center/home/.local/bin/dotfiles-control-center`
  - remove `apps_page`, Docker helpers/page, Install Docker entry, `Maintenance help`
  - add `wifi_hardware_present`, `bluetooth_hardware_present`
  - add `lock_screen_page` (Configuration → Lock screen)
- Modify: `packages/catalog.tsv` (remove docker, docker-compose, lazydocker rows)
- Modify: `README.md`, `README.uk.md` (remove Docker/Apps/Maintenance mentions)
- Test: `tests/control-center.sh`

**Interfaces:**
- Produces: `wifi_hardware_present` returns 0 when `nmcli -t -f TYPE device` lists `wifi`.
- Produces: `bluetooth_hardware_present` returns 0 when `bluetoothctl list` is non-empty.
- Produces: `control_center_pages` prints `Docs Menu Style Configuration Install Uninstall Update Power`.

- [ ] **Step 1: Write the failing test**

Source the Control Center and assert:

- `control_center_pages` contains neither `Apps` nor any `Docker` entry
- `grep -c 'Maintenance help' "$CC"` is 0
- `wifi_hardware_present` is false when a stub `nmcli` prints only `ethernet`
- `lock_screen_page` exists and calls `hyprlock`

- [ ] **Step 2: Run it**

Run: `bash tests/control-center.sh`
Expected: FAIL on all four.

- [ ] **Step 3: Implement**

- Main menu icons/names arrays and the dispatch index list drop `Apps`.
- `--list-actions` prints `control_center_pages`.
- Delete `docker_ready`, `docker_pull`, `docker_page`, and the catalog rows.
- Delete the `Maintenance help` spec and case.
- Gate `Wi-Fi`/`Bluetooth` entries with the hardware helpers.
- Add `Lock screen` to Configuration, running `hyprlock` when present and
  `message "Install hyprlock (idle module) ..."` otherwise.

- [ ] **Step 4: Re-run**

Run: `bash tests/control-center.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/control-center packages/catalog.tsv README.md README.uk.md tests/control-center.sh
git commit -m "feat(control-center): drop Docker, Apps and maintenance help"
```

---

### Task 7: hyprlock and fastfetch follow the palette

**Files:**
- Create: `modules/matugen/home/.config/matugen/templates/hyprlock.conf`
- Create: `modules/matugen/home/.config/matugen/templates/fastfetch.jsonc`
- Modify: `modules/matugen/home/.config/matugen/config.toml.in`
- Delete: `modules/idle/home/.config/hypr/hyprlock.conf` (replaced by the generated file)
- Create: `modules/apps/home/.config/fastfetch/config.jsonc.in`? No — fastfetch is generated by matugen, like dunst.
- Test: `tests/theme-templates.sh`

**Interfaces:**
- Produces: matugen outputs `~/.config/hypr/hyprlock.conf` and `~/.config/fastfetch/config.jsonc`.
- Produces: both templates use `{{colors.…}}` placeholders and `Inter`.

- [ ] **Step 1: Write the failing test**

Assert the two template files exist, contain `Inter`, and contain at least three
`{{colors.` placeholders; assert `config.toml.in` registers both output paths.

- [ ] **Step 2: Run it** — expected FAIL.

- [ ] **Step 3: Implement**

- hyprlock template: wallpaper background (`path = screenshot` keeps it cheap),
  surface/primary colors, rounded input field, Inter labels.
- fastfetch template: `logo` colors from palette keys, `display` separator, module
  order matching the system look.
- `config.toml.in` gains `[templates.hyprlock]` and `[templates.fastfetch]`.

- [ ] **Step 4: Re-run** — expected PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/matugen modules/idle modules/apps tests/theme-templates.sh
git commit -m "feat(theme): generate hyprlock and fastfetch from the palette"
```

---

### Task 8: DNS chain that can be repaired

**Files:**
- Create: `system/unbound/pi-hole.conf` (replaces `system/unbound/unbound.conf`)
- Delete: `system/unbound/unbound.conf`
- Create: `system/pihole/dotfiles-dnsmasq.conf`
- Delete: `system/pihole/dnsmasq.conf`
- Create: `system/pihole/adlists.txt`
- Create: `lib/dns_config.sh`
- Modify: `lib/system.sh` (`system_file_map`, `install_system_configs`)
- Modify: `lib/dns.sh` (do not trip the ERR trap)
- Delete: `system/pihole/pihole.toml.example` from the file map (keep the file as documentation)
- Test: `tests/dns.sh`

**Interfaces:**
- Produces: `dns_unbound_conf_path` → `/etc/unbound/unbound.conf.d/pi-hole.conf`
- Produces: `dns_write_unbound SRC` writes, backs up, runs `unbound-checkconf`, restores on failure.
- Produces: `dns_pihole_apply` runs `pihole-FTL --config` for each key and is idempotent.
- Produces: `dns_adlists_sync FILE` inserts missing addresses and runs `pihole -g` once.
- Produces: `dns_root_hints_install URL` downloads to a temp file, validates it starts with `.` zone data, installs atomically.

- [ ] **Step 1: Write the failing test**

Use stub `pihole-FTL`, `pihole`, `unbound-checkconf`, `curl` in `PATH` and a temp
`ROOT_DIR` override. Assert:

- `dns_pihole_apply` issues `--config dns.upstreams '["127.0.0.1#5335"]'`,
  `--config dns.port 53`, `--config misc.etc_dnsmasq_d true`
- running it twice issues the same commands (idempotent)
- `dns_adlists_sync` inserts only missing rows
- `dns_write_unbound` restores the old file when `unbound-checkconf` fails

- [ ] **Step 2: Run it** — expected FAIL.

- [ ] **Step 3: Write the unbound drop-in**

Follow the official Pi-hole guide: `interface: 127.0.0.1`, `port: 5335`,
`do-ip4: yes`, `do-udp: yes`, `do-tcp: yes`, `do-ip6: no`, `prefer-ip6: no`,
`root-hints: "/etc/unbound/root.hints"`, `harden-glue: yes`,
`harden-dnssec-stripped: yes`, `use-caps-for-id: no`,
`edns-buffer-size: 1232`, `prefetch: yes`, `num-threads: 1`, `so-rcvbuf: 1m`,
plus the private-address list.

- [ ] **Step 4: Map the drop-in and remove the gate**

`system_file_map` maps `unbound/pi-hole.conf` → the drop-in path and
`pihole/dotfiles-dnsmasq.conf` → `/etc/dnsmasq.d/dotfiles.conf`. Remove the
`!dns_ok` skip block; after applying, probe the chain and warn on failures.

- [ ] **Step 5: Fix `lib/dns.sh`**

```bash
answer="$(dns_query "$server" "$port" "$DNS_PROBE_NAME" || true)"
```

and make the `dig` branch `|| true`. `dns_chain_ok` must never trigger the ERR trap.

- [ ] **Step 6: Re-run** — expected PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/dns.sh lib/dns_config.sh lib/system.sh system/unbound system/pihole tests/dns.sh
git commit -m "fix(dns): repairable Pi-hole and unbound chain with drop-ins"
```

---

### Task 9: Firewall and Syncthing

**Files:**
- Create: `lib/firewall.sh`
- Modify: `lib/system.sh` (`enable_system_services` or `install_system_configs`)
- Modify: `packages/catalog.tsv` if `openssh` is not yet listed
- Test: `tests/firewall.sh`, `tests/services.sh`

**Interfaces:**
- Produces: `firewall_rules` prints one `PORT/PROTO` per line, only what is reachable:
  `22/tcp` when `sshd` exists, `22000/tcp` and `22000/udp` when `syncthing` exists.
- Produces: `firewall_apply RULES` is idempotent (`ufw allow` duplicate is a no-op).
- Produces: `enable_syncthing_user_service` runs `systemctl --user enable --now syncthing.service`.

- [ ] **Step 1: Write the failing test**

Stub `command -v` by creating fake binaries in a temp `PATH`; assert
`firewall_rules` output with and without `sshd`/`syncthing`, and that
`firewall_apply` runs `ufw default deny incoming` and `ufw default allow outgoing`
once and each rule once (even when called twice).

- [ ] **Step 2: Run it** — expected FAIL.

- [ ] **Step 3: Implement**

`firewall_apply` order: defaults → rules → `ufw --force enable`. Never open 53, 5335,
8384, 631.

- [ ] **Step 4: Re-run and commit**

```bash
git add lib/firewall.sh lib/system.sh tests/firewall.sh tests/services.sh
git commit -m "feat(system): enable ufw with a minimal rule set and start syncthing"
```

---

### Task 10: System files as drop-ins

**Files:**
- Move: `system/grub/default-grub` → `system/grub/99-dotfiles.cfg`
- Move: `system/mkinitcpio/mkinitcpio.conf` → `system/mkinitcpio/99-dotfiles.conf`
- Move: `system/zram/zram-generator.conf` → `system/zram/99-dotfiles.conf`
- Modify: `lib/system.sh:54-80` (`system_file_map`)
- Modify: `lib/system.sh:580-600` (restart after change)
- Test: `tests/system-files.sh`

**Interfaces:**
- Produces mappings:
  - `/etc/default/grub.d/99-dotfiles.cfg`
  - `/etc/mkinitcpio.conf.d/99-dotfiles.conf`
  - `/etc/systemd/zram-generator.conf.d/99-dotfiles.conf`
- Produces: `system_conf_validate DST` runs `unbound-checkconf` for unbound files,
  `bash -n` for scripts, and `systemd-analyze verify` for unit files; on failure the
  previous file is restored.

- [ ] **Step 1: Write the failing test** — assert the new destinations and that no
  mapping writes `/etc/default/grub`, `/etc/mkinitcpio.conf`, or
  `/etc/systemd/zram-generator.conf` directly.

- [ ] **Step 2: Run it** — expected FAIL.

- [ ] **Step 3: Convert the files** — keep only the settings we need, not the stock
  copies; GRUB keeps its kernel cmdline, mkinitcpio keeps `MODULES`/`HOOKS`,
  zram keeps its `[zram0]` section.

- [ ] **Step 4: Hook validation into the install loop** (after backup, before the
  service restart).

- [ ] **Step 5: Re-run and commit**

```bash
git add system lib/system.sh tests/system-files.sh
git commit -m "refactor(system): manage drop-ins and validate before restart"
```

---

### Task 11: Readable hand-written configs

**Files:**
- Modify: `modules/hypr/home/.config/hypr/hyprland.lua`
- Modify: `modules/waybar/home/.config/waybar/config.jsonc`
- Modify: `modules/rofi/home/.config/rofi/launcher.rasi`
- Modify: `modules/dunst/home/.config/dunst/dunstrc.in`
- Modify: `modules/idle/home/.config/hypr/hypridle.conf`
- Modify: `modules/fish/home/.config/fish/config.fish`
- Modify (headers only): matugen templates
- Test: `tests/configs.sh`

**Interfaces:**
- Produces: every hand-written config starts with a title and one-line purpose; each
  section has a short `--`/`#` divider; every window rule has a one-line reason.

- [ ] **Step 1: Write the failing test** — assert each file's first line is a comment,
  and that `hyprland.lua` window rules have a comment immediately above each
  `hl.window_rule({` when the rule is non-obvious.

- [ ] **Step 2: Run it** — expected FAIL.

- [ ] **Step 3: Rewrite for readability** — do not change behavior; do not touch the
  user's clipboard bind or Waybar spacing values.

- [ ] **Step 4: Verify** — `bash tests/configs.sh`, `bash -n` on shell configs,
  `hyprctl configerrors` when available.

- [ ] **Step 5: Commit**

```bash
git add modules tests/configs.sh
git commit -m "style(configs): consistent headers, dividers and rule comments"
```

---

### Task 12: Documentation and final verification

**Files:**
- Modify: `README.md`, `README.uk.md` (DNS, firewall, lock screen, removed entries)
- Modify: `docs/superpowers/specs/2026-11-20-dotfiles-reliability-design.md` (status)
- Test: `tests/run.sh` (whole suite)

- [ ] **Step 1: Update docs** — no Docker, no Apps page, no Maintenance help; describe
  the DNS chain and the ufw rule set; mention the new Lock screen entry.

- [ ] **Step 2: Run everything**

```bash
make lint
./tests/run.sh
./install.sh --all --no-packages --yes --dry-run
```

Expected: lint clean, all behavior tests pass, dry-run completes without sudo and
without writing files.

- [ ] **Step 3: Commit**

```bash
git add README.md README.uk.md docs tests
git commit -m "docs: document the reliability pass"
```
