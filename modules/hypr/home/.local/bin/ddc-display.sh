#!/usr/bin/env bash
# DDC/CI control for external monitors over i2c.
#
# Desktops have no internal backlight, so brightness keys and idle dimming go
# through ddcutil instead. The i2c group is handled by install.sh; without it
# every call fails with a permission error.
#
# Usage:
#   ddc-display.sh available
#   ddc-display.sh list
#   ddc-display.sh get <vcp>
#   ddc-display.sh set <vcp> <percent>
#   ddc-display.sh adjust <vcp> <delta>
#   ddc-display.sh save <vcp>
#   ddc-display.sh restore <vcp>
#
# VCP codes: 10 brightness, 12 contrast.
set -uo pipefail

VCP_BRIGHTNESS=10
VCP_CONTRAST=12
MIN_PERCENT=5
MAX_PERCENT=100

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
DISPLAY_CACHE="$RUNTIME/dotfiles-ddc-displays"
SAVE_DIR="$STATE_DIR/ddc-levels"

# ddcutil waits between i2c writes by default; monitors tolerate much less and
# the keys feel instant with a smaller multiplier.
SLEEP_MULTIPLIER=0.05

have() { command -v "$1" >/dev/null 2>&1; }

available() {
    have ddcutil || return 1
    [[ -n $(displays) ]]
}

# Display numbers are stable for a session. Detection takes a second or two,
# so cache the result in the runtime directory.
displays() {
    if [[ -s $DISPLAY_CACHE ]]; then
        cat "$DISPLAY_CACHE"
        return 0
    fi
    local list
    list="$(ddcutil detect --brief 2>/dev/null |
        sed -n 's/^Display \([0-9][0-9]*\)$/\1/p')"
    [[ -n $list ]] || return 1
    printf '%s\n' "$list" >"$DISPLAY_CACHE" 2>/dev/null || true
    printf '%s\n' "$list"
}

# read_vcp <display> <vcp> -> "current max", empty when the display ignores it.
read_vcp() {
    ddcutil --display "$1" --sleep-multiplier "$SLEEP_MULTIPLIER" \
        getvcp "$2" --brief 2>/dev/null |
        awk '$1 == "VCP" && $3 == "C" { print $4, $5 }'
}

to_percent() {
    local current="$1" maximum="$2"
    ((maximum > 0)) || {
        printf '0'
        return 0
    }
    printf '%s' $(((current * 100 + maximum / 2) / maximum))
}

to_raw() {
    local percent="$1" maximum="$2"
    ((maximum > 0)) || {
        printf '0'
        return 0
    }
    printf '%s' $(((percent * maximum + 50) / 100))
}

# The first display that answers decides the value shown in menus.
get_percent() {
    local code="$1" display current maximum
    while read -r display; do
        read -r current maximum < <(read_vcp "$display" "$code")
        [[ -n ${current:-} && -n ${maximum:-} ]] || continue
        to_percent "$current" "$maximum"
        return 0
    done < <(displays)
    return 1
}

set_percent() {
    local code="$1" percent="$2" display current maximum raw changed=1
    while read -r display; do
        read -r current maximum < <(read_vcp "$display" "$code")
        [[ -n ${current:-} && -n ${maximum:-} ]] || continue
        raw="$(to_raw "$percent" "$maximum")"
        ddcutil --display "$display" --sleep-multiplier "$SLEEP_MULTIPLIER" \
            setvcp "$code" "$raw" >/dev/null 2>&1 && changed=0
    done < <(displays)
    return "$changed"
}

adjust_percent() {
    local code="$1" delta="$2" current next
    current="$(get_percent "$code")" || return 1
    next=$((current + delta))
    ((next > MAX_PERCENT)) && next=$MAX_PERCENT
    ((next < MIN_PERCENT)) && next=$MIN_PERCENT
    set_percent "$code" "$next"
    printf '%s' "$next"
}

save_levels() {
    local code="$1" display current maximum
    mkdir -p -- "$SAVE_DIR" 2>/dev/null || return 1
    : >"$SAVE_DIR/$code"
    while read -r display; do
        read -r current maximum < <(read_vcp "$display" "$code")
        [[ -n ${current:-} && -n ${maximum:-} ]] || continue
        printf '%s %s\n' "$display" "$current" >>"$SAVE_DIR/$code"
    done < <(displays)
}

restore_levels() {
    local code="$1" file="$SAVE_DIR/$code" display raw
    [[ -r $file ]] || return 1
    while read -r display raw; do
        [[ -n ${display:-} && -n ${raw:-} ]] || continue
        ddcutil --display "$display" --sleep-multiplier "$SLEEP_MULTIPLIER" \
            setvcp "$code" "$raw" >/dev/null 2>&1 || true
    done <"$file"
    rm -f -- "$file"
}

usage() {
    printf 'usage: %s available|list|get <vcp>|set <vcp> <percent>|adjust <vcp> <delta>|save <vcp>|restore <vcp>\n' \
        "$(basename "$0")" >&2
}

command_name="${1:-}"
shift || true

case "$command_name" in
    available) available ;;
    list) displays ;;
    get) get_percent "${1:?missing vcp}" ;;
    set) set_percent "${1:?missing vcp}" "${2:?missing percent}" ;;
    adjust) adjust_percent "${1:?missing vcp}" "${2:?missing delta}" ;;
    save) save_levels "${1:?missing vcp}" ;;
    restore) restore_levels "${1:?missing vcp}" ;;
    *) usage; exit 2 ;;
esac
