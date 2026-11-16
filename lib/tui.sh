# shellcheck shell=bash
# Minimal TUI abstraction: gum when available, plain bash otherwise.
[[ -n ${_DOTFILES_TUI:-} ]] && return 0
_DOTFILES_TUI=1

TUI_SELECTION=()

tui_has_gum() { command -v gum >/dev/null 2>&1; }

tui_header() {
    if tui_has_gum; then
        gum style --border normal --border-foreground 6 --padding "0 1" --margin "0 0" "$1"
    else
        printf '\n%s\n' "$1"
        printf '%*s\n' "${#1}" '' | tr ' ' '─'
    fi
}

tui_confirm() {
    local prompt="$1" default="${2:-no}"

    if (( ASSUME_YES )); then
        return 0
    fi

    if tui_has_gum; then
        if [[ $default == yes ]]; then
            gum confirm --default=true "$prompt"
        else
            gum confirm --default=false "$prompt"
        fi
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
        return
    fi

    if tui_has_gum; then
        gum input --prompt "$prompt: " --value "$default"
        return
    fi

    local reply
    printf '%s [%s]: ' "$prompt" "$default"
    read -r reply || true
    printf '%s\n' "${reply:-$default}"
}

tui_radio() {
    local title="$1"
    shift
    local items=("$@")

    if tui_has_gum; then
        printf '%s\n' "${items[@]}" | gum choose --header "$title"
        return
    fi

    local i choice
    printf '\n%s\n' "$title"
    for i in "${!items[@]}"; do
        printf '  %2d) %s\n' "$((i + 1))" "${items[$i]}"
    done
    while true; do
        printf 'Select 1-%d: ' "${#items[@]}"
        read -r choice || return 1
        if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
            printf '%s\n' "${items[$((choice - 1))]}"
            return 0
        fi
        printf 'Invalid selection.\n'
    done
}

tui_checklist() {
    local title="$1"
    shift
    local items=("$@")
    TUI_SELECTION=()

    if ((${#items[@]} == 0)); then
        return 0
    fi

    if tui_has_gum; then
        local line
        while IFS= read -r line; do
            [[ -n $line ]] && TUI_SELECTION+=("$line")
        done < <(printf '%s\n' "${items[@]}" | gum choose --no-limit --header "$title")
        return 0
    fi

    local i
    local -a choice=()
    printf '\n%s\n' "$title"
    for i in "${!items[@]}"; do
        printf '  %2d) %s\n' "$((i + 1))" "${items[$i]}"
    done
    printf 'Numbers separated by spaces (empty = none): '
    read -r -a choice || true
    for i in "${choice[@]}"; do
        if [[ $i =~ ^[0-9]+$ ]] && (( i >= 1 && i <= ${#items[@]} )); then
            TUI_SELECTION+=("${items[$((i - 1))]}")
        fi
    done
}
