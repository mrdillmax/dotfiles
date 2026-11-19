# First-run session, services, theme and control-center fixes

Date: 2026-11-19

## Intent

A fresh install logs in through getty into bash, never starts Hyprland, leaves
fish without its prompt and with a broken `.cargo` source, enables services
without starting them, prints "run this manually" for cpupower/grub/mkinitcpio,
never generates matugen colours, renders control-center rows white, keeps a
terminal open after every action, hides Spicetify update in the wrong page as
three entries, and cannot add autostart programs. Cursor and wallpaper are not
in the repository.

This change makes the installed system usable immediately after the first run
and moves daily actions to the Control Center.

## Approved decisions

- Execute every possible follow-up during the system step (daemon-reload,
  zram, cpupower, services, `grub-mkconfig`, `mkinitcpio -P`, DNS restarts)
  when the matching component ran; warn instead of printing "do it yourself".
- Make fish the login shell with `chsh -s /usr/bin/fish <user>` during the
  system step, with confirmation. Hyprland then starts from `config.fish`.
- Install Tide during the configuration step with `fish -c 'fisher update'`;
  a failure warns and does not abort setup.
- Source `~/.cargo/env.fish` only when it exists.
- Regenerate matugen on install and on every wallpaper/mode/type change.
- Rofi rows use an explicit `@surface` background, never `transparent`.
- A terminal opened by the Control Center waits for one key press, then closes.
- Spicetify update is one button in the updates page: `spicetify backup apply`.
  The Music page is removed.
- Control Center pages lose `Back`; the main menu loses `Close`; Esc closes.
- Autostart gains "Add a program" with name and command prompts.
- Cursor theme `win11_concept_cursos` and wallpaper `example.jpg` live in the
  repository under `assets/`; the wallpaper is installed as
  `~/.local/share/wallpapers/dotfiles/example.jpg` and seeds matugen.
- Kitty is written into `kdeglobals` as `TerminalApplication`/`TerminalService`
  when selected; otherwise the first installed of foot, ghostty, alacritty,
  wezterm.
- Hyprlock shows `$USER`; `$HOST` is not a hyprlock variable.

## Non-goals

- No marketplace install for Spicetify before Spotify is launched.
- No wallpaper picker changes beyond the default asset.
- No new menu entries for services.

## Constraints

- Repo changes are delivered by `install.sh`; live files change only through
  it. `--dry-run` prints and changes nothing.
- System actions need root and stay behind `--system` with confirmation.
- Assets are public: cursor theme and wallpaper are redistributable.

## Files

- `modules/fish/.../rustup.fish`, `install.sh`: shell and Tide.
- `lib/system.sh`: services, chsh, follow-up actions.
- `system/services/services.conf`: selected-by-default policy unchanged; the
  installer starts what is selected.
- `lib/theme.sh`, `install.sh`, `modules/theme-menu/...`: matugen and default
  wallpaper.
- `modules/control-center/...`, `modules/apps`/control-center rasi.
- `modules/autostart/home/.local/bin/autostart.sh`.
- `modules/idle/home/.config/hypr/hyprlock.conf`.
- `modules/theming/home/.config/kdeglobals.in`, `install.sh`.
- `lib/cursor.sh`, `assets/cursors/`, `assets/wallpapers/`.
