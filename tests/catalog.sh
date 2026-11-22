#!/usr/bin/env bash
# Package catalog defaults. Docker is not supported anymore; fonts are trimmed
# in a later task and checked there.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT/packages/catalog.tsv"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

if awk -F'\t' '$1 ~ /^(docker|docker-compose|lazydocker)$/ {found=1} END{exit !found}' "$CATALOG"; then
    fail "Docker packages are still in the catalog"
else
    pass "Docker packages are gone"
fi

row="$(awk -F'\t' '$1 == "openssh" {print $1"|"$4}' "$CATALOG")"
if [[ $row == 'openssh|no' ]]; then
    pass "openssh is optional"
else
    fail "openssh row is missing or defaulted on: ${row:-none}"
fi

if awk -F'\t' 'BEGIN{ok=1} /^#/ || NF==0 {next} $1=="" || $2=="" || $3=="" || $4=="" {ok=0} END{exit !ok}' "$CATALOG"; then
    pass "every catalog row has all required columns"
else
    fail "catalog has an empty required column"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
