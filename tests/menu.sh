#!/usr/bin/env bash
# Menu entries map to a real action and keep --verbose for the child install.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat >"$work/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$ARGS_FILE"
EOF
chmod +x "$work/install.sh"

export DOTFILES_DIR="$work"
export ARGS_FILE="$work/args"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/menu.sh"

VERBOSE=0 DRY_RUN=0
out="$(menu_action uninstall 2>&1)"
if [[ -f $ARGS_FILE ]] && grep -qx -- '--uninstall' "$ARGS_FILE" &&
    [[ $out != *"no action"* ]]; then
    pass "the Uninstall item runs --uninstall"
else
    fail "uninstall menu action: ${out} / $(cat "$ARGS_FILE" 2>/dev/null)"
fi

export VERBOSE=1 DRY_RUN=0
out="$(menu_action doctor 2>&1)"
if grep -qx -- '--doctor --verbose' "$ARGS_FILE"; then
    pass "the menu forwards --verbose to the action"
else
    fail "verbose forwarding: $(cat "$ARGS_FILE" 2>/dev/null)"
fi

# Removing selected modules is its own menu entry, not the full uninstall.
if menu_items_for maintenance | grep -q '^remove-modules|'; then
    pass "the maintenance menu offers module removal"
else
    fail "the maintenance menu has no module removal entry"
fi

mkdir -p "$work/state/dotfiles"
printf 'link\t/home/x/.config/a\t%s/modules/demo/home/.config/a\t-\t-\n' "$work" \
    >"$work/state/dotfiles/managed.tsv"
(
    export XDG_STATE_HOME="$work/state"
    capture="$work/remove-args"
    # shellcheck disable=SC2329
    tui_checklist() { TUI_SELECTION=("demo"); }
    # shellcheck disable=SC2329
    tui_confirm() { return 0; }
    # shellcheck disable=SC2329
    menu_run() { printf '%s\n' "$*" >"$capture"; }
    menu_action_remove_modules
)
if [[ $(cat "$work/remove-args" 2>/dev/null) == "--uninstall --modules demo --remove-packages" ]]; then
    pass "module removal passes the selection and the package flag"
else
    fail "module removal command: $(cat "$work/remove-args" 2>/dev/null)"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
