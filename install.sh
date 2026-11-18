#!/usr/bin/env bash
# Interactive dotfiles installer.
#
# Safety model:
#   * every replaced file is backed up under ~/.dotfiles-backup/<timestamp>/
#   * --dry-run prints actions without touching anything
#   * /etc files are installed only with --system, one file at a time
#   * grub/mkinitcpio/autologin always need an explicit confirmation
#   * no service is restarted and no bootloader/initramfs is regenerated
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L $SOURCE ]]; do
    dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$dir/$SOURCE"
done
DOTFILES_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
export DOTFILES_DIR

DRY_RUN=0
ASSUME_YES=0
ALL=0
DO_PACKAGES=1
DO_SYSTEM=0
DO_MOUSE=0
DO_MONITORS=0
DO_DOCK=0
DOCK_LAYOUT_ARG=""
DO_CURSOR=0
DO_KERNEL=0
LIST_ONLY=0
MODULES_ARG=""
HOST_ARG=""
GPU_ARG=""
CURSOR_ARCHIVE_ARG=""
CURSOR_THEME_ARG=""
CURSOR_SIZE_ARG=""
WALLPAPER_ARG=""
DO_WALLPAPER=0
DO_HOOKS=0
DO_DOCTOR=0
DO_JSON=0
DO_DNS_CHECK=0
DO_RESTORE=0
RESTORE_DATE=""
DO_SYNC=0
SYNC_COMMAND=""
SYNC_TARGET=""
IFACE_ARG=""
AUTOLOGIN_USER_ARG=""
KERNEL_LEVEL_ARG=""
CATEGORY_ARG=""
APPS_ARG=""
PACKAGES_ARG=""
ONLY_PACKAGES=0
DO_THEME=0
DO_THEME_MENU=0
AUTOSTART_ACTION=""
GAMEMODE_ACTION=""
IDLE_ACTION=""
LID_ACTION=""
BINDS_MODE=""
MONITOR_PROFILES_ACTION=""
PKG_SYNC_ACTION=""
SYSTEM_COMPONENTS_ARG=""
HAS_ACTION=0

# Load helpers before parsing so die() is available for bad options.
# shellcheck source=lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=lib/tui.sh
source "$DOTFILES_DIR/lib/tui.sh"
# shellcheck source=lib/monitors.sh
source "$DOTFILES_DIR/lib/monitors.sh"
# shellcheck source=lib/dock.sh
source "$DOTFILES_DIR/lib/dock.sh"
# shellcheck source=lib/packages.sh
source "$DOTFILES_DIR/lib/packages.sh"
# shellcheck source=lib/system.sh
source "$DOTFILES_DIR/lib/system.sh"
# shellcheck source=lib/cursor.sh
source "$DOTFILES_DIR/lib/cursor.sh"
# shellcheck source=lib/kernel.sh
source "$DOTFILES_DIR/lib/kernel.sh"
# shellcheck source=lib/wallpaper.sh
source "$DOTFILES_DIR/lib/wallpaper.sh"
# shellcheck source=lib/restore.sh
source "$DOTFILES_DIR/lib/restore.sh"
# shellcheck source=lib/theme.sh
source "$DOTFILES_DIR/lib/theme.sh"
# shellcheck source=lib/menu.sh
source "$DOTFILES_DIR/lib/menu.sh"

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Without options (and with a terminal) the main menu opens. Every menu action
has a flag below, so the same work can be scripted.

Installation:
  --all                 select every module and the default packages
  --modules a,b,c       install only these modules
  --category a,b        install only these package categories
  --apps a,b            add specific packages on top of the categories
  --packages a,b        install exactly these packages (no app picker)
  --no-packages         skip package installation
  --only-packages       install packages without touching configuration files
  --host desktop|laptop override host detection
  --gpu PROFILE         nvidia|amd|intel|hybrid|vm|software

Settings:
  --monitors            reconfigure monitor layout and exit
  --dock-layout LAYOUT  store right|left|mirror|ask for external monitors
  --mouse               run the mouse/touchpad tuner
  --cursor              install/configure the cursor theme and exit
  --cursor-archive PATH install a cursor theme from a local archive (not committed)
  --cursor-theme NAME   cursor theme name (default: host cursor.conf)
  --cursor-size N       cursor size 16..128 (default: 24)
  --wallpaper PATH      store the wallpaper path and optionally apply it
  --theme               regenerate colours from the current wallpaper (matugen)
  --theme-menu          wallpaper/mode/scheme menu
  --autostart ACTION    list|enable|disable|toggle|add|remove|reset|run|pick
  --gamemode ACTION     on|off|toggle|status
  --idle ACTION         apply|set|configure|watch|status
  --lid ACTION          closed|open|status
  --binds [MODE]        keybind cheatsheet: plain, rofi or json
  --monitor-profiles ACTION
                        apply|watch|status

System (/etc, run the write actions with sudo):
  --system              install opt-in /etc files one by one
  --system-components a,b
                        dns|zram|cpupower|services|pacman|grub|ram
                        (default: every component)
  --iface IFACE         network interface for Pi-hole (@IFACE@ rendering)
  --autologin-user USER user for the getty autologin drop-in (with --system)

Kernel:
  --kernel              detect the CPU level and install a matching kernel
  --kernel-level LEVEL  override the kernel level: v1, v2, v3 or v4
                        (above-CPU levels require typing I UNDERSTAND)

Maintenance:
  --doctor              read-only health check and exit (never needs sudo)
  --json                machine-readable output (use with --doctor/--dns-check)
  --dns-check           read-only DNS chain check and exit
  --restore [date]      list backups and restore one from ~/.dotfiles-backup
                        (combine with --modules a,b; /etc needs --system)
  --sync COMMAND [target]
                        status|diff|pull to copy live changes back, or
                        packages to compare package lists
  --pkg-sync ACTION     status|check|pull package drift
  --hooks               install the repository pre-commit hook and exit

Other:
  --dry-run             show what would happen, change nothing
  --yes, -y             answer "yes" to confirmations
  --list                list modules, GPU profiles and package categories
  -h, --help            this help

Examples:
  ./install.sh --dry-run --all
  ./install.sh --modules hypr,waybar,rofi --gpu nvidia
  ./install.sh --only-packages --category Terminal,Office --apps foot
  sudo ./install.sh --system --system-components dns
  ./install.sh --mouse
EOF
}

while (($#)); do
    case "$1" in
        --all)        ALL=1; HAS_ACTION=1 ;;
        --dry-run)    DRY_RUN=1 ;;
        --yes|-y)     ASSUME_YES=1 ;;
        --no-packages) DO_PACKAGES=0; HAS_ACTION=1 ;;
        --only-packages) ONLY_PACKAGES=1; HAS_ACTION=1 ;;
        --modules)    MODULES_ARG="${2:?missing value for --modules}"; HAS_ACTION=1; shift ;;
        --category)   CATEGORY_ARG="${2:?missing value for --category}"; HAS_ACTION=1; shift ;;
        --apps)       APPS_ARG="${2:?missing value for --apps}"; HAS_ACTION=1; shift ;;
        --packages)   PACKAGES_ARG="${2:?missing value for --packages}"; HAS_ACTION=1; shift ;;
        --host)       HOST_ARG="${2:?missing value for --host}"; shift ;;
        --gpu)        GPU_ARG="${2:?missing value for --gpu}"; shift ;;
        --monitors)   DO_MONITORS=1; HAS_ACTION=1 ;;
        --dock-layout) DO_DOCK=1; DOCK_LAYOUT_ARG="${2:?missing value for --dock-layout}"; HAS_ACTION=1; shift ;;
        --mouse)      DO_MOUSE=1; HAS_ACTION=1 ;;
        --cursor)     DO_CURSOR=1; HAS_ACTION=1 ;;
        --cursor-archive) CURSOR_ARCHIVE_ARG="${2:?missing value for --cursor-archive}"; DO_CURSOR=1; HAS_ACTION=1; shift ;;
        --cursor-theme)   CURSOR_THEME_ARG="${2:?missing value for --cursor-theme}"; DO_CURSOR=1; HAS_ACTION=1; shift ;;
        --cursor-size)    CURSOR_SIZE_ARG="${2:?missing value for --cursor-size}"; DO_CURSOR=1; HAS_ACTION=1; shift ;;
        --wallpaper)  WALLPAPER_ARG="${2:?missing value for --wallpaper}"; DO_WALLPAPER=1; HAS_ACTION=1; shift ;;
        --theme)      DO_THEME=1; HAS_ACTION=1 ;;
        --theme-menu) DO_THEME_MENU=1; HAS_ACTION=1 ;;
        --autostart)  AUTOSTART_ACTION="${2:?missing value for --autostart}"; HAS_ACTION=1; shift ;;
        --gamemode)   GAMEMODE_ACTION="${2:?missing value for --gamemode}"; HAS_ACTION=1; shift ;;
        --idle)       IDLE_ACTION="${2:?missing value for --idle}"; HAS_ACTION=1; shift ;;
        --lid)        LID_ACTION="${2:?missing value for --lid}"; HAS_ACTION=1; shift ;;
        --binds)
            BINDS_MODE="plain"
            HAS_ACTION=1
            if [[ -n ${2:-} && ${2} != -* ]]; then
                BINDS_MODE="$2"
                shift
            fi
            ;;
        --monitor-profiles) MONITOR_PROFILES_ACTION="${2:?missing value for --monitor-profiles}"; HAS_ACTION=1; shift ;;
        --pkg-sync)   PKG_SYNC_ACTION="${2:?missing value for --pkg-sync}"; HAS_ACTION=1; shift ;;
        --system)     DO_SYSTEM=1; HAS_ACTION=1 ;;
        --system-components) SYSTEM_COMPONENTS_ARG="${2:?missing value for --system-components}"; shift ;;
        --iface)      IFACE_ARG="${2:?missing value for --iface}"; shift ;;
        --autologin-user) AUTOLOGIN_USER_ARG="${2:?missing value for --autologin-user}"; shift ;;
        --kernel)     DO_KERNEL=1; HAS_ACTION=1 ;;
        --kernel-level) KERNEL_LEVEL_ARG="${2:?missing value for --kernel-level}"; shift ;;
        --hooks)      DO_HOOKS=1; HAS_ACTION=1 ;;
        --doctor)     DO_DOCTOR=1; HAS_ACTION=1 ;;
        --json)       DO_JSON=1 ;;
        --dns-check)  DO_DNS_CHECK=1; HAS_ACTION=1 ;;
        --restore)
            DO_RESTORE=1
            HAS_ACTION=1
            if [[ -n ${2:-} && ${2} != -* ]]; then
                RESTORE_DATE="$2"
                shift
            fi
            ;;
        --sync)
            DO_SYNC=1
            HAS_ACTION=1
            SYNC_COMMAND="${2:?missing command for --sync}"
            shift
            if [[ -n ${2:-} && ${2} != -* ]]; then
                SYNC_TARGET="$2"
                shift
            fi
            ;;
        --list)       LIST_ONLY=1; HAS_ACTION=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

if [[ -n $AUTOLOGIN_USER_ARG && $DO_SYSTEM -eq 0 ]]; then
    die "--autologin-user requires --system"
fi
if [[ -n $SYSTEM_COMPONENTS_ARG && $DO_SYSTEM -eq 0 ]]; then
    die "--system-components requires --system"
fi
if (( ONLY_PACKAGES && !DO_PACKAGES )); then
    die "--only-packages and --no-packages are mutually exclusive"
fi
if (( ONLY_PACKAGES )); then
    DO_PACKAGES=1
fi
if [[ -n $SYSTEM_COMPONENTS_ARG ]]; then
    IFS=',' read -r -a SYSTEM_COMPONENTS <<<"$SYSTEM_COMPONENTS_ARG"
    for component in "${SYSTEM_COMPONENTS[@]}"; do
        case "$component" in
            dns|zram|cpupower|services|pacman|grub|ram) ;;
            *) die "unknown system component: $component (dns, zram, cpupower, services, pacman, grub, ram)" ;;
        esac
    done
fi

REAL_HOME="$(real_home)"
[[ -n $REAL_HOME ]] || die "cannot determine home directory"

TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
BACKUP_DIR="$REAL_HOME/.dotfiles-backup/$TIMESTAMP"
STATE_DIR="${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles"
STATE_FILE="$STATE_DIR/managed.tsv"

if (( DRY_RUN )); then
    LOG_FILE="$(mktemp)"
else
    mkdir -p "$STATE_DIR"
    LOG_FILE="$STATE_DIR/install-$TIMESTAMP.log"
    mkdir -p "$BACKUP_DIR"
    printf 'target\tbackup\n' >"$BACKUP_DIR/manifest.tsv"
fi

HOST_NAME="${HOST_ARG:-$(detect_host_type)}"
GPU_PROFILE="${GPU_ARG:-$(detect_gpu_profile)}"

CONTROL_CENTER_BIND="SUPER + Space"
if [[ -r $DOTFILES_DIR/hosts/$HOST_NAME/control-center.conf ]]; then
    # shellcheck source=/dev/null
    source "$DOTFILES_DIR/hosts/$HOST_NAME/control-center.conf"
fi

UI_FONT="Inter"
UI_SIZE=11
MONO_FONT="JetBrainsMono Nerd Font"
MONO_SIZE=11
ICON_THEME="breeze-dark"
GTK_THEME_DARK="adw-gtk3-dark"
GTK_THEME_LIGHT="adw-gtk3"
if [[ -r $DOTFILES_DIR/hosts/$HOST_NAME/appearance.conf ]]; then
    # shellcheck source=/dev/null
    source "$DOTFILES_DIR/hosts/$HOST_NAME/appearance.conf"
fi

THEME_MODE=dark
if [[ -r $STATE_DIR/theme.conf ]]; then
    while IFS='=' read -r key value; do
        [[ $key == mode ]] && THEME_MODE="$value"
    done <"$STATE_DIR/theme.conf"
fi
GTK_THEME="$GTK_THEME_DARK"
[[ $THEME_MODE == light ]] && GTK_THEME="$GTK_THEME_LIGHT"

QT_UI_FONT5="$UI_FONT,$UI_SIZE,-1,5,50,0,0,0,0,0"
QT_MONO_FONT5="$MONO_FONT,$MONO_SIZE,-1,5,50,0,0,0,0,0"
QT_UI_FONT6="$UI_FONT,$UI_SIZE,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
QT_MONO_FONT6="$MONO_FONT,$MONO_SIZE,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"

if (( DO_KERNEL )); then
    install_kernel
    exit 0
fi

if (( DO_WALLPAPER )); then
    set_wallpaper "$WALLPAPER_ARG"
    exit 0
fi

list_all() {
    printf '%s\n' "Modules:"
    local dir name desc
    for dir in "$DOTFILES_DIR"/modules/*/; do
        name="$(basename "$dir")"
        desc=""
        if [[ -r $dir/module.conf ]]; then
            # shellcheck source=/dev/null
            desc="$(source "$dir/module.conf" 2>/dev/null; printf '%s' "${DESCRIPTION:-}")"
        fi
        printf '  %-20s %s\n' "$name" "$desc"
    done
    printf '\nGPU profiles:\n'
    for dir in "$DOTFILES_DIR"/profiles/gpu/*/; do
        printf '  %s\n' "$(basename "$dir")"
    done
    printf '\nPackage categories:\n'
    local category
    while IFS= read -r category; do
        printf '  %-20s %s packages\n' "$category" "$(catalog_category_count "$category")"
    done < <(catalog_categories)
}

if (( LIST_ONLY )); then
    list_all
    exit 0
fi

if (( DO_JSON && !DO_DOCTOR && !DO_DNS_CHECK )); then
    die "--json requires --doctor or --dns-check"
fi

# No action flags and a terminal: open the main menu. Without a TTY the old
# non-interactive flow below stays in charge.
if menu_should_run; then
    menu_main
    exit 0
fi

if (( DO_DOCTOR )); then
    doctor_args=()
    (( DO_JSON )) && doctor_args+=(--json)
    exec bash "$DOTFILES_DIR/scripts/doctor.sh" "${doctor_args[@]}"
fi

if (( DO_DNS_CHECK )); then
    dns_args=()
    (( DO_JSON )) && dns_args+=(--json)
    exec bash "$DOTFILES_DIR/scripts/dns-check.sh" "${dns_args[@]}"
fi

if (( DO_RESTORE )); then
    restore_run "$RESTORE_DATE" "$MODULES_ARG"
    exit $?
fi

if (( DO_SYNC )); then
    sync_args=("$SYNC_COMMAND")
    [[ -n $SYNC_TARGET ]] && sync_args+=("$SYNC_TARGET")
    (( DRY_RUN )) && sync_args+=(--dry-run)
    (( ASSUME_YES )) && sync_args+=(--yes)
    exec bash "$DOTFILES_DIR/scripts/sync.sh" "${sync_args[@]}"
fi

if (( DO_HOOKS )); then
    hook_args=()
    (( DRY_RUN )) && hook_args+=(--dry-run)
    exec bash "$DOTFILES_DIR/scripts/install-hooks.sh" "${hook_args[@]}"
fi

if [[ -n $BINDS_MODE ]]; then
    binds_args=()
    case "$BINDS_MODE" in
        plain) ;;
        rofi)  binds_args+=(--rofi) ;;
        json)  binds_args+=(--json) ;;
        *)     die "unknown binds mode: $BINDS_MODE (plain, rofi, json)" ;;
    esac
    exec bash "$DOTFILES_DIR/modules/binds-cheatsheet/home/.local/bin/binds-cheatsheet.sh" "${binds_args[@]}"
fi

if [[ -n $MONITOR_PROFILES_ACTION ]]; then
    profiles_args=("$MONITOR_PROFILES_ACTION")
    (( DRY_RUN )) && profiles_args+=(--dry-run)
    exec bash "$DOTFILES_DIR/modules/monitor-profiles/home/.local/bin/monitor-profiles.sh" "${profiles_args[@]}"
fi

if [[ -n $PKG_SYNC_ACTION ]]; then
    pkg_sync_args=("$PKG_SYNC_ACTION")
    (( DRY_RUN )) && pkg_sync_args+=(--dry-run)
    (( ASSUME_YES )) && pkg_sync_args+=(--yes)
    exec bash "$DOTFILES_DIR/scripts/pkg-sync.sh" "${pkg_sync_args[@]}"
fi

if (( DO_THEME )); then
    generate_theme
    exit 0
fi

if (( DO_THEME_MENU )); then
    theme_menu_args=()
    (( DRY_RUN )) && theme_menu_args+=(--dry-run)
    exec bash "$DOTFILES_DIR/modules/theme-menu/home/.local/bin/theme-menu.sh" "${theme_menu_args[@]}"
fi

if [[ -n $AUTOSTART_ACTION ]]; then
    autostart_args=("$AUTOSTART_ACTION")
    (( DRY_RUN )) && autostart_args+=(--dry-run)
    exec bash "$DOTFILES_DIR/modules/autostart/home/.local/bin/autostart.sh" "${autostart_args[@]}"
fi

if [[ -n $GAMEMODE_ACTION ]]; then
    gamemode_args=("$GAMEMODE_ACTION")
    (( DRY_RUN )) && gamemode_args+=(--dry-run)
    exec bash "$DOTFILES_DIR/modules/gamemode/home/.local/bin/gamemode.sh" "${gamemode_args[@]}"
fi

if [[ -n $IDLE_ACTION ]]; then
    idle_args=("$IDLE_ACTION")
    (( DRY_RUN )) && idle_args+=(--dry-run)
    exec bash "$DOTFILES_DIR/modules/idle/home/.local/bin/idle-tune.sh" "${idle_args[@]}"
fi

if [[ -n $LID_ACTION ]]; then
    lid_args=("$LID_ACTION")
    (( DRY_RUN )) && lid_args+=(--dry-run)
    exec bash "$DOTFILES_DIR/modules/lid/home/.local/bin/lid-handler.sh" "${lid_args[@]}"
fi

if (( DO_SYSTEM )); then
    kernel_report
    printf '\n'
    install_system_configs
    exit 0
fi

if (( DO_MOUSE )); then
    exec bash "$DOTFILES_DIR/modules/mouse-sensitivity/home/.local/bin/mouse-tune.sh" --repo "$DOTFILES_DIR"
fi

if (( DO_DOCK )); then
    write_dock_layout "$DOCK_LAYOUT_ARG"
    exit $?
fi

if (( DO_MONITORS )); then
    configure_monitors
    configure_dock_layout
    exit 0
fi

if (( DO_CURSOR )) && [[ -z $MODULES_ARG ]]; then
    MODULES_ARG="cursor"
    DO_PACKAGES=0
fi

info "host: $HOST_NAME   gpu: $GPU_PROFILE   repo: $DOTFILES_DIR"
menu_prerequisite_hint

if [[ ! -d $DOTFILES_DIR/hosts/$HOST_NAME ]]; then
    die "unknown host profile: $HOST_NAME (expected hosts/desktop or hosts/laptop)"
fi
if [[ ! -d $DOTFILES_DIR/profiles/gpu/$GPU_PROFILE ]]; then
    die "unknown GPU profile: $GPU_PROFILE"
fi

load_cursor_conf

if (( !ASSUME_YES )) && [[ -t 0 ]]; then
    if [[ -z $HOST_ARG ]]; then
        HOST_NAME="$(tui_radio "Host profile" "desktop" "laptop")" || die "host selection cancelled"
    fi
    if [[ -z $GPU_ARG ]]; then
        GPU_PROFILE="$(tui_radio "GPU profile" nvidia amd intel hybrid vm software)" || die "GPU selection cancelled"
    fi
    info "selected host: $HOST_NAME   gpu: $GPU_PROFILE"
fi

MODULES=()

load_module_conf() {
    DESCRIPTION=""
    PACKAGES=()
    SERVICES=()
    REQUIRES=()
    SYMLINKS=()
    # shellcheck source=/dev/null
    source "$1"
}

module_list() {
    local dir
    for dir in "$DOTFILES_DIR"/modules/*/; do
        [[ -r $dir/module.conf ]] || continue
        basename "$dir"
    done
}

monitor_count() {
    detect_monitors | wc -l
}

select_modules() {
    local required=() labels=() required_labels=()
    local dir name desc count monitors optional label
    monitors="$(monitor_count)"

    for dir in "$DOTFILES_DIR"/modules/*/; do
        name="$(basename "$dir")"
        [[ -r $dir/module.conf ]] || continue
        [[ $name == lid && ${HOST_NAME:-} != laptop ]] && continue
        if [[ $name == workspaces-split ]] && (( monitors < 2 )); then
            continue
        fi
        load_module_conf "$dir/module.conf"
        count="${#PACKAGES[@]}"
        optional=0
        case "$name" in
            idle|lid|ram-cache) optional=1 ;;
        esac
        label="$name — ${DESCRIPTION:-} (${count} pkgs)"
        ((optional)) && label+=" [optional]"
        labels+=("$label")
        if ((!optional)); then
            required+=("$name")
            required_labels+=("$label")
        fi
    done

    if [[ -n $MODULES_ARG ]]; then
        IFS=',' read -r -a MODULES <<<"$MODULES_ARG"
        return 0
    fi

    if (( ALL )); then
        MODULES=("${required[@]}")
        return 0
    fi

    if (( !ASSUME_YES )) && [[ -t 0 ]]; then
        TUI_CHECKED_ITEMS=("${required_labels[@]}")
        tui_checklist "Modules to install" "${labels[@]}"
        local line
        for line in "${TUI_SELECTION[@]}"; do
            MODULES+=("${line%% — *}")
        done
    else
        MODULES=("${required[@]}")
    fi
}

firefox_profile_dir() {
    local candidate
    for candidate in "$REAL_HOME"/.config/mozilla/firefox/*.default-release; do
        if [[ -d $candidate ]]; then
            basename "$candidate"
            return 0
        fi
    done
    printf 'default-release\n'
}

obsidian_vault() {
    local candidate
    for candidate in "$REAL_HOME"/Obsidian/*/; do
        if [[ -d $candidate ]]; then
            basename "$candidate"
            return 0
        fi
    done
    printf 'Obsidian\n'
}

install_module_files() {
    local name="$1"
    local root="$DOTFILES_DIR/modules/$name/home"
    local src rel dst

    [[ -d $root ]] || return 0

    while IFS= read -r src; do
        rel="${src#"$root"/}"
        local templated=0
        if [[ $rel == *@FIREFOX_PROFILE_DIR@* || $rel == *@OBSIDIAN_VAULT@* ]]; then
            templated=1
        fi
        rel="${rel//@FIREFOX_PROFILE_DIR@/$(firefox_profile_dir)}"
        rel="${rel//@OBSIDIAN_VAULT@/$(obsidian_vault)}"
        if [[ $rel == *.in ]]; then
            dst="$REAL_HOME/${rel%.in}"
            render_template "$src" "$dst"
        elif (( templated )); then
            dst="$REAL_HOME/$rel"
            copy_file "$src" "$dst" 0644
        else
            dst="$REAL_HOME/$rel"
            link_path "$src" "$dst"
        fi
    done < <(find "$root" -type f | sort)

    load_module_conf "$DOTFILES_DIR/modules/$name/module.conf"
    local entry link target
    for entry in "${SYMLINKS[@]:-}"; do
        [[ -n $entry ]] || continue
        link="${entry%%:*}"
        target="${entry#*:}"
        if [[ -e $target ]]; then
            link_path "$target" "$REAL_HOME/$link"
        else
            warn "skipping symlink $REAL_HOME/$link: target missing ($target)"
        fi
    done
}

render_template() {
    local src="$1" dst="$2"
    local content tmp
    content="$(<"$src")"

    content="${content//@HOME@/$REAL_HOME}"
    content="${content//@FIREFOX_PROFILE_DIR@/$(firefox_profile_dir)}"
    content="${content//@OBSIDIAN_VAULT@/$(obsidian_vault)}"
    content="${content//@CURSOR_THEME@/$CURSOR_THEME}"
    content="${content//@CURSOR_SIZE@/$CURSOR_SIZE}"
    content="${content//@CONTROL_CENTER_BIND@/$CONTROL_CENTER_BIND}"
    content="${content//@UI_FONT@/$UI_FONT}"
    content="${content//@UI_SIZE@/$UI_SIZE}"
    content="${content//@MONO_FONT@/$MONO_FONT}"
    content="${content//@MONO_SIZE@/$MONO_SIZE}"
    content="${content//@ICON_THEME@/$ICON_THEME}"
    content="${content//@GTK_THEME@/$GTK_THEME}"
    content="${content//@QT_UI_FONT5@/$QT_UI_FONT5}"
    content="${content//@QT_MONO_FONT5@/$QT_MONO_FONT5}"
    content="${content//@QT_UI_FONT6@/$QT_UI_FONT6}"
    content="${content//@QT_MONO_FONT6@/$QT_MONO_FONT6}"

    tmp="$(mktemp)"
    printf '%s\n' "$content" >"$tmp"
    copy_file "$tmp" "$dst" 0644
    rm -f -- "$tmp"
}

render_uwsm() {
    local profile_env="$DOTFILES_DIR/profiles/gpu/$GPU_PROFILE/env"
    local module="$DOTFILES_DIR/modules/uwsm"
    local tmp

    [[ -r $profile_env ]] || die "missing GPU profile: $profile_env"

    tmp="$(mktemp)"
    {
        printf '# Generated by install.sh: uwsm env for GPU profile %s.\n' "$GPU_PROFILE"
        printf '# Source of truth: modules/uwsm/env.common + profiles/gpu/%s/env\n\n' "$GPU_PROFILE"
        cat -- "$module/env.common"
        printf '\n'
        cat -- "$profile_env"
        printf '\n# === Cursor ===\n'
        printf 'export XCURSOR_THEME="%s"\n' "$CURSOR_THEME"
        printf 'export XCURSOR_SIZE=%s\n' "$CURSOR_SIZE"
    } >"$tmp"
    copy_file "$tmp" "$REAL_HOME/.config/uwsm/env" 0644

    local host_hypr="$DOTFILES_DIR/hosts/$HOST_NAME/env-hyprland"
    {
        printf '# Generated by install.sh: Hyprland-only environment.\n\n'
        cat -- "$module/env-hyprland.common"
        if [[ -r $host_hypr ]]; then
            printf '\n'
            cat -- "$host_hypr"
        fi
        if [[ -r $REAL_HOME/.config/uwsm/env-hyprland.local ]]; then
            printf '\n'
            cat -- "$REAL_HOME/.config/uwsm/env-hyprland.local"
        fi
    } >"$tmp"
    copy_file "$tmp" "$REAL_HOME/.config/uwsm/env-hyprland" 0644
    rm -f -- "$tmp"
}

install_selected_modules() {
    local name

    # Cursor settings must be written before uwsm/theming render their templates.
    if [[ " ${MODULES[*]} " == *" cursor "* ]]; then
        install_cursor
    fi

    for name in "${MODULES[@]}"; do
        if [[ ! -d $DOTFILES_DIR/modules/$name ]]; then
            die "unknown module: $name"
        fi
        info "module: $name"
        install_module_files "$name"
        case "$name" in
            hypr)      render_monitors ;;
            uwsm)      render_uwsm ;;
            mouse-sensitivity)
                copy_file "$DOTFILES_DIR/hosts/$HOST_NAME/input.lua" "$REAL_HOME/.config/hypr/input.lua" 0644
                ;;
        esac
    done
}

enable_services() {
    local name service labels=()

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        info "skipping service selection (non-interactive)"
        return 0
    fi

    for name in "${MODULES[@]}"; do
        load_module_conf "$DOTFILES_DIR/modules/$name/module.conf"
        for service in "${SERVICES[@]:-}"; do
            [[ -n $service ]] || continue
            labels+=("$name: $service")
        done
    done

    ((${#labels[@]})) || return 0

    local picked=()
    tui_checklist "User services to enable (not started)" "${labels[@]}"
    local line
    for line in "${TUI_SELECTION[@]}"; do
        picked+=("${line#*: }")
    done

    ((${#picked[@]})) || { info "no services selected"; return 0; }

    if ! tui_confirm "Enable ${#picked[@]} user service(s)?" no; then
        warn "services not enabled"
        return 0
    fi

    for service in "${picked[@]}"; do
        run systemctl --user enable "$service"
    done
}

if (( ONLY_PACKAGES )); then
    info "packages only; configuration modules are skipped"
else
    select_modules
    if ((${#MODULES[@]} == 0)); then
        die "no modules selected"
    fi

    # Resolve module dependencies (REQUIRES=... in module.conf).
    for name in "${MODULES[@]}"; do
        load_module_conf "$DOTFILES_DIR/modules/$name/module.conf"
        for req in "${REQUIRES[@]:-}"; do
            [[ -n $req ]] || continue
            if [[ " ${MODULES[*]} " != *" $req "* ]]; then
                MODULES+=("$req")
            fi
        done
    done

    # hypr is the base for workspace/mouse modules.
    for name in workspaces-split mouse-sensitivity; do
        if [[ " ${MODULES[*]} " == *" $name "* && " ${MODULES[*]} " != *" hypr "* ]]; then
            MODULES+=(hypr)
        fi
    done

    maybe_create_snapshot
    install_selected_modules
fi

if (( DO_PACKAGES )); then
    select_categories
    select_apps

    # A selected module carries its own package requirements. This keeps
    # --modules ram-cache (or idle) useful without a second package pick.
    for name in "${MODULES[@]}"; do
        load_module_conf "$DOTFILES_DIR/modules/$name/module.conf"
        for pkg in "${PACKAGES[@]:-}"; do
            [[ -n $pkg ]] || continue
            if ! printf '%s\n' "${SELECTED_APPLICATIONS[@]:-}" | grep -Fxq -- "$pkg"; then
                SELECTED_APPLICATIONS+=("$pkg")
            fi
        done
    done

    install_packages
fi

if (( !DRY_RUN )); then
    enable_services
fi

printf '\n'
info "Done."
if (( DRY_RUN )); then
    info "dry-run log: $LOG_FILE"
else
    info "backup: $BACKUP_DIR"
    info "log:    $LOG_FILE"
    printf '\nNext steps:\n'
    printf '  ./install.sh            # main menu for anything else\n'
    printf '  ./install.sh --theme    # regenerate matugen colours\n'
    printf '  ./install.sh --doctor   # read-only health check\n'
fi
