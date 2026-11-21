# Dotfiles consistency pass — design addendum

Date: 2026-11-21
Status: awaiting approval
Extends: `2026-11-20-dotfiles-reliability-design.md`

## Intent

The repo works, but it is not readable as one project: helper scripts live in
three different places, module metadata is written ad hoc, configs have no
shared shape, and the installer still pulls fonts nobody uses. The machine also
never tells the user that the repository moved ahead on GitHub, and the fish
autologin in the repo is outdated compared to the live one.

## Decisions

### One place for executables

Every executable helper moves to `~/.local/bin`; `~/.config` keeps only
declarative configuration. References are updated in the same change.

| From | To |
|------|----|
| `modules/rofi/home/.config/rofi/scripts/powermenu.sh` | `modules/rofi/home/.local/bin/powermenu.sh` |
| `modules/rofi/home/.config/rofi/scripts/rofi-dunst-history.sh` | `modules/rofi/home/.local/bin/dunst-history.sh` |
| `modules/waybar/home/.config/waybar/scripts/dunst.sh` | `modules/waybar/home/.local/bin/waybar-dunst.sh` |
| `modules/workspaces-split/home/.config/hypr/switch_ws.sh` | `modules/workspaces-split/home/.local/bin/switch-workspace.sh` |

`powermenu.sh` keeps its name because docs and the Control Center already use
it. The other two names say what they are and where they belong.

References to update: `hyprland.lua` (`powermenu`, `history`, `switch_ws`),
Waybar `config.jsonc` (`exec`), Control Center `power_page` fallback.

### Module shape

Each module stays `module.conf` + `home/`. `module.conf` always lists keys in
this order: `DESCRIPTION`, `PACKAGES`, `SERVICES`, `REQUIRES`. Empty arrays stay
explicit. No per-module README: a generated table in `docs/modules.md` lists
module, purpose, packages and binaries, so the documentation cannot drift from
the files.

### Config style

- First line: `# <Name> — <one-line purpose>`, then a blank line.
- Sections: `# --- <section> ---------------------------------------------`.
- Comments in English; one line, practical, why over what.
- Scripts: shebang, purpose line, `Usage:` when they take arguments.
- File names in kebab-case.
- Trailing whitespace and missing final newline are errors.
- Values the user owns (Waybar spacing, the clipboard bind) are not reformatted.

`tests/style.sh` enforces headers, trailing whitespace, final newline, kebab-case
script names, and that no script lives under `home/.config`.

### Visual language

The palette already comes from matugen. This pass aligns what the palette does
not: one radius scale (8 px small, 12 px cards, 16 px windows), one spacing step
(8 px), Inter for UI, JetBrains Mono Nerd for mono, and the same muted border
colour across rofi, Waybar, dunst, hyprlock and fastfetch. hyprlock and fastfetch
become matugen templates in the main plan (Task 7).

### Fish

Adopt the live autologin:

```fish
if uwsm check may-start; and string match -q '/dev/tty1' (tty)
```

Keep `fish_add_path $HOME/.local/bin`, because that is now the only place for
helpers. Header comment stays (the live copy lost it). Anchor the autologin to
the same block that already runs `fastfetch` at login.

### GitHub update check

New helper `dotfiles-update-check.sh` in `~/.local/bin`:

- Reads the repository path from the installed symlink.
- Asks the public GitHub API for the latest commit on the default branch with
  `ETag` caching, then compares with the local `HEAD`.
- Uses the compare endpoint for the exact "N commits behind" count.
- Caches the answer in `~/.cache/dotfiles/update-check` for 6 hours; `--refresh`
  ignores the cache.
- Prints one of: `up to date`, `N commits behind`, `3 commits ahead`,
  `cannot check (offline)`.
- Never fetches, never touches the working tree.

The Control Center update page gets this as its first row, e.g.
`dotfiles: 4 commits behind`; selecting it refreshes the check. The existing
"Pull repo and apply" stays the action.

### Fonts

Keep what the system actually uses:

`inter-font`, `ttf-jetbrains-mono-nerd`, `noto-fonts-emoji`, `ttf-ms-fonts`
(Firefox/Steam/Zoom), `ttf-liberation` (Arial/Times/Courier metrics),
`ttf-dejavu` (universal fallback), `ttf-roboto` (web UI), `terminus-font`
(console), `hunspell-uk`, `hyphen-uk`.

Move to opt-in (`default=no`): `gnu-free-fonts`, `ttf-croscore`,
`adwaita-fonts`, `woff2-font-awesome`.

`noto-fonts-cjk` is 299 MiB. Default `yes` if CJK pages must render without
tofu; otherwise `no` and the user opts in.

No other package changes in this pass.

## Non-goals

- No package removals on the live machine; catalog defaults only.
- No rewrite of large upstream files (`kitty.conf`, stock `unbound.conf`).
- No Waybar spacing changes.

## Verification

- `tests/style.sh` fails on a script under `.config`, a missing header, a
  trailing space, or a snake_case script name.
- `tests/update-check.sh` stubs `curl` and proves: cached answer is reused,
  `--refresh` bypasses it, offline prints `cannot check`, behind-count parses.
- `bash -n` + `shellcheck` for every moved script.
- Waybar/rofi/hypr configs parse after reference updates (`waybar` on a live
  session is the real check; otherwise `jq` on the JSONC after stripping
  comments).
