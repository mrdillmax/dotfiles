# shellcheck shell=bash
# Manifest-driven uninstall. Removes what this repository installed and puts
# back the recorded original files. Packages are never removed.
[[ -n ${_DOTFILES_UNINSTALL:-} ]] && return 0
_DOTFILES_UNINSTALL=1

# Remove the packages listed by the selected modules. Only packages that are
# installed and not used by another module are touched; pacman keeps its own
# confirmation prompts.
uninstall_remove_packages() {
    local modules_csv="${1:-}"
    local -a selected=() remove=()
    local mod conf pkg
    local sudo_bin="${SUDO_BIN:-sudo}"
    declare -A keep=()

    [[ -n $modules_csv ]] || { warn "package removal requires --modules"; return 1; }
    IFS=, read -r -a selected <<<"$modules_csv"

    for conf in "$DOTFILES_DIR"/modules/*/module.conf; do
        mod="$(basename "$(dirname "$conf")")"
        [[ " ${selected[*]} " == *" $mod "* ]] && continue
        while IFS= read -r pkg; do
            [[ -n $pkg ]] && keep["$pkg"]=1
        done < <( (
            # shellcheck source=/dev/null
            source "$conf"
            printf '%s\n' "${PACKAGES[@]:-}"
        ) )
    done

    for mod in "${selected[@]}"; do
        conf="$DOTFILES_DIR/modules/$mod/module.conf"
        [[ -r $conf ]] || { warn "unknown module: $mod"; continue; }
        while IFS= read -r pkg; do
            [[ -n $pkg && -z ${keep[$pkg]:-} ]] || continue
            command -v pacman >/dev/null 2>&1 || continue
            pacman -Qq "$pkg" >/dev/null 2>&1 || continue
            remove+=("$pkg")
        done < <( (
            # shellcheck source=/dev/null
            source "$conf"
            printf '%s\n' "${PACKAGES[@]:-}"
        ) )
    done

    if ((${#remove[@]})); then
        local -A unique=()
        local -a deduped=()
        for pkg in "${remove[@]}"; do
            [[ -n ${unique[$pkg]:-} ]] && continue
            unique["$pkg"]=1
            deduped+=("$pkg")
        done
        remove=("${deduped[@]}")
    fi
    ((${#remove[@]})) || { info "no module packages to remove"; return 0; }
    info "packages to remove: ${remove[*]}"
    if (( ${DRY_RUN:-0} )); then
        log "${C_DIM}[dry-run]${C_RESET} $sudo_bin pacman -Rns -- ${remove[*]}"
        return 0
    fi
    if (( !ASSUME_YES )); then
        tui_confirm "Remove ${#remove[@]} package(s)?" no \
            || { info "packages kept"; return 0; }
    fi
    run "$sudo_bin" pacman -Rns -- "${remove[@]}"
}

# uninstall_run [modules_csv]
#
# Empty module list means every recorded path. Uses DRY_RUN, ASSUME_YES,
# DO_SYSTEM and FORCE from the caller.
uninstall_run() {
    local modules_csv="${1:-}"
    local manifest="${STATE_FILE:-}"
    local path kind source digest original
    local mod pkgs="" manifest_mode=""
    # Test seam: root-only branches must be provable without running as root.
    local effective_euid="${UNINSTALL_EUID:-$EUID}"
    local -a modules=() plan_paths=() plan_actions=() plan_originals=()
    declare -A row_for=() handled=() handled_mods=()

    if [[ ! -r $manifest ]]; then
        err "no managed state at $manifest; nothing to uninstall (use --restore for backups)"
        return 1
    fi

    if [[ -n $modules_csv ]]; then
        IFS=, read -r -a modules <<<"$modules_csv"
    fi

    # The latest row for a path wins; uninstall works from that snapshot.
    while IFS=$'\t' read -r kind path source digest original; do
        [[ -n ${kind:-} && -n ${path:-} ]] || continue
        row_for["$path"]="$kind"$'\t'"${source:-}"$'\t'"${digest:--}"$'\t'"${original:--}"
    done <"$manifest"

    local module route wanted action restored=0 removed=0 kept=0 skipped=0
    for path in "${!row_for[@]}"; do
        IFS=$'\t' read -r kind source digest original <<<"${row_for[$path]}"

        if ((${#modules[@]})); then
            module="$(restore_module_for_target "$path")"
            wanted=0
            for route in "${modules[@]}"; do
                [[ $route == all || $route == "$module" ]] && wanted=1
            done
            if ((!wanted)); then
                skipped=$((skipped + 1))
                continue
            fi
        fi

        if [[ $path == "$REAL_HOME"/* ]] && ((effective_euid == 0)); then
            warn "skipping $path: run uninstall as your desktop user, not root"
            skipped=$((skipped + 1))
            continue
        fi

        if [[ $kind == system ]]; then
            if ((!DO_SYSTEM)); then
                warn "skipping $path: add --system to remove system files"
                skipped=$((skipped + 1))
                continue
            fi
            if ((effective_euid != 0)); then
                warn "skipping $path: system files need root"
                skipped=$((skipped + 1))
                continue
            fi
        fi

        case "$kind" in
            link)
                if [[ ! -e $path && ! -L $path ]]; then
                    skipped=$((skipped + 1))
                    continue
                fi
                if [[ ! -L $path ]]; then
                    warn "keeping $path: not a symlink anymore"
                    kept=$((kept + 1))
                    continue
                fi
                if [[ "$(readlink -f -- "$path" 2>/dev/null || true)" != \
                    "$(readlink -f -- "$source" 2>/dev/null || true)" ]]; then
                    warn "keeping $path: link target no longer matches the record"
                    kept=$((kept + 1))
                    continue
                fi
                ;;
            copy|system)
                if [[ ! -e $path ]]; then
                    skipped=$((skipped + 1))
                    continue
                fi
                if [[ $digest != - ]]; then
                    if [[ "$(file_digest "$path")" != "$digest" ]] && ((!FORCE)); then
                        warn "keeping $path: edited since install (use --force to remove)"
                        kept=$((kept + 1))
                        continue
                    fi
                elif ((!FORCE)); then
                    # A row from before v2 has no digest. A plain copy can be
                    # checked against its source; a rendered copy cannot.
                    if [[ ! -f $source ]] || ! cmp -s -- "$source" "$path"; then
                        warn "keeping $path: no recorded digest (use --force to remove)"
                        kept=$((kept + 1))
                        continue
                    fi
                fi
                ;;
            *)
                skipped=$((skipped + 1))
                continue
                ;;
        esac

        if [[ -n $original && $original != - && -e $original ]]; then
            action=restore
        else
            action=remove
        fi
        module="$(restore_module_for_target "$path")"
        case "$module" in
            other|system) ;;
            *) handled_mods["$module"]=1 ;;
        esac
        plan_paths+=("$path")
        plan_actions+=("$action")
        plan_originals+=("$original")
        handled["$path"]=1
    done

    if ((${#plan_paths[@]} == 0)); then
        if (( ${REMOVE_PACKAGES:-0} )); then
            uninstall_remove_packages "$modules_csv" || true
        else
            info "nothing to uninstall"
        fi
        return 0
    fi

    if ((!ASSUME_YES && !DRY_RUN)); then
        tui_confirm "Uninstall ${#plan_paths[@]} path(s) and restore originals?" no \
            || { info "uninstall cancelled"; return 0; }
    fi

    local i dir daemon_reload=0 unit
    for i in "${!plan_paths[@]}"; do
        path="${plan_paths[$i]}"
        action="${plan_actions[$i]}"
        original="${plan_originals[$i]}"

        if ((DRY_RUN)); then
            log "${C_DIM}[dry-run]${C_RESET} $action $path"
            if [[ $action == restore ]]; then
                restored=$((restored + 1))
            else
                removed=$((removed + 1))
            fi
            continue
        fi

        # Undo point for the pre-uninstall state; never used as a restore source.
        if [[ -e $path || -L $path ]]; then
            backup_path "$path"
        fi

        if [[ $action == remove && $path == "$REAL_HOME"/.config/systemd/user/* ]]; then
            unit="$(basename "$path")"
            if command -v systemctl >/dev/null 2>&1; then
                systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
                daemon_reload=1
            fi
        fi

        if [[ $action == restore ]]; then
            rm -f -- "$path"
            mkdir -p -- "$(dirname "$path")"
            cp -a -- "$original" "$path"
            ok "restored $path"
            restored=$((restored + 1))
        else
            rm -f -- "$path"
            ok "removed $path"
            removed=$((removed + 1))
            dir="$(dirname "$path")"
            while [[ $dir == "$REAL_HOME"/* ]]; do
                rmdir -- "$dir" 2>/dev/null || break
                dir="$(dirname "$dir")"
            done
        fi
    done

    if ((!DRY_RUN)); then
        local tmp rkind rpath rest
        manifest_mode="$(stat -c %a "$manifest" 2>/dev/null || true)"
        tmp="$(mktemp "$manifest.XXXXXX")"
        while IFS=$'\t' read -r rkind rpath rest; do
            [[ -n ${rpath:-} ]] || continue
            [[ -n ${handled[$rpath]:-} ]] && continue
            if [[ -n ${rest:-} ]]; then
                printf '%s\t%s\t%s\n' "$rkind" "$rpath" "$rest"
            else
                printf '%s\t%s\n' "$rkind" "$rpath"
            fi
        done <"$manifest" >"$tmp"
        mv -f -- "$tmp" "$manifest"
        state_file_permissions "$manifest" "$manifest_mode"

        if ((daemon_reload)) && command -v systemctl >/dev/null 2>&1; then
            systemctl --user daemon-reload >/dev/null 2>&1 || true
        fi
    fi

    info "uninstall: $removed removed, $restored restored, $kept kept, $skipped skipped"

    for mod in "${!handled_mods[@]}"; do
        [[ -r $DOTFILES_DIR/modules/$mod/module.conf ]] || continue
        pkgs+="$( (
            # shellcheck source=/dev/null
            source "$DOTFILES_DIR/modules/$mod/module.conf"
            printf '%s ' "${PACKAGES[@]:-}"
        ) )"
    done
    info "packages were not removed${pkgs:+: ${pkgs% }}"
    info "login shell was not changed; revert with: chsh -s /bin/bash \$USER"
    info "fisher plugins were not removed; update fish_plugins, then: fish -c 'fisher update'"

    if (( ${REMOVE_PACKAGES:-0} )); then
        uninstall_remove_packages "$modules_csv" || true
    fi
    return 0
}
