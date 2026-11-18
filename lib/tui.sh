# shellcheck shell=bash
# Minimal TUI abstraction: gum -> whiptail -> dialog -> plain bash.
[[ -n ${_DOTFILES_TUI:-} ]] && return 0
_DOTFILES_TUI=1

TUI_SELECTION=()
TUI_SELECTION_INDEXES=()
TUI_CHECKED_ITEMS=()
TUI_CHOICE=""
TUI_CHOICE_INDEX=-1

tui_has_gum()      { command -v gum >/dev/null 2>&1; }
tui_has_whiptail() { command -v whiptail >/dev/null 2>&1; }
tui_has_dialog()   { command -v dialog >/dev/null 2>&1; }

# The first available full-screen dialog tool, if any.
tui_dialog_tool() {
    if tui_has_whiptail; then
        printf 'whiptail'
    elif tui_has_dialog; then
        printf 'dialog'
    fi
}

# Which backend will be used, for styling decisions.
tui_backend() {
    if tui_has_gum; then
        printf 'gum'
    elif [[ -n $(tui_dialog_tool) && -t 0 ]]; then
        tui_dialog_tool
    else
        printf 'plain'
    fi
}

tui_utf8() {
    [[ $(locale charmap 2>/dev/null) == UTF-8 ]]
}

# Unicode symbols with an ASCII fallback for non-UTF-8 terminals.
tui_ascii() {
    [[ ${DOTFILES_ASCII:-0} == 1 ]] || ! tui_utf8
}

tui_symbol() {
    local name="$1" ascii=0
    tui_ascii && ascii=1
    case "$name" in
        star)
            if (( ascii )); then printf '[*]'; else printf '★'; fi ;;
        circle)
            if (( ascii )); then printf '[ ]'; else printf '○'; fi ;;
        dot)
            if (( ascii )); then printf '[p]'; else printf '•'; fi ;;
        check)
            if (( ascii )); then printf '[i]'; else printf '✓'; fi ;;
        unavailable)
            if (( ascii )); then printf '[-]'; else printf '⊘'; fi ;;
        *) printf '%s' "$name" ;;
    esac
}

tui_header() {
    if tui_has_gum; then
        gum style --border normal --border-foreground 6 --padding "0 1" --margin "0 0" "$1"
    else
        printf '\n%s\n' "$1"
        printf '%*s\n' "${#1}" '' | tr ' ' '─'
    fi
}

tui_legend() {
    printf '%s %s   %s %s   %s %s\n' \
        "$(tui_symbol star)" "main (config in repo)" \
        "$(tui_symbol circle)" "alternative (package only)" \
        "$(tui_symbol check)" "installed"
}

tui_confirm() {
    local prompt="$1" default="${2:-no}"

    if (( ASSUME_YES )); then
        return 0
    fi

    # Without a terminal there is nobody to answer; treat it as "no".
    if [[ ! -t 0 ]]; then
        return 1
    fi

    if tui_has_gum; then
        if [[ $default == yes ]]; then
            gum confirm --default=true "$prompt"
        else
            gum confirm --default=false "$prompt"
        fi
        return $?
    fi

    local tool
    tool="$(tui_dialog_tool)"
    if [[ -n $tool ]]; then
        "$tool" --yesno "$prompt" 0 0
        return $?
    fi

    local reply
    printf '%s [%s]: ' "$prompt" "$([[ $default == yes ]] && echo 'Y/n' || echo 'y/N')"
    read -r reply || true
    reply="${reply:-$default}"
    [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
}

tui_input() {
    local prompt="$1" default="${2:-}"

    if (( ASSUME_YES )); then
        printf '%s\n' "$default"
        return 0
    fi

    if tui_has_gum; then
        gum input --prompt "$prompt: " --value "$default"
        return 0
    fi

    local tool
    tool="$(tui_dialog_tool)"
    if [[ -n $tool && -t 0 ]]; then
        local value
        if [[ $tool == whiptail ]]; then
            value="$(whiptail --inputbox "$prompt" 0 0 "$default" 3>&1 1>&2 2>&3)" || return 1
        else
            value="$(dialog --inputbox "$prompt" 0 0 "$default" 3>&1 1>&2 2>&3)" || return 1
        fi
        printf '%s\n' "$value"
        return 0
    fi

    if [[ ! -t 0 ]]; then
        printf '%s\n' "$default"
        return 0
    fi

    local reply
    printf '%s [%s]: ' "$prompt" "$default"
    read -r reply || true
    printf '%s\n' "${reply:-$default}"
}

# Print the chosen index (0-based). A negative default means "no default".
tui_radio_index() {
    local title="$1" default="$2"
    shift 2
    local items=("$@")
    local i

    ((${#items[@]} == 0)) && return 1

    if tui_has_gum; then
        local choice
        choice="$(printf '%s\n' "${items[@]}" | gum choose --header "$title")" || return 1
        for i in "${!items[@]}"; do
            if [[ ${items[$i]} == "$choice" ]]; then
                printf '%s\n' "$i"
                return 0
            fi
        done
        return 1
    fi

    local tool
    tool="$(tui_dialog_tool)"
    if [[ -n $tool && -t 0 ]]; then
        local args=() choice
        for i in "${!items[@]}"; do
            args+=("$i" "${items[$i]}")
        done
        local default_args=()
        if (( default >= 0 && default < ${#items[@]} )); then
            default_args=(--default-item "$default")
        fi
        if [[ $tool == whiptail ]]; then
            choice="$(whiptail --title "$title" --menu "$title" 0 0 0 "${default_args[@]}" "${args[@]}" 3>&1 1>&2 2>&3)" || return 1
        else
            choice="$(dialog --title "$title" --menu "$title" 0 0 0 "${default_args[@]}" "${args[@]}" 3>&1 1>&2 2>&3)" || return 1
        fi
        if [[ $choice =~ ^[0-9]+$ ]] && ((choice < ${#items[@]})); then
            printf '%s\n' "$choice"
            return 0
        fi
        return 1
    fi

    if [[ ! -t 0 ]]; then
        return 1
    fi

    local choice
    printf '\n%s\n' "$title"
    for i in "${!items[@]}"; do
        printf '  %2d) %s\n' "$((i + 1))" "${items[$i]}"
    done
    while true; do
        if (( default >= 0 && default < ${#items[@]} )); then
            printf 'Select 1-%d [%d]: ' "${#items[@]}" "$((default + 1))"
        else
            printf 'Select 1-%d: ' "${#items[@]}"
        fi
        read -r choice || return 1
        if [[ -z $choice ]] && (( default >= 0 && default < ${#items[@]} )); then
            printf '%s\n' "$default"
            return 0
        fi
        if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#items[@]})); then
            printf '%s\n' "$((choice - 1))"
            return 0
        fi
        printf 'Invalid selection.\n'
    done
}

tui_radio() {
    local title="$1"
    shift
    local items=("$@")
    local index
    index="$(tui_radio_index "$title" -1 "${items[@]}")" || return 1
    printf '%s\n' "${items[$index]}"
}

# Fill TUI_SELECTION_INDEXES with the chosen 0-based indexes. Items listed in
# TUI_CHECKED_ITEMS start selected.
tui_checklist_indexes() {
    local title="$1"
    shift
    local items=("$@")
    local i checked
    TUI_SELECTION_INDEXES=()

    ((${#items[@]} == 0)) && return 0

    if tui_has_gum; then
        local line
        local -a selected=()

        for checked in "${TUI_CHECKED_ITEMS[@]}"; do
            for i in "${!items[@]}"; do
                if [[ ${items[$i]} == "$checked" ]]; then
                    selected+=("$i")
                    break
                fi
            done
        done

        local -a args=(--no-limit --header "$title")
        if ((${#selected[@]})); then
            local list=""
            for i in "${selected[@]}"; do
                list+="${items[$i]},"
            done
            args+=(--selected "${list%,}")
        fi

        while IFS= read -r line; do
            [[ -n $line ]] || continue
            for i in "${!items[@]}"; do
                if [[ ${items[$i]} == "$line" ]]; then
                    TUI_SELECTION_INDEXES+=("$i")
                    break
                fi
            done
        done < <(printf '%s\n' "${items[@]}" | gum choose "${args[@]}")
        return 0
    fi

    local tool
    tool="$(tui_dialog_tool)"
    if [[ -n $tool && -t 0 ]]; then
        local args=() selected tag state
        for i in "${!items[@]}"; do
            state="OFF"
            for checked in "${TUI_CHECKED_ITEMS[@]}"; do
                [[ ${items[$i]} == "$checked" ]] && state="ON" && break
            done
            args+=("$i" "${items[$i]}" "$state")
        done
        if [[ $tool == whiptail ]]; then
            selected="$(whiptail --title "$title" --checklist "$title" 0 0 0 "${args[@]}" 3>&1 1>&2 2>&3)" || return 0
        else
            selected="$(dialog --title "$title" --checklist "$title" 0 0 0 "${args[@]}" 3>&1 1>&2 2>&3)" || return 0
        fi
        for tag in $selected; do
            tag="${tag//\"/}"
            if [[ $tag =~ ^[0-9]+$ ]] && ((tag < ${#items[@]})); then
                TUI_SELECTION_INDEXES+=("$tag")
            fi
        done
        return 0
    fi

    if [[ ! -t 0 ]]; then
        return 0
    fi

    local -a choice=() defaults=()
    printf '\n%s\n' "$title"
    for i in "${!items[@]}"; do
        printf '  %2d) %s\n' "$((i + 1))" "${items[$i]}"
    done
    for i in "${!items[@]}"; do
        for checked in "${TUI_CHECKED_ITEMS[@]}"; do
            [[ ${items[$i]} == "$checked" ]] && defaults+=("$((i + 1))")
        done
    done
    if ((${#defaults[@]})); then
        printf 'Numbers separated by spaces (empty = keep %s): ' "${defaults[*]}"
    else
        printf 'Numbers separated by spaces (empty = none): '
    fi
    read -r -a choice || true
    if ((${#choice[@]} == 0)) && ((${#defaults[@]})); then
        for i in "${defaults[@]}"; do
            TUI_SELECTION_INDEXES+=("$((i - 1))")
        done
        return 0
    fi
    for i in "${choice[@]}"; do
        if [[ $i =~ ^[0-9]+$ ]] && ((i >= 1 && i <= ${#items[@]})); then
            TUI_SELECTION_INDEXES+=("$((i - 1))")
        fi
    done
}

tui_checklist() {
    local title="$1"
    shift
    local items=("$@")
    local index
    TUI_SELECTION=()

    tui_checklist_indexes "$title" "${items[@]}"
    for index in "${TUI_SELECTION_INDEXES[@]}"; do
        TUI_SELECTION+=("${items[$index]}")
    done
}

# A menu entry is "key|label|description". Sets TUI_CHOICE to the key.
tui_menu() {
    local title="$1"
    shift
    local entries=("$@")
    local entry key label description
    local -a keys=() labels=()

    for entry in "${entries[@]}"; do
        IFS='|' read -r key label description <<<"$entry"
        keys+=("$key")
        labels+=("$label — $description")
    done

    local index
    index="$(tui_radio_index "$title" 0 "${labels[@]}")" || return 1
    # shellcheck disable=SC2034 # read by callers (menu.sh, packages.sh)
    TUI_CHOICE_INDEX="$index"
    # shellcheck disable=SC2034 # read by callers
    TUI_CHOICE="${keys[$index]}"
}
