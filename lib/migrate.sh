# shellcheck shell=bash
# Config version and ordered migrations.
[[ -n ${_DOTFILES_MIGRATE:-} ]] && return 0
_DOTFILES_MIGRATE=1

repo_version() {
    local file="${VERSION_FILE:-$DOTFILES_DIR/VERSION}" value
    value="$(tr -d '[:space:]' <"$file" 2>/dev/null || true)"
    [[ $value =~ ^[0-9]+$ ]] || die "invalid VERSION file: $file"
    printf '%s\n' "$value"
}

# A version file wins. Without it, an existing managed.tsv means an install
# from before the framework, while no state at all means a fresh clone that
# must not replay old migrations.
stored_version() {
    local file="${STATE_DIR:?}/version" value
    if [[ -r $file ]]; then
        value="$(tr -d '[:space:]' <"$file")"
        if [[ $value =~ ^[0-9]+$ ]]; then
            printf '%s\n' "$value"
        else
            warn "invalid state version in $file; treating it as 0"
            printf '0\n'
        fi
        return 0
    fi
    if [[ -e ${STATE_FILE:-} ]]; then
        printf '0\n'
        return 0
    fi
    repo_version
}

pending_migrations() {
    local from="$1" to="$2" dir file name number
    dir="${MIGRATIONS_DIR:-$DOTFILES_DIR/migrations}"
    [[ -d $dir ]] || return 0
    for file in "$dir"/*.sh; do
        [[ -f $file ]] || continue
        name="${file##*/}"
        [[ $name =~ ^([0-9]+)-.*\.sh$ ]] || continue
        number=$((10#${BASH_REMATCH[1]}))
        (( number > from && number <= to )) && printf '%s\n' "$file"
    done | sort
}

migration_title() {
    awk 'NR == 1 && /^#!/ { next } /^# / { sub(/^# /, ""); print; exit }' "$1"
}

run_migrations() {
    local from to file title
    local -a pending=()

    from="$(stored_version)"
    to="$(repo_version)"
    if (( from > to )); then
        warn "state version $from is newer than repository version $to; leaving it alone"
        return 0
    fi

    mapfile -t pending < <(pending_migrations "$from" "$to")
    for file in "${pending[@]}"; do
        title="$(migration_title "$file")"
        info "migration $(basename "$file"): ${title:-untitled}"
    done

    # Dry-run lists the plan and executes nothing, so a badly written
    # migration can never touch the machine in that mode.
    if (( DRY_RUN )); then
        return 0
    fi

    if ((${#pending[@]})) && (( !ASSUME_YES )); then
        tui_confirm "Run ${#pending[@]} migration(s)?" yes \
            || die "migrations declined; install stopped"
    fi

    for file in "${pending[@]}"; do
        if ! (
            export DOTFILES_DIR REAL_HOME STATE_DIR STATE_FILE BACKUP_DIR
            export DRY_RUN ASSUME_YES
            bash "$file"
        ); then
            die "migration failed: $(basename "$file")"
        fi
    done

    mkdir -p "$STATE_DIR"
    printf '%s\n' "$to" >"$STATE_DIR/version.tmp"
    mv -f "$STATE_DIR/version.tmp" "$STATE_DIR/version"
}
