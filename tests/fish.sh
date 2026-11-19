#!/usr/bin/env bash
# First-run session: cargo guard, fish login shell and Tide.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# 1. The cargo environment is sourced only when rustup created it.
conf="$ROOT/modules/fish/home/.config/fish/conf.d/rustup.fish"
if grep -Eq '^source .*\.cargo/env\.fish' "$conf"; then
    fail "rustup.fish sources .cargo/env.fish unconditionally"
else
    pass "the cargo environment is guarded"
fi
if grep -q 'test -f' "$conf"; then
    pass "the cargo guard checks the file"
else
    fail "the cargo guard does not check the file"
fi

# 2. The installer prepares the shell and the plugins.
if grep -q '^set_login_shell_fish()' "$ROOT/lib/system.sh" \
    && grep -q 'set_login_shell_fish || true' "$ROOT/lib/system.sh"; then
    pass "the system step changes the login shell"
else
    fail "the login shell is never changed"
fi
if grep -q 'fisher update' "$ROOT/install.sh"; then
    pass "the configuration step installs Tide through fisher"
else
    fail "Tide is never installed"
fi

# 3. An already-fish account is left alone.
out="$(DOTFILES_DIR="$ROOT" bash -c '
    set -uo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/system.sh"
    getent() { printf "dill:x:1000:1000::/home/dill:/usr/bin/fish\n"; }
    chsh() { printf "chsh called\n"; }
    command() { if [[ $1 == -v && $2 == fish ]]; then printf "/usr/bin/fish\n"; else builtin command "$@"; fi; }
    ASSUME_YES=1
    DRY_RUN=0
    set_login_shell_fish dill
' 2>&1)"
rc=$?
if [[ $rc -eq 0 && $out != *'chsh called'* ]]; then
    pass "fish is not re-applied when it is already the login shell"
else
    fail "an existing fish login shell is changed again (rc $rc)"
fi

# 4. The Tide prompt configuration ships with the module and parses.
tide="$ROOT/modules/fish/home/.config/fish/conf.d/0-tide.fish"
if [[ -f $tide ]] && fish -n "$tide"; then
    pass "the Tide prompt configuration is present and valid"
else
    fail "the Tide prompt configuration is missing or invalid"
fi
if grep -q '^set -U tide_left_prompt_items ' "$tide"; then
    pass "the Tide prompt items are configured"
else
    fail "the Tide prompt items are not configured"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
