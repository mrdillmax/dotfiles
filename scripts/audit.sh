#!/usr/bin/env bash
# Read-only audit of the live configuration and of this repository.
# It never edits files, never restarts services and never requires root.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR

# shellcheck source=lib/secrets.sh
source "$DOTFILES_DIR/lib/secrets.sh"
# shellcheck source=lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=lib/kernel.sh
source "$DOTFILES_DIR/lib/kernel.sh"

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m' C_BOLD=$'\033[1m'
    C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m'
else
    C_RESET="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
fi

PASS=0
WARN=0
FAIL=0

section() { printf '\n%s== %s ==%s\n' "$C_BOLD" "$1" "$C_RESET"; }
pass()    { PASS=$((PASS + 1)); printf '%sPASS%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { WARN=$((WARN + 1)); printf '%sWARN%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail()    { FAIL=$((FAIL + 1)); printf '%sFAIL%s %s\n' "$C_RED" "$C_RESET" "$*"; }
note()    { printf '%snote%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }

has() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- repository --

section "Repository"

for path in install.sh Makefile README.md README.uk.md AUDIT.md lib/common.sh; do
    if [[ -e $DOTFILES_DIR/$path ]]; then
        pass "present: $path"
    else
        fail "missing: $path"
    fi
done

if has git && git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$DOTFILES_DIR" check-ignore -q "$DOTFILES_DIR/pihole.toml"; then
        pass "pihole.toml is git-ignored"
    else
        fail "pihole.toml is NOT git-ignored"
    fi

    # Templates under matugen/templates/ are the source files, not generated output.
    tracked_generated="$(git -C "$DOTFILES_DIR" ls-files | grep -v '/matugen/templates/' | grep -E \
        '(^|/)(colors\.lua|colors\.css|colors\.rasi|Matugen\.conf|dunstrc)$' || true)"
    if [[ -z $tracked_generated ]]; then
        pass "no generated matugen output is tracked"
    else
        fail "generated files are tracked: $tracked_generated"
    fi
else
    warn "not a git repository; skipping ignore checks"
fi

if check_forbidden_paths "$DOTFILES_DIR"; then
    pass "no forbidden secret/config paths inside the repository"
else
    fail "forbidden paths are present (see above)"
fi

section "Secrets"
if scan_secrets "$DOTFILES_DIR"; then
    pass "no high-confidence secret patterns found"
else
    fail "possible secrets found (see above)"
fi

# ---------------------------------------------------------------- Hyprland --

section "Hyprland"

if has hyprctl && hyprctl version >/dev/null 2>&1; then
    note "version: $(hyprctl version | sed -n '1p')"
    errors="$(hyprctl configerrors 2>/dev/null || true)"
    if [[ -z $errors ]]; then
        pass "no config errors reported by Hyprland"
    else
        fail "Hyprland reports config errors:"
        printf '%s\n' "$errors"
    fi

    duplicates="$(hyprctl binds -j 2>/dev/null \
        | jq -r '.[] | "\(.modmask)|\(.key)|\(.submap)"' \
        | sort | uniq -d)"
    if [[ -z $duplicates ]]; then
        pass "no duplicate key binds"
    else
        warn "duplicate key binds in the live config:"
        printf '%s\n' "$duplicates"
    fi

    note "input values:"
    for option in input:sensitivity input:accel_profile input:force_no_accel \
                  input:scroll_factor input:touchpad:natural_scroll \
                  input:touchpad:tap-to-click input:touchpad:disable_while_typing; do
        printf '  %-40s %s\n' "$option" "$(hyprctl getoption "$option" 2>/dev/null | sed -n '1p')"
    done
else
    warn "Hyprland is not running; skipping live checks"
fi

# ------------------------------------------------------- monitors / paths --

section "Monitor portability"

monitor_hits="$(grep -rnE 'HDMI-A-[0-9]|DP-[0-9]|eDP-[0-9]|HEADLESS-[0-9]' \
    "$DOTFILES_DIR" \
    --exclude-dir=.git \
    --exclude=monitors.conf.sh \
    --exclude=AUDIT.md \
    --exclude=README.md \
    --exclude=README.uk.md 2>/dev/null || true)"
if [[ -z $monitor_hits ]]; then
    pass "no hardcoded monitor names outside the host preset and docs"
else
    fail "hardcoded monitor names found:"
    printf '%s\n' "$monitor_hits"
fi

note "monitor names still present in the live configuration:"
grep -rnE 'HDMI-A-[0-9]|DP-[0-9]|eDP-[0-9]|HEADLESS-[0-9]' \
    "$HOME/.config/hypr" "$HOME/.config/sunshine" 2>/dev/null \
    | grep -v '\.log' || true

section "Hardcoded paths"

home_hits="$(grep -rnP '(?<![A-Za-z0-9._/-])/home/[A-Za-z0-9._-]+/' \
    "$DOTFILES_DIR" \
    --exclude-dir=.git \
    --exclude='*.md' \
    --exclude=.gitignore 2>/dev/null || true)"
if [[ -z $home_hits ]]; then
    pass "no hardcoded user home paths"
else
    fail "hardcoded home paths found:"
    printf '%s\n' "$home_hits"
fi

# --------------------------------------------------------------- systemd --

section "systemd"

unit_files=()
while IFS= read -r unit; do
    unit_files+=("$unit")
done < <(find "$DOTFILES_DIR/modules" -type f \( -name '*.service' -o -name '*.timer' \) | sort)

if has systemd-analyze && ((${#unit_files[@]})); then
    if output="$(systemd-analyze verify "${unit_files[@]}" 2>&1)"; then
        pass "user units and timers verify"
    else
        fail "systemd-analyze verify failed:"
        printf '%s\n' "$output"
    fi
else
    warn "systemd-analyze not available; skipping unit verification"
fi

# ------------------------------------------------------------ system files --

section "System configuration"

if has unbound-checkconf && [[ -r /etc/unbound/unbound.conf ]]; then
    if output="$(unbound-checkconf /etc/unbound/unbound.conf 2>&1)"; then
        pass "unbound-checkconf: $output"
    else
        fail "unbound-checkconf failed:"
        printf '%s\n' "$output"
    fi
else
    warn "unbound config not readable or unbound-checkconf missing"
fi

pacnew="$(find /etc -maxdepth 3 -name '*.pacnew' 2>/dev/null || true)"
if [[ -z $pacnew ]]; then
    pass "no .pacnew files in /etc"
else
    warn "unmerged .pacnew files:"
    printf '%s\n' "$pacnew"
fi

if [[ -r /etc/pihole/dnsmasq.conf ]]; then
    iface="$(sed -n 's/^[[:space:]]*interface=//p' /etc/pihole/dnsmasq.conf | head -n1)"
    if [[ -n $iface ]]; then
        note "Pi-hole dnsmasq is bound to interface: $iface (installer does not rewrite it)"
    fi
fi

if [[ -e $HOME/.config/gtk-4.0/gtk.css ]]; then
    if [[ -L $HOME/.config/gtk-4.0/gtk.css && -e $HOME/.config/gtk-4.0/gtk.css ]]; then
        pass "GTK4 theme symlinks resolve (adw-gtk3-dark)"
    else
        warn "GTK4 gtk.css is not a valid symlink"
    fi
fi

section "Kernel and CPU"
cpu_level="$(detect_cpu_level)"
note "CPU supports x86-64-$cpu_level"

installed_level=""
mapfile -t audit_kernels < <(installed_kernel_packages)
for pkg in "${audit_kernels[@]}"; do
    pkg_level="$(kernel_package_level "$pkg")"
    if [[ $pkg_level != generic ]]; then
        if [[ -z $installed_level ]] || (( $(kernel_level_rank "$pkg_level") > $(kernel_level_rank "$installed_level") )); then
            installed_level="$pkg_level"
        fi
    fi
done

if [[ -z $installed_level ]]; then
    note "no level-aware kernel installed; generic kernels are not a bug"
elif (( $(kernel_level_rank "$installed_level") > $(kernel_level_rank "$cpu_level") )); then
    fail "installed kernel level x86-64-$installed_level is above CPU level x86-64-$cpu_level"
elif (( $(kernel_level_rank "$installed_level") < $(kernel_level_rank "$cpu_level") )); then
    warn "installed kernel level x86-64-$installed_level is below CPU level x86-64-$cpu_level"
else
    pass "installed kernel level matches CPU level (x86-64-$cpu_level)"
fi

if pacman -Qq "$FALLBACK_KERNEL_PACKAGE" >/dev/null 2>&1; then
    pass "fallback kernel present: $FALLBACK_KERNEL_PACKAGE"
else
    warn "fallback kernel missing: $FALLBACK_KERNEL_PACKAGE"
fi

if any_dkms_installed; then
    dkms_missing=0
    for pkg in "${audit_kernels[@]}"; do
        case "$pkg" in
            linux)     hdr="linux-headers" ;;
            linux-lts) hdr="linux-lts-headers" ;;
            linux-zen) hdr="linux-zen-headers" ;;
            *-x64v*)   hdr="${pkg/-linux-bin-/-linux-headers-bin-}" ;;
            *)         hdr="" ;;
        esac
        if [[ -n $hdr ]] && ! pacman -Qq "$hdr" >/dev/null 2>&1; then
            warn "DKMS headers missing for $pkg: $hdr"
            dkms_missing=1
        fi
    done
    ((dkms_missing)) || pass "NVIDIA DKMS has matching headers for every kernel"
else
    note "NVIDIA DKMS not installed; header pairing is not required"
fi

section "Ownership notes"
note "workspaces-split: switch_ws.sh works in the owner's setup and is verified; do not change its behaviour."
note "GTK4 imports resolved through symlinks are expected, not a bug."
note "This audit is read-only. Fixes are applied separately, after explicit permission."

printf '\n%sSummary:%s %d passed, %d warnings, %d failures\n' \
    "$C_BOLD" "$C_RESET" "$PASS" "$WARN" "$FAIL"

((FAIL == 0)) || exit 1
