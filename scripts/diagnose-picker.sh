#!/usr/bin/env bash
# Read-only diagnosis of the package picker.
#
# Prints the catalog counts, the TUI backend and the result of the same
# selection functions the menu uses. Nothing is installed or written.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR

# shellcheck source=lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=lib/monitors.sh
source "$DOTFILES_DIR/lib/monitors.sh"
# shellcheck source=lib/tui.sh
source "$DOTFILES_DIR/lib/tui.sh"
# shellcheck source=lib/packages.sh
source "$DOTFILES_DIR/lib/packages.sh"

HOST_NAME="${HOST_NAME:-$(detect_host_type)}"
GPU_PROFILE="${GPU_PROFILE:-$(detect_gpu_profile)}"
# Read by select_categories/select_apps in lib/packages.sh.
# shellcheck disable=SC2034
ALL=0
# shellcheck disable=SC2034
ASSUME_YES=0
# shellcheck disable=SC2034
PACKAGES_ARG=""
# shellcheck disable=SC2034
CATEGORY_ARG=""
# shellcheck disable=SC2034
APPS_ARG=""

printf 'repository: %s\n' "$DOTFILES_DIR"
printf 'commit:     %s\n' "$(git -C "$DOTFILES_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
printf 'bash:       %s\n' "$(bash --version | head -1)"
printf 'host/gpu:   %s / %s\n' "$HOST_NAME" "$GPU_PROFILE"
printf 'backend:    %s\n' "$(tui_backend)"
printf 'locale:     %s\n' "$(locale charmap 2>/dev/null || printf 'unknown')"

printf '\ntools:\n'
for tool in awk sed sort grep gum whiptail dialog pacman yay sudo; do
    printf '  %-10s %s\n' "$tool" "$(command -v "$tool" || printf 'MISSING')"
done
if command -v gum >/dev/null 2>&1; then
    printf '  gum ver    %s\n' "$(gum --version 2>&1 | head -1)"
    for flag in --selected --no-limit; do
        if gum choose --help 2>&1 | grep -q -- "$flag"; then
            printf '  gum %-9s supported\n' "$flag"
        else
            printf '  gum %-9s MISSING\n' "$flag"
        fi
    done
fi

printf '\ncatalog:\n'
for file in "$CATALOG" "$LOCAL_CATALOG"; do
    if [[ -r $file ]]; then
        printf '  %s: %s rows\n' "$file" "$(awk 'NF && $0 !~ /^#/' "$file" | wc -l)"
    else
        printf '  %s: NOT READABLE\n' "$file"
    fi
done
printf '  categories: %s\n' "$(catalog_categories | wc -l)"
printf '  defaults:   %s\n' "$(catalog_default_packages | wc -l)"

if [[ ! -t 0 ]]; then
    printf '\nnot a terminal; run this script in the same terminal as ./install.sh\n'
    exit 1
fi

SELECTED_CATEGORIES=()
SELECTED_APPLICATIONS=()
printf '\nselect categories and applications exactly as in the menu:\n'
select_categories
printf 'selected categories: %s\n' "${SELECTED_CATEGORIES[*]:-<none>}"
select_apps
printf 'selected packages: %d\n' "${#SELECTED_APPLICATIONS[@]}"
printf '%s\n' "${SELECTED_APPLICATIONS[@]:-<none>}"

printf '\nmenu would run:\n'
list="$(printf '%s,' "${SELECTED_APPLICATIONS[@]:-}")"
list="${list%,}"
printf '  ./install.sh --only-packages --packages %q\n' "$list"
