# shellcheck shell=bash
# Package catalog selection, per-application picker and installation.
[[ -n ${_DOTFILES_PACKAGES:-} ]] && return 0
_DOTFILES_PACKAGES=1

SELECTED_CATEGORIES=()
SELECTED_APPLICATIONS=()
declare -gA PACKAGE_INSTALLED=()

CATALOG="$DOTFILES_DIR/packages/catalog.tsv"
LOCAL_CATALOG="$DOTFILES_DIR/packages/local.tsv"

# The order is the order of the category tabs in the installer.
CATEGORY_ORDER=(
    System Desktop Hyprland Audio Network Development Games Virtualization
    Fonts Drivers Terminal Launcher Bar Notifications Browser Files Editor
    Music "System Monitor" Session Media Local
)

catalog_lines() {
    local file
    for file in "$CATALOG" "$LOCAL_CATALOG"; do
        [[ -r $file ]] || continue
        awk 'NF && $0 !~ /^#/' "$file"
    done
}

catalog_categories() {
    local category
    for category in "${CATEGORY_ORDER[@]}"; do
        if catalog_lines | awk -F'\t' -v c="$category" '$2 == c { found = 1 } END { exit !found }'; then
            printf '%s\n' "$category"
        fi
    done
    catalog_lines | awk -F'\t' '{ print $2 }' | sort -u | while IFS= read -r category; do
        case " ${CATEGORY_ORDER[*]} " in
            *" $category "*) ;;
            *) printf '%s\n' "$category" ;;
        esac
    done
}

catalog_category_count() {
    catalog_lines | awk -F'\t' -v c="$1" '$2 == c { n++ } END { print n + 0 }'
}

catalog_category_defaults() {
    catalog_lines | awk -F'\t' -v c="$1" '$2 == c && $4 == "yes" { n++ } END { print n + 0 }'
}

# Prints package<TAB>role<TAB>default<TAB>host<TAB>gpu<TAB>description.
catalog_rows_for_category() {
    catalog_lines | awk -F'\t' -v c="$1" '$2 == c'
}

catalog_current_host() {
    printf '%s' "${HOST_NAME:-}"
}

catalog_current_gpu() {
    printf '%s' "${GPU_PROFILE:-}"
}

catalog_applicable() {
    local row_host="$1" row_gpu="$2"
    local host gpu
    host="$(catalog_current_host)"
    gpu="$(catalog_current_gpu)"

    [[ $row_host == any || -z $host || $row_host == "$host" ]] || return 1
    if [[ $row_gpu == any || -z $gpu ]]; then
        return 0
    fi
    [[ ",$row_gpu," == *",$gpu,"* ]]
}

# Prints the default packages for the current host and GPU.
catalog_default_packages() {
    local pkg _category _role default host gpu _description
    while IFS=$'\t' read -r pkg _category _role default host gpu _description; do
        [[ $default == yes ]] || continue
        catalog_applicable "$host" "$gpu" || continue
        printf '%s\n' "$pkg"
    done < <(catalog_lines)
}

catalog_default_packages_for_category() {
    local category="$1"
    local pkg _category _role default host gpu _description
    while IFS=$'\t' read -r pkg _category _role default host gpu _description; do
        [[ $default == yes ]] || continue
        catalog_applicable "$host" "$gpu" || continue
        printf '%s\n' "$pkg"
    done < <(catalog_rows_for_category "$category")
}

# Prints every package the catalog knows about, regardless of host or default.
catalog_all_packages() {
    catalog_lines | cut -f1
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
    # Spicetify is not a pacman package.
    command -v spicetify >/dev/null 2>&1 && PACKAGE_INSTALLED[spicetify-cli]=1
}

app_installed() {
    package_installed_map
    [[ -n ${PACKAGE_INSTALLED[$1]:-} ]] && printf '1' || printf '0'
}

# Kept for callers that want a friendly label. Catalog categories already use
# the names shown to the user.
app_category_label() {
    printf '%s' "$1"
}

# Colour and weight are used only in gum; every other backend gets the symbols.
app_style_picker() {
    [[ ${DOTFILES_PLAIN:-0} == 1 ]] && return 1
    [[ $(tui_backend) == gum ]]
}

app_label() {
    local role="$1" pkg="$2" installed="$3" description="${4:-}"
    local label symbol text

    case "$role" in
        main)
            symbol="$(tui_symbol star)"
            text="main, config in repo"
            ;;
        alt)
            symbol="$(tui_symbol circle)"
            text="alternative, package only"
            ;;
        *)
            symbol="$(tui_symbol dot)"
            text="package"
            ;;
    esac

    label="$symbol $pkg — $text"
    if [[ -n $description ]]; then
        description="${description//,/;}"
        label+=" — ${description:0:80}"
    fi
    [[ $installed == 1 ]] && label+=" $(tui_symbol check)"

    if app_style_picker; then
        if [[ $role == main ]]; then
            printf '\033[1m%s\033[0m' "$label"
        elif [[ $role == alt ]]; then
            printf '\033[2m%s\033[0m' "$label"
        else
            printf '%s' "$label"
        fi
    else
        printf '%s' "$label"
    fi
}

select_categories() {
    local -a categories=() labels=()
    local category

    SELECTED_CATEGORIES=()
    mapfile -t categories < <(catalog_categories)

    [[ -n ${PACKAGES_ARG:-} ]] && return 0
    ((${#categories[@]} == 0)) && return 0

    if [[ -n ${CATEGORY_ARG:-} ]]; then
        local -a names=()
        IFS=',' read -r -a names <<<"$CATEGORY_ARG"
        local name
        for name in "${names[@]}"; do
            [[ -n $name ]] || continue
            if ! printf '%s\n' "${categories[@]}" | grep -Fxq -- "$name"; then
                die "unknown package category: $name"
            fi
            SELECTED_CATEGORIES+=("$name")
        done
        return 0
    fi

    if (( ALL )); then
        SELECTED_CATEGORIES=("${categories[@]}")
        return 0
    fi

    # Non-interactive mode without --all: install no packages.
    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        return 0
    fi

    for category in "${categories[@]}"; do
        labels+=("$category — $(catalog_category_count "$category") packages, $(catalog_category_defaults "$category") by default")
    done

    TUI_CHECKED_ITEMS=()
    tui_checklist "Package categories" "${labels[@]}"
    local line
    for line in "${TUI_SELECTION[@]}"; do
        SELECTED_CATEGORIES+=("${line%% — *}")
    done
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

    if (( ALL )); then
        mapfile -t SELECTED_APPLICATIONS < <(catalog_default_packages)
        return 0
    fi

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        # A category without a terminal selects its defaults. With no category
        # the caller asked for nothing.
        if [[ -n ${CATEGORY_ARG:-} ]]; then
            local category
            for category in "${SELECTED_CATEGORIES[@]}"; do
                while IFS= read -r pkg; do
                    SELECTED_APPLICATIONS+=("$pkg")
                done < <(catalog_default_packages_for_category "$category")
            done
        fi
        return 0
    fi

    local category pkg role default host gpu description
    local -a packages=() labels=() checked=()
    local index

    tui_legend
    for category in "${SELECTED_CATEGORIES[@]}"; do
        packages=()
        labels=()
        checked=()

        while IFS=$'\t' read -r pkg _category role default host gpu description; do
            catalog_applicable "$host" "$gpu" || continue
            packages+=("$pkg")
            labels+=("$(app_label "$role" "$pkg" "$(app_installed "$pkg")" "$description")")
            [[ $default == yes ]] && checked+=("${labels[-1]}")
        done < <(catalog_rows_for_category "$category")

        ((${#labels[@]})) || continue

        # shellcheck disable=SC2034 # read by tui_checklist_indexes
        TUI_CHECKED_ITEMS=("${checked[@]}")
        tui_checklist_indexes "$category" "${labels[@]}"
        for index in "${TUI_SELECTION_INDEXES[@]}"; do
            SELECTED_APPLICATIONS+=("${packages[$index]}")
        done
    done
}

collect_packages() {
    printf '%s\n' "${SELECTED_APPLICATIONS[@]:-}" | sed '/^$/d' | sort -u
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

    # Spicetify is installed by its upstream script, not by pacman or an AUR
    # helper. Keep it in the catalog so it sits with the other Music apps.
    local -a script_packages=() manager_packages=()
    for pkg in "${missing[@]}"; do
        case "$pkg" in
            spicetify-cli) script_packages+=("$pkg") ;;
            *)             manager_packages+=("$pkg") ;;
        esac
    done
    if ((${#script_packages[@]})); then
        run bash "$DOTFILES_DIR/scripts/install-spicetify.sh" --yes
    fi
    missing=("${manager_packages[@]}")
    ((${#missing[@]})) || return 0

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
