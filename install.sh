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
IFACE_ARG=""
KERNEL_LEVEL_ARG=""

# Load helpers before parsing so die() is available for bad options.
# shellcheck source=lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=lib/tui.sh
source "$DOTFILES_DIR/lib/tui.sh"
# shellcheck source=lib/monitors.sh
source "$DOTFILES_DIR/lib/monitors.sh"
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

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Modes:
  (no options)          interactive install
  --all                 select every module and package group
  --dry-run             show what would happen, change nothing
  --yes                 answer "yes" to confirmations
  --modules a,b,c       install only these modules
  --no-packages         skip package installation
  --host desktop|laptop override host detection
  --gpu PROFILE         nvidia|amd|intel|hybrid|vm|software
  --monitors            reconfigure monitor layout and exit
  --mouse               run the mouse/touchpad tuner
  --cursor              install/configure the cursor theme and exit
  --cursor-archive PATH install a cursor theme from a local archive (not committed)
  --cursor-theme NAME   cursor theme name (default: host cursor.conf)
  --cursor-size N       cursor size 16..128 (default: 24)
  --wallpaper PATH      store the wallpaper path and optionally apply it
  --system              install opt-in /etc files (run with sudo)
  --iface IFACE         network interface for Pi-hole (@IFACE@ rendering)
  --kernel              detect the CPU level and install a matching kernel
  --kernel-level LEVEL  override the kernel level: v1, v2, v3 or v4
                        (above-CPU levels require typing I UNDERSTAND)
  --hooks               install the repository pre-commit hook and exit
  --doctor              read-only health check and exit (never needs sudo)
  --json                machine-readable output (use with --doctor)
  --list                list modules, GPU profiles and package groups
  -h, --help            this help

Examples:
  ./install.sh --dry-run --all
  ./install.sh --modules hypr,waybar,rofi --gpu nvidia
  sudo ./install.sh --system
  ./install.sh --mouse
EOF
}

while (($#)); do
    case "$1" in
        --all)        ALL=1 ;;
        --dry-run)    DRY_RUN=1 ;;
        --yes|-y)     ASSUME_YES=1 ;;
        --no-packages) DO_PACKAGES=0 ;;
        --modules)    MODULES_ARG="${2:?missing value for --modules}"; shift ;;
        --host)       HOST_ARG="${2:?missing value for --host}"; shift ;;
        --gpu)        GPU_ARG="${2:?missing value for --gpu}"; shift ;;
        --monitors)   DO_MONITORS=1 ;;
        --mouse)      DO_MOUSE=1 ;;
        --cursor)     DO_CURSOR=1 ;;
        --cursor-archive) CURSOR_ARCHIVE_ARG="${2:?missing value for --cursor-archive}"; DO_CURSOR=1; shift ;;
        --cursor-theme)   CURSOR_THEME_ARG="${2:?missing value for --cursor-theme}"; DO_CURSOR=1; shift ;;
        --cursor-size)    CURSOR_SIZE_ARG="${2:?missing value for --cursor-size}"; DO_CURSOR=1; shift ;;
        --wallpaper)  WALLPAPER_ARG="${2:?missing value for --wallpaper}"; DO_WALLPAPER=1; shift ;;
        --system)     DO_SYSTEM=1 ;;
        --iface)      IFACE_ARG="${2:?missing value for --iface}"; shift ;;
        --kernel)     DO_KERNEL=1 ;;
        --kernel-level) KERNEL_LEVEL_ARG="${2:?missing value for --kernel-level}"; shift ;;
        --hooks)      DO_HOOKS=1 ;;
        --doctor)     DO_DOCTOR=1 ;;
        --json)       DO_JSON=1 ;;
        --list)       LIST_ONLY=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

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
    printf '\nPackage groups:\n'
    local files=() file
    mapfile -t files < <(category_files)
    for file in "${files[@]}"; do
        printf '  %-20s %s packages\n' "$file" "$(category_count "$file")"
    done
}

if (( LIST_ONLY )); then
    list_all
    exit 0
fi

if (( DO_JSON && !DO_DOCTOR )); then
    die "--json requires --doctor"
fi

if (( DO_DOCTOR )); then
    doctor_args=()
    (( DO_JSON )) && doctor_args+=(--json)
    exec bash "$DOTFILES_DIR/scripts/doctor.sh" "${doctor_args[@]}"
fi

if (( DO_HOOKS )); then
    hook_args=()
    (( DRY_RUN )) && hook_args+=(--dry-run)
    exec bash "$DOTFILES_DIR/scripts/install-hooks.sh" "${hook_args[@]}"
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

if (( DO_MONITORS )); then
    configure_monitors
    exit 0
fi

if (( DO_CURSOR )) && [[ -z $MODULES_ARG ]]; then
    MODULES_ARG="cursor"
    DO_PACKAGES=0
fi

info "host: $HOST_NAME   gpu: $GPU_PROFILE   repo: $DOTFILES_DIR"

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
    local available=() labels=() dir name desc count
    local monitors
    monitors="$(monitor_count)"

    for dir in "$DOTFILES_DIR"/modules/*/; do
        name="$(basename "$dir")"
        [[ -r $dir/module.conf ]] || continue
        if [[ $name == workspaces-split ]] && (( monitors < 2 )); then
            continue
        fi
        load_module_conf "$dir/module.conf"
        count="${#PACKAGES[@]}"
        labels+=("$name — ${DESCRIPTION:-} (${count} pkgs)")
        available+=("$name")
    done

    if [[ -n $MODULES_ARG ]]; then
        IFS=',' read -r -a MODULES <<<"$MODULES_ARG"
        return 0
    fi

    if (( ALL )); then
        MODULES=("${available[@]}")
        return 0
    fi

    if (( !ASSUME_YES )) && [[ -t 0 ]]; then
        tui_checklist "Modules to install" "${labels[@]}"
        local line
        for line in "${TUI_SELECTION[@]}"; do
            MODULES+=("${line%% — *}")
        done
    else
        MODULES=("${available[@]}")
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

install_selected_modules

if (( DO_PACKAGES )); then
    select_categories
    select_alternatives
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
    printf '  make theme     # regenerate matugen colors\n'
    printf '  make audit     # read-only configuration audit\n'
    printf '  ./install.sh --mouse   # tune pointer sensitivity interactively\n'
fi
