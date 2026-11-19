#!/usr/bin/env bash
# Theme menu: wallpaper, matugen mode and color scheme in one place.
#
# Interactive menu order: rofi -> gum -> whiptail -> dialog -> plain bash.
# Non-interactive flags make the script testable and scriptable:
#   theme-menu.sh --wallpaper PATH --mode dark --type scheme-tonal-spot --apply
#
# State is stored outside the repository:
#   ~/.local/state/dotfiles/theme.conf
set -uo pipefail

REAL_HOME="${HOME:?HOME is not set}"
STATE_DIR="${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles"
STATE_FILE="$STATE_DIR/theme.conf"
MATUGEN_CONFIG="$REAL_HOME/.config/matugen/config.toml"

VALID_MODES=(dark light smart)
VALID_TYPES=(
    scheme-content
    scheme-expressive
    scheme-fidelity
    scheme-fruit-salad
    scheme-monochrome
    scheme-neutral
    scheme-rainbow
    scheme-tonal-spot
    scheme-vibrant
    scheme-smart
)

DRY_RUN=0
PRINT=0
LIST_TYPES=0
DO_APPLY=0
WALLPAPER_ONLY=0
ARG_WALLPAPER=""
ARG_MODE=""
ARG_TYPE=""
WALLPAPER=""
MODE=""
TYPE=""
STATE_DIRTY=0

usage() {
    cat <<'EOF'
Usage: theme-menu.sh [options]

Interactive:
  (no options)             open the menu

Non-interactive:
  --wallpaper PATH         record a wallpaper (must exist)
  --mode dark|light|smart  matugen mode
  --type TYPE              matugen color scheme type
  --apply                  regenerate colors and apply the wallpaper
  --wallpaper-only         apply the wallpaper without regenerating colors
  --print                  print the current settings and exit
  --list-types             print the supported matugen scheme types
  --dry-run                print commands, change nothing
  -h, --help               this help

State: ~/.local/state/dotfiles/theme.conf
EOF
}

die() { printf 'theme-menu: %s\n' "$*" >&2; exit 1; }
info() { printf ':: %s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

has() { command -v "$1" >/dev/null 2>&1; }

valid_mode() {
    local m
    for m in "${VALID_MODES[@]}"; do
        [[ $m == "$1" ]] && return 0
    done
    return 1
}

valid_type() {
    local t
    for t in "${VALID_TYPES[@]}"; do
        [[ $t == "$1" ]] && return 0
    done
    return 1
}

while (($#)); do
    case "$1" in
        --wallpaper)  ARG_WALLPAPER="${2:?missing value for --wallpaper}"; shift ;;
        --mode)       ARG_MODE="${2:?missing value for --mode}"; shift ;;
        --type)       ARG_TYPE="${2:?missing value for --type}"; shift ;;
        --apply)      DO_APPLY=1 ;;
        --wallpaper-only) WALLPAPER_ONLY=1 ;;
        --dry-run)    DRY_RUN=1 ;;
        --print)      PRINT=1 ;;
        --list-types) LIST_TYPES=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

if ((LIST_TYPES)); then
    printf '%s\n' "${VALID_TYPES[@]}"
    exit 0
fi

# ---------------------------------------------------------------- state -----

load_state() {
    local key value

    [[ -r $STATE_FILE ]] || return 0
    while IFS='=' read -r key value; do
        case "$key" in
            wallpaper) [[ -z $WALLPAPER ]] && WALLPAPER="$value" ;;
            mode)      [[ -z $MODE ]] && MODE="$value" ;;
            type)      [[ -z $TYPE ]] && TYPE="$value" ;;
        esac
    done <"$STATE_FILE"
}

wallpaper_from_hypr() {
    local state="$REAL_HOME/.config/hypr/wallpaper.path"
    local image=""

    if [[ -r $state ]]; then
        image="$(<"$state")"
    fi
    if [[ -z $image && -r $REAL_HOME/.config/hypr/colors.lua ]]; then
        image="$(awk -F'"' '/^[[:space:]]*image[[:space:]]*=/{print $2; exit}' \
            "$REAL_HOME/.config/hypr/colors.lua" 2>/dev/null || true)"
    fi
    printf '%s\n' "$image"
}

load_state

[[ -n $ARG_WALLPAPER ]] && { WALLPAPER="$ARG_WALLPAPER"; STATE_DIRTY=1; }
[[ -n $ARG_MODE ]] && { MODE="$ARG_MODE"; STATE_DIRTY=1; }
[[ -n $ARG_TYPE ]] && { TYPE="$ARG_TYPE"; STATE_DIRTY=1; }

if [[ -z $WALLPAPER ]]; then
    WALLPAPER="$(wallpaper_from_hypr)"
fi

MODE="${MODE:-dark}"
TYPE="${TYPE:-scheme-tonal-spot}"

valid_mode "$MODE" || die "invalid mode: $MODE (use dark, light or smart)"
valid_type "$TYPE" || die "invalid scheme type: $TYPE (see --list-types)"
[[ -z $WALLPAPER || -f $WALLPAPER ]] || die "wallpaper not found: $WALLPAPER"

write_state() {
    local tmp

    if ((DRY_RUN)); then
        info "[dry-run] would write $STATE_FILE"
        return 0
    fi

    mkdir -p -- "$STATE_DIR"
    tmp="$(mktemp)"
    {
        printf 'wallpaper=%s\n' "$WALLPAPER"
        printf 'mode=%s\n' "$MODE"
        printf 'type=%s\n' "$TYPE"
    } >"$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
    ok "settings saved to $STATE_FILE"
}

print_state() {
    printf 'wallpaper=%s\n' "$WALLPAPER"
    printf 'mode=%s\n' "$MODE"
    printf 'type=%s\n' "$TYPE"
}

# --------------------------------------------------------------- actions ----

apply_wallpaper() {
    [[ -n $WALLPAPER && -f $WALLPAPER ]] || die "no wallpaper selected; use --wallpaper PATH"

    if ! has awww; then
        warn "awww is not installed; wallpaper not applied"
        return 0
    fi

    if ((DRY_RUN)); then
        info "[dry-run] awww img $WALLPAPER"
        return 0
    fi

    if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        warn "not inside a Hyprland session; wallpaper not applied"
        return 0
    fi

    awww img "$WALLPAPER"
    ok "wallpaper applied: $WALLPAPER"
}

sync_color_scheme() {
    local scheme gtk_theme
    case "$MODE" in
        light) scheme="prefer-light"; gtk_theme="adw-gtk3" ;;
        *)     scheme="prefer-dark";  gtk_theme="adw-gtk3-dark" ;;
    esac
    if ((DRY_RUN)); then
        info "[dry-run] gsettings color-scheme $scheme; gtk-theme $gtk_theme"
        return 0
    fi
    has gsettings || return 0
    gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" 2>/dev/null || true
}

apply_colors() {
    [[ -r $MATUGEN_CONFIG ]] || die "missing matugen config: $MATUGEN_CONFIG (install the matugen module)"
    has matugen || die "matugen is not installed"
    [[ -n $WALLPAPER && -f $WALLPAPER ]] || die "no wallpaper selected; use --wallpaper PATH"

    if ((DRY_RUN)); then
        info "[dry-run] matugen image $WALLPAPER --mode $MODE --type $TYPE --config $MATUGEN_CONFIG"
    else
        matugen image "$WALLPAPER" --mode "$MODE" --type "$TYPE" \
            --prefer saturation --config "$MATUGEN_CONFIG"
        ok "colors regenerated from $WALLPAPER ($MODE, $TYPE)"
    fi

    apply_wallpaper
    sync_color_scheme
}

# ----------------------------------------------------------- interactive -----

menu_choose() {
    local prompt="$1"
    shift
    local -a items=("$@")
    local tool choice
    local -a args=()

    ((${#items[@]})) || return 1

    if has rofi && [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
        printf '%s\n' "${items[@]}" | rofi -theme "$REAL_HOME/.config/rofi/launcher.rasi" -dmenu -p "$prompt" -no-custom
        return
    fi

    if has gum; then
        printf '%s\n' "${items[@]}" | gum choose --header "$prompt"
        return
    fi

    tool="$(command -v whiptail || command -v dialog || true)"
    if [[ -n $tool && -t 0 ]]; then
        local i
        for i in "${!items[@]}"; do
            args+=("$((i + 1))" "${items[$i]}")
        done
        if [[ ${tool##*/} == whiptail ]]; then
            choice="$(whiptail --title "$prompt" --menu "$prompt" 0 0 0 "${args[@]}" 3>&1 1>&2 2>&3)" || return 1
        else
            choice="$(dialog --title "$prompt" --menu "$prompt" 0 0 0 "${args[@]}" 3>&1 1>&2 2>&3)" || return 1
        fi
        [[ $choice =~ ^[0-9]+$ ]] || return 1
        printf '%s\n' "${items[$((choice - 1))]}"
        return 0
    fi

    [[ -t 0 ]] || return 1

    local i
    printf '\n%s\n' "$prompt"
    for i in "${!items[@]}"; do
        printf '  %2d) %s\n' "$((i + 1))" "${items[$i]}"
    done
    printf 'Select 1-%d: ' "${#items[@]}"
    read -r choice || return 1
    [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#items[@]})) || return 1
    printf '%s\n' "${items[$((choice - 1))]}"
}

prompt_path() {
    local prompt="$1"

    if has rofi && [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
        rofi -theme "$REAL_HOME/.config/rofi/launcher.rasi" -dmenu -p "$prompt" -no-custom
    elif has gum; then
        gum input --prompt "$prompt: "
    elif [[ -t 0 ]]; then
        local value
        printf '%s: ' "$prompt"
        read -r value || return 1
        printf '%s\n' "$value"
    else
        return 1
    fi
}

collect_wallpapers() {
    local dir
    local -a dirs=(
        "$REAL_HOME/.local/share/wallpapers"
        "$REAL_HOME/Pictures/Wallpapers"
        "$REAL_HOME/Pictures"
        "$REAL_HOME/Wallpapers"
    )

    [[ -n $WALLPAPER && -f $WALLPAPER ]] && printf '%s\n' "$WALLPAPER"
    for dir in "${dirs[@]}"; do
        [[ -d $dir ]] || continue
        find "$dir" -maxdepth 2 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
            2>/dev/null
    done | sort -u
}

pick_wallpaper() {
    local choice
    local -a images=()

    mapfile -t images < <(collect_wallpapers)

    if ((${#images[@]})); then
        choice="$(menu_choose "Wallpaper" "${images[@]}")" || return 1
    else
        choice="$(prompt_path "Wallpaper path")" || return 1
    fi

    [[ -f $choice ]] || { warn "not a file: $choice"; return 1; }
    WALLPAPER="$choice"
    STATE_DIRTY=1
    ok "wallpaper selected: $WALLPAPER"
}

pick_mode() {
    local choice
    choice="$(menu_choose "Mode" "${VALID_MODES[@]}")" || return 1
    MODE="$choice"
    STATE_DIRTY=1
}

pick_type() {
    local choice
    choice="$(menu_choose "Color scheme" "${VALID_TYPES[@]}")" || return 1
    TYPE="$choice"
    STATE_DIRTY=1
}

menu() {
    local choice
    local name

    while true; do
        if [[ -n $WALLPAPER ]]; then
            name="$(basename "$WALLPAPER")"
        else
            name="(none)"
        fi

        choice="$(menu_choose "Theme — mode: $MODE, scheme: $TYPE" \
            "Wallpaper: $name" \
            "Mode: $MODE" \
            "Scheme: $TYPE" \
            "Apply now" \
            "Quit")" || break

        case "$choice" in
            "Wallpaper:"*) pick_wallpaper ;;
            "Mode:"*)      pick_mode ;;
            "Scheme:"*)    pick_type ;;
            "Apply now")
                write_state
                apply_colors
                STATE_DIRTY=0
                ;;
            "Quit") break ;;
        esac
    done
}

# ------------------------------------------------------------------ main -----

if ((PRINT)); then
    print_state
    exit 0
fi

if ((WALLPAPER_ONLY)); then
    ((STATE_DIRTY)) && write_state
    apply_wallpaper
    exit $?
fi

if ((DO_APPLY)); then
    write_state
    apply_colors
    exit $?
fi

if ((STATE_DIRTY)); then
    write_state
    exit 0
fi

# No explicit action: open the menu when a terminal or a graphical session is
# available, otherwise print the state instead of hanging.
if [[ -t 0 || -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
    menu
else
    print_state
fi
