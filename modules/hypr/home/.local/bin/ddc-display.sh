#!/usr/bin/env bash
# DDC/CI control for external monitors over i2c.
#
# Desktops have no internal backlight, so brightness keys and idle dimming go
# through ddcutil instead. The i2c group is handled by install.sh; without it
# every call fails with a permission error.
#
# Usage:
#   ddc-display.sh available
#   ddc-display.sh list                        # "N<TAB>monitor name" per display
#   ddc-display.sh get <vcp> [--display N]
#   ddc-display.sh set <vcp> <value> [--display N]
#   ddc-display.sh adjust <vcp> <delta> [--display N]
#   ddc-display.sh save <vcp> [--display N]
#   ddc-display.sh restore <vcp> [--display N]
#
# Without --display every connected monitor is changed. VCP codes: 10
# brightness, 12 contrast, 18 colour preset, 60 input source, 62 audio volume,
# 87 sharpness, 0x6C/0x6E/0x70 red/green/blue gain.
set -uo pipefail

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

# One line per display: number, then the monitor name.
detect_displays() {
    ddcutil detect 2>/dev/null | awk '
        /^Display [0-9]+/ { n = $2 }
        /^[[:space:]]*Monitor:/ {
            sub(/^[[:space:]]*Monitor:[[:space:]]*/, "")
            print n "\t" $0
        }
    '
}

# Display numbers and names are stable for a session. Detection takes a second
# or two, so cache the result in the runtime directory.
display_table() {
    if [[ -s $DISPLAY_CACHE ]]; then
        cat "$DISPLAY_CACHE"
        return 0
    fi
    local table
    table="$(detect_displays)"
    [[ -n $table ]] || return 1
    printf '%s\n' "$table" >"$DISPLAY_CACHE" 2>/dev/null || true
    printf '%s\n' "$table"
}

displays() {
    display_table | cut -f1
}

available() {
    have ddcutil || return 1
    [[ -n "$(display_table)" ]]
}

target_displays() {
    if [[ -n $TARGET ]]; then
        printf '%s\n' "$TARGET"
    else
        displays
    fi
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

get_percent() {
    local code="$1" display current maximum
    while read -r display; do
        read -r current maximum < <(read_vcp "$display" "$code")
        [[ -n ${current:-} && -n ${maximum:-} ]] || continue
        to_percent "$current" "$maximum"
        return 0
    done < <(target_displays)
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
    done < <(target_displays)
    return "$changed"
}

adjust_percent() {
    local code="$1" delta="$2" display current maximum next raw changed=1
    while read -r display; do
        read -r current maximum < <(read_vcp "$display" "$code")
        [[ -n ${current:-} && -n ${maximum:-} ]] || continue
        next=$((current + delta))
        ((next > MAX_PERCENT)) && next=$MAX_PERCENT
        ((next < MIN_PERCENT)) && next=$MIN_PERCENT
        raw="$(to_raw "$next" "$maximum")"
        ddcutil --display "$display" --sleep-multiplier "$SLEEP_MULTIPLIER" \
            setvcp "$code" "$raw" >/dev/null 2>&1 && changed=0
    done < <(target_displays)
    return "$changed"
}

# Raw values for enumerated controls (input source, colour preset): these are
# codes, not percentages, so they must not be scaled to the VCP maximum.
get_raw_value() {
    local code="$1" display current maximum
    while read -r display; do
        read -r current maximum < <(read_vcp "$display" "$code")
        [[ -n ${current:-} ]] || continue
        printf '%s' "$current"
        return 0
    done < <(target_displays)
    return 1
}

set_raw_value() {
    local code="$1" value="$2" display changed=1
    while read -r display; do
        ddcutil --display "$display" --sleep-multiplier "$SLEEP_MULTIPLIER" \
            setvcp "$code" "$value" >/dev/null 2>&1 && changed=0
    done < <(target_displays)
    return "$changed"
}

save_levels() {    local code="$1" display current maximum
    mkdir -p -- "$SAVE_DIR" 2>/dev/null || return 1
    local file="$SAVE_DIR/$code${TARGET:+-$TARGET}"
    : >"$file"
    while read -r display; do
        read -r current maximum < <(read_vcp "$display" "$code")
        [[ -n ${current:-} && -n ${maximum:-} ]] || continue
        printf '%s %s\n' "$display" "$current" >>"$file"
    done < <(target_displays)
}

restore_levels() {
    local code="$1" display raw
    local file="$SAVE_DIR/$code${TARGET:+-$TARGET}"
    [[ -r $file ]] || return 1
    while read -r display raw; do
        [[ -n ${display:-} && -n ${raw:-} ]] || continue
        ddcutil --display "$display" --sleep-multiplier "$SLEEP_MULTIPLIER" \
            setvcp "$code" "$raw" >/dev/null 2>&1 || true
    done <"$file"
    rm -f -- "$file"
}

usage() {
    printf 'usage: %s available|list|get <vcp>|getraw <vcp>|set <vcp> <value>|setraw <vcp> <value>|adjust <vcp> <delta>|save <vcp>|restore <vcp> [--display N]\n' \
        "$(basename "$0")" >&2
}

command_name="${1:-}"
shift || true

TARGET=""
positional=()
while (($#)); do
    case "$1" in
        --display)
            TARGET="${2:?missing display number}"
            shift
            ;;
        *)
            positional+=("$1")
            ;;
    esac
    shift
done

case "$command_name" in
    available) available ;;
    list) display_table ;;
    get) get_percent "${positional[0]:?missing vcp}" ;;
    getraw) get_raw_value "${positional[0]:?missing vcp}" ;;
    set) set_percent "${positional[0]:?missing vcp}" "${positional[1]:?missing value}" ;;
    setraw) set_raw_value "${positional[0]:?missing vcp}" "${positional[1]:?missing value}" ;;
    adjust) adjust_percent "${positional[0]:?missing vcp}" "${positional[1]:?missing delta}" ;;
    save) save_levels "${positional[0]:?missing vcp}" ;;
    restore) restore_levels "${positional[0]:?missing vcp}" ;;
    *) usage; exit 2 ;;
esac
