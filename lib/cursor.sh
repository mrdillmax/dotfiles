# shellcheck shell=bash
# Cursor theme installation and rendering.
#
# The cursor theme archive and its files are never stored in this repository.
# The host configuration only records the theme name and size.
[[ -n ${_DOTFILES_CURSOR:-} ]] && return 0
_DOTFILES_CURSOR=1

CURSOR_THEME="${CURSOR_THEME:-win11_concept_cursos}"
CURSOR_SIZE="${CURSOR_SIZE:-24}"
CURSOR_INSTALLED_THEME=""

load_cursor_conf() {
    local conf="$DOTFILES_DIR/hosts/${HOST_NAME:-desktop}/cursor.conf"

    CURSOR_THEME="win11_concept_cursos"
    CURSOR_SIZE=24
    if [[ -r $conf ]]; then
        # shellcheck source=/dev/null
        source "$conf"
    fi
    CURSOR_THEME="${CURSOR_THEME:-win11_concept_cursos}"
    CURSOR_SIZE="${CURSOR_SIZE:-24}"
}

cursor_validate_size() {
    local size="$1"
    if [[ ! $size =~ ^[0-9]+$ ]] || (( size < 16 || size > 128 )); then
        die "invalid cursor size: $size (expected 16..128)"
    fi
}

cursor_theme_dir() {
    local theme="$1" base
    for base in "/usr/share/icons" "$REAL_HOME/.local/share/icons" "$REAL_HOME/.icons"; do
        if [[ -d $base/$theme ]]; then
            printf '%s\n' "$base/$theme"
            return 0
        fi
    done
    return 1
}

cursor_theme_exists() {
    local dir
    dir="$(cursor_theme_dir "$1")" || return 1
    [[ -f $dir/index.theme || -f $dir/cursor.theme ]]
}

cursor_archive_default() {
    local dir="$DOTFILES_DIR/personal/cursor"
    local candidate
    [[ -d $dir ]] || return 1
    for candidate in "$dir"/*.7z "$dir"/*.zip "$dir"/*.tar.gz "$dir"/*.tgz "$dir"/*.tar.xz; do
        if [[ -f $candidate ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

cursor_extract_archive() {
    local archive="$1" dest="$2"
    case "$archive" in
        *.7z)
            command -v 7z >/dev/null 2>&1 || die "7z is required to extract $archive"
            7z x -y -o"$dest" -- "$archive" >/dev/null
            ;;
        *.zip)
            command -v unzip >/dev/null 2>&1 || die "unzip is required to extract $archive"
            unzip -q -- "$archive" -d "$dest"
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "$archive" -C "$dest"
            ;;
        *.tar.xz)
            tar -xJf "$archive" -C "$dest"
            ;;
        *)
            die "unsupported cursor archive type: $archive"
            ;;
    esac
}

cursor_find_theme_dir() {
    local root="$1" candidate
    while IFS= read -r candidate; do
        if [[ -f $candidate/index.theme || -f $candidate/cursor.theme ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find "$root" -mindepth 1 -maxdepth 2 -type d | sort)
    return 1
}

cursor_install_archive() {
    local archive="$1"
    local tmp theme_src theme

    [[ -f $archive ]] || die "cursor archive not found: $archive"

    tmp="$(mktemp -d)"
    cursor_extract_archive "$archive" "$tmp"
    theme_src="$(cursor_find_theme_dir "$tmp")" || {
        rm -rf -- "$tmp"
        die "no cursor theme directory (index.theme/cursor.theme) found in $archive"
    }
    theme="$(basename "$theme_src")"
    info "cursor archive: $archive"
    info "theme found:   $theme"
    info "target:        /usr/share/icons/$theme"

    if ! tui_confirm "Install cursor theme '$theme' into /usr/share/icons?" no; then
        warn "cursor theme installation skipped"
        rm -rf -- "$tmp"
        return 1
    fi

    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} sudo install -d /usr/share/icons"
        log "${C_DIM}[dry-run]${C_RESET} sudo cp -a $theme_src /usr/share/icons/$theme"
        log "${C_DIM}[dry-run]${C_RESET} sudo chmod -R 755 /usr/share/icons/$theme"
    else
        sudo install -d /usr/share/icons
        sudo cp -a -- "$theme_src" "/usr/share/icons/$theme"
        sudo chmod -R 755 "/usr/share/icons/$theme"
        ok "installed /usr/share/icons/$theme"
    fi

    rm -rf -- "$tmp"
    CURSOR_INSTALLED_THEME="$theme"
    return 0
}

cursor_installed_themes() {
    local base dir
    for base in "/usr/share/icons" "$REAL_HOME/.local/share/icons" "$REAL_HOME/.icons"; do
        [[ -d $base ]] || continue
        for dir in "$base"/*; do
            [[ -d $dir ]] || continue
            if [[ -f $dir/index.theme || -f $dir/cursor.theme ]]; then
                basename "$dir"
            fi
        done
    done | sort -u
}

cursor_install_package() {
    local package="$1"
    local official=0

    if pacman -Si "$package" >/dev/null 2>&1; then
        official=1
    fi

    if (( official )); then
        run sudo pacman -S --needed --noconfirm "$package"
    else
        local helper=""
        if command -v yay >/dev/null 2>&1; then
            helper="yay"
        elif command -v paru >/dev/null 2>&1; then
            helper="paru"
        fi
        [[ -n $helper ]] || die "no AUR helper found for $package"
        run "$helper" -S --needed --noconfirm "$package"
    fi
}

cursor_offer_packages() {
    local choice package
    local -a themes=()

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        warn "cursor theme '$CURSOR_THEME' is not installed and no archive was provided"
        return 1
    fi

    choice="$(tui_radio "Cursor theme is missing. Install a package?" \
        "breeze (extra, package only)" \
        "capitaine-cursors (extra, package only)" \
        "bibata-cursor-theme (AUR, package only)" \
        "skip")" || return 1

    case "$choice" in
        breeze*)            package="breeze" ;;
        capitaine*)         package="capitaine-cursors" ;;
        bibata*)            package="bibata-cursor-theme" ;;
        *)                  warn "cursor package installation skipped"; return 1 ;;
    esac

    cursor_install_package "$package"
    (( DRY_RUN )) && return 1

    mapfile -t themes < <(cursor_installed_themes)
    ((${#themes[@]})) || {
        warn "no installed cursor themes found after installing $package"
        return 1
    }

    choice="$(tui_radio "Select the cursor theme to use" "${themes[@]}")" || return 1
    CURSOR_THEME="$choice"
    ok "selected cursor theme: $CURSOR_THEME"
}

cursor_write_conf() {
    local theme="$1" size="$2"
    local target="$DOTFILES_DIR/hosts/$HOST_NAME/cursor.conf"
    local tmp

    tmp="$(mktemp)"
    {
        printf '# Cursor theme for this host. Rendered into uwsm env, GTK and xsettingsd.\n'
        printf '# The theme files themselves are NOT stored in this repository.\n'
        printf 'CURSOR_THEME="%s"\n' "$theme"
        printf 'CURSOR_SIZE=%s\n' "$size"
    } >"$tmp"

    if [[ -f $target ]] && cmp -s -- "$tmp" "$target"; then
        ok "cursor settings unchanged: hosts/$HOST_NAME/cursor.conf"
        rm -f -- "$tmp"
        return 0
    fi

    if [[ -f $target ]]; then
        log "Proposed changes to hosts/$HOST_NAME/cursor.conf:"
        diff -u -- "$target" "$tmp" || true
        if ! tui_confirm "Write this cursor configuration?" yes; then
            warn "cursor configuration not written"
            rm -f -- "$tmp"
            return 1
        fi
    fi

    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} write hosts/$HOST_NAME/cursor.conf"
    else
        install -m 0644 -- "$tmp" "$target"
        ok "wrote hosts/$HOST_NAME/cursor.conf"
    fi
    rm -f -- "$tmp"
}

cursor_apply_live() {
    local theme="$1" size="$2"

    if ! command -v hyprctl >/dev/null 2>&1 || [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        return 0
    fi

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        info "to apply now: hyprctl setcursor $theme $size"
        return 0
    fi

    if ! tui_confirm "Apply cursor '$theme' size $size to the current session now?" no; then
        return 0
    fi

    run hyprctl setcursor "$theme" "$size"
}

install_cursor() {
    local theme size archive

    load_cursor_conf
    theme="${CURSOR_THEME_ARG:-$CURSOR_THEME}"
    size="${CURSOR_SIZE_ARG:-$CURSOR_SIZE}"
    cursor_validate_size "$size"

    if [[ -n $CURSOR_ARCHIVE_ARG ]]; then
        archive="$CURSOR_ARCHIVE_ARG"
    else
        archive="$(cursor_archive_default || true)"
    fi

    if [[ -n $archive ]]; then
        if cursor_install_archive "$archive"; then
            theme="$CURSOR_INSTALLED_THEME"
        else
            theme="$CURSOR_THEME"
        fi
    fi

    if ! cursor_theme_exists "$theme"; then
        warn "cursor theme is not installed: $theme"
        if [[ -z $archive ]]; then
            cursor_offer_packages || true
            theme="${CURSOR_THEME:-$theme}"
        fi
    fi

    cursor_write_conf "$theme" "$size" || true

    if cursor_theme_exists "$theme"; then
        ok "cursor theme: $theme (size $size)"
        cursor_apply_live "$theme" "$size"
    else
        warn "keeping configured theme '$theme' even though it is not installed yet"
    fi
}
