# shellcheck shell=bash
# Package category selection, application picker and installation.
[[ -n ${_DOTFILES_PACKAGES:-} ]] && return 0
_DOTFILES_PACKAGES=1

SELECTED_CATEGORIES=()
SELECTED_APPLICATIONS=()
declare -gA PACKAGE_INSTALLED=()

APP_REGISTRY="$DOTFILES_DIR/packages/alternatives.txt"
APP_CATEGORY_ORDER=(terminal launcher status-bar notifications browser file-manager editor music system-monitor)

category_files() {
    find "$DOTFILES_DIR/packages" -maxdepth 1 -type f -name '*.txt' ! -name 'alternatives.txt' -printf '%f\n' | sort
}

category_count() {
    local file="$DOTFILES_DIR/packages/$1"
    grep -cvE '^[[:space:]]*(#|$)' -- "$file" || true
}

package_manager() {
    if command -v pacman >/dev/null 2>&1; then
        printf 'pacman\n'
    elif command -v apt-get >/dev/null 2>&1; then
        printf 'apt\n'
    elif command -v dnf >/dev/null 2>&1; then
        printf 'dnf\n'
    else
        printf 'unknown\n'
    fi
}

package_installed_map() {
    ((${#PACKAGE_INSTALLED[@]})) && return 0
    command -v pacman >/dev/null 2>&1 || return 0
    local pkg
    while IFS= read -r pkg; do
        [[ -n $pkg ]] && PACKAGE_INSTALLED["$pkg"]=1
    done < <(pacman -Qq 2>/dev/null || true)
}

app_installed() {
    package_installed_map
    [[ -n ${PACKAGE_INSTALLED[$1]:-} ]] && printf '1' || printf '0'
}

app_category_label() {
    case "$1" in
        terminal)       printf 'Terminal' ;;
        launcher)       printf 'Launcher' ;;
        status-bar)     printf 'Bar' ;;
        notifications)  printf 'Notifications' ;;
        browser)        printf 'Browser' ;;
        file-manager)   printf 'File manager' ;;
        editor)         printf 'Editor' ;;
        music)          printf 'Music' ;;
        system-monitor) printf 'Other (system monitor)' ;;
        *)              printf '%s' "$1" ;;
    esac
}

# Colour and weight are used only in gum; every other backend gets the symbols.
app_style_picker() {
    [[ ${DOTFILES_PLAIN:-0} == 1 ]] && return 1
    [[ $(tui_backend) == gum ]]
}

app_label() {
    local role="$1" pkg="$2" installed="$3" label symbol text
    if [[ $role == main ]]; then
        symbol="$(tui_symbol star)"
        text="main, config in repo"
    else
        symbol="$(tui_symbol circle)"
        text="alternative, package only"
    fi
    label="$symbol $pkg — $text"
    [[ $installed == 1 ]] && label+=" $(tui_symbol check)"

    if app_style_picker; then
        if [[ $role == main ]]; then
            printf '\033[1m%s\033[0m' "$label"
        else
            printf '\033[2m%s\033[0m' "$label"
        fi
    else
        printf '%s' "$label"
    fi
}

select_categories() {
    local files=() labels=() file
    mapfile -t files < <(category_files)
    SELECTED_CATEGORIES=()

    if [[ -n ${PACKAGES_ARG:-} ]]; then
        return 0
    fi

    if ((${#files[@]} == 0)); then
        return 0
    fi

    if [[ -n ${GROUPS_ARG:-} ]]; then
        local -a names=()
        IFS=',' read -r -a names <<<"$GROUPS_ARG"
        local name
        for name in "${names[@]}"; do
            [[ -n $name ]] || continue
            [[ $name == *.txt ]] || name="$name.txt"
            [[ -r $DOTFILES_DIR/packages/$name ]] || die "unknown package group: $name"
            SELECTED_CATEGORIES+=("$name")
        done
        return 0
    fi

    if (( ALL )); then
        SELECTED_CATEGORIES=("${files[@]}")
        return 0
    fi

    # Non-interactive mode without --all: install no package groups.
    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        return 0
    fi

    for file in "${files[@]}"; do
        labels+=("${file} — $(category_count "$file") packages")
    done

    tui_checklist "Package groups to install" "${labels[@]}"
    local line
    for line in "${TUI_SELECTION[@]}"; do
        SELECTED_CATEGORIES+=("${line%% — *}")
    done
}

app_pick_category() {
    local category="$1"
    local -a mains=() alts=() labels=()
    local pkg cat role note entry index main_pkg=""

    while IFS=$'\t' read -r pkg cat role note; do
        [[ -z $pkg || $pkg == \#* ]] && continue
        [[ $cat == "$category" ]] || continue
        case "$role" in
            main) mains+=("$pkg|$note") ;;
            alt)  alts+=("$pkg|$note") ;;
        esac
    done <"$APP_REGISTRY"

    if ((${#mains[@]})); then
        for entry in "${mains[@]}"; do
            pkg="${entry%%|*}"
            labels+=("$(app_label main "$pkg" "$(app_installed "$pkg")")")
        done
        labels+=("(none)")

        index="$(tui_radio_index "Main application: $(app_category_label "$category")" 0 "${labels[@]}")" || return 0
        if (( index < ${#mains[@]} )); then
            main_pkg="${mains[$index]%%|*}"
            SELECTED_APPLICATIONS+=("$main_pkg")
        fi
    fi

    if ((${#alts[@]})); then
        labels=()
        for entry in "${alts[@]}"; do
            pkg="${entry%%|*}"
            labels+=("$(app_label alt "$pkg" "$(app_installed "$pkg")")")
        done
        tui_checklist_indexes "Alternatives: $(app_category_label "$category")" "${labels[@]}"

        local -a chosen=()
        local idx
        for idx in "${TUI_SELECTION_INDEXES[@]}"; do
            chosen+=("${alts[$idx]%%|*}")
        done

        if ((${#chosen[@]})) && [[ -n $main_pkg ]]; then
            warn "config exists only for $main_pkg; ${chosen[*]} will be package-only"
            if ! tui_confirm "Install the alternatives anyway?" no; then
                chosen=()
            fi
        fi
        if ((${#chosen[@]})); then
            SELECTED_APPLICATIONS+=("${chosen[@]}")
        fi
    fi
}

select_apps() {
    SELECTED_APPLICATIONS=()

    if [[ -n ${PACKAGES_ARG:-} ]]; then
        IFS=',' read -r -a SELECTED_APPLICATIONS <<<"$PACKAGES_ARG"
        return 0
    fi

    if [[ -n ${APPS_ARG:-} ]]; then
        IFS=',' read -r -a SELECTED_APPLICATIONS <<<"$APPS_ARG"
        return 0
    fi

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        return 0
    fi
    [[ -r $APP_REGISTRY ]] || return 0

    local -a categories=() labels=()
    local category count index
    for category in "${APP_CATEGORY_ORDER[@]}"; do
        count="$(awk -F'\t' -v c="$category" '$1 !~ /^#/ && $2 == c { n++ } END { print n + 0 }' "$APP_REGISTRY")"
        (( count )) || continue
        categories+=("$category")
        labels+=("$(app_category_label "$category") ($count apps)")
    done

    if ((${#categories[@]} == 0)); then
        return 0
    fi

    tui_legend
    tui_checklist_indexes "Application categories (optional)" "${labels[@]}"
    for index in "${TUI_SELECTION_INDEXES[@]}"; do
        app_pick_category "${categories[$index]}"
    done
}

collect_packages() {
    local -a pkgs=()
    local category pkg
    local file

    for category in "${SELECTED_CATEGORIES[@]}"; do
        file="$DOTFILES_DIR/packages/$category"
        while IFS= read -r pkg; do
            [[ -z $pkg || $pkg == \#* ]] && continue
            pkgs+=("$pkg")
        done <"$file"
    done

    pkgs+=("${SELECTED_APPLICATIONS[@]:-}")
    printf '%s\n' "${pkgs[@]}" | sed '/^$/d' | sort -u
}

install_packages() {
    local -a all=() missing=()
    local pkg
    mapfile -t all < <(collect_packages)

    if ((${#all[@]} == 0)); then
        info "no packages selected"
        return 0
    fi

    package_installed_map
    for pkg in "${all[@]}"; do
        [[ -n ${PACKAGE_INSTALLED[$pkg]:-} ]] || missing+=("$pkg")
    done

    if ((${#missing[@]} == 0)); then
        ok "all selected packages are already installed"
        return 0
    fi

    info "${#missing[@]} package(s) to install:"
    printf '  %s\n' "${missing[@]}"

    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} would install the packages listed above"
        return 0
    fi

    if ! tui_confirm "Install these packages now?" yes; then
        warn "package installation skipped"
        return 0
    fi

    case "$(package_manager)" in
        pacman)
            local -a official=() aur=()
            declare -A OFFICIAL=()
            while IFS= read -r pkg; do OFFICIAL["$pkg"]=1; done < <(pacman -Slq 2>/dev/null || true)
            for pkg in "${missing[@]}"; do
                if [[ -n ${OFFICIAL[$pkg]:-} ]]; then
                    official+=("$pkg")
                else
                    aur+=("$pkg")
                fi
            done
            if ((${#official[@]})); then
                run sudo pacman -S --needed --noconfirm "${official[@]}"
            fi
            if ((${#aur[@]})); then
                local helper=""
                if command -v yay >/dev/null 2>&1; then
                    helper="yay"
                elif command -v paru >/dev/null 2>&1; then
                    helper="paru"
                fi
                if [[ -n $helper ]]; then
                    run "$helper" -S --needed --noconfirm "${aur[@]}"
                else
                    warn "no AUR helper found (yay/paru); install manually:"
                    printf '  %s\n' "${aur[@]}"
                fi
            fi
            ;;
        apt)
            run sudo apt-get install -y "${missing[@]}"
            ;;
        dnf)
            run sudo dnf install -y "${missing[@]}"
            ;;
        *)
            warn "unknown package manager; install manually:"
            printf '  %s\n' "${missing[@]}"
            ;;
    esac
}
