#!/usr/bin/env bash
# Main menu: availability rules, non-interactive safety and flag coverage.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

check_nonempty() {
    local value="$1" message="$2"
    if [[ -n $value ]]; then
        pass "$message"
    else
        fail "$message"
    fi
}

check_empty() {
    local value="$1" message="$2"
    if [[ -z $value ]]; then
        pass "$message"
    else
        fail "$message (got: $value)"
    fi
}

export DOTFILES_DIR="$ROOT"
DRY_RUN=0
ASSUME_YES=0
HAS_ACTION=0
HOST_NAME=desktop
GPU_PROFILE=amd

# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/tui.sh
source "$ROOT/lib/tui.sh"
# shellcheck source=lib/monitors.sh
source "$ROOT/lib/monitors.sh"
# shellcheck source=lib/dock.sh
source "$ROOT/lib/dock.sh"
# shellcheck source=lib/packages.sh
source "$ROOT/lib/packages.sh"
# shellcheck source=lib/system.sh
source "$ROOT/lib/system.sh"
# shellcheck source=lib/cursor.sh
source "$ROOT/lib/cursor.sh"
# shellcheck source=lib/kernel.sh
source "$ROOT/lib/kernel.sh"
# shellcheck source=lib/wallpaper.sh
source "$ROOT/lib/wallpaper.sh"
# shellcheck source=lib/restore.sh
source "$ROOT/lib/restore.sh"
# shellcheck source=lib/theme.sh
source "$ROOT/lib/theme.sh"
# shellcheck source=lib/menu.sh
source "$ROOT/lib/menu.sh"

# 1. Every actionable menu entry has a flag.
missing=()
for menu in $(menu_menu_names); do
    while IFS='|' read -r id _ _; do
        [[ -n $id ]] || continue
        case "$id" in
            menu:*|back|exit) continue ;;
        esac
        [[ -n ${MENU_FLAG[$id]:-} ]] || missing+=("$id")
    done < <(menu_items_for "$menu")
done
if ((${#missing[@]} == 0)); then
    pass "every menu entry maps to a flag"
else
    fail "menu entries without a flag: ${missing[*]}"
fi

# 2. Those flags are all documented.
help_text="$(cd "$ROOT" && ./install.sh --help)"
undocumented=()
for id in "${!MENU_FLAG[@]}"; do
    for flag in ${MENU_FLAG[$id]}; do
        grep -qF -- "$flag" <<<"$help_text" || undocumented+=("$id:$flag")
    done
done
if ((${#undocumented[@]} == 0)); then
    pass "all menu flags are in --help"
else
    fail "undocumented menu flags: ${undocumented[*]}"
fi

# 3. Availability rules follow the detected profile.
MENU_HOST=desktop MENU_GPU=amd
check_empty "$(menu_unavailable_reason idle-status)" "idle is available on a desktop"
check_nonempty "$(menu_unavailable_reason lid-status)" "lid is unavailable on a desktop"
check_nonempty "$(menu_unavailable_reason system-grub)" "GRUB is unavailable without NVIDIA"

MENU_HOST=laptop MENU_GPU=nvidia
check_empty "$(menu_unavailable_reason idle-status)" "idle is available on a laptop"
check_empty "$(menu_unavailable_reason lid-status)" "lid is available on a laptop"
check_empty "$(menu_unavailable_reason system-grub)" "GRUB is available with NVIDIA"

# 4. Unavailable entries are rendered with a reason, available ones do not.
MENU_HOST=desktop
label="$(menu_decorate 'lid-status|Status|show the behaviour')"
if grep -q 'unavailable: laptop host only' <<<"$label"; then
    pass "unavailable entries carry a reason"
else
    fail "unavailable entry lost its reason: $label"
fi

label="$(menu_decorate 'monitors|Monitors|detect the layout')"
if grep -q '^monitors|Monitors|' <<<"$label"; then
    pass "available entries stay unchanged"
else
    fail "available entry was decorated unexpectedly: $label"
fi

# 5. The menu never opens without a terminal.
HAS_ACTION=0 ASSUME_YES=0
if menu_should_run; then
    fail "menu_should_run returned true without a TTY"
else
    pass "menu_should_run is false without a TTY"
fi
HAS_ACTION=1
if menu_should_run; then
    fail "menu_should_run ignored HAS_ACTION"
else
    pass "menu_should_run honours action flags"
fi
HAS_ACTION=0 ASSUME_YES=1
if menu_should_run; then
    fail "menu_should_run ignored --yes"
else
    pass "menu_should_run honours --yes"
fi

# 6. No-argument non-interactive run terminates and does not open the menu.
log="$(mktemp)"
if timeout 90 bash "$ROOT/install.sh" --dry-run </dev/null >"$log" 2>&1; then
    if grep -q 'Main menu' "$log"; then
        fail "non-interactive run opened the menu"
    else
        pass "non-interactive run finishes without the menu"
    fi
else
    rc=$?
    fail "non-interactive run exited with status $rc (timeout is 124)"
fi
rm -f -- "$log"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
