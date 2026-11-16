# shellcheck shell=bash
# Package category selection and installation.
[[ -n ${_DOTFILES_PACKAGES:-} ]] && return 0
_DOTFILES_PACKAGES=1

SELECTED_CATEGORIES=()
SELECTED_ALTERNATIVES=()

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

select_categories() {
    local files=() labels=() file
    mapfile -t files < <(category_files)
    SELECTED_CATEGORIES=()

    if ((${#files[@]} == 0)); then
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

select_alternatives() {
    local file="$DOTFILES_DIR/packages/alternatives.txt"
    SELECTED_ALTERNATIVES=()

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        return 0
    fi
    [[ -r $file ]] || return 0

    local labels=() line pkg category role label
    declare -A LABEL2PKG=()

    while IFS=$'\t' read -r pkg category role _; do
        [[ -z $pkg || $pkg == \#* ]] && continue
        if [[ $role == main ]]; then
            label="[main, config] $pkg — $category"
        else
            label="[package only] $pkg — $category"
        fi
        labels+=("$label")
        LABEL2PKG["$label"]="$pkg"
    done <"$file"

    if ((${#labels[@]} == 0)); then
        return 0
    fi

    tui_checklist "Optional / alternative packages" "${labels[@]}"
    for line in "${TUI_SELECTION[@]}"; do
        [[ -n ${LABEL2PKG[$line]:-} ]] && SELECTED_ALTERNATIVES+=("${LABEL2PKG[$line]}")
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

    pkgs+=("${SELECTED_ALTERNATIVES[@]:-}")
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

    declare -A INSTALLED=()
    if command -v pacman >/dev/null 2>&1; then
        while IFS= read -r pkg; do INSTALLED["$pkg"]=1; done < <(pacman -Qq 2>/dev/null || true)
    fi

    for pkg in "${all[@]}"; do
        [[ -n ${INSTALLED[$pkg]:-} ]] || missing+=("$pkg")
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
