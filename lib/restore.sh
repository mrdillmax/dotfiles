# shellcheck shell=bash
# Backup listing and manifest-driven restore. Never touches services.
[[ -n ${_DOTFILES_RESTORE:-} ]] && return 0
_DOTFILES_RESTORE=1

: "${DOTFILES_DIR:?DOTFILES_DIR must be set}"

restore_backup_root() {
    printf '%s\n' "${DOTFILES_BACKUP_DIR:-$REAL_HOME/.dotfiles-backup}"
}

restore_dates() {
    local root="$1" dir
    [[ -d $root ]] || return 0
    for dir in "$root"/*/; do
        [[ -r $dir/manifest.tsv ]] || continue
        basename "$dir"
    done | sort
}

restore_file_count() {
    local manifest="$1/manifest.tsv"
    [[ -r $manifest ]] || { printf '0'; return 0; }
    awk -F'\t' 'NR > 1 && NF >= 2' "$manifest" | wc -l
}

# Maps a restored path back to the module that owns it.
restore_module_for_target() {
    local target="$1" rel m

    case "$target" in
        /etc/*|/usr/local/*) printf 'system'; return 0 ;;
    esac

    rel="${target#"$REAL_HOME"/}"
    for m in "$DOTFILES_DIR"/modules/*/; do
        m="$(basename "$m")"
        if [[ -e "$DOTFILES_DIR/modules/$m/home/$rel" ]]; then
            printf '%s' "$m"
            return 0
        fi
    done

    case "$rel" in
        .config/hypr/monitors.lua|.config/hypr/monitors.conf.sh|.config/hypr/control-center.lua)
            printf 'hypr' ;;
        .config/hypr/monitor-profiles.conf) printf 'monitor-profiles' ;;
        .config/hypr/input.lua)             printf 'mouse-sensitivity' ;;
        .config/uwsm/env|.config/uwsm/env-hyprland) printf 'uwsm' ;;
        *) printf 'other' ;;
    esac
}

restore_backup_modules() {
    local backup_dir="$1"
    local manifest="$backup_dir/manifest.tsv"
    local target _ module
    local -A seen=()
    local modules=()

    [[ -r $manifest ]] || return 0

    while IFS=$'\t' read -r target _; do
        [[ -n $target ]] || continue
        module="$(restore_module_for_target "$target")"
        [[ -n ${seen[$module]:-} ]] && continue
        seen["$module"]=1
        modules+=("$module")
    done < <(tail -n +2 -- "$manifest")

    local IFS=,
    printf '%s' "${modules[*]}"
}

restore_list() {
    local root date
    local dates=()

    root="$(restore_backup_root)"
    mapfile -t dates < <(restore_dates "$root")

    if ((${#dates[@]} == 0)); then
        printf 'No backups found in %s\n' "$root"
        return 1
    fi

    printf '%-22s %6s  %s\n' "DATE" "FILES" "MODULES"
    for date in "${dates[@]}"; do
        printf '%-22s %6s  %s\n' \
            "$date" \
            "$(restore_file_count "$root/$date")" \
            "$(restore_backup_modules "$root/$date")"
    done
    return 0
}

restore_pick() {
    local root="$1" date line
    local dates=() labels=()

    mapfile -t dates < <(restore_dates "$root")
    ((${#dates[@]})) || return 1

    for date in "${dates[@]}"; do
        labels+=("$date — $(restore_file_count "$root/$date") files — $(restore_backup_modules "$root/$date")")
    done

    line="$(tui_radio "Choose a backup to restore" "${labels[@]}")" || return 1
    printf '%s\n' "${line%% — *}"
}

restore_show_diff() {
    local target="$1" backup="$2" label="$3"

    if [[ ! -e $target ]]; then
        printf 'new file: %s\n' "$target"
    elif cmp -s -- "$target" "$backup"; then
        printf 'unchanged: %s\n' "$target"
    else
        printf '\n--- %s\n' "$label"
        diff -u --label "$target (current)" --label "$target (backup)" -- "$target" "$backup" || true
    fi
}

restore_prepare_backup() {
    local source_date="$1"

    if [[ -z ${BACKUP_DIR:-} ]]; then
        BACKUP_DIR="$(restore_backup_root)/$(date +%Y-%m-%d_%H%M%S)"
    fi

    if ((DRY_RUN)); then
        info "[dry-run] would back up the current state to $BACKUP_DIR"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    [[ -r $BACKUP_DIR/manifest.tsv ]] || printf 'target\tbackup\n' >"$BACKUP_DIR/manifest.tsv"
    printf '%s\n' "$source_date" >"$BACKUP_DIR/restore-from.txt"
    info "pre-restore backup: $BACKUP_DIR"
}

# restore_run [date] [module1,module2]
restore_run() {
    local date="${1:-}" modules_csv="${2:-}"
    local root manifest target backup module filter wanted
    local -a modules_filter=() rows=() home_rows=() system_rows=()

    root="$(restore_backup_root)"

    if [[ -z $date ]]; then
        restore_list || return 1
        date="$(restore_pick "$root")" || { warn "no backup selected"; return 1; }
    fi

    if [[ ! -d $root/$date || ! -r $root/$date/manifest.tsv ]]; then
        err "backup not found or has no manifest: $root/$date"
        return 1
    fi
    manifest="$root/$date/manifest.tsv"

    if [[ -n $modules_csv ]]; then
        IFS=, read -r -a modules_filter <<<"$modules_csv"
    fi

    while IFS=$'\t' read -r target backup; do
        [[ -n $target && $target != target ]] || continue

        if ((${#modules_filter[@]})); then
            module="$(restore_module_for_target "$target")"
            wanted=0
            for filter in "${modules_filter[@]}"; do
                if [[ $filter == all || $filter == "$module" ]]; then
                    wanted=1
                fi
            done
            ((wanted)) || continue
        fi

        rows+=("$target"$'\t'"$backup")
        case "$target" in
            /etc/*|/usr/local/*) system_rows+=("$target"$'\t'"$backup") ;;
            *)                   home_rows+=("$target"$'\t'"$backup") ;;
        esac
    done < <(tail -n +2 -- "$manifest")

    if ((${#rows[@]} == 0)); then
        info "nothing to restore for the selected filter"
        return 0
    fi

    if ((${#system_rows[@]})); then
        if ((!DO_SYSTEM)); then
            warn "skipping ${#system_rows[@]} system file(s); add --system to restore them"
            rows=("${home_rows[@]}")
        elif ((EUID != 0)) && ((!DRY_RUN)); then
            warn "skipping system files: run this restore with sudo to write under /etc"
            rows=("${home_rows[@]}")
        elif ! tui_confirm "Restore ${#system_rows[@]} file(s) under /etc? This is a separate confirmation from home files." no; then
            warn "system files skipped"
            rows=("${home_rows[@]}")
        fi
    fi

    if ((${#rows[@]} == 0)); then
        info "no files selected after the safety checks"
        return 0
    fi

    local missing=0
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r target backup <<<"$row"
        if [[ ! -e $backup ]]; then
            warn "backup file is missing: $backup"
            missing=1
            continue
        fi
        restore_show_diff "$target" "$backup" "$date"
    done
    ((missing)) && warn "files with missing backups will be skipped"

    if ((!DRY_RUN)); then
        if ! tui_confirm "Restore ${#rows[@]} file(s) from $date?" no; then
            info "restore cancelled"
            return 0
        fi
        restore_prepare_backup "$date"
    fi

    local restored=0
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r target backup <<<"$row"
        if [[ ! -e $backup ]]; then
            continue
        fi

        if [[ -e $target ]] && ((!DRY_RUN)); then
            backup_path "$target"
        fi

        run mkdir -p "$(dirname "$target")"
        # cp -a writes through a symlink; remove it so the backup replaces
        # the link itself instead of the file it points at.
        if [[ -L $target ]]; then
            run rm -f -- "$target"
        fi
        run cp -a -- "$backup" "$target"
        ok "restored $target"
        restored=$((restored + 1))
    done

    if ((DRY_RUN)); then
        info "[dry-run] would restore $restored file(s) from $date"
    else
        ok "restored $restored file(s) from $date"
        info "pre-restore backup: $BACKUP_DIR"
        info "no service was restarted; run ./install.sh --doctor to verify"
    fi
}

# Offer a snapper snapshot before installing. Never creates snapper configs and
# never restarts services.
maybe_create_snapshot() {
    local configs config

    if ! command -v snapper >/dev/null 2>&1; then
        info "snapper not installed; skipping the pre-install snapshot"
        return 0
    fi

    configs="$(snapper --csvout list-configs 2>/dev/null | tail -n +2 | cut -d, -f1 || true)"
    if [[ -z $configs ]]; then
        info "snapper is installed but has no configurations; skipping the pre-install snapshot"
        return 0
    fi

    config="root"
    if ! grep -qx root <<<"$configs"; then
        config="$(printf '%s\n' "$configs" | head -n1)"
    fi

    if ((DRY_RUN)); then
        info "[dry-run] would offer: snapper -c $config create -d \"dotfiles pre-install\""
        return 0
    fi

    if ! tui_confirm "Create a snapper snapshot ($config) before installing?" no; then
        info "snapshot skipped"
        return 0
    fi

    info "creating snapshot: snapper -c $config create -d \"dotfiles pre-install\""
    if ((EUID == 0)); then
        snapper -c "$config" create -d "dotfiles pre-install" || warn "snapper snapshot failed; continuing"
    else
        sudo snapper -c "$config" create -d "dotfiles pre-install" || warn "snapper snapshot failed or was cancelled; continuing"
    fi
}
