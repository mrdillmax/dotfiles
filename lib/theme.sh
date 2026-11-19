# shellcheck shell=bash
# Wallpaper-driven colour generation (matugen).
[[ -n ${_DOTFILES_THEME:-} ]] && return 0
_DOTFILES_THEME=1

theme_wallpaper_path() {
    local candidate=""

    if [[ -n ${WALLPAPER_ARG:-} ]]; then
        candidate="$WALLPAPER_ARG"
    elif [[ -r $REAL_HOME/.config/hypr/wallpaper.path ]]; then
        candidate="$(<"$REAL_HOME/.config/hypr/wallpaper.path")"
    elif [[ -r $REAL_HOME/.config/hypr/colors.lua ]]; then
        candidate="$(awk -F'"' '/^[[:space:]]*image[[:space:]]*=/{print $2; exit}' \
            "$REAL_HOME/.config/hypr/colors.lua" 2>/dev/null || true)"
    fi

    [[ -n $candidate && -f $candidate ]] || return 1
    printf '%s\n' "$candidate"
}

generate_theme() {
    local wallpaper
    if ! wallpaper="$(theme_wallpaper_path)"; then
        die "no wallpaper found; run ./install.sh --wallpaper PATH first"
    fi

    info "generating colours from $wallpaper"
    run matugen image "$wallpaper" --prefer saturation \
        --config "$REAL_HOME/.config/matugen/config.toml"
    if (( !DRY_RUN )) && command -v pkill >/dev/null 2>&1; then
        pkill -SIGUSR2 waybar 2>/dev/null || true
    fi
}

# Generate colours during the install step when the pieces exist. Missing
# pieces warn; they do not abort the configuration step.
generate_theme_if_possible() {
    local wallpaper

    if ! command -v matugen >/dev/null 2>&1; then
        warn "matugen is not installed; colours were not generated"
        return 0
    fi
    if [[ ! -r $REAL_HOME/.config/matugen/config.toml ]]; then
        warn "matugen config is missing; colours were not generated"
        return 0
    fi
    if ! wallpaper="$(theme_wallpaper_path)"; then
        warn "no wallpaper recorded; colours were not generated"
        return 0
    fi
    info "generating colours from $wallpaper"
    run matugen image "$wallpaper" --config "$REAL_HOME/.config/matugen/config.toml"
    if (( !DRY_RUN )) && command -v pkill >/dev/null 2>&1; then
        pkill -SIGUSR2 waybar 2>/dev/null || true
    fi
}
