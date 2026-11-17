#!/usr/bin/env bash
# Toggle a lightweight gaming mode for Hyprland.
#
# Enable disables animations, blur, shadows and rounding. The values that were
# active before the first enable are captured with `hyprctl getoption` and kept
# in ~/.local/state/dotfiles/gamemode.conf. Enabling again never overwrites
# them, so `off` always restores the real pre-gamemode values.
#
# Usage:
#   gamemode.sh on|off|toggle|status [--dry-run]
set -uo pipefail

REAL_HOME="${HOME:?HOME is not set}"
STATE_DIR="${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles"
STATE_FILE="$STATE_DIR/gamemode.conf"

OPTIONS=(
    animations:enabled
    decoration:blur:enabled
    decoration:shadow:enabled
    decoration:rounding
)

# Lua literals applied while gamemode is on.
GAMEMODE_LUA=(
    animations:enabled=false
    decoration:blur:enabled=false
    decoration:shadow:enabled=false
    decoration:rounding=0
)

DRY_RUN=0
COMMAND=""

usage() {
    cat <<'EOF'
Usage: gamemode.sh <on|off|toggle|status> [--dry-run]

  on       capture the current values once, then disable animations,
           blur, shadows and rounding
  off      restore the captured values (no-op when gamemode is off)
  toggle   on when off, off when on
  status   show whether gamemode is enabled and the captured values
  --dry-run  print the hyprctl commands, change nothing
EOF
}

die() { printf 'gamemode: %s\n' "$*" >&2; exit 1; }
info() { printf ':: %s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

while (($#)); do
    case "$1" in
        on|off|toggle|status)
            [[ -z $COMMAND ]] || die "only one command is allowed"
            COMMAND="$1"
            ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

[[ -n $COMMAND ]] || { usage >&2; exit 2; }

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

require_session() {
    command -v hyprctl >/dev/null 2>&1 || die "hyprctl is not installed"
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \
        || die "not inside a Hyprland session (HYPRLAND_INSTANCE_SIGNATURE is unset)"
}

# "bool: true" -> "bool:true"; empty on failure.
read_option() {
    local key="$1" raw first

    raw="$(hyprctl getoption "$key" 2>/dev/null || true)"
    [[ -n $raw ]] || return 1
    grep -q '^no such option' <<<"$raw" && return 1

    first="$(sed -n '1p' <<<"$raw")"
    [[ -n $first ]] || return 1
    printf '%s:%s\n' "$(trim "${first%%:*}")" "$(trim "${first#*:}")"
}

# raw type:value -> Lua literal; fails on unknown or malformed values.
raw_to_lua() {
    local raw="$1" type value

    type="${raw%%:*}"
    value="$(trim "${raw#*:}")"

    case "$type" in
        bool)
            case "$value" in
                true|false) printf '%s' "$value" ;;
                *) return 1 ;;
            esac
            ;;
        int)
            [[ $value =~ ^-?[0-9]+$ ]] || return 1
            printf '%s' "$value"
            ;;
        float)
            [[ $value =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || return 1
            printf '%s' "$value"
            ;;
        str)
            value="${value//\\/\\\\}"
            value="${value//\"/\\\"}"
            printf '"%s"' "$value"
            ;;
        *) return 1 ;;
    esac
}

# option:path -> hl.config({ path = { to = { key = value } } })
apply_option() {
    local key="$1" literal="$2" nested="" part
    local -a parts=()

    IFS=: read -r -a parts <<<"$key"
    ((${#parts[@]})) || return 1

    local i
    for ((i = ${#parts[@]} - 1; i >= 0; i--)); do
        part="${parts[$i]}"
        if [[ -z $nested ]]; then
            nested="$part = $literal"
        else
            nested="$part = { $nested }"
        fi
    done

    if ((DRY_RUN)); then
        info "[dry-run] hyprctl eval \"hl.config({ $nested })\""
        return 0
    fi

    hyprctl eval "hl.config({ $nested })" >/dev/null 2>&1 || {
        warn "failed to apply $key=$literal"
        return 1
    }
}

write_state() {
    local tmp

    if ((DRY_RUN)); then
        info "[dry-run] would write $STATE_FILE"
        return 0
    fi

    mkdir -p -- "$STATE_DIR"
    tmp="$(mktemp)"
    {
        printf '# Original Hyprland values captured before gamemode.\n'
        printf '# Do not edit while gamemode is enabled.\n'
        local i
        for i in "${!OPTIONS[@]}"; do
            printf '%s\t%s\n' "${OPTIONS[$i]}" "${CAPTURED[$i]}"
        done
    } >"$tmp"
    chmod 0600 "$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
}

read_state() {
    local key value

    [[ -r $STATE_FILE ]] || return 1
    while IFS=$'\t' read -r key value; do
        [[ -z $key || $key == \#* ]] && continue
        printf '%s\t%s\n' "$key" "$value"
    done <"$STATE_FILE"
}

capture_originals() {
    local i raw

    CAPTURED=()
    for i in "${!OPTIONS[@]}"; do
        raw="$(read_option "${OPTIONS[$i]}")" \
            || die "cannot read Hyprland option ${OPTIONS[$i]}"
        CAPTURED+=("$raw")
    done
}

enable_gamemode() {
    local i key literal applied=0

    require_session
    capture_originals

    if [[ -f $STATE_FILE ]]; then
        warn "gamemode is already enabled; original values are preserved"
    else
        write_state || die "cannot write $STATE_FILE"
    fi

    for i in "${!GAMEMODE_LUA[@]}"; do
        key="${GAMEMODE_LUA[$i]%%=*}"
        literal="${GAMEMODE_LUA[$i]#*=}"
        apply_option "$key" "$literal" || return 1
        applied=$((applied + 1))
    done

    ((DRY_RUN)) || ok "gamemode enabled ($applied options changed)"
}

disable_gamemode() {
    local key raw literal restored=0
    local -a keys=() raws=() literals=()

    require_session

    if [[ ! -r $STATE_FILE ]]; then
        warn "gamemode is not enabled (no state file)"
        return 0
    fi

    while IFS=$'\t' read -r key raw; do
        literal="$(raw_to_lua "$raw")" \
            || die "invalid stored value for $key: $raw"
        keys+=("$key")
        raws+=("$raw")
        literals+=("$literal")
    done < <(read_state)

    if ((${#keys[@]} == 0)); then
        warn "no captured values in $STATE_FILE; leaving it untouched"
        return 1
    fi

    local i
    for i in "${!keys[@]}"; do
        apply_option "${keys[$i]}" "${literals[$i]}" || return 1
        restored=$((restored + 1))
    done

    if ((DRY_RUN)); then
        info "[dry-run] would remove $STATE_FILE"
        return 0
    fi

    rm -f -- "$STATE_FILE"
    ok "gamemode disabled ($restored options restored)"
    return 0
}

show_status() {
    local key raw

    if [[ -r $STATE_FILE ]]; then
        printf 'gamemode: enabled\n'
        printf 'state: %s\n' "$STATE_FILE"
        while IFS=$'\t' read -r key raw; do
            printf '  %-28s %s\n' "$key" "$raw"
        done < <(read_state)
    else
        printf 'gamemode: disabled\n'
        printf 'state: %s (missing)\n' "$STATE_FILE"
    fi
}

case "$COMMAND" in
    on)     enable_gamemode ;;
    off)    disable_gamemode ;;
    toggle)
        if [[ -r $STATE_FILE ]]; then
            disable_gamemode
        else
            enable_gamemode
        fi
        ;;
    status) show_status ;;
esac
