# Migrations

Each migration upgrades live state once, in numeric order, before the
installer writes configuration files. The applied version lives in
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/version` and the repository
version is `VERSION`.

## Contract

- Standalone bash script named `NNN-short-name.sh`; numbers are zero-padded
  and need not be contiguous (100, 200, 300 leaves room in between).
- The first `# ` line after the shebang is the title the installer prints.
- Start with `set -euo pipefail` and source
  `"$DOTFILES_DIR/lib/common.sh"` for `backup_path` and the log helpers.
- Idempotent: running it twice must change nothing the second time.
- Back up every path it edits with `backup_path` before touching it.
- Never call `sudo`; print the command instead and let the user run it.
- Never run under `--dry-run`: the installer lists titles and executes none.

Environment available to a migration: `DOTFILES_DIR`, `REAL_HOME`,
`STATE_DIR`, `STATE_FILE`, `BACKUP_DIR`, `DRY_RUN`.
