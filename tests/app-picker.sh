#!/usr/bin/env bash
# Application picker: labels, symbols, installed marks and package collection.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

check_prefix() {
    local expected="$1" actual="$2" message="$3"
    if [[ $actual == "$expected"* ]]; then
        pass "$message"
    else
        fail "$message (got: $actual)"
    fi
}

check_contains() {
    local needle="$1" actual="$2" message="$3"
    if [[ $actual == *"$needle"* ]]; then
        pass "$message"
    else
        fail "$message (got: $actual)"
    fi
}

export DOTFILES_DIR="$ROOT"
export DRY_RUN=1
export ASSUME_YES=0
export ALL=0
export GROUPS_ARG=""
export APPS_ARG=""
export PACKAGES_ARG=""
SELECTED_CATEGORIES=()
SELECTED_APPLICATIONS=()

# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/tui.sh
source "$ROOT/lib/tui.sh"
# shellcheck source=lib/packages.sh
source "$ROOT/lib/packages.sh"

# Deterministic "installed" database.
# shellcheck disable=SC2032 # test stub; never invoked through sudo here
pacman() {
    case "$1" in
        -Qq) printf 'kitty\nfoot\n' ;;
        *) return 1 ;;
    esac
}
export DOTFILES_PLAIN=1

# 1. ASCII fallback symbols.
export DOTFILES_ASCII=1
main_label="$(app_label main kitty 0)"
alt_label="$(app_label alt foot 0)"
installed_label="$(app_label main kitty 1)"
check_prefix "[*] kitty" "$main_label" "ASCII main label uses [*]"
check_prefix "[ ] foot" "$alt_label" "ASCII alternative label uses [ ]"
check_contains "[i]" "$installed_label" "ASCII installed mark uses [i]"

# 2. Unicode symbols when the locale is UTF-8.
export DOTFILES_ASCII=0
locale() { printf 'UTF-8\n'; }
main_label="$(app_label main kitty 0)"
alt_label="$(app_label alt foot 0)"
installed_label="$(app_label main kitty 1)"
check_prefix "★ kitty" "$main_label" "Unicode main label uses a star"
check_prefix "○ foot" "$alt_label" "Unicode alternative label uses a circle"
check_contains "✓" "$installed_label" "Unicode installed mark uses a check"

# 3. Legend explains all three marks.
export DOTFILES_ASCII=1
legend="$(tui_legend)"
check_contains "[*] main" "$legend" "ASCII legend names the main mark"
check_contains "[ ] alternative" "$legend" "ASCII legend names the alternative mark"
check_contains "[i] installed" "$legend" "ASCII legend names the installed mark"

# 4. Human-readable category names.
check_prefix "Terminal" "$(app_category_label terminal)" "terminal category has a label"
check_prefix "File manager" "$(app_category_label file-manager)" "file manager category has a label"

# 5. The main application is listed first in every category.
first_ok=1
for category in "${APP_CATEGORY_ORDER[@]}"; do
    first_role="$(awk -F'\t' -v c="$category" '$1 !~ /^#/ && $2 == c { print $3; exit }' "$APP_REGISTRY")"
    if [[ $first_role != main ]]; then
        first_ok=0
        printf '  %s starts with role=%s\n' "$category" "$first_role"
    fi
done
if ((first_ok)); then
    pass "every category starts with its main application"
else
    fail "a category does not start with its main application"
fi

# 6. The kernel pseudo-category is not part of the picker.
kernel_in_picker=0
for category in "${APP_CATEGORY_ORDER[@]}"; do
    [[ $category == kernel ]] && kernel_in_picker=1
done
if ((kernel_in_picker == 0)); then
    pass "kernel packages stay out of the app picker"
else
    fail "kernel is offered as an application category"
fi

# 7. --groups selects package groups without prompting.
export GROUPS_ARG=base,desktop
SELECTED_CATEGORIES=()
select_categories
if [[ ${SELECTED_CATEGORIES[*]} == 'base.txt desktop.txt' ]]; then
    pass "--groups selects base and desktop"
else
    fail "--groups produced: ${SELECTED_CATEGORIES[*]}"
fi

# 8. Unknown groups fail loudly.
export GROUPS_ARG=does-not-exist
if (select_categories) >/dev/null 2>&1; then
    fail "an unknown group was accepted"
else
    pass "an unknown group is rejected"
fi
export GROUPS_ARG=""

# 9. --apps fills the selection without prompting.
export APPS_ARG=foot,alacritty
SELECTED_APPLICATIONS=()
select_apps
if [[ ${SELECTED_APPLICATIONS[*]} == 'foot alacritty' ]]; then
    pass "--apps selects the listed packages"
else
    fail "--apps produced: ${SELECTED_APPLICATIONS[*]}"
fi
export APPS_ARG=""

# 10. Non-interactive runs never block on the picker.
# shellcheck disable=SC2016 # $0 is the repository path passed to bash -c
if timeout 15 bash -c 'source "$0/lib/common.sh"; source "$0/lib/tui.sh"; source "$0/lib/packages.sh"; select_apps' "$ROOT" </dev/null; then
    pass "the picker returns immediately without a TTY"
else
    fail "the picker failed or hung without a TTY"
fi

# 11. Duplicate apps are installed once.
SELECTED_CATEGORIES=(base.txt)
SELECTED_APPLICATIONS=(foot foot kitty)
packages="$(collect_packages)"
if [[ $(grep -cx 'foot' <<<"$packages") == 1 ]]; then
    pass "duplicate packages are deduplicated"
else
    fail "packages were not deduplicated"
fi
if grep -qx 'kitty' <<<"$packages"; then
    pass "main applications stay in the install list"
else
    fail "main application missing from the install list"
fi

# 12. --packages is an exact list and skips both pickers.
export PACKAGES_ARG=foot,kitty
SELECTED_CATEGORIES=(base.txt)
SELECTED_APPLICATIONS=()
select_categories
select_apps
if [[ ${#SELECTED_CATEGORIES[@]} -eq 0 && ${SELECTED_APPLICATIONS[*]} == 'foot kitty' ]]; then
    pass "--packages installs exactly the listed packages"
else
    fail "--packages produced categories=${SELECTED_CATEGORIES[*]} apps=${SELECTED_APPLICATIONS[*]}"
fi
export PACKAGES_ARG=""

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
