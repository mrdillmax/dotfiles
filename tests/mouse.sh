#!/usr/bin/env bash
# Tests for the mouse tuner's numeric formatting. Only the function prelude is
# sourced; the interactive main section is never executed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/mouse-sensitivity/home/.local/bin/mouse-tune.sh"
PASS=0
FAIL=0
TMP_DIRS=()

cleanup() {
    local d
    for d in "${TMP_DIRS[@]}"; do
        rm -rf -- "$d"
    done
}
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# The prelude ends at the main section marker. Sourcing it defines the helpers
# and parses no arguments.
prelude="$(mktemp)"
TMP_DIRS+=("$prelude")
sed -n '1,/ main --$/p' "$SCRIPT" >"$prelude"

# 1. The script pins the numeric locale before any number is formatted.
if grep -qx 'export LC_NUMERIC=C' "$SCRIPT"; then
    pass "the script pins LC_NUMERIC=C"
else
    fail "the script does not pin LC_NUMERIC=C"
fi

# Pick an installed locale with a comma decimal separator.
comma_locale=""
for candidate in uk_UA.UTF-8 uk_UA.utf8 de_DE.UTF-8 de_DE.utf8 fr_FR.UTF-8 fr_FR.utf8; do
    if locale -a 2>/dev/null | grep -qx "$candidate"; then
        comma_locale="$candidate"
        break
    fi
done

if [[ -n $comma_locale ]]; then
    # 2. Sanity check: this locale really does reject the old formatting.
    if env LC_NUMERIC="$comma_locale" bash -c "printf '% .2f' -0.30" >/dev/null 2>&1; then
        fail "the comma locale did not reproduce the old printf failure"
    else
        pass "a comma locale rejects the old printf conversion"
    fi

    # 3. format_value still prints a dot, as Lua requires.
    rendered="$(env LC_NUMERIC="$comma_locale" PRELUDE="$prelude" \
        bash -c "source \"\$PRELUDE\"; format_value -0.30" 2>&1)"
    if [[ $rendered == "-0.30" ]]; then
        pass "a negative sensitivity renders with a dot"
    else
        fail "a negative sensitivity rendered as: $rendered"
    fi

    # 4. Positive values keep the leading space for the sign.
    rendered="$(env LC_NUMERIC="$comma_locale" PRELUDE="$prelude" \
        bash -c "source \"\$PRELUDE\"; format_value 0.2" 2>&1)"
    if [[ $rendered == " 0.20" ]]; then
        pass "a positive value keeps the sign column"
    else
        fail "a positive value rendered as: $rendered"
    fi

    # 5. The live slider itself renders a negative value without an error.
    # shellcheck disable=SC2016  # the snippet is evaluated by the inner bash
    rendered="$(env LC_NUMERIC="$comma_locale" PRELUDE="$prelude" \
        bash -c 'source "$PRELUDE"; apply_input_field() { :; }; v=-0.30; live_adjust sensitivity v sensitivity -1 1 0.05 0.01 0' \
        </dev/null 2>&1)"
    if [[ $rendered == *"sensitivity: -0.30"* && $rendered != *"invalid number"* ]]; then
        pass "the live slider renders a negative value"
    else
        fail "the live slider failed: $rendered"
    fi
else
    printf 'note: no comma-decimal locale installed; locale checks skipped\n'
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
