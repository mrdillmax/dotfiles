#!/usr/bin/env bash
# Package catalog: category labels, symbols, defaults and exact selections.
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
export CATEGORY_ARG=""
export APPS_ARG=""
export PACKAGES_ARG=""
export HOST_NAME=desktop
export GPU_PROFILE=nvidia
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
main_label="$(app_label main kitty 0 'terminal')"
alt_label="$(app_label alt foot 0 'terminal')"
pkg_label="$(app_label pkg btop 0 'monitor')"
installed_label="$(app_label main kitty 1 'terminal')"
check_prefix "[*] kitty" "$main_label" "ASCII main label uses [*]"
check_prefix "[ ] foot" "$alt_label" "ASCII alternative label uses [ ]"
check_prefix "[p] btop" "$pkg_label" "ASCII package label uses [p]"
check_contains "[i]" "$installed_label" "ASCII installed mark uses [i]"

# 2. Unicode symbols when the locale is UTF-8.
export DOTFILES_ASCII=0
locale() { printf 'UTF-8\n'; }
main_label="$(app_label main kitty 0 'terminal')"
alt_label="$(app_label alt foot 0 'terminal')"
pkg_label="$(app_label pkg btop 0 'monitor')"
installed_label="$(app_label main kitty 1 'terminal')"
check_prefix "★ kitty" "$main_label" "Unicode main label uses a star"
check_prefix "○ foot" "$alt_label" "Unicode alternative label uses a circle"
check_prefix "• btop" "$pkg_label" "Unicode package label uses a dot"
check_contains "✓" "$installed_label" "Unicode installed mark uses a check"

# 3. Legend explains the marks.
export DOTFILES_ASCII=1
legend="$(tui_legend)"
check_contains "[*] main" "$legend" "ASCII legend names the main mark"
check_contains "[ ] alternative" "$legend" "ASCII legend names the alternative mark"
check_contains "[i] installed" "$legend" "ASCII legend names the installed mark"

# 4. The catalog has the expected categories and no duplicate rows.
for removed in gum grub jq mprime onlinefix-linux-launcher-bin linux-lts; do
    if catalog_lines | cut -f1 | grep -qx "$removed"; then
        fail "$removed should not be in the catalog"
    fi
done
pass "removed system packages stay out of the catalog"

# 4b. The requested catalogue cleanup is applied.
for removed in base base-devel efibootmgr git gitleaks tcpdump cups-pdf \
    fbida smath networkmanager clang cmake jdk17-openjdk lld llvm uv rustup \
    jpegoptim oxipng; do
    if catalog_lines | cut -f1 | grep -qx "$removed"; then
        fail "$removed should have been removed from the catalog"
    fi
done
pass "requested removals are gone from the catalog"

for optional in inotify-tools snap-pac cpu-x gsmartcontrol hardinfo2 \
    kdiskmark pdfcraft-bin s-tui docker docker-compose libvirt qemu-base \
    qemu-desktop swtpm virt-manager; do
    if ! catalog_lines | awk -F'\t' -v p="$optional" '$1 == p && $4 == "no" { found = 1 } END { exit !found }'; then
        fail "$optional should be optional (default=no)"
    fi
done
pass "requested optional packages default to no"

if catalog_lines | awk -F'\t' '$1 == "profile-sync-daemon" && $2 == "System" { found = 1 } END { exit !found }'; then
    pass "profile-sync-daemon moved to System"
else
    fail "profile-sync-daemon is not in System"
fi
category_list="$(catalog_categories)"
if grep -qx 'Office' <<<"$category_list" || grep -qx 'Engineering' <<<"$category_list"; then
    fail "the removed Office or Engineering category is still present"
else
    pass "Office and Engineering are merged into other categories"
fi
check_contains "Terminal" "$category_list" "catalog has the Terminal category"
check_contains "Games" "$category_list" "catalog has the Games category"
check_contains "System" "$category_list" "catalog has the System category"
default_category_list="$(catalog_default_categories)"
check_contains "Terminal" "$default_category_list" "Terminal has default packages"
check_contains "Desktop" "$default_category_list" "Desktop has default packages"
if grep -qx 'Virtualization' <<<"$default_category_list"; then
    fail "Virtualization has no default packages but is preselected"
else
    pass "categories without defaults stay unchecked"
fi
duplicates="$(catalog_lines | cut -f1 | sort | uniq -d)"
if [[ -z $duplicates ]]; then
    pass "catalog has no duplicate packages"
else
    fail "catalog duplicates: $duplicates"
fi

# 5. Defaults follow the catalog flags.
default_list="$(catalog_default_packages)"
check_contains "kitty" "$default_list" "main terminal is a default"
check_contains "firefox" "$default_list" "main browser is a default"
if grep -qx 'cadcraft-bin' <<<"$default_list" || grep -qx 'easyeda-pro-bin' <<<"$default_list"; then
    fail "optional CAD apps are defaults"
else
    pass "optional CAD and EasyEDA apps are not defaults"
fi
if grep -qx 'hypridle' <<<"$default_list"; then
    fail "optional hypridle is a default"
else
    pass "optional hypridle is not a default"
fi
if grep -qx 'cuda-12.9' <<<"$default_list"; then
    fail "optional cuda is a default"
else
    pass "optional cuda is not a default"
fi
if grep -qx 'virtio-win' <<<"$default_list"; then
    fail "optional virtio-win is a default"
else
    pass "optional virtio-win is not a default"
fi
if grep -qx 'profile-sync-daemon' <<<"$default_list"; then
    fail "optional profile-sync-daemon is a default"
else
    pass "optional profile-sync-daemon is not a default"
fi

# 5b. Spicetify is a main Music entry and stays selected.
if catalog_lines | awk -F'\t' '$1 == "spicetify-cli" && $2 == "Music" && $3 == "main" && $4 == "yes" { found = 1 } END { exit !found }'; then
    pass "Spicetify is a selected main Music entry"
else
    fail "Spicetify is not a selected main Music entry"
fi

# 6. Alternatives stay visible but are not selected by default.
alts="$(catalog_lines | awk -F'\t' '$2 == "Terminal" && $3 == "alt" { print $1 }')"
check_contains "foot" "$alts" "terminal alternatives are listed"
if grep -qx 'foot' <<<"$default_list"; then
    fail "alternative foot is a default"
else
    pass "alternative foot is not a default"
fi

# 7. --category selects the category and its defaults without a terminal.
export CATEGORY_ARG=Terminal
SELECTED_CATEGORIES=()
SELECTED_APPLICATIONS=()
select_categories
select_apps
if [[ ${SELECTED_CATEGORIES[*]} == Terminal ]] \
    && [[ " ${SELECTED_APPLICATIONS[*]} " == *" kitty "* ]] \
    && [[ " ${SELECTED_APPLICATIONS[*]} " != *" foot "* ]]; then
    pass "--category selects the category defaults"
else
    fail "--category produced categories=${SELECTED_CATEGORIES[*]} apps=${SELECTED_APPLICATIONS[*]}"
fi
export CATEGORY_ARG=""

# 8. Unknown categories fail loudly.
export CATEGORY_ARG=does-not-exist
if (select_categories) >/dev/null 2>&1; then
    fail "an unknown category was accepted"
else
    pass "an unknown category is rejected"
fi
export CATEGORY_ARG=""

# 9. --apps is an exact list and does not add defaults.
export APPS_ARG=foot,alacritty
SELECTED_APPLICATIONS=()
select_apps
if [[ ${SELECTED_APPLICATIONS[*]} == 'foot alacritty' ]]; then
    pass "--apps selects exactly the listed packages"
else
    fail "--apps produced: ${SELECTED_APPLICATIONS[*]}"
fi
export APPS_ARG=""

# 10. --packages is an exact list and skips both pickers.
export PACKAGES_ARG=foot,kitty
SELECTED_CATEGORIES=(Terminal)
SELECTED_APPLICATIONS=()
select_categories
select_apps
if [[ ${#SELECTED_CATEGORIES[@]} -eq 0 && ${SELECTED_APPLICATIONS[*]} == 'foot kitty' ]]; then
    pass "--packages installs exactly the listed packages"
else
    fail "--packages produced categories=${SELECTED_CATEGORIES[*]} apps=${SELECTED_APPLICATIONS[*]}"
fi
export PACKAGES_ARG=""

# 11. Non-interactive runs never block on the picker.
# shellcheck disable=SC2016 # $0 is the repository path passed to bash -c
if timeout 15 bash -c 'source "$0/lib/common.sh"; source "$0/lib/tui.sh"; source "$0/lib/packages.sh"; select_apps' "$ROOT" </dev/null; then
    pass "the picker returns immediately without a TTY"
else
    fail "the picker failed or hung without a TTY"
fi

# 12. Duplicate selections become one package.
SELECTED_APPLICATIONS=(foot foot kitty)
selected="$(collect_packages)"
if [[ $(grep -cx 'foot' <<<"$selected") == 1 ]]; then
    pass "duplicate packages are deduplicated"
else
    fail "packages were not deduplicated"
fi
if grep -qx 'kitty' <<<"$selected"; then
    pass "the selected package list is preserved"
else
    fail "the selected package is missing"
fi

# 13. --only-packages without a selector cannot silently do nothing.
guard_log="$(mktemp)"
if (cd "$ROOT" && timeout 20 ./install.sh --dry-run --yes --only-packages) \
    >"$guard_log" 2>&1; then
    fail "--only-packages without a selector succeeded"
else
    if grep -q 'needs --packages, --category or --apps' "$guard_log"; then
        pass "--only-packages without a selector fails loudly"
    else
        fail "--only-packages failed without a clear message"
        cat "$guard_log"
    fi
fi
rm -f -- "$guard_log"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
