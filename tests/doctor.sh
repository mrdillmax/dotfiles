#!/usr/bin/env bash
# Tests for scripts/doctor.sh. Plain bash; no bats dependency.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/scripts/doctor.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

json_ok() {
    local data
    data="$(cat)"
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$data" | jq -e . >/dev/null 2>&1
    else
        printf '%s\n' "$data" | grep -q '"checks"' \
            && printf '%s\n' "$data" | grep -q '"summary"'
    fi
}

# 1. JSON output is valid and contains checks.
out="$("$DOCTOR" --json)"
rc=$?
if ((rc == 0 || rc == 1)); then
    pass "exit code is 0 or 1 ($rc)"
else
    fail "unexpected exit code: $rc"
fi

if printf '%s\n' "$out" | json_ok; then
    pass "doctor --json emits valid JSON"
else
    fail "doctor --json is not valid JSON"
fi

if printf '%s\n' "$out" | grep -q '"checks":\['; then
    pass "JSON contains a checks array"
else
    fail "JSON has no checks array"
fi

if printf '%s\n' "$out" | grep -q $'\033'; then
    fail "JSON output contains ANSI escapes"
else
    pass "JSON output has no ANSI escapes"
fi

# 2. Every level is one of the four documented values.
if command -v jq >/dev/null 2>&1; then
    bad_levels="$(printf '%s\n' "$out" | jq -r '.checks[].level' | grep -Ev '^(OK|WARN|FAIL|SKIPPED)$' || true)"
    if [[ -z $bad_levels ]]; then
        pass "levels are OK/WARN/FAIL/SKIPPED only"
    else
        fail "unexpected levels: $bad_levels"
    fi

    summary_fail="$(printf '%s\n' "$out" | jq -r '.summary.fail')"
    expected=0
    ((summary_fail > 0)) && expected=1
    if ((rc == expected)); then
        pass "exit code matches summary.fail ($summary_fail)"
    else
        fail "exit code $rc does not match summary.fail $summary_fail"
    fi
else
    printf 'SKIP jq is not installed; level/exit consistency checks skipped\n'
fi

# 3. Unknown options are rejected.
if "$DOCTOR" --definitely-not-an-option >/dev/null 2>&1; then
    fail "unknown option was accepted"
else
    pass "unknown option is rejected"
fi

# 4. --help works.
if "$DOCTOR" --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help failed"
fi

# 5. The installer exposes the same entry point.
if "$ROOT/install.sh" --doctor --json 2>/dev/null | json_ok; then
    pass "install.sh --doctor --json works"
else
    fail "install.sh --doctor --json failed"
fi

# 6. --json without --doctor is rejected by the installer.
if "$ROOT/install.sh" --json >/dev/null 2>&1; then
    fail "install.sh accepted --json without --doctor"
else
    pass "install.sh rejects --json without --doctor"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
