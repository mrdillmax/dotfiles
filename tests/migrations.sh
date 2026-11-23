#!/usr/bin/env bash
# Migrations: gaps only, ordered, dry-run safe, failure keeps the old version.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export DOTFILES_DIR="$ROOT"
STATE_DIR="$work/state"
STATE_FILE="$STATE_DIR/managed.tsv"
BACKUP_DIR="$work/backup"
MIGRATIONS_DIR="$work/migrations"
mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$MIGRATIONS_DIR"
printf 'target\tbackup\n' >"$BACKUP_DIR/manifest.tsv"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/migrate.sh"

printf '2\n' >"$work/repo-version"
repo_file="$work/repo-version"

cat >"$MIGRATIONS_DIR/0001-one.sh" <<'EOF'
#!/usr/bin/env bash
# first migration
set -euo pipefail
printf 'one\n' >>"$MIGRATION_LOG"
EOF
cat >"$MIGRATIONS_DIR/0002-two.sh" <<'EOF'
#!/usr/bin/env bash
# second migration
set -euo pipefail
printf 'two\n' >>"$MIGRATION_LOG"
if [ "${FAIL_AT:-}" = two ]; then exit 1; fi
EOF
chmod +x "$MIGRATIONS_DIR"/*.sh

export MIGRATION_LOG="$work/log"

# A tiny env override for the fixture version file.
repo_version() { tr -d '[:space:]' <"$repo_file"; }

: >"$MIGRATION_LOG"
( ASSUME_YES=1 run_migrations ) >/dev/null 2>&1
if [[ $(tr -d '[:space:]' <"$STATE_DIR/version" 2>/dev/null) == 2 && ! -s $MIGRATION_LOG ]]; then
    pass "a fresh clone stamps the current version and runs nothing"
else
    fail "fresh clone: $(cat "$STATE_DIR/version" 2>/dev/null) / $(cat "$MIGRATION_LOG" 2>/dev/null)"
fi

printf 'kind\tpath\tsource\n' >"$STATE_FILE"
rm -f "$STATE_DIR/version"
: >"$MIGRATION_LOG"
( ASSUME_YES=1 run_migrations ) >/dev/null 2>&1
if [[ $(tr -d '[:space:]' <"$STATE_DIR/version") == 2 && $(cat "$MIGRATION_LOG") == $'one\ntwo' ]]; then
    pass "pre-framework state runs every migration in order"
else
    fail "order/version: $(cat "$MIGRATION_LOG" 2>/dev/null) / $(cat "$STATE_DIR/version" 2>/dev/null)"
fi

printf '1\n' >"$STATE_DIR/version"
: >"$MIGRATION_LOG"
( ASSUME_YES=1 run_migrations ) >/dev/null 2>&1
if [[ $(cat "$MIGRATION_LOG") == two ]]; then
    pass "only the missing gap runs"
else
    fail "gap log: $(cat "$MIGRATION_LOG")"
fi

: >"$MIGRATION_LOG"
printf '0\n' >"$STATE_DIR/version"
out="$( ( DRY_RUN=1 run_migrations ) 2>&1 )"
if [[ $out == *"0001"* && ! -s $MIGRATION_LOG ]]; then
    pass "dry-run lists migrations and runs none"
else
    fail "dry-run output: $out"
fi

printf '0\n' >"$STATE_DIR/version"
if ( FAIL_AT=two ASSUME_YES=1 run_migrations ) >/dev/null 2>&1; then
    fail "a failing migration reported success"
else
    pass "a failing migration fails the run"
fi
if [[ $(tr -d '[:space:]' <"$STATE_DIR/version") == 0 ]]; then
    pass "a failed run keeps the old version"
else
    fail "version advanced after failure: $(cat "$STATE_DIR/version")"
fi

printf '9\n' >"$STATE_DIR/version"
out="$( ( ASSUME_YES=1 run_migrations ) 2>&1 )"
if [[ $out == *"newer"* && $(tr -d '[:space:]' <"$STATE_DIR/version") == 9 ]]; then
    pass "a newer stored version warns and is left alone"
else
    fail "downgrade output: $out"
fi

# The real 0001 upgrades three columns, idempotently.
printf 'link\t/home/x/.config/a\t/repo/a\n' >"$STATE_FILE"
chmod 0640 "$STATE_FILE"
export REAL_HOME="$work/home"
mkdir -p "$REAL_HOME"
env DOTFILES_DIR="$ROOT" REAL_HOME="$REAL_HOME" STATE_DIR="$STATE_DIR" \
    STATE_FILE="$STATE_FILE" BACKUP_DIR="$BACKUP_DIR" \
    bash "$ROOT/migrations/0001-managed-tsv-v2.sh"
if [[ $(awk -F'\t' 'NR==1{print NF}' "$STATE_FILE") == 5 ]]; then
    pass "0001 upgrades a three-column manifest"
else
    fail "0001 columns: $(head -n1 "$STATE_FILE")"
fi
before="$(sha256sum "$STATE_FILE" | cut -d' ' -f1)"
env DOTFILES_DIR="$ROOT" REAL_HOME="$REAL_HOME" STATE_DIR="$STATE_DIR" \
    STATE_FILE="$STATE_FILE" BACKUP_DIR="$BACKUP_DIR" \
    bash "$ROOT/migrations/0001-managed-tsv-v2.sh"
if [[ $(stat -c %a "$STATE_FILE") == 640 ]]; then
    pass "0001 keeps the manifest mode"
else
    fail "0001 mode: $(stat -c %a "$STATE_FILE")"
fi
if [[ $(sha256sum "$STATE_FILE" | cut -d' ' -f1) == "$before" ]]; then
    pass "0001 is idempotent"
else
    fail "0001 changed an already-upgraded manifest"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
