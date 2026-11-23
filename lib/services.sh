# shellcheck shell=bash
# User services for the selected modules.
[[ -n ${_DOTFILES_SERVICES:-} ]] && return 0
_DOTFILES_SERVICES=1

user_unit_exists() {
    local unit="$1"
    if systemctl --user list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .; then
        return 0
    fi
    [[ -f "/usr/lib/systemd/user/$unit" || -f "/etc/systemd/user/$unit" \
        || -f "$REAL_HOME/.config/systemd/user/$unit" ]]
}

# Interactive runs offer a checklist. A non-interactive run enables only the
# modules named on the command line, so --all never starts new daemons.
enable_services() {
    local name conf service line labels=() picked=() explicit=0

    [[ -n ${MODULES_ARG:-} ]] && explicit=1

    for name in "${MODULES[@]}"; do
        conf="$DOTFILES_DIR/modules/$name/module.conf"
        [[ -r $conf ]] || continue
        while IFS= read -r service; do
            [[ -n $service ]] || continue
            if ! user_unit_exists "$service"; then
                warn "service not installed, skipping: $service"
                continue
            fi
            labels+=("$name: $service")
        done < <( (
            # shellcheck source=/dev/null
            source "$conf"
            printf '%s\n' "${SERVICES[@]:-}"
        ) )
    done

    ((${#labels[@]})) || return 0

    # Unit files may have just been replaced; reload before enabling.
    run systemctl --user daemon-reload || warn "could not reload user units"

    if ((ASSUME_YES)) || [[ ! -t 0 ]]; then
        if ((!explicit)); then
            info "skipping service selection (non-interactive)"
            return 0
        fi
        info "enabling services for the modules named on the command line"
        for line in "${labels[@]}"; do
            picked+=("${line#*: }")
        done
    else
        # shellcheck disable=SC2034 # read by tui_checklist
        TUI_CHECKED_ITEMS=("${labels[@]}")
        tui_checklist "User services to enable and start" "${labels[@]}"
        for line in "${TUI_SELECTION[@]}"; do
            picked+=("${line#*: }")
        done
        ((${#picked[@]})) || { info "no services selected"; return 0; }
        if ! tui_confirm "Enable and start ${#picked[@]} user service(s)?" no; then
            warn "services not enabled"
            return 0
        fi
    fi

    for service in "${picked[@]}"; do
        run systemctl --user enable --now "$service" \
            || warn "could not enable or start $service"
    done
}
