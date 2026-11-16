#!/usr/bin/env bash
# Read-only health check for the installed dotfiles and the live system.
# It never edits files, never restarts services and never requires root.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR
export DRY_RUN=1
export ASSUME_YES=1

# shellcheck source=lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"

REAL_HOME="$(real_home)"
# shellcheck source=lib/monitors.sh
source "$DOTFILES_DIR/lib/monitors.sh"
# shellcheck source=lib/kernel.sh
source "$DOTFILES_DIR/lib/kernel.sh"
# shellcheck source=lib/cursor.sh
source "$DOTFILES_DIR/lib/cursor.sh"

if [[ -t 1 ]]; then
    C_BOLD=$'\033[1m'
else
    C_BOLD=""
fi

PASS=0
WARN=0
FAIL=0

section() { printf '\n%s== %s ==%s\n' "$C_BOLD" "$1" "$C_RESET"; }
pass()    { PASS=$((PASS + 1)); printf '%sPASS%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { WARN=$((WARN + 1)); printf '%sWARN%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail()    { FAIL=$((FAIL + 1)); printf '%sFAIL%s %s\n' "$C_RED" "$C_RESET" "$*"; }
note()    { printf '%snote%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }

section "Repository"
for path in install.sh Makefile README.md AUDIT.md lib/kernel.sh packages/base.txt; do
    if [[ -e $DOTFILES_DIR/$path ]]; then
        pass "present: $path"
    else
        fail "missing: $path"
    fi
done

HOST_NAME="$(detect_host_type)"
GPU_PROFILE="$(detect_gpu_profile)"
if [[ -d $DOTFILES_DIR/hosts/$HOST_NAME ]]; then
    pass "host profile: $HOST_NAME"
else
    fail "host profile not found: hosts/$HOST_NAME"
fi
if [[ -d $DOTFILES_DIR/profiles/gpu/$GPU_PROFILE ]]; then
    pass "GPU profile: $GPU_PROFILE"
else
    fail "GPU profile not found: profiles/gpu/$GPU_PROFILE"
fi

section "Kernel and CPU"
cpu="$(detect_cpu_level)"
note "CPU supports x86-64-$cpu"

installed_level=""
mapfile -t kernels < <(installed_kernel_packages)
if ((${#kernels[@]} == 0)); then
    warn "no Linux kernel package detected"
else
    note "installed kernels: ${kernels[*]}"
fi
for pkg in "${kernels[@]}"; do
    pkg_level="$(kernel_package_level "$pkg")"
    if [[ $pkg_level != generic ]]; then
        if [[ -z $installed_level ]] || (( $(kernel_level_rank "$pkg_level") > $(kernel_level_rank "$installed_level") )); then
            installed_level="$pkg_level"
        fi
    fi
done

if [[ -z $installed_level ]]; then
    warn "no x86-64-level-aware kernel installed (generic kernels are fine, but not level-tuned)"
elif (( $(kernel_level_rank "$installed_level") > $(kernel_level_rank "$cpu") )); then
    fail "installed kernel level x86-64-$installed_level is above CPU level x86-64-$cpu"
elif (( $(kernel_level_rank "$installed_level") < $(kernel_level_rank "$cpu") )); then
    warn "installed kernel level x86-64-$installed_level is below CPU level x86-64-$cpu"
else
    pass "installed kernel level matches CPU level (x86-64-$cpu)"
fi

if pacman -Qq "$FALLBACK_KERNEL_PACKAGE" >/dev/null 2>&1; then
    pass "fallback kernel present: $FALLBACK_KERNEL_PACKAGE"
else
    warn "fallback kernel missing: $FALLBACK_KERNEL_PACKAGE"
fi

if any_dkms_installed; then
    missing_headers=0
    for pkg in "${kernels[@]}"; do
        case "$pkg" in
            linux)     headers="linux-headers" ;;
            linux-lts) headers="linux-lts-headers" ;;
            linux-zen) headers="linux-zen-headers" ;;
            *-x64v*)   headers="${pkg/-linux-bin-/-linux-headers-bin-}" ;;
            *)         headers="" ;;
        esac
        if [[ -n $headers ]] && ! pacman -Qq "$headers" >/dev/null 2>&1; then
            warn "DKMS headers missing for $pkg: $headers"
            missing_headers=1
        fi
    done
    ((missing_headers)) || pass "NVIDIA DKMS has matching kernel headers"
else
    note "NVIDIA DKMS is not installed; header pairing not needed"
fi

section "Cursor"
load_cursor_conf
if cursor_theme_exists "$CURSOR_THEME"; then
    pass "cursor theme installed: $CURSOR_THEME"
else
    warn "cursor theme not installed: $CURSOR_THEME (run ./install.sh --cursor)"
fi
if [[ -f $REAL_HOME/.config/gtk-3.0/settings.ini ]]; then
    gtk_cursor="$(sed -n 's/^gtk-cursor-theme-name=//p' "$REAL_HOME/.config/gtk-3.0/settings.ini" | head -n1)"
    if [[ $gtk_cursor == "$CURSOR_THEME" ]]; then
        pass "GTK3 cursor matches host config ($CURSOR_THEME)"
    else
        warn "GTK3 cursor '$gtk_cursor' differs from host config '$CURSOR_THEME'"
    fi
fi

section "Wallpaper"
wallpaper_state="$REAL_HOME/.config/hypr/wallpaper.path"
if [[ -r $wallpaper_state ]]; then
    wallpaper_image="$(<"$wallpaper_state")"
    if [[ -f $wallpaper_image ]]; then
        pass "wallpaper path resolves: $wallpaper_image"
    else
        warn "wallpaper path does not exist: $wallpaper_image"
    fi
else
    wallpaper_image="$(awk -F'"' '/^[[:space:]]*image[[:space:]]*=/{print $2; exit}' \
        "$REAL_HOME/.config/hypr/colors.lua" 2>/dev/null || true)"
    if [[ -n $wallpaper_image && -f $wallpaper_image ]]; then
        note "wallpaper comes from colors.lua; run ./install.sh --wallpaper to record it"
    else
        warn "no wallpaper path recorded (run ./install.sh --wallpaper PATH)"
    fi
fi

section "Managed files"
state_file="${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles/managed.tsv"
if [[ -r $state_file ]]; then
    broken=0
    while IFS=$'\t' read -r kind path source; do
        [[ $kind == link ]] || continue
        if [[ ! -e $path ]]; then
            warn "broken managed link: $path -> $source"
            broken=1
        fi
    done <"$state_file"
    ((broken)) || pass "all recorded symlinks resolve"
else
    note "no managed.tsv yet (installer has not run here)"
fi

printf '\n%sSummary:%s %d passed, %d warnings, %d failures\n' \
    "$C_BOLD" "$C_RESET" "$PASS" "$WARN" "$FAIL"

((FAIL == 0))
