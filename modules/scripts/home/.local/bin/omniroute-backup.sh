#!/usr/bin/env bash
# Daily consistent snapshot of OmniRoute's SQLite DB.
# Independent of the in-app scheduler: works even if the app is idle.
set -euo pipefail
umask 077

DB="$HOME/.config/omniroute/storage.sqlite"
DIR="$HOME/.config/omniroute/db_backups"
KEEP=7

[ -f "$DB" ] || { echo "no db at $DB" >&2; exit 0; }
mkdir -p "$DIR"

TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$DIR/cron_${TS}.sqlite"

# .backup is safe on a live WAL database (consistent snapshot).
sqlite3 "file:${DB}?mode=ro" ".backup '${OUT}'"

# Fail loudly if the snapshot is not readable.
sqlite3 "$OUT" "PRAGMA quick_check;" >/dev/null

# Rotation for our own files only (never touches the app's db_*.sqlite).
mapfile -t OLD < <(find "$DIR" -maxdepth 1 -type f -name 'cron_*.sqlite' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | tail -n +$((KEEP + 1)) | cut -f2-)
for f in "${OLD[@]:-}"; do
  [ -n "$f" ] && rm -f -- "$f"
done

echo "ok $(basename "$OUT") $(du -h "$OUT" | cut -f1)"
