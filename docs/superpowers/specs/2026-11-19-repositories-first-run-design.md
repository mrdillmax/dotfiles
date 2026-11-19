# Repositories before the first package install

Date: 2026-11-19

## Intent

On a fresh VM the guided setup installs packages before `/etc/pacman.conf`
has `[multilib]`. Every `lib32-*` package then fails with `target not found`,
and the package database is stale, so the user has to stop, enable multilib,
run `pacman -Syu`, and start again. The installer already knows how to merge
`[multilib]` into `pacman.conf`, but only the separate `--system` step calls
it.

This change makes the first run prepare the repositories before it installs
anything.

## Approved decisions

- Only the guided `--setup` flow gets the new stage. A normal
  `1. Packages` run keeps its current behaviour.
- The stage runs only when `[multilib]` is missing. If it is already enabled,
  nothing happens: no prompt, no full upgrade.
- Enabling `[multilib]` reuses `merge_pacman_conf`: diff, backup, per-file
  confirmation.
- After the merge the database is refreshed with `pacman -Syu`, not `-Sy`.
  `-Sy` alone is a partial upgrade and is exactly what breaks a system.
- The stage needs root and runs as `sudo install.sh --repositories`, the same
  way the `--system` stage does.
- `--dry-run` prints the proposal and the planned command, and never calls
  `sudo` or touches `/etc`.
- The numbered menu stays 1–4. The new entry is an unnumbered precondition
  shown only when it will do something.

## Goals

- `--setup` on a machine without `[multilib]` enables it and refreshes the
  database before the packages step.
- `--repositories` works on its own and has a clear failure when run without
  root.
- `multilib_enabled` reads a given `pacman.conf` so it can be tested without
  `/etc`.

## Non-goals

- No automatic upgrade during `1. Packages` or `--only-packages`.
- No mirror list change; the Control Center already refreshes mirrors.
- No retry of a failed `pacman -Syu` and no keyring handling.

## Behaviour

```
First-time setup
  Repositories — enable [multilib] and refresh the package database? (sudo)
  Step 1/4 packages ...
```

When `[multilib]` is already enabled:

```
:: multilib is already enabled; nothing to do
```

and the next prompt is `Step 1/4`.

## Files

- `lib/system.sh`: `multilib_enabled [conf]`.
- `install.sh`: `prepare_repositories`, `--repositories`, root guard, setup
  stage, help text.
- `tests/repositories.sh`: detection, dry-run, root guard, setup order.
- `README.md`, `README.uk.md`: first-run order and the new flag.
