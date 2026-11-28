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
ARG_SOURCE_INDEX=""
ARG_OUTPUT=""
WALLPAPER=""
MODE=""
TYPE=""
SOURCE_INDEX="auto"
STATE_DIRTY=0
declare -A WALLPAPER_BY_OUTPUT=()

usage() {
    cat <<'EOF'
Usage: theme-menu.sh [options]

Interactive:
  (no options)             open the menu

Non-interactive:
  --wallpaper PATH         record a wallpaper (must exist)
  --output NAME            apply the wallpaper only to that monitor
  --mode dark|light|smart  matugen mode
  --type TYPE              matugen color scheme type
  --source-index N|auto    accent: 0-4 from the wallpaper's source colours
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

valid_source_index() {
    [[ $1 == auto || $1 =~ ^[0-4]$ ]]
}

while (($#)); do
    case "$1" in
        --wallpaper)  ARG_WALLPAPER="${2:?missing value for --wallpaper}"; shift ;;
        --output)     ARG_OUTPUT="${2:?missing value for --output}"; shift ;;
        --mode)       ARG_MODE="${2:?missing value for --mode}"; shift ;;
        --type)       ARG_TYPE="${2:?missing value for --type}"; shift ;;
        --source-index) ARG_SOURCE_INDEX="${2:?missing value for --source-index}"; shift ;;
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
            wallpaper_*) WALLPAPER_BY_OUTPUT["${key#wallpaper_}"]="$value" ;;
            mode)      [[ -z $MODE ]] && MODE="$value" ;;
            type)      [[ -z $TYPE ]] && TYPE="$value" ;;
            source_index) [[ -z $ARG_SOURCE_INDEX ]] && SOURCE_INDEX="$value" ;;
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

if [[ -n $ARG_WALLPAPER ]]; then
    if [[ -n $ARG_OUTPUT ]]; then
        WALLPAPER_BY_OUTPUT["$ARG_OUTPUT"]="$ARG_WALLPAPER"
    else
        WALLPAPER="$ARG_WALLPAPER"
    fi
    STATE_DIRTY=1
fi
[[ -n $ARG_MODE ]] && { MODE="$ARG_MODE"; STATE_DIRTY=1; }
[[ -n $ARG_TYPE ]] && { TYPE="$ARG_TYPE"; STATE_DIRTY=1; }
[[ -n $ARG_SOURCE_INDEX ]] && { SOURCE_INDEX="$ARG_SOURCE_INDEX"; STATE_DIRTY=1; }

if [[ -z $WALLPAPER ]]; then
    WALLPAPER="$(wallpaper_from_hypr)"
fi

MODE="${MODE:-dark}"
TYPE="${TYPE:-scheme-tonal-spot}"
SOURCE_INDEX="${SOURCE_INDEX:-auto}"

valid_mode "$MODE" || die "invalid mode: $MODE (use dark, light or smart)"
valid_type "$TYPE" || die "invalid scheme type: $TYPE (see --list-types)"
valid_source_index "$SOURCE_INDEX" || die "invalid source index: $SOURCE_INDEX (use 0-4 or auto)"
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
        local output
        for output in "${!WALLPAPER_BY_OUTPUT[@]}"; do
            printf 'wallpaper_%s=%s\n' "$output" "${WALLPAPER_BY_OUTPUT[$output]}"
        done
        printf 'mode=%s\n' "$MODE"
        printf 'type=%s\n' "$TYPE"
        printf 'source_index=%s\n' "$SOURCE_INDEX"
    } >"$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
    sync_wallpaper_path
    ok "settings saved to $STATE_FILE"
}

# Hyprland, the wallpaper picker and the theme scripts all read this file.
sync_wallpaper_path() {
    local path="$REAL_HOME/.config/hypr/wallpaper.path"

    [[ -n $WALLPAPER ]] || return 0
    if ((DRY_RUN)); then
        info "[dry-run] would write $path"
        return 0
    fi
    mkdir -p -- "$(dirname -- "$path")"
    printf '%s\n' "$WALLPAPER" >"$path"
}

print_state() {
    printf 'wallpaper=%s\n' "$WALLPAPER"
    local output
    for output in "${!WALLPAPER_BY_OUTPUT[@]}"; do
        printf 'wallpaper_%s=%s\n' "$output" "${WALLPAPER_BY_OUTPUT[$output]}"
    done
    printf 'mode=%s\n' "$MODE"
    printf 'type=%s\n' "$TYPE"
    printf 'source_index=%s\n' "$SOURCE_INDEX"
}

# --------------------------------------------------------------- actions ----

apply_wallpaper() {
    local primary="$WALLPAPER" output image applied=0

    if [[ -n $ARG_OUTPUT ]]; then
        primary="${WALLPAPER_BY_OUTPUT[$ARG_OUTPUT]:-$WALLPAPER}"
    fi
    [[ -n $primary && -f $primary ]] || die "no wallpaper selected; use --wallpaper PATH"

    if ! has awww; then
        warn "awww is not installed; wallpaper not applied"
        return 0
    fi

    if ((DRY_RUN)); then
        info "[dry-run] awww img $primary"
        return 0
    fi

    if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        warn "not inside a Hyprland session; wallpaper not applied"
        return 0
    fi

    if [[ -n $ARG_OUTPUT ]]; then
        awww img "$primary" --outputs "$ARG_OUTPUT"
        ok "wallpaper applied to $ARG_OUTPUT: $primary"
        return 0
    fi

    awww img "$primary"
    applied=1
    for output in "${!WALLPAPER_BY_OUTPUT[@]}"; do
        image="${WALLPAPER_BY_OUTPUT[$output]}"
        [[ -n $image && -f $image ]] || continue
        awww img "$image" --outputs "$output"
        applied=1
    done
    ((applied)) && ok "wallpaper applied: $primary"
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
    local -a source_args=()

    [[ -r $MATUGEN_CONFIG ]] || die "missing matugen config: $MATUGEN_CONFIG (install the matugen module)"
    has matugen || die "matugen is not installed"
    [[ -n $WALLPAPER && -f $WALLPAPER ]] || die "no wallpaper selected; use --wallpaper PATH"

    [[ $SOURCE_INDEX != auto ]] && source_args=(--source-color-index "$SOURCE_INDEX")

    if ((DRY_RUN)); then
        info "[dry-run] matugen image $WALLPAPER --mode $MODE --type $TYPE ${source_args[*]:-} --config $MATUGEN_CONFIG"
    else
        matugen image "$WALLPAPER" --mode "$MODE" --type "$TYPE" \
            "${source_args[@]}" --prefer saturation --config "$MATUGEN_CONFIG"
        ok "colors regenerated from $WALLPAPER ($MODE, $TYPE, accent: $SOURCE_INDEX)"
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
        printf '%s\n' "${items[@]}" | rofi -theme "$REAL_HOME/.config/rofi/launcher.rasi" -dmenu -p "" -no-custom -no-fixed-num-lines \
            -theme-str "entry { placeholder: \"$prompt\"; }"
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
        rofi -theme "$REAL_HOME/.config/rofi/launcher.rasi" -dmenu -p "" -no-custom -no-fixed-num-lines \
            -theme-str "entry { placeholder: \"$prompt\"; }"
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

pick_source_index() {
    local choice i
    local -a colors=() labels=("Automatic")

    if ! has matugen || [[ -z $WALLPAPER || ! -f $WALLPAPER ]]; then
        warn "pick a wallpaper before choosing an accent colour"
        return 1
    fi
    mapfile -t colors < <(matugen image "$WALLPAPER" --show-source-colors 2>/dev/null |
        grep -E '^#[0-9A-Fa-f]{6}$' | head -n5)
    ((${#colors[@]})) || { warn "matugen found no source colours in this wallpaper"; return 1; }

    for i in "${!colors[@]}"; do
        labels+=("$((i + 1)). ${colors[$i]}")
    done
    choice="$(menu_choose "Accent colour" "${labels[@]}")" || return 1
    if [[ $choice == Automatic ]]; then
        SOURCE_INDEX="auto"
    else
        choice="${choice%%.*}"
        [[ $choice =~ ^[0-9]+$ ]] || return 1
        SOURCE_INDEX=$((choice - 1))
    fi
    STATE_DIRTY=1
    ok "accent source index: $SOURCE_INDEX"
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
            "Accent: $SOURCE_INDEX" \
            "Apply now" \
            "Quit")" || break

        case "$choice" in
            "Wallpaper:"*) pick_wallpaper ;;
            "Mode:"*)      pick_mode ;;
            "Scheme:"*)    pick_type ;;
            "Accent:"*)    pick_source_index ;;
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
