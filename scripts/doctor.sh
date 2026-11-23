#!/usr/bin/env bash
# Read-only health check for the installed dotfiles and the live system.
# It never edits files, never restarts services and never requests sudo.
#
# Levels: OK | WARN | FAIL | SKIPPED
# Exit code is nonzero only when at least one FAIL is reported.
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
# shellcheck source=lib/secrets.sh
source "$DOTFILES_DIR/lib/secrets.sh"

JSON=0
while (($#)); do
    case "$1" in
        --json) JSON=1 ;;
        -h|--help)
            cat <<'EOF'
Usage: scripts/doctor.sh [--json]

Read-only checks. Nothing is changed, no service is restarted, no sudo is used.
Exit code is nonzero only when a FAIL is reported.
EOF
            exit 0
            ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

if [[ -t 1 ]]; then
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_DIM=$'\033[2m'
else
    C_BOLD="" C_RESET="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_DIM=""
fi

GUM=0
if (( !JSON )) && [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then
    GUM=1
fi

OK=0
WARN=0
FAIL=0
SKIPPED=0
SECTION="General"
R_LEVEL=()
R_AREA=()
R_CHECK=()

section() {
    SECTION="$1"
    if (( !JSON && !GUM )); then
        printf '\n%s== %s ==%s\n' "$C_BOLD" "$1" "$C_RESET"
    fi
}

record() {
    local level="$1" message="$2"

    case "$level" in
        OK)      OK=$((OK + 1)) ;;
        WARN)    WARN=$((WARN + 1)) ;;
        FAIL)    FAIL=$((FAIL + 1)) ;;
        SKIPPED) SKIPPED=$((SKIPPED + 1)) ;;
    esac

    R_LEVEL+=("$level")
    R_AREA+=("$SECTION")
    R_CHECK+=("$message")

    ((JSON)) && return 0
    ((GUM)) && return 0

    local color=""
    case "$level" in
        OK)      color="$C_GREEN" ;;
        WARN)    color="$C_YELLOW" ;;
        FAIL)    color="$C_RED" ;;
        SKIPPED) color="$C_DIM" ;;
    esac
    printf '%s%-7s%s %s\n' "$color" "$level" "$C_RESET" "$message"
}

ok()   { record OK "$*"; }
warn() { record WARN "$*"; }
fail() { record FAIL "$*"; }
skip() { record SKIPPED "$*"; }
note() {
    ((JSON)) && return 0
    printf '%snote%s %s\n' "$C_BLUE" "$C_RESET" "$*"
}

has() { command -v "$1" >/dev/null 2>&1; }

json_escape() {
    local json_value="$1"
    json_value="${json_value//\\/\\\\}"
    json_value="${json_value//\"/\\\"}"
    json_value="${json_value//$'\n'/\\n}"
    json_value="${json_value//$'\t'/\\t}"
    json_value="${json_value//$'\r'/\\r}"
    printf '%s' "$json_value"
}

csv_escape() {
    local csv_value="$1"
    csv_value="${csv_value//\"/\"\"}"
    printf '"%s"' "$csv_value"
}

# ---------------------------------------------------------------- repository --

section "Repository"
for path in install.sh Makefile README.md README.uk.md \
            lib/common.sh lib/secrets.sh hooks/pre-commit; do
    if [[ -e $DOTFILES_DIR/$path ]]; then
        ok "present: $path"
    else
        fail "missing: $path"
    fi
done

HOST_NAME="$(detect_host_type)"
GPU_PROFILE="$(detect_gpu_profile)"
if [[ -d $DOTFILES_DIR/hosts/$HOST_NAME ]]; then
    ok "host profile: $HOST_NAME"
else
    fail "host profile not found: hosts/$HOST_NAME"
fi
if [[ -d $DOTFILES_DIR/profiles/gpu/$GPU_PROFILE ]]; then
    ok "GPU profile: $GPU_PROFILE"
else
    fail "GPU profile not found: profiles/gpu/$GPU_PROFILE"
fi

section "Module dependencies"

# Detection is best-effort: managed.tsv when the installer has run, plus live
# symlinks that point into the repository.
STATE_DIR="${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles"
STATE_FILE="$STATE_DIR/managed.tsv"
declare -A INSTALLED_MODULES=()

stored_version=""
[[ -r $STATE_DIR/version ]] && stored_version="$(tr -d '[:space:]' <"$STATE_DIR/version")"
repo_version=""
[[ -r $DOTFILES_DIR/VERSION ]] && repo_version="$(tr -d '[:space:]' <"$DOTFILES_DIR/VERSION")"
if [[ -z $repo_version ]]; then
    fail "VERSION file is missing or empty"
elif [[ -n $stored_version ]]; then
    if [[ $stored_version == "$repo_version" ]]; then
        ok "config version: $stored_version"
    elif ((stored_version < repo_version)); then
        warn "config version: $stored_version, repository $repo_version (migrations pending)"
    else
        warn "config version: $stored_version, repository $repo_version (repository is behind)"
    fi
elif [[ -e $STATE_FILE ]]; then
    warn "config version: not recorded (pre-framework install; the next install migrates)"
else
    skip "config version: not installed yet"
fi

if [[ -r $STATE_FILE ]]; then
    while IFS=$'\t' read -r kind path source _; do
        [[ -n ${kind:-} ]] || continue
        case "$source" in
            "$DOTFILES_DIR"/modules/*)
                rel="${source#"$DOTFILES_DIR"/modules/}"
                INSTALLED_MODULES["${rel%%/*}"]=1
                ;;
        esac
    done <"$STATE_FILE"
fi

if ((${#INSTALLED_MODULES[@]} == 0)); then
    for base in "$REAL_HOME/.config" "$REAL_HOME/.local/bin"; do
        [[ -d $base ]] || continue
        while IFS= read -r link; do
            target="$(readlink -f -- "$link" 2>/dev/null || true)"
            case "$target" in
                "$DOTFILES_DIR"/modules/*)
                    rel="${target#"$DOTFILES_DIR"/modules/}"
                    INSTALLED_MODULES["${rel%%/*}"]=1
                    ;;
            esac
        done < <(find "$base" -type l 2>/dev/null)
    done
fi

missing_requires=()
for dir in "$DOTFILES_DIR"/modules/*/; do
    name="$(basename "$dir")"
    if [[ ! -r $dir/module.conf ]]; then
        fail "module $name: module.conf is missing"
        continue
    fi
    while IFS= read -r req; do
        [[ -n $req ]] || continue
        if [[ ! -d $DOTFILES_DIR/modules/$req ]]; then
            missing_requires+=("$name -> $req")
        fi
    done < <(
        # shellcheck source=/dev/null
        source "$dir/module.conf"
        printf '%s\n' "${REQUIRES[@]:-}"
    )
done

if ((${#missing_requires[@]})); then
    fail "missing module dependencies: ${missing_requires[*]}"
else
    ok "module REQUIRES resolve"
fi

if ! has pacman; then
    skip "pacman is not available; package dependency check skipped"
elif ((${#INSTALLED_MODULES[@]} == 0)); then
    skip "no installed modules detected; package dependency check skipped"
else
    missing_packages=()
    for name in "${!INSTALLED_MODULES[@]}"; do
        conf="$DOTFILES_DIR/modules/$name/module.conf"
        [[ -r $conf ]] || continue
        while IFS= read -r pkg; do
            [[ -n $pkg ]] || continue
            if ! pacman -Qq "$pkg" >/dev/null 2>&1; then
                missing_packages+=("$name:$pkg")
            fi
        done < <(
            # shellcheck source=/dev/null
            source "$conf"
            printf '%s\n' "${PACKAGES[@]:-}"
        )
    done

    if ((${#missing_packages[@]})); then
        fail "missing packages for installed modules: ${missing_packages[*]}"
    else
        ok "packages for installed modules are present"
    fi
fi

# --------------------------------------------------------------- Hyprland --

section "Hyprland"

live_conf="$REAL_HOME/.config/hypr/hyprland.lua"
hypr_bin="$(command -v Hyprland || command -v hyprland || true)"
if [[ -n $hypr_bin && -r $live_conf ]]; then
    verify_out="$(timeout 20 "$hypr_bin" --verify-config -c "$live_conf" 2>&1 || true)"
    if grep -q 'config ok' <<<"$verify_out"; then
        ok "Hyprland --verify-config: config ok"
    else
        fail "Hyprland --verify-config reported errors"
        printf '%s\n' "$verify_out" | tail -n 20
    fi
elif [[ -z $hypr_bin ]]; then
    skip "Hyprland binary not found; config verification skipped"
else
    skip "no live Hyprland config at $live_conf"
fi

if has hyprctl && hyprctl version >/dev/null 2>&1; then
    note "version: $(hyprctl version | sed -n '1p')"

    errors="$(hyprctl configerrors 2>/dev/null || true)"
    if [[ -z $errors ]]; then
        ok "hyprctl configerrors is empty"
    else
        fail "hyprctl configerrors reports problems"
        printf '%s\n' "$errors"
    fi

    if has jq; then
        duplicates="$(hyprctl binds -j 2>/dev/null \
            | jq -r '.[] | "\(.modmask)|\(.key)|\(.submap)"' \
            | sort | uniq -d || true)"
        if [[ -z $duplicates ]]; then
            ok "no duplicate key binds"
        else
            warn "duplicate key binds in the live config: $(printf '%s ' "$duplicates")"
        fi
    else
        skip "jq is not installed; duplicate bind check skipped"
    fi
else
    skip "Hyprland is not running; live checks skipped"
fi

# ---------------------------------------------------- DNS / system config --

section "DNS chain"

resolv_nameservers=""
if [[ -r /etc/resolv.conf ]]; then
    resolv_nameservers="$(awk '$1 == "nameserver" {print $2}' /etc/resolv.conf 2>/dev/null | tr '\n' ' ')"
fi
if [[ -n $resolv_nameservers ]]; then
    if [[ $resolv_nameservers == *127.0.0.1* ]]; then
        ok "/etc/resolv.conf points to the local resolver ($resolv_nameservers)"
    else
        warn "/etc/resolv.conf does not use 127.0.0.1 (found: $resolv_nameservers)"
    fi
else
    skip "/etc/resolv.conf is not readable"
fi

DNS_TOOL=""
if has dig; then
    DNS_TOOL="dig"
elif has drill; then
    DNS_TOOL="drill"
fi

dns_resolve() {
    local server="$1" port="$2" name="$3"
    case "$DNS_TOOL" in
        dig)
            dig +short +time=2 +tries=1 -p "$port" "$name" "@$server" 2>/dev/null \
                | awk 'NF {print; exit}'
            ;;
        drill)
            drill -p "$port" "$name" "@$server" 2>/dev/null \
                | awk '/IN[[:space:]]+A[[:space:]]/ {print $NF; exit}'
            ;;
    esac
}

if [[ -z $DNS_TOOL ]]; then
    skip "neither dig nor drill is installed (install bind or ldns)"
else
    for entry in "127.0.0.1:53:Pi-hole" "127.0.0.1:5335:unbound"; do
        IFS=: read -r server port label <<<"$entry"
        first="$(dns_resolve "$server" "$port" archlinux.org)"
        second="$(dns_resolve "$server" "$port" github.com)"
        if [[ -n $first && -n $second ]]; then
            ok "$label resolves domains via $server:$port"
        elif [[ -z $first && -z $second ]]; then
            fail "$label cannot resolve anything via $server:$port"
        else
            fail "$label resolves some names but not others via $server:$port"
        fi
    done
fi

unbound_conf=/etc/unbound/unbound.conf
[[ -r /etc/unbound/unbound.conf.d/pi-hole.conf ]] && \
    unbound_conf=/etc/unbound/unbound.conf.d/pi-hole.conf
if has unbound-checkconf && [[ -r $unbound_conf ]]; then
    if unbound_out="$(unbound-checkconf "$unbound_conf" 2>&1)"; then
        ok "unbound-checkconf: $unbound_out"
    else
        fail "unbound-checkconf failed"
        printf '%s\n' "$unbound_out"
    fi
else
    skip "unbound-checkconf or an unbound config is not available"
fi

section "System files"

mapfile -t pacnew < <(find /etc -maxdepth 3 \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null | sort)
if ((${#pacnew[@]} == 0)); then
    ok "no .pacnew/.pacsave files in /etc"
else
    warn "unmerged .pacnew/.pacsave files: ${pacnew[*]}"
    if [[ -e /etc/unbound/unbound.conf.pacnew ]]; then
        note "review manually: diff -u /etc/unbound/unbound.conf /etc/unbound/unbound.conf.pacnew"
    fi
fi

if [[ -e /etc/pihole/pihole.toml ]]; then
    pihole_perms="$(stat -Lc '%a %U:%G' /etc/pihole/pihole.toml 2>/dev/null || true)"
    pihole_mode="${pihole_perms%% *}"
    if [[ -z $pihole_mode ]]; then
        skip "cannot read permissions of /etc/pihole/pihole.toml"
    elif [[ ${pihole_mode: -1} == 0 ]]; then
        ok "pihole.toml is not world-accessible ($pihole_perms)"
    else
        fail "pihole.toml is world-accessible ($pihole_perms); expected 640 pihole:pihole"
    fi
else
    skip "/etc/pihole/pihole.toml is not present"
fi

if has systemctl; then
    for service in pihole-FTL unbound NetworkManager; do
        state="$(systemctl is-active "$service" 2>/dev/null || true)"
        case "$state" in
            active) ok "$service: active" ;;
            failed) fail "$service: failed" ;;
            "")     skip "$service: state unknown" ;;
            *)      warn "$service: $state" ;;
        esac
    done
else
    skip "systemctl is not available; service status check skipped"
fi

# --------------------------------------------------------- kernel / desktop --

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
    ok "installed kernel level matches CPU level (x86-64-$cpu)"
fi

if pacman -Qq "$FALLBACK_KERNEL_PACKAGE" >/dev/null 2>&1; then
    ok "fallback kernel present: $FALLBACK_KERNEL_PACKAGE"
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
    ((missing_headers)) || ok "NVIDIA DKMS has matching kernel headers"
else
    note "NVIDIA DKMS is not installed; header pairing not needed"
fi

section "Cursor"
load_cursor_conf
if cursor_theme_exists "$CURSOR_THEME"; then
    ok "cursor theme installed: $CURSOR_THEME"
else
    warn "cursor theme not installed: $CURSOR_THEME (run ./install.sh --cursor)"
fi
if [[ -f $REAL_HOME/.config/gtk-3.0/settings.ini ]]; then
    gtk_cursor="$(sed -n 's/^gtk-cursor-theme-name=//p' "$REAL_HOME/.config/gtk-3.0/settings.ini" | head -n1)"
    if [[ $gtk_cursor == "$CURSOR_THEME" ]]; then
        ok "GTK3 cursor matches host config ($CURSOR_THEME)"
    else
        warn "GTK3 cursor '$gtk_cursor' differs from host config '$CURSOR_THEME'"
    fi
fi

section "Wallpaper"
wallpaper_state="$REAL_HOME/.config/hypr/wallpaper.path"
if [[ -r $wallpaper_state ]]; then
    wallpaper_image="$(<"$wallpaper_state")"
    if [[ -f $wallpaper_image ]]; then
        ok "wallpaper path resolves: $wallpaper_image"
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
scan_dirs=("$REAL_HOME/.config")
[[ -d $REAL_HOME/.local/bin ]] && scan_dirs+=("$REAL_HOME/.local/bin")

if [[ -d $REAL_HOME/.config || -d $REAL_HOME/.local/bin ]]; then
    mapfile -t broken_links < <(find "${scan_dirs[@]}" -xtype l 2>/dev/null | sort)
    if ((${#broken_links[@]} == 0)); then
        ok "no broken symlinks under ~/.config or ~/.local/bin"
    else
        warn "${#broken_links[@]} broken symlink(s), first 10: ${broken_links[*]:0:10}"
    fi
else
    skip "no ~/.config or ~/.local/bin to scan for broken symlinks"
fi

if [[ -r $STATE_FILE ]]; then
    bad_managed=()
    while IFS=$'\t' read -r kind path source _; do
        [[ -n ${kind:-} ]] || continue
        case "$kind" in
            link)
                if [[ ! -e $path ]]; then
                    bad_managed+=("broken link: $path -> $source")
                elif [[ "$(readlink -f -- "$path" 2>/dev/null || true)" != "$(readlink -f -- "$source" 2>/dev/null || true)" ]]; then
                    bad_managed+=("link points elsewhere: $path -> $(readlink -- "$path" 2>/dev/null || true)")
                fi
                ;;
            copy)
                if [[ ! -e $path ]]; then
                    bad_managed+=("missing copy: $path")
                elif [[ $digest != - ]]; then
                    [[ "$(file_digest "$path")" == "$digest" ]] \
                        || bad_managed+=("copy differs from the recorded digest: $path")
                elif ! cmp -s -- "$source" "$path"; then
                    bad_managed+=("copy differs from repo: $path")
                fi
                ;;
        esac
    done <"$STATE_FILE"

    if ((${#bad_managed[@]})); then
        warn "managed files diverged: ${bad_managed[*]}"
    else
        ok "managed files match the repository"
    fi
else
    skip "managed.tsv not found; divergence check skipped (installer has not run here)"
fi

section "Appearance"

if has gsettings; then
    scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"
    case "$scheme" in
        "'prefer-dark'"|"'prefer-light'") ok "portal color scheme: $scheme" ;;
        *) warn "portal color scheme is not set (got ${scheme:-empty})" ;;
    esac
    gtk4_theme="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || true)"
    case "$gtk4_theme" in
        "'adw-gtk3'"|"'adw-gtk3-dark'") ok "GTK theme: $gtk4_theme" ;;
        *) warn "unexpected GTK theme: ${gtk4_theme:-empty}" ;;
    esac
else
    skip "gsettings is not available"
fi

portal_conf="$REAL_HOME/.config/xdg-desktop-portal/portals.conf"
if [[ -r $portal_conf ]]; then
    if grep -q 'FileChooser=gtk' "$portal_conf" \
        && grep -q 'ScreenCast=hyprland' "$portal_conf" \
        && grep -q 'Settings=gtk' "$portal_conf"; then
        ok "portal backends are explicit and non-conflicting"
    else
        warn "portals.conf does not pin Settings/FileChooser/ScreenCast"
    fi
else
    warn "no user portals.conf; backend selection comes from the system defaults"
fi

if [[ -n ${QT_QPA_PLATFORMTHEME:-} ]]; then
    ok "Qt platform theme: $QT_QPA_PLATFORMTHEME"
else
    warn "QT_QPA_PLATFORMTHEME is not set"
fi

if has fc-match; then
    for family in "Inter" "JetBrainsMono Nerd Font"; do
        matched="$(fc-match "$family" -f '%{family}' 2>/dev/null || true)"
        if [[ $matched == *"$family"* ]]; then
            ok "font available: $family"
        else
            warn "font missing or aliased: $family (matched: ${matched:-none})"
        fi
    done
else
    skip "fontconfig tools are not available"
fi

if [[ -r $REAL_HOME/.config/gtk-4.0/gtk.css ]]; then
    if grep -q 'colors.css' "$REAL_HOME/.config/gtk-4.0/gtk.css"; then
        ok "GTK4 user stylesheet imports matugen colors"
    else
        warn "GTK4 user stylesheet does not import colors.css"
    fi
else
    warn "GTK4 user stylesheet is missing"
fi

section "RAM cache"

if has ramcache; then
    if ramcache status >/dev/null 2>&1; then
        ok "ramcache configuration is readable"
    else
        warn "ramcache status failed"
    fi
    if has systemctl && systemctl --user is-active psd.service >/dev/null 2>&1; then
        ok "profile-sync-daemon is active"
    else
        warn "profile-sync-daemon is not active"
    fi
    if has systemctl && systemctl is-active preload.service >/dev/null 2>&1; then
        ok "preload is active"
    else
        warn "preload is not active"
    fi
    if [[ -r /proc/meminfo ]]; then
        note "RAM: $(awk '/^MemTotal:/{printf "%.1f GiB total", $2/1048576}' /proc/meminfo)"
    fi
else
    skip "ramcache is not installed (optional module)"
fi

# ------------------------------------------------------------------ output --

if ((JSON)); then
    printf '{"checks":['
    for i in "${!R_LEVEL[@]}"; do
        ((i)) && printf ','
        printf '{"level":"%s","area":"%s","check":"%s"}' \
            "$(json_escape "${R_LEVEL[$i]}")" \
            "$(json_escape "${R_AREA[$i]}")" \
            "$(json_escape "${R_CHECK[$i]}")"
    done
    printf '],"summary":{"ok":%d,"warn":%d,"fail":%d,"skipped":%d},"exit":%d}\n' \
        "$OK" "$WARN" "$FAIL" "$SKIPPED" "$((FAIL > 0 ? 1 : 0))"
elif ((GUM)); then
    {
        printf 'STATUS,AREA,CHECK\n'
        for i in "${!R_LEVEL[@]}"; do
            msg="${R_CHECK[$i]}"
            if ((${#msg} > 110)); then
                msg="${msg:0:107}..."
            fi
            printf '%s,%s,%s\n' \
                "$(csv_escape "${R_LEVEL[$i]}")" \
                "$(csv_escape "${R_AREA[$i]}")" \
                "$(csv_escape "$msg")"
        done
    } | gum table --separator "," --print --border rounded
    printf '\n%sSummary:%s %d OK, %d WARN, %d FAIL, %d SKIPPED\n' \
        "$C_BOLD" "$C_RESET" "$OK" "$WARN" "$FAIL" "$SKIPPED"
else
    printf '\n%sSummary:%s %d OK, %d WARN, %d FAIL, %d SKIPPED\n' \
        "$C_BOLD" "$C_RESET" "$OK" "$WARN" "$FAIL" "$SKIPPED"
fi

((FAIL == 0)) || exit 1
