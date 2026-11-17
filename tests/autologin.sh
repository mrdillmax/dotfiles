#!/usr/bin/env bash
# Tests for the getty autologin template and the --autologin-user flag.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

export DOTFILES_DIR="$ROOT"
export DRY_RUN=1
export ASSUME_YES=1

# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/system.sh
source "$ROOT/lib/system.sh"

CONF="$ROOT/system/systemd/getty@tty1.service.d/autologin.conf"

# 1. The tracked template contains a placeholder, never a fixed account.
if grep -q -- '--autologin @USER@' "$CONF" && ! grep -q 'dill' "$CONF"; then
    pass "the autologin drop-in uses @USER@"
else
    fail "the autologin drop-in contains a fixed user or no placeholder"
fi

# 2. Rendering replaces the placeholder and leaves the agetty arguments.
rendered="$(render_system_placeholders "$CONF" "" "testuser")"
if grep -q -- "--autologin testuser %I \$TERM" "$rendered" \
    && ! grep -q '@USER@' "$rendered"; then
    pass "the autologin template renders the requested user"
else
    fail "the autologin template did not render correctly"
    cat "$rendered"
fi
rm -f -- "$rendered"

# 3. --autologin-user wins over the environment.
AUTOLOGIN_USER_ARG="$(id -un)"
SUDO_USER="nobody-else"
resolved="$(resolve_autologin_user)"
if [[ $resolved == "$(id -un)" ]]; then
    pass "--autologin-user takes precedence over SUDO_USER"
else
    fail "--autologin-user was ignored: $resolved"
fi
unset AUTOLOGIN_USER_ARG SUDO_USER

# 4. An invalid name is rejected instead of being written to a unit file.
AUTOLOGIN_USER_ARG='bad user'
if resolve_autologin_user >/dev/null 2>&1; then
    fail "an invalid autologin user was accepted"
else
    pass "an invalid autologin user is rejected"
fi
unset AUTOLOGIN_USER_ARG

# 5. The flag requires --system and is documented in --help.
if ./install.sh --help 2>/dev/null | grep -q -- '--autologin-user'; then
    pass "--autologin-user is listed in --help"
else
    fail "--autologin-user is missing from --help"
fi

if output="$(./install.sh --autologin-user "$(id -un)" --dry-run --all 2>&1)"; then
    fail "--autologin-user without --system was accepted"
else
    if grep -q -- '--autologin-user requires --system' <<<"$output"; then
        pass "--autologin-user without --system is refused"
    else
        fail "the refusal message is missing"
        printf '%s\n' "$output"
    fi
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
