#!/usr/bin/env bash
# Theme state: respects XDG_STATE_HOME, consistent with wallpaper.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

export DOTFILES_DIR="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/theme.sh"

tmp_home="$(mktemp -d)"
tmp_state="$(mktemp -d)"
trap 'rm -rf "$tmp_home" "$tmp_state"' EXIT
mkdir -p "$tmp_state/dotfiles"

# --- F001: theme_source_index must honour XDG_STATE_HOME ---
# Set XDG_STATE_HOME to a *different* path than REAL_HOME/.local/state.
# If theme.sh respects XDG_STATE_HOME it reads from tmp_state;
# if it uses hardcoded REAL_HOME it reads nothing.
export XDG_STATE_HOME="$tmp_state"
export REAL_HOME="$tmp_home"
printf 'source_index=2\n' >"$tmp_state/dotfiles/theme.conf"

result="$(theme_source_index)"
if [[ $result == "2" ]]; then
    pass "theme_source_index respects XDG_STATE_HOME"
else
    fail "theme_source_index ignores XDG_STATE_HOME: got '${result}' (expected 2)"
fi

# Without XDG_STATE_HOME, the fallback should still work via REAL_HOME.
unset XDG_STATE_HOME
# Write to the REAL_HOME fallback path.
mkdir -p "$tmp_home/.local/state/dotfiles"
printf 'source_index=3\n' >"$tmp_home/.local/state/dotfiles/theme.conf"
result="$(theme_source_index)"
if [[ $result == "3" ]]; then
    pass "theme_source_index falls back to REAL_HOME/.local/state"
else
    fail "fallback broken: got '${result}'"
fi

# Invalid value should return nothing.
printf 'source_index=9\n' >"$tmp_home/.local/state/dotfiles/theme.conf"
result="$(theme_source_index)"
if [[ -z $result ]]; then
    pass "rejects invalid source_index"
else
    fail "accepted invalid source_index: ${result}"
fi

# Missing file returns nothing.
rm -f "$tmp_home/.local/state/dotfiles/theme.conf"
result="$(theme_source_index)"
if [[ -z $result ]]; then
    pass "returns nothing when file is missing"
else
    fail "returned value with missing file: ${result}"
fi

# --- theme_source_args passes valid index to matugen ---
export XDG_STATE_HOME="$tmp_state"
printf 'source_index=1\n' >"$tmp_state/dotfiles/theme.conf"
args="$(theme_source_args)"
if [[ $args == *"--source-color-index"*"1"* ]]; then
    pass "theme_source_args includes --source-color-index 1"
else
    fail "theme_source_args wrong: ${args}"
fi

# No index -> prefer saturation (default "auto" path).
rm -f "$tmp_state/dotfiles/theme.conf"
args="$(theme_source_args)"
if [[ $args == *"--prefer"*"saturation"* ]]; then
    pass "theme_source_args falls back to --prefer saturation"
else
    fail "theme_source_args fallback wrong: ${args}"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
