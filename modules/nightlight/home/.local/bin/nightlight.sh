#!/usr/bin/env bash
# Night light control for hyprsunset.
#
# hyprsunset exposes setters but no query, so this helper owns the state:
# enabled and the temperature live in $STATE_DIR/nightlight.conf.
set -uo pipefail

STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
STATE_FILE="$STATE_DIR/nightlight.conf"
enabled=0
temperature="${NIGHT_TEMP:-4000}"

die() { printf 'nightlight: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

notify() {
    if have notify-send; then
        notify-send -a "Night light" "$*" >/dev/null 2>&1 || true
    else
        printf '%s\n' "$*"
    fi
}

load_state() {
    [[ -r $STATE_FILE ]] || return 0
    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            enabled) [[ $value =~ ^[01]$ ]] && enabled="$value" ;;
            temperature) [[ $value =~ ^[0-9]+$ ]] && temperature="$value" ;;
        esac
    done <"$STATE_FILE"
}

save_state() {
    mkdir -p "$STATE_DIR" || die "cannot create $STATE_DIR"
    local tmp
    tmp="$(mktemp "$STATE_FILE.XXXXXX")" || die "cannot write state"
    printf 'enabled=%s\ntemperature=%s\n' "$enabled" "$temperature" >"$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
}

valid_temp() { [[ $1 =~ ^[0-9]+$ ]] && (($1 >= 1000 && $1 <= 10000)); }

daemon_running() { pgrep -x hyprsunset >/dev/null 2>&1; }

ensure_daemon() {
    daemon_running && return 0
    have hyprsunset || die "hyprsunset is not installed"
    (setsid hyprsunset >/dev/null 2>&1 &)
}

apply() {
    ensure_daemon
    have hyprctl || die "hyprctl is not available"
    hyprctl hyprsunset temperature "$temperature" >/dev/null \
        || die "hyprctl could not set the temperature"
}

disable() {
    save_state
    daemon_running || return 0
    hyprctl hyprsunset identity >/dev/null 2>&1 || true
}

load_state

case "${1:-}" in
    on)
        enabled=1
        save_state
        apply
        notify "Night light on (${temperature} K)"
        ;;
    off)
        enabled=0
        disable
        notify "Night light off"
        ;;
    toggle)
        if ((enabled)); then
            enabled=0
            disable
            notify "Night light off"
        else
            enabled=1
            save_state
            apply
            notify "Night light on (${temperature} K)"
        fi
        ;;
    temp)
        value="${2:-}"
        valid_temp "$value" || die "temperature must be 1000..10000"
        temperature="$value"
        save_state
        ((enabled)) && apply
        printf '%s K\n' "$temperature"
        ;;
    restore)
        if ((enabled)); then
            apply
        else
            disable
        fi
        ;;
    status)
        if ((enabled)); then
            printf 'night light: enabled, %s K\n' "$temperature"
        else
            printf 'night light: disabled\n'
        fi
        ;;
    -h|--help)
        printf 'Usage: %s on|off|toggle|status|temp N|restore\n' "$(basename "$0")"
        ;;
    '')
        printf 'Usage: %s on|off|toggle|status|temp N|restore\n' "$(basename "$0")" >&2
        exit 2
        ;;
    *) die "unknown action: $1 (see --help)" ;;
esac
