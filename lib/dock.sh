# shellcheck shell=bash
# Repository <-> live configuration for the external/dock monitor layout.
# The choice is stored in hosts/<host>/monitor-profiles.conf and copied to
# ~/.config/hypr/monitor-profiles.conf for monitor-profiles.sh.
[[ -n ${_DOTFILES_DOCK:-} ]] && return 0
_DOTFILES_DOCK=1

DOCK_LAYOUTS=(right left mirror ask)

dock_layout_valid() {
    local layout
    for layout in "${DOCK_LAYOUTS[@]}"; do
        [[ $layout == "$1" ]] && return 0
    done
    return 1
}

repo_dock_conf() {
    printf '%s/hosts/%s/monitor-profiles.conf' "$DOTFILES_DIR" "$HOST_NAME"
}

# Prints the stored layout, or "right" when unset/invalid.
read_dock_layout() {
    local conf layout

    conf="$(repo_dock_conf)"
    layout=""
    if [[ -r $conf ]]; then
        # shellcheck source=/dev/null
        source "$conf" 2>/dev/null || true
    fi
    if dock_layout_valid "${DOCK_LAYOUT:-}"; then
        printf '%s' "$DOCK_LAYOUT"
    else
        printf 'right'
    fi
}

write_dock_layout() {
    local layout="$1" conf tmp
    local live="${XDG_CONFIG_HOME:-$REAL_HOME/.config}/hypr/monitor-profiles.conf"

    dock_layout_valid "$layout" || {
        err "invalid dock layout: $layout (use: ${DOCK_LAYOUTS[*]})"
        return 1
    }

    conf="$(repo_dock_conf)"
    tmp="$(mktemp)"
    {
        printf '# Layout for an external/dock monitor: right|left|mirror|ask.\n'
        printf '# Read by ~/.local/bin/monitor-profiles.sh (hotplug watcher).\n'
        printf '# ask = never move monitors automatically; leave a notification.\n'
        printf 'DOCK_LAYOUT=%s\n' "$layout"
    } >"$tmp"

    if [[ -f $conf ]] && cmp -s -- "$tmp" "$conf"; then
        ok "dock layout unchanged: hosts/$HOST_NAME/monitor-profiles.conf"
        rm -f -- "$tmp"
    else
        if [[ -f $conf ]]; then
            log "Proposed changes to hosts/$HOST_NAME/monitor-profiles.conf:"
            diff -u -- "$conf" "$tmp" || true
            if ((!DRY_RUN)) && ! tui_confirm "Write this dock layout?" yes; then
                warn "dock layout not written"
                rm -f -- "$tmp"
                return 1
            fi
            ((DRY_RUN)) || backup_path "$conf"
        fi

        if ((DRY_RUN)); then
            log "${C_DIM}[dry-run]${C_RESET} write $conf"
        else
            install -m 0644 -- "$tmp" "$conf"
            ok "wrote hosts/$HOST_NAME/monitor-profiles.conf ($layout)"
        fi
        rm -f -- "$tmp"
    fi

    if ((DRY_RUN)) && [[ ! -f $conf ]]; then
        log "${C_DIM}[dry-run]${C_RESET} write $live"
        return 0
    fi

    copy_file "$conf" "$live" 0644
}

# Copy the repository layout to ~/.config/hypr/monitor-profiles.conf.
install_dock_conf() {
    local conf live

    conf="$(repo_dock_conf)"
    live="${XDG_CONFIG_HOME:-$REAL_HOME/.config}/hypr/monitor-profiles.conf"

    if [[ ! -r $conf ]]; then
        log "no dock layout configured; monitor-profiles.sh will use right"
        return 0
    fi
    copy_file "$conf" "$live" 0644
}

configure_dock_layout() {
    local current choice layout

    current="$(read_dock_layout)"

    if ((ASSUME_YES)); then
        write_dock_layout "$current"
        return
    fi

    choice="$(tui_radio "External/dock monitor layout" \
        "Right of the internal panel" \
        "Left of the internal panel" \
        "Mirror the internal panel (clone at 0x0)" \
        "Ask each time (no automatic changes)" \
        "Keep current ($current)")" || return 1

    case "$choice" in
        Right*)  layout=right ;;
        Left*)   layout=left ;;
        Mirror*) layout=mirror ;;
        Ask*)    layout=ask ;;
        Keep*)   layout="$current" ;;
        *)       return 1 ;;
    esac

    write_dock_layout "$layout"
}
