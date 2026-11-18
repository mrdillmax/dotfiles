#!/usr/bin/env bash
# Every flag accepted by install.sh must be documented in --help.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# Source of truth: the option parser, not the help text.
parser="$(awk '/^while \(\(\$#\)\); do$/{found=1} found{print} found && /^done$/{exit}' "$ROOT/install.sh")"
flags="$(grep -oE -- '--[a-z][a-z0-9-]*' <<<"$parser" | sort -u)"
help="$(cd "$ROOT" && ./install.sh --help)"

if [[ -z $parser ]]; then
    fail "could not find the option parser in install.sh"
else
    pass "option parser found"
fi

for flag in $flags; do
    if grep -qF -- "$flag" <<<"$help"; then
        pass "--help documents $flag"
    else
        fail "--help is missing $flag"
    fi
done

# The help must stay grouped like the menu.
for heading in 'Installation:' 'Settings:' 'System' 'Kernel:' 'Maintenance:' 'Other:'; do
    if grep -qF -- "$heading" <<<"$help"; then
        pass "--help has the '$heading' group"
    else
        fail "--help is missing the '$heading' group"
    fi
done

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
