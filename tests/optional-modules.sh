#!/usr/bin/env bash
# Optional modules stay out of --all and are marked in the generated docs.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

for module in ram-cache workspaces-split; do
    if grep -qx 'OPTIONAL=1' "$ROOT/modules/$module/module.conf"; then
        pass "$module is marked optional in module.conf"
    else
        fail "$module/module.conf has no OPTIONAL=1"
    fi
done

if grep -Eq '\| .*ram-cache.* \| .*\(optional\)' "$ROOT/docs/modules.md" &&
    grep -Eq '\| .*workspaces-split.* \| .*\(optional\)' "$ROOT/docs/modules.md"; then
    pass "the generated module table marks optional modules"
else
    fail "docs/modules.md does not mark optional modules"
fi

if "$ROOT/scripts/modules-doc.sh" --check >/dev/null 2>&1; then
    pass "docs/modules.md is current"
else
    fail "docs/modules.md is stale"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
