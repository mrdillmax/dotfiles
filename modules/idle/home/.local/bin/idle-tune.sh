#!/usr/bin/env bash
# Idle-time tuner for hypridle (battery and AC profiles).
#
# Defaults:
#   battery  dim 150  lock 300  screen-off 330  suspend 900
#   AC       dim 300  lock 600  screen-off 660  suspend 1800
#
# A value of 0 disables that stage. Validation requires dim < lock <= off <
# suspend for every pair of enabled stages. Settings live in
# ~/.local/state/dotfiles/idle.conf; the generated file is
# ~/.config/hypr/hypridle.conf (the previous file is backed up first).
#
# Usage:
#   idle-tune.sh apply [--profile auto|battery|ac]
#   idle-tune.sh set --battery-dim 150 --battery-lock 300 ...
#   idle-tune.sh configure
#   idle-tune.sh watch
#   idle-tune.sh status
#   idle-tune.sh enable|disable|toggle|run
set -uo pipefail

REAL_HOME="${HOME:?HOME is not set}"
STATE_DIR="${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles"
STATE_FILE="$STATE_DIR/idle.conf"
BACKUP_DIR="$STATE_DIR/idle-backup"
CONFIG="${XDG_CONFIG_HOME:-$REAL_HOME/.config}/hypr/hypridle.conf"

BATTERY_DIM=150
BATTERY_LOCK=300
BATTERY_OFF=330
BATTERY_SUSPEND=900
AC_DIM=300
AC_LOCK=600
AC_OFF=660
AC_SUSPEND=1800
ENABLED=1

DRY_RUN=0
COMMAND=""
PROFILE="auto"
SET_CHANGED=0
declare -A CLI_OVERRIDE=()

usage() {
    cat <<'EOF'
Usage: idle-tune.sh <apply|set|configure|watch|status|enable|disable|toggle|run> [options]

Commands:
  apply       render ~/.config/hypr/hypridle.conf and reload hypridle
  set         change values, save them, then apply
  configure   interactive prompts for all eight values
  watch       apply when AC/battery state changes (checks every 30s)
  status      show stored values, enabled state and the power source
  enable      allow hypridle to run and start it now
  disable     stop hypridle and keep it off at login
  toggle      switch the enabled state
  run         start hypridle only when enabled (used by autostart)

Options:
  --profile auto|battery|ac   profile for apply (default: auto)
  --battery-dim N --battery-lock N --battery-off N --battery-suspend N
  --ac-dim N --ac-lock N --ac-off N --ac-suspend N
  --dry-run                   print what would change
  -h, --help                  this help

0 disables a stage. Enabled stages must satisfy:
  dim < lock <= off < suspend
EOF
}

die() { printf 'idle-tune: %s\n' "$*" >&2; exit 1; }
info() { printf ':: %s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

get_var() {
    printf '%s' "${!1:-0}"
}

load_state() {
    local key value

    [[ -r $STATE_FILE ]] || return 0
    while IFS='=' read -r key value; do
        [[ -z $key || $key == \#* ]] && continue
        case "$key" in
            BATTERY_DIM|BATTERY_LOCK|BATTERY_OFF|BATTERY_SUSPEND|\
            AC_DIM|AC_LOCK|AC_OFF|AC_SUSPEND|ENABLED)
                # Values given on the command line win over the stored state.
                if [[ -n ${CLI_OVERRIDE[$key]:-} ]]; then
                    continue
                fi
                if [[ $value =~ ^[0-9]+$ ]]; then
                    printf -v "$key" '%s' "$value"
                else
                    warn "ignoring invalid $key=$value in $STATE_FILE"
                fi
                ;;
            *) warn "ignoring unknown key $key in $STATE_FILE" ;;
        esac
    done <"$STATE_FILE"
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
        printf '# Written by idle-tune.sh (battery and AC idle stages).\n'
        printf 'BATTERY_DIM=%s\n' "$BATTERY_DIM"
        printf 'BATTERY_LOCK=%s\n' "$BATTERY_LOCK"
        printf 'BATTERY_OFF=%s\n' "$BATTERY_OFF"
        printf 'BATTERY_SUSPEND=%s\n' "$BATTERY_SUSPEND"
        printf 'AC_DIM=%s\n' "$AC_DIM"
        printf 'AC_LOCK=%s\n' "$AC_LOCK"
        printf 'AC_OFF=%s\n' "$AC_OFF"
        printf 'AC_SUSPEND=%s\n' "$AC_SUSPEND"
        printf 'ENABLED=%s\n' "$ENABLED"
    } >"$tmp"
    chmod 0600 "$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
}

validate_profile() {
    local prefix="$1"
    local dim lock off suspend name value

    for name in DIM LOCK OFF SUSPEND; do
        value="$(get_var "${prefix}_${name}")"
        [[ $value =~ ^[0-9]+$ ]] \
            || die "$prefix ${name,,} must be a non-negative integer (got '$value')"
    done

    dim="$(get_var "${prefix}_DIM")"
    lock="$(get_var "${prefix}_LOCK")"
    off="$(get_var "${prefix}_OFF")"
    suspend="$(get_var "${prefix}_SUSPEND")"

    if ((dim > 0 && lock > 0 && dim >= lock)); then
        die "$prefix: dim must be less than lock (dim=$dim lock=$lock)"
    fi
    if ((lock > 0 && off > 0 && lock > off)); then
        die "$prefix: lock must be at or before screen-off (lock=$lock off=$off)"
    fi
    if ((off > 0 && suspend > 0 && off >= suspend)); then
        die "$prefix: screen-off must be before suspend (off=$off suspend=$suspend)"
    fi
}

detect_power() {
    local status found=0 online=0

    case "${IDLE_POWER:-}" in
        ac|battery) printf '%s' "$IDLE_POWER"; return 0 ;;
        "") : ;;
        *) warn "ignoring invalid IDLE_POWER=${IDLE_POWER:-}" ;;
    esac

    for status in /sys/class/power_supply/A*/online; do
        [[ -e $status ]] || continue
        found=1
        [[ -r $status && "$(<"$status")" == 1 ]] && online=1
    done

    if ((found)); then
        ((online)) && printf 'ac' || printf 'battery'
    else
        # Desktops and VMs usually have no AC supply; use the relaxed profile.
        printf 'ac'
    fi
}

resolve_profile() {
    case "$1" in
        auto)    detect_power ;;
        battery|ac) printf '%s' "$1" ;;
        *) die "invalid profile: $1 (use auto, battery or ac)" ;;
    esac
}

render_config() {
    local profile="$1" target="$2"
    local prefix dim lock off suspend

    case "$profile" in
        battery) prefix=BATTERY ;;
        ac)      prefix=AC ;;
        *) die "invalid profile: $profile" ;;
    esac

    dim="$(get_var "${prefix}_DIM")"
    lock="$(get_var "${prefix}_LOCK")"
    off="$(get_var "${prefix}_OFF")"
    suspend="$(get_var "${prefix}_SUSPEND")"

    {
        printf '# Generated by idle-tune.sh; profile=%s.\n' "$profile"
        printf '# Source of truth: ~/.local/state/dotfiles/idle.conf\n'
        printf '# 0 disables a stage. Tune with: idle-tune.sh set --help\n\n'
        printf 'general {\n'
        printf '    lock_cmd = lock-screen.sh lock --from-idle\n'
        printf '    unlock_cmd = lock-screen.sh unlocked\n'
        printf '    before_sleep_cmd = loginctl lock-session\n'
        printf '    after_sleep_cmd = lock-screen.sh resume\n'
        printf '    inhibit_sleep = 3\n'
        printf '}\n\n'

        if ((dim > 0)); then
            printf 'listener {\n'
            printf '    timeout = %s\n' "$dim"
            printf '    on-timeout = idle-dim.sh dim\n'
            printf '    on-resume = idle-dim.sh restore\n'
            printf '}\n\n'
        fi
        if ((lock > 0)); then
            printf 'listener {\n'
            printf '    timeout = %s\n' "$lock"
            printf '    on-timeout = loginctl lock-session\n'
            printf '}\n\n'
        fi
        if ((off > 0)); then
            printf 'listener {\n'
            printf '    timeout = %s\n' "$off"
            printf '    on-timeout = lock-screen.sh screen-off\n'
            printf '    on-resume = lock-screen.sh unlocked\n'
            printf '    condition_cmd = lock-screen.sh can-dpms-off\n'
            printf '}\n\n'
        fi
        if ((suspend > 0)); then
            printf 'listener {\n'
            printf '    timeout = %s\n' "$suspend"
            printf '    on-timeout = lock-screen.sh suspend\n'
            printf '    condition_cmd = lock-screen.sh can-suspend\n'
            printf '}\n'
        fi
    } >"$target"
}

backup_config() {
    local file="$1" stamp

    ((DRY_RUN)) && return 0
    [[ -e $file ]] || return 0
    stamp="$(date +%Y-%m-%d_%H%M%S)"
    mkdir -p -- "$BACKUP_DIR"
    cp -a -- "$file" "$BACKUP_DIR/hypridle.conf.$stamp"
    info "previous config backed up: $BACKUP_DIR/hypridle.conf.$stamp"
}

service_unit_exists() {
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl --user list-unit-files --no-legend hypridle.service 2>/dev/null \
        | grep -q .
}

reload_hypridle() {
    if ((DRY_RUN)); then
        info "[dry-run] restart hypridle"
        return 0
    fi
    if service_unit_exists &&
        systemctl --user is-active --quiet hypridle.service 2>/dev/null; then
        systemctl --user restart hypridle.service >/dev/null 2>&1 \
            || warn "could not restart hypridle.service"
        return 0
    fi
    if command -v pkill >/dev/null 2>&1; then
        pkill -USR1 -x hypridle >/dev/null 2>&1 || true
    fi
}

apply_config() {
    local requested="$1" profile prefix tmp

    load_state
    profile="$(resolve_profile "$requested")"
    prefix="${profile^^}"
    validate_profile "$prefix"

    if ((DRY_RUN)); then
        info "[dry-run] profile=$profile dim=$(get_var "${prefix}_DIM") lock=$(get_var "${prefix}_LOCK") off=$(get_var "${prefix}_OFF") suspend=$(get_var "${prefix}_SUSPEND")"
        info "[dry-run] would write $CONFIG"
        reload_hypridle
        return 0
    fi

    tmp="$(mktemp)"
    render_config "$profile" "$tmp"
    if [[ -r $CONFIG && ! -L $CONFIG ]] && cmp -s -- "$tmp" "$CONFIG"; then
        rm -f -- "$tmp"
        return 0
    fi
    backup_config "$CONFIG"
    mkdir -p -- "$(dirname "$CONFIG")"
    # Older installs linked the file into the repository; never write through
    # that link, it would edit the checkout instead of the live config.
    [[ -L $CONFIG ]] && rm -f -- "$CONFIG"
    install -m 0644 -- "$tmp" "$CONFIG"
    rm -f -- "$tmp"

    reload_hypridle
    ok "applied $profile profile to $CONFIG"
}

# Same chain as lib/tui.sh: gum -> whiptail -> dialog -> plain read.
ask_value() {
    local var="$1" label="$2" current value
    current="$(get_var "$var")"

    [[ -t 0 ]] || die "configure needs a terminal (use set --$var ... instead)"

    if command -v gum >/dev/null 2>&1; then
        value="$(gum input --prompt "$label: " --value "$current")" \
            || die "input cancelled"
    elif command -v whiptail >/dev/null 2>&1; then
        value="$(whiptail --inputbox "$label" 0 0 "$current" 3>&1 1>&2 2>&3)" \
            || die "input cancelled"
    elif command -v dialog >/dev/null 2>&1; then
        value="$(dialog --inputbox "$label" 0 0 "$current" 3>&1 1>&2 2>&3)" \
            || die "input cancelled"
    else
        printf '%s [%s]: ' "$label" "$current"
        read -r value || die "input cancelled"
    fi

    value="${value:-$current}"
    [[ $value =~ ^[0-9]+$ ]] || die "$label must be a non-negative integer"
    printf -v "$var" '%s' "$value"
}

configure_interactive() {
    load_state
    printf 'Battery profile (0 disables a stage)\n'
    ask_value BATTERY_DIM "  dim seconds"
    ask_value BATTERY_LOCK "  lock seconds"
    ask_value BATTERY_OFF "  screen-off seconds"
    ask_value BATTERY_SUSPEND "  suspend seconds"
    printf 'AC profile (0 disables a stage)\n'
    ask_value AC_DIM "  dim seconds"
    ask_value AC_LOCK "  lock seconds"
    ask_value AC_OFF "  screen-off seconds"
    ask_value AC_SUSPEND "  suspend seconds"

    validate_profile BATTERY
    validate_profile AC
    write_state
    apply_config auto
}

show_status() {
    local power stored_profile

    load_state
    power="$(detect_power)"

    printf 'power: %s\n' "$power"
    printf 'enabled: %s\n' "$ENABLED"
    printf 'state: %s\n' "$STATE_FILE"
    stored_profile=""
    if [[ -r $CONFIG ]]; then
        stored_profile="$(sed -n 's/^# Generated by idle-tune.sh; profile=\([a-z]*\).*/\1/p' "$CONFIG" | head -n1)"
        printf 'config: %s%s\n' "$CONFIG" \
            "${stored_profile:+ (profile $stored_profile)}"
    else
        printf 'config: %s (missing)\n' "$CONFIG"
    fi

    printf 'battery: dim=%s lock=%s off=%s suspend=%s\n' \
        "$BATTERY_DIM" "$BATTERY_LOCK" "$BATTERY_OFF" "$BATTERY_SUSPEND"
    printf 'ac:      dim=%s lock=%s off=%s suspend=%s\n' \
        "$AC_DIM" "$AC_LOCK" "$AC_OFF" "$AC_SUSPEND"
}

is_running() {
    pgrep -x hypridle >/dev/null 2>&1
}

set_enabled() {
    local value="$1"

    load_state
    ENABLED="$value"
    write_state

    if service_unit_exists; then
        if ((DRY_RUN)); then
            if [[ $value == 1 ]]; then
                info "[dry-run] systemctl --user enable --now hypridle.service"
            else
                info "[dry-run] systemctl --user disable --now hypridle.service"
            fi
        elif [[ $value == 1 ]]; then
            if systemctl --user enable --now hypridle.service; then
                ok "hypridle service enabled and started"
            else
                warn "could not enable or start hypridle.service"
            fi
        elif systemctl --user disable --now hypridle.service; then
            ok "hypridle service disabled and stopped"
        else
            warn "could not disable or stop hypridle.service"
        fi
        return 0
    fi

    if [[ $value == 1 ]]; then
        if is_running; then
            ok "hypridle is already running"
        elif ((DRY_RUN)); then
            info "[dry-run] would start hypridle"
        elif command -v hypridle >/dev/null 2>&1; then
            setsid hypridle >/dev/null 2>&1 &
            ok "hypridle started"
        else
            warn "hypridle is not installed"
        fi
    else
        if ((DRY_RUN)); then
            info "[dry-run] would stop hypridle"
        elif is_running; then
            pkill -x hypridle 2>/dev/null || true
            ok "hypridle stopped"
        else
            ok "hypridle is already stopped"
        fi
    fi
}

run_autostart() {
    load_state
    if [[ $ENABLED != 1 ]]; then
        info "idle is disabled; not starting hypridle"
        return 0
    fi

    # Login may follow a power-source change while the session was off; render
    # the matching battery/AC profile before the daemon starts.
    apply_config auto

    if service_unit_exists; then
        # systemd owns the process. Enable on login when the unit is still
        # disabled (upgrades from the autostart-only setup), otherwise just
        # make sure it came up; never start a second copy next to the unit.
        if systemctl --user is-enabled --quiet hypridle.service 2>/dev/null; then
            systemctl --user start hypridle.service >/dev/null 2>&1 \
                || warn "could not start hypridle.service"
        else
            systemctl --user enable --now hypridle.service >/dev/null 2>&1 \
                || warn "could not enable or start hypridle.service"
        fi
        return 0
    fi

    command -v hypridle >/dev/null 2>&1 || die "hypridle is not installed"
    exec hypridle
}

watch_power() {
    local interval="${IDLE_WATCH_INTERVAL:-30}"
    local last current

    load_state
    last="$(detect_power)"
    apply_config "$last"
    while true; do
        sleep "$interval"
        current="$(detect_power)"
        if [[ $current != "$last" ]]; then
            info "power changed: $last -> $current"
            apply_config "$current"
            last="$current"
        fi
    done
}

while (($#)); do
    case "$1" in
        apply|set|configure|watch|status|enable|disable|toggle|run)
            [[ -z $COMMAND ]] || die "only one command is allowed"
            COMMAND="$1"
            ;;
        --profile)
            PROFILE="${2:?missing value for --profile}"
            shift
            ;;
        --battery-dim)     BATTERY_DIM="${2:?missing value}"; CLI_OVERRIDE[BATTERY_DIM]=1; SET_CHANGED=1; shift ;;
        --battery-lock)    BATTERY_LOCK="${2:?missing value}"; CLI_OVERRIDE[BATTERY_LOCK]=1; SET_CHANGED=1; shift ;;
        --battery-off)     BATTERY_OFF="${2:?missing value}"; CLI_OVERRIDE[BATTERY_OFF]=1; SET_CHANGED=1; shift ;;
        --battery-suspend) BATTERY_SUSPEND="${2:?missing value}"; CLI_OVERRIDE[BATTERY_SUSPEND]=1; SET_CHANGED=1; shift ;;
        --ac-dim)          AC_DIM="${2:?missing value}"; CLI_OVERRIDE[AC_DIM]=1; SET_CHANGED=1; shift ;;
        --ac-lock)         AC_LOCK="${2:?missing value}"; CLI_OVERRIDE[AC_LOCK]=1; SET_CHANGED=1; shift ;;
        --ac-off)          AC_OFF="${2:?missing value}"; CLI_OVERRIDE[AC_OFF]=1; SET_CHANGED=1; shift ;;
        --ac-suspend)      AC_SUSPEND="${2:?missing value}"; CLI_OVERRIDE[AC_SUSPEND]=1; SET_CHANGED=1; shift ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

load_state

case "$COMMAND" in
    enable)
        set_enabled 1
        ;;
    disable)
        set_enabled 0
        ;;
    toggle)
        if [[ $ENABLED == 1 ]]; then set_enabled 0; else set_enabled 1; fi
        ;;
    run)
        run_autostart
        ;;
    apply)
        apply_config "$PROFILE"
        ;;
    set)
        ((SET_CHANGED)) || die "set needs at least one --battery-* or --ac-* value"
        validate_profile BATTERY
        validate_profile AC
        write_state
        apply_config "$PROFILE"
        ;;
    configure)
        configure_interactive
        ;;
    watch)
        watch_power
        ;;
    status)
        show_status
        ;;
    "")
        usage >&2
        exit 2
        ;;
esac
