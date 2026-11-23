# Dotfiles reliability pass — design

Date: 2026-11-20
Status: implemented

## Intent

The repository installs and looks right, but everyday flows still fail on a real
machine: package installs die at the pacman prompt, Firefox colors never reach the
profile, DNS is skipped exactly when it is broken, the firewall and Syncthing are
never started, and the Control Center shows entries that cannot work. This pass
makes those flows work on a fresh install and keeps the polish the user already has.

## Goals

- Package install and removal stay interactive (no `--noconfirm`) and no longer
  die at the `[Y/n]` prompt.
- Firefox chrome CSS is installed and regenerated in the profile that actually
  exists.
- Pi-hole + unbound form a working caching recursive chain; existing files are
  merged or extended, never replaced with stock examples. Blocklists are added.
- ufw active with deny-incoming / allow-outgoing and only the ports that must be
  reachable from the LAN.
- Syncthing user service starts.
- hyprlock and fastfetch follow the matugen palette and the system look.
- Control Center loses Docker, the Apps page, and Maintenance help; Wi-Fi and
  Bluetooth entries appear only when the hardware exists.
- Wallpaper picker fits the screen, shows the real current wallpaper.
- New keybinds are valid Lua, commented with `--`, inserted in the binds section.
- Hyprland config is rewritten for readability; the same header/section style is
  applied to the other hand-written configs.

## Non-goals

- No package installs or removals, no pushing, no changes to live files without
  the installer.
- No rewrite of large upstream files such as the 1881-line `kitty.conf` beyond the
  parts we own.
- Docker support is removed, not repaired.

## Constraints

- All repo changes reach the machine through `install.sh` only.
- `--dry-run` changes nothing and never calls sudo.
- Interactive package prompts must remain possible; the user must be able to
  decline a dependency set.

## Key decisions

### Packages (interactive, no xargs)

`xargs` redirects the child's stdin from `/dev/null`, which is why pacman sees EOF
at its confirmation prompt. Selection is read into an array with `mapfile`, then

    sudo pacman -S --needed "${selected[@]}"

keeps the terminal attached, so pacman's own prompt decides. Same shape for the
AUR helper and for `pacman -Rns`. No `--noconfirm`.

### Firefox profile discovery

Candidates, first match wins:

1. `~/.config/mozilla/firefox/*.default*` (current Arch layout, confirmed here)
2. `~/.mozilla/firefox/*.default*` (classic layout)
3. `~/.var/app/org.mozilla.firefox/.mozilla/firefox/*.default*` (Flatpak)

If none exists, the installer warns and skips the chrome files instead of writing
into a made-up directory. A generated `user.js` enables
`toolkit.legacyUserProfileCustomizations.stylesheets` so the CSS applies without a
manual about:config change. The matugen config is rendered with the detected
profile each run, so colors regenerate with every wallpaper change.

### DNS: drop-in, merge, verify

Follows the official Pi-hole unbound guide, adapted to Arch:

- `/etc/unbound/unbound.conf` (pacman-owned, 1509 lines) is no longer managed.
- Our recursive resolver lives in `/etc/unbound/unbound.conf.d/pi-hole.conf`:
  listen `127.0.0.1@5335`, UDP+TCP, DNSSEC validation, hardened glue,
  `edns-buffer-size: 1232`, `prefetch: yes`, private ranges, cache sizes sized
  for a desktop. This is where unbound's caching comes from.
- `/etc/unbound/root.hints` is fetched from
  `https://www.internic.net/domain/named.root` with `curl` (the user asked for
  exactly this) and validated before install.
- Pi-hole keeps `/etc/pihole/pihole.toml`, but keys are merged in place instead of
  replacing the file: `dns.upstreams = ["127.0.0.1#5335"]`, `dns.port = 53`,
  `misc.etc_dnsmasq_d = true`, query logging stays as configured. Unknown keys and
  comments are preserved.
- Extra dnsmasq settings go to `/etc/dnsmasq.d/dotfiles.conf`, because Pi-hole
  regenerates `/etc/pihole/dnsmasq.conf` on every config change.
- Blocklists are inserted into `/etc/pihole/gravity.db` with
  `pihole-FTL sqlite3 ... INSERT OR IGNORE` keyed by address, then `pihole -g`.
  The list is a small curated file in the repo (StevenBlack unified + a couple of
  well-known lists), editable in one place.
- The "skip every DNS file while the chain is unhealthy" gate is removed: it made
  repair impossible. Files are applied, services restarted, then the chain is
  probed; a failing probe prints actionable warnings.
- `lib/dns.sh` stops tripping the ERR trap: `dig` exit 9 means "no reply", which is
  an expected probe result, so probe calls are guarded instead of raising.

### ufw

`ufw default deny incoming`, `ufw default allow outgoing`, `ufw enable` at install.
Inbound rules only for services that must be reachable:

- `22/tcp` when `sshd` is installed.
- `22000/tcp` and `22000/udp` when Syncthing is installed.

Pi-hole (53), unbound (5335), the Pi-hole web UI (80/443 on localhost), Syncthing's
8384 UI and CUPS stay bound to localhost and get no rule.

### Syncthing

`systemctl --user enable --now syncthing.service` in the services step, with the
unit looked up before use.

### hyprlock and fastfetch

- hyprlock stays optional: the idle module already installs it, and nothing forces
  it on a machine that does not want a locker. The Control Center Lock action uses
  hyprlock when it is installed and keeps the current `loginctl` fallback
  otherwise.
- Configuration gets its own "Lock screen" entry that runs hyprlock directly, so
  the route is explicit instead of hidden behind the power page.
- The hyprlock config becomes a matugen template: background is the current
  wallpaper, colors come from the generated palette, font stays Inter, and the
  field is rounded to match rofi/waybar.
- fastfetch gets a module config generated by matugen so keys/logo colors follow
  the palette and the layout matches the system look.

### conf.d first, and validate what we write

Every system file that a daemon can read as a drop-in moves to its `conf.d` /
`*.d` directory instead of replacing a package-owned file:

- `/etc/unbound/unbound.conf.d/pi-hole.conf`
- `/etc/dnsmasq.d/dotfiles.conf`
- `/etc/default/grub.d/99-dotfiles.cfg`
- `/etc/mkinitcpio.conf.d/99-dotfiles.conf`
- `/etc/systemd/zram-generator.conf.d/99-dotfiles.conf`

Files without a drop-in mechanism (Pi-hole's TOML, `cpupower`, unit files) are
merged or kept whole. Whenever the unbound config is written, the installer runs
`unbound-checkconf` before restarting; a failing check restores the previous file
and reports the error.

### Wallpaper picker

One card per row (the two-column grid cannot fit 300 px cards in the panel), card
width fixed to the window, name underneath. Cache keys include the `(current)`
label so the marker updates. The current wallpaper is read from the theme state,
which is the source of truth after `theme-menu.sh` runs; `theme-menu.sh` also
writes `wallpaper.path` so both readers agree.

### Keybind creation

`--` for comments, and the new `hl.bind` is inserted after the last existing
`hl.bind(` line inside the binds section, not appended after window rules.

### Tests

The existing 500 grep-based checks are disabled, not deleted: they move to
`tests/legacy/`, which is ignored by git, and stop being part of `make check`.
They asserted source text, so they passed while real flows broke.

They are replaced by a small behavior suite that runs the real scripts against
stubs and temporary HOME/XDG state:

- package selection builds the exact argv (no xargs) for install and removal
- Firefox profile discovery finds all three layouts and skips cleanly
- Pi-hole TOML merge preserves unknown keys; adlist insert is idempotent
- unbound drop-in is generated, checked with `unbound-checkconf`, and root.hints
  is validated
- ufw rule set contains only the intended ports
- hyprlock/fastfetch templates render with palette colors
- wallpaper `(current)` marker follows state
- Lua add-bind writes `--` and lands among the binds

## Resolved questions

1. Config formatting covers only hand-written configs, not large upstream files.
2. Old tests are disabled and gitignored rather than deleted.
