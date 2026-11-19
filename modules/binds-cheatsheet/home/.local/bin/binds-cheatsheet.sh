#!/usr/bin/env bash
# Hyprland keybind cheatsheet generated from the Lua configuration.
#
# Hyprland 0.57 with Lua dispatchers reports opaque numeric arguments in
# `hyprctl binds -j`, so the readable source is the config itself:
#   ~/.config/hypr/hyprland.lua
#
# Output: plain table (default), markdown, JSON, or a rofi menu.
set -uo pipefail

REAL_HOME="${HOME:?HOME is not set}"
CONFIG="${HYPRLAND_CONFIG:-$REAL_HOME/.config/hypr/hyprland.lua}"

MODE="plain"
CHECK_DUPLICATES=0

usage() {
    cat <<'EOF'
Usage: binds-cheatsheet.sh [options]

  --plain         aligned table (default)
  --markdown      markdown table
  --json          JSON array of {keybind, action, dynamic}
  --rofi          show the table in rofi (falls back to plain)
  --duplicates    print duplicate keybinds and exit 1 when any exist
  --file PATH     parse another Hyprland Lua config
  -h, --help      this help
EOF
}

die() { printf 'binds-cheatsheet: %s\n' "$*" >&2; exit 1; }

while (($#)); do
    case "$1" in
        --plain)      MODE="plain" ;;
        --markdown)   MODE="markdown" ;;
        --json)       MODE="json" ;;
        --rofi)       MODE="rofi" ;;
        --duplicates) CHECK_DUPLICATES=1 ;;
        --file)       CONFIG="${2:?missing value for --file}"; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

[[ -r $CONFIG ]] || die "cannot read config: $CONFIG"

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

# Variables from the [VAR] section, e.g. local terminal = "kitty".
declare -A VARS=()
while IFS= read -r line; do
    if [[ $line =~ ^local[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
        VARS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    elif [[ $line =~ ^local[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*os\.getenv\(\"HOME\"\)[[:space:]]*\.\.[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
        VARS["${BASH_REMATCH[1]}"]="$REAL_HOME${BASH_REMATCH[2]}"
    fi
done <"$CONFIG"

# Split at the first top-level comma, ignoring commas inside quotes/brackets.
split_bind_args() {
    local text="$1"
    local i ch depth=0 quote="" left="" right=""

    for ((i = 0; i < ${#text}; i++)); do
        ch="${text:i:1}"
        if [[ -n $quote ]]; then
            [[ $ch == "$quote" ]] && quote=""
            left+="$ch"
            continue
        fi
        case "$ch" in
            '"'|"'") quote="$ch"; left+="$ch" ;;
            '('|'['|'{') depth=$((depth + 1)); left+="$ch" ;;
            ')'|']'|'}') depth=$((depth - 1)); left+="$ch" ;;
            ,) if ((depth == 0)); then right="${text:i+1}"; break; else left+="$ch"; fi ;;
            *) left+="$ch" ;;
        esac
    done

    printf '%s\t%s\n' "$(trim "$left")" "$(trim "$right")"
}

resolve_expr() {
    local expr
    expr="$(trim "$1")"

    if [[ $expr =~ ^\"(.*)\"$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ $expr =~ ^\'(.*)\'$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ -n ${VARS[$expr]:-} ]]; then
        printf '%s' "${VARS[$expr]}"
        return 0
    fi
    printf '%s' "$expr"
}

normalize_key() {
    local expr="$1"
    local dynamic=0 key stripped

    stripped="${expr//mainMod/}"
    stripped="$(printf '%s' "$stripped" | sed 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')"
    if [[ $stripped =~ [A-Za-z_] ]]; then
        dynamic=1
    fi

    key="${expr//mainMod/SUPER}"
    key="${key//\"/}"
    key="${key//\'/}"
    key="${key//../}"
    key="$(printf '%s' "$key" | tr -s ' ')"
    key="$(trim "$key")"
    key="$(printf '%s' "$key" | sed 's/[[:space:]]*+[[:space:]]*/ + /g')"
    if ((dynamic)); then
        key="$(printf '%s' "$key" | sed 's/[^[:space:]]*$/<dynamic>/')"
    fi

    printf '%s\t%s\n' "$key" "$dynamic"
}

# Content of the first balanced (...) call after a prefix, e.g. exec_cmd(...).
extract_call_arg() {
    local text="$1" prefix="$2"
    local rest="${text#*"$prefix"}"
    local i ch depth=0 quote="" inner=""

    [[ $rest == "("* ]] || return 1
    for ((i = 1; i < ${#rest}; i++)); do
        ch="${rest:i:1}"
        if [[ -n $quote ]]; then
            [[ $ch == "$quote" ]] && quote=""
            inner+="$ch"
            continue
        fi
        case "$ch" in
            '"'|"'") quote="$ch"; inner+="$ch" ;;
            '(') depth=$((depth + 1)); inner+="$ch" ;;
            ')') if ((depth == 0)); then break; else depth=$((depth - 1)); inner+="$ch"; fi ;;
            *) inner+="$ch" ;;
        esac
    done

    printf '%s' "$inner"
}

normalize_action() {
    local action
    action="$(trim "$1")"

    if [[ $action == *'hl.dsp.exec_cmd('* ]]; then
        printf 'exec: %s' "$(resolve_expr "$(extract_call_arg "$action" 'hl.dsp.exec_cmd')")"
        return 0
    fi
    if [[ $action == *'window.close()'* ]]; then
        printf 'close window'
        return 0
    fi
    if [[ $action == *'window.float'* ]]; then
        printf 'toggle floating'
        return 0
    fi
    if [[ $action == *'window.fullscreen'* ]]; then
        printf 'toggle fullscreen'
        return 0
    fi
    if [[ $action =~ hl\.dsp\.focus\(\{[^}]*workspace[[:space:]]*=[[:space:]]*\"?([^\"}]+)\"? ]]; then
        printf 'focus workspace %s' "$(trim "${BASH_REMATCH[1]}")"
        return 0
    fi
    if [[ $action =~ hl\.dsp\.window\.move\(\{[^}]*workspace[[:space:]]*=[[:space:]]*\"?([^\"}]+)\"? ]]; then
        printf 'move window to workspace %s' "$(trim "${BASH_REMATCH[1]}")"
        return 0
    fi
    if [[ $action =~ hl\.dsp\.focus\(\{[^}]*direction[[:space:]]*=[[:space:]]*\"([a-z]+)\" ]]; then
        printf 'focus %s' "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ $action =~ hl\.dsp\.workspace\.toggle_special\(\"([^\"]+)\" ]]; then
        printf 'toggle special workspace %s' "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ $action =~ hl\.dsp\.layout\(\"([^\"]+)\" ]]; then
        printf 'layout %s' "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ $action == *'window.drag()'* ]]; then
        printf 'drag window'
        return 0
    fi
    if [[ $action == *'window.resize()'* ]]; then
        printf 'resize window'
        return 0
    fi
    if [[ $action == 'function('* ]]; then
        printf 'dynamic workspace bind'
        return 0
    fi

    printf '%s' "$action"
}

KEYS=()
ACTIONS=()
DYNAMIC=()

while IFS= read -r line; do
    [[ $line == *'hl.bind('* ]] || continue

    rest="${line#*hl.bind(}"
    IFS=$'\t' read -r key_expr action_expr < <(split_bind_args "$rest")
    [[ -n $key_expr ]] || continue

    IFS=$'\t' read -r key dynamic < <(normalize_key "$key_expr")
    action="$(normalize_action "$action_expr")"

    KEYS+=("$key")
    ACTIONS+=("$action")
    DYNAMIC+=("$dynamic")
done <"$CONFIG"

if ((${#KEYS[@]} == 0)); then
    die "no hl.bind() lines found in $CONFIG"
fi

# ------------------------------------------------------------- duplicates ----

find_duplicates() {
    local i found=0
    local -A seen=()

    for i in "${!KEYS[@]}"; do
        ((DYNAMIC[i])) && continue
        if [[ -n ${seen[${KEYS[$i]}]:-} ]]; then
            printf '%s\n' "${KEYS[$i]}"
            found=1
        fi
        seen["${KEYS[$i]}"]=1
    done

    return "$found"
}

if ((CHECK_DUPLICATES)); then
    duplicates="$(find_duplicates)"
    if [[ -z $duplicates ]]; then
        printf 'No duplicate keybinds.\n'
        exit 0
    fi
    printf 'Duplicate keybinds:\n'
    printf '  %s\n' "$duplicates" | sort -u
    exit 1
fi

# ------------------------------------------------------------------ output ---

print_plain() {
    local i width=4
    for i in "${!KEYS[@]}"; do
        ((${#KEYS[$i]} > width)) && width=${#KEYS[$i]}
    done

    printf '%-*s  %s\n' "$width" "KEYBIND" "ACTION"
    for i in "${!KEYS[@]}"; do
        printf '%-*s  %s\n' "$width" "${KEYS[$i]}" "${ACTIONS[$i]}"
    done
}

print_markdown() {
    local i action
    printf '| Keybind | Action |\n'
    printf '|---------|--------|\n'
    for i in "${!KEYS[@]}"; do
        action="${ACTIONS[$i]//|/\\|}"
        # shellcheck disable=SC2016
        printf '| `%s` | %s |\n' "${KEYS[$i]}" "$action"
    done
}

print_json() {
    local i
    printf '['
    for i in "${!KEYS[@]}"; do
        ((i)) && printf ','
        printf '{"keybind":"%s","action":"%s","dynamic":%s}' \
            "$(json_escape "${KEYS[$i]}")" \
            "$(json_escape "${ACTIONS[$i]}")" \
            "$([[ ${DYNAMIC[$i]} == 1 ]] && echo true || echo false)"
    done
    printf ']\n'
}

print_rofi() {
    local i
    local -a rows=()

    for i in "${!KEYS[@]}"; do
        rows+=("$(printf '%-28s %s' "${KEYS[$i]}" "${ACTIONS[$i]}")")
    done

    if command -v rofi >/dev/null 2>&1 && [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
        printf '%s\n' "${rows[@]}" | rofi -theme "${XDG_CONFIG_HOME:-$HOME/.config}/rofi/launcher.rasi" -dmenu -p "Hyprland binds" -no-custom
    else
        print_plain
    fi
}

case "$MODE" in
    plain)    print_plain ;;
    markdown) print_markdown ;;
    json)     print_json ;;
    rofi)     print_rofi ;;
esac
