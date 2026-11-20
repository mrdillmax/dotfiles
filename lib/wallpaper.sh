# shellcheck shell=bash
# Wallpaper path handling.
#
# The image file is never copied into the repository. The installer only
# records its absolute path in a generated, untracked file under $HOME.
[[ -n ${_DOTFILES_WALLPAPER:-} ]] && return 0
_DOTFILES_WALLPAPER=1

wallpaper_state_file() {
    printf '%s\n' "$REAL_HOME/.config/hypr/wallpaper.path"
}

set_wallpaper() {
    local image="$1"
    local state tmp

    [[ -f $image ]] || die "wallpaper not found: $image"
    image="$(readlink -f -- "$image")"
    state="$(wallpaper_state_file)"

    info "wallpaper: $image"
    tmp="$(mktemp)"
    printf '%s\n' "$image" >"$tmp"
    copy_file "$tmp" "$state" 0644
    rm -f -- "$tmp"

    if command -v awww >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && [[ -t 0 ]]; then
        if tui_confirm "Apply this wallpaper to the current session now?" no; then
            run awww img "$image"
        fi
    fi
}

wallpaper_from_state() {
    local state
    state="$(wallpaper_state_file)"
    [[ -r $state ]] || return 1
    local image
    image="$(<"$state")"
    [[ -n $image ]] || return 1
    printf '%s\n' "$image"
}

# The theme menu records its choice in $XDG_STATE_HOME. That file is written
# last, so it is the truth; wallpaper.path is kept in sync for older readers.
wallpaper_theme_state_file() {
    printf '%s\n' "${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles/theme.conf"
}

wallpaper_current_image() {
    local state image
    state="$(wallpaper_theme_state_file)"
    if [[ -r $state ]]; then
        image="$(sed -n 's/^wallpaper=//p' "$state" | head -n1)"
        if [[ -n $image ]]; then
            printf '%s\n' "$image"
            return 0
        fi
    fi
    wallpaper_from_state
}

# Cache key for a wallpaper card. The label carries the "(current)" marker, so
# including it regenerates the caption when the selection changes.
wallpaper_card_key() {
    printf '%s\n%s\n' "$1" "$2"
}

default_wallpaper_source() {
    printf '%s\n' "$DOTFILES_DIR/assets/wallpapers/example.jpg"
}

# Install the repository wallpaper on a first run. An existing choice wins.
install_default_wallpaper() {
    local src dest state

    src="$(default_wallpaper_source)"
    [[ -f $src ]] || return 1

    state="$(wallpaper_state_file)"
    if [[ -r $state ]] && [[ -n $(<"$state") ]]; then
        return 0
    fi
    # The generated Hyprland config also records a wallpaper; respect it.
    if declare -F theme_wallpaper_path >/dev/null 2>&1 \
        && theme_wallpaper_path >/dev/null 2>&1; then
        return 0
    fi

    dest="$REAL_HOME/.local/share/wallpapers/dotfiles/example.jpg"
    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} install $src -> $dest"
        return 0
    fi
    copy_file "$src" "$dest" 0644
    mkdir -p -- "$(dirname -- "$state")"
    printf '%s\n' "$dest" >"$state"
    ok "default wallpaper: $dest"
}
