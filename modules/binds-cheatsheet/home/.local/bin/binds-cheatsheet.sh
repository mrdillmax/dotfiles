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
ADD_KEY=""
ADD_COMMAND=""

usage() {
    cat <<'EOF'
Usage: binds-cheatsheet.sh [options]

  --plain         aligned table (default)
  --markdown      markdown table
  --json          JSON array of {keybind, action, dynamic}
  --rofi          show the table in rofi (falls back to plain)
  --rofi-edit     pick a bind and print "<config>:<line>" for an editor
  --add KEY CMD   append a bind using "SUPER + KEY" (e.g. "SHIFT + X")
  --duplicates    print duplicate keybinds and exit 1 when any exist
  --file PATH     parse another Hyprland Lua config
  -h, --help      this help
EOF
}

die() { printf 'binds-cheatsheet: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok %s\n' "$*" >&2; }

while (($#)); do
    case "$1" in
        --plain)      MODE="plain" ;;
        --markdown)   MODE="markdown" ;;
        --json)       MODE="json" ;;
        --rofi)       MODE="rofi" ;;
        --rofi-edit)  MODE="rofi-edit" ;;
        --add)        MODE="add"; ADD_KEY="${2:?missing key for --add}"; ADD_COMMAND="${3:?missing command for --add}"; shift 2 ;;
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
LINES=()
line_number=0

while IFS= read -r line; do
    ((line_number++))
    [[ $line == *'hl.bind('* ]] || continue

    rest="${line#*hl.bind(}"
    IFS=$'\t' read -r key_expr action_expr < <(split_bind_args "$rest")
    [[ -n $key_expr ]] || continue

    IFS=$'\t' read -r key dynamic < <(normalize_key "$key_expr")
    action="$(normalize_action "$action_expr")"

    KEYS+=("$key")
    ACTIONS+=("$action")
    DYNAMIC+=("$dynamic")
    LINES+=("$line_number")
done <"$CONFIG"

if ((${#KEYS[@]} == 0)); then
    die "no hl.bind() lines found in $CONFIG"
fi

add_bind() {
    local suffix command candidate escaped line_no i

    suffix="$(trim "$1")"
    command="$(trim "$2")"
    [[ -n $suffix ]] || die "missing key after SUPER"
    [[ $suffix =~ ^[A-Za-z0-9_+.[:space:]-]+$ ]] || die "invalid key: $suffix (use letters, digits, +, ., _ or -)"
    [[ -n $command && $command != *$'\n'* ]] || die "the command must be a single non-empty line"

    candidate="SUPER + $suffix"
    candidate="$(printf '%s' "$candidate" | sed 's/[[:space:]]*+[[:space:]]*/ + /g; s/[[:space:]][[:space:]]*/ /g')"
    for i in "${!KEYS[@]}"; do
        [[ ${KEYS[$i]} == "$candidate" ]] && die "keybind already exists: $candidate"
    done

    escaped="${command//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"

    # Insert after the last existing bind so the new line stays in the binds
    # section instead of landing below the window rules at the end of the file.
    local last_bind tmp
    last_bind="$(grep -n 'hl\.bind(' "$CONFIG" | tail -n1 | cut -d: -f1)"
    tmp="$(mktemp)"

    if [[ -n $last_bind ]]; then
        {
            head -n "$last_bind" "$CONFIG"
            printf -- '-- Added by binds-cheatsheet on %s\n' "$(date +%F)"
            printf 'hl.bind(mainMod .. " + %s", hl.dsp.exec_cmd("%s"))\n\n' "$suffix" "$escaped"
            tail -n "+$((last_bind + 1))" "$CONFIG"
        } >"$tmp"
        line_no=$((last_bind + 2))
    else
        {
            cat "$CONFIG"
            [[ -s $CONFIG && -n "$(tail -c1 "$CONFIG")" ]] && printf '\n'
            printf -- '-- Added by binds-cheatsheet on %s\n' "$(date +%F)"
            printf 'hl.bind(mainMod .. " + %s", hl.dsp.exec_cmd("%s"))\n' "$suffix" "$escaped"
        } >"$tmp"
        line_no="$(wc -l <"$tmp")"
    fi

    mv -- "$tmp" "$CONFIG"

    ok "added $candidate"
    printf '%s:%s\n' "$CONFIG" "$line_no"
}

add_bind_prompt() {
    local suffix command
    local theme="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/launcher.rasi"

    if command -v rofi >/dev/null 2>&1 && [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
        suffix="$(printf '\n' | rofi -theme "$theme" -dmenu -p "" -l 0 \
            -no-fixed-num-lines \
            -theme-str 'entry { placeholder: "Key after SUPER (e.g. SHIFT + X)"; }')" || return 1
        command="$(printf '\n' | rofi -theme "$theme" -dmenu -p "" -l 0 \
            -no-fixed-num-lines \
            -theme-str 'entry { placeholder: "Command"; }')" || return 1
    elif [[ -t 0 ]]; then
        printf 'Key after SUPER (e.g. SHIFT + X): '
        read -r suffix || return 1
        printf 'Command: '
        read -r command || return 1
    else
        return 1
    fi
    add_bind "$suffix" "$command"
}

if [[ $MODE == add ]]; then
    add_bind "$ADD_KEY" "$ADD_COMMAND"
    exit $?
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
        printf '%s\n' "${rows[@]}" | rofi -theme "${XDG_CONFIG_HOME:-$HOME/.config}/rofi/launcher.rasi" -dmenu -p "" -no-custom -no-fixed-num-lines \
            -theme-str 'entry { placeholder: "Hyprland binds"; }'
    else
        print_plain
    fi
}

print_rofi_edit() {
    local i index bind_index
    local -a rows=("<span font='JetBrainsMono Nerd Font 13'></span>  Add keybind")

    for i in "${!KEYS[@]}"; do
        rows+=("<span font='JetBrainsMono Nerd Font 13'></span>  $(printf '%-28s %s' "${KEYS[$i]}" "${ACTIONS[$i]}")")
    done

    if ! command -v rofi >/dev/null 2>&1 || [[ -z ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
        return 1
    fi
    index="$(printf '%s\n' "${rows[@]}" | rofi \
        -theme "${XDG_CONFIG_HOME:-$HOME/.config}/rofi/launcher.rasi" \
        -dmenu -p "" -no-fixed-num-lines -markup-rows -format i \
        -theme-str 'window { width: 820px; } entry { placeholder: "Keybinds — pick one to edit"; }')" || return 1
    [[ $index =~ ^[0-9]+$ ]] || return 1
    if ((index == 0)); then
        add_bind_prompt || return 1
        return 0
    fi
    bind_index=$((index - 1))
    ((bind_index < ${#KEYS[@]})) || return 1
    printf '%s:%s\n' "$CONFIG" "${LINES[$bind_index]}"
}

case "$MODE" in
    plain)     print_plain ;;
    markdown)  print_markdown ;;
    json)      print_json ;;
    rofi)      print_rofi ;;
    rofi-edit) print_rofi_edit ;;
esac
