# Migrations

Migrations upgrade live state when the repository version advances. They run
once, in numeric order, before the installer writes configuration files.

## How it works

The installer compares the repository `VERSION` file with the stored version
at `~/.local/state/dotfiles/version`. Any migrations with a number higher
than the stored version are applied, then the stored version is updated.

## Writing a migration

Each migration is a standalone bash script named `NNN-short-name.sh` in this
directory:

```bash
#!/usr/bin/env bash
set -euo pipefail
# Title shown during install
source "$DOTFILES_DIR/lib/common.sh"

# Your migration code here — always idempotent
```

Rules:

- **Idempotent** — running twice must change nothing the second time
- **Back up before editing** — use `backup_path` for every file you modify
- **No sudo** — print commands for the user to run
- **Never runs under `--dry-run`** — the installer lists titles only

Available variables: `DOTFILES_DIR`, `REAL_HOME`, `STATE_DIR`, `STATE_FILE`,
`BACKUP_DIR`.

## Current migrations

(See file names: `NNN-short-name.sh` — the number is the trigger version.)
