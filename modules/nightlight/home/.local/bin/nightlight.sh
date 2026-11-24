#!/usr/bin/env bash
# Night light control for hyprsunset.
#
# hyprsunset exposes setters but no query, so this helper owns the state:
# enabled, temperature and the optional schedule live in
# $STATE_DIR/nightlight.conf.
#
# Schedule modes:
#   off    manual on/off only
#   times  on at on_time, off at off_time (24-hour, wraps across midnight)
#   sun    on at sunset, off at sunrise for latitude,longitude
set -uo pipefail

STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
STATE_FILE="$STATE_DIR/nightlight.conf"
PID_FILE="$STATE_DIR/nightlight.watch.pid"
LOG_FILE="$STATE_DIR/nightlight.log"
enabled=0
temperature="${NIGHT_TEMP:-4000}"
schedule=off
on_time=18:00
off_time=07:00
latitude=50.45
longitude=30.52
last_schedule=""

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
            schedule) [[ $value =~ ^(off|times|sun)$ ]] && schedule="$value" ;;
            on_time) valid_time "$value" && on_time="$value" ;;
            off_time) valid_time "$value" && off_time="$value" ;;
            latitude) valid_latitude "$value" && latitude="$value" ;;
            longitude) valid_longitude "$value" && longitude="$value" ;;
            last_schedule) [[ $value =~ ^(on|off)$ ]] && last_schedule="$value" ;;
        esac
    done <"$STATE_FILE"
}

save_state() {
    mkdir -p "$STATE_DIR" || die "cannot create $STATE_DIR"
    local tmp
    tmp="$(mktemp "$STATE_FILE.XXXXXX")" || die "cannot write state"
    {
        printf 'enabled=%s\n' "$enabled"
        printf 'temperature=%s\n' "$temperature"
        printf 'schedule=%s\n' "$schedule"
        printf 'on_time=%s\n' "$on_time"
        printf 'off_time=%s\n' "$off_time"
        printf 'latitude=%s\n' "$latitude"
        printf 'longitude=%s\n' "$longitude"
        printf 'last_schedule=%s\n' "$last_schedule"
    } >"$tmp"
    chmod 0600 "$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
}

valid_temp() { [[ $1 =~ ^[0-9]+$ ]] && (($1 >= 1000 && $1 <= 10000)); }
valid_time() { [[ $1 =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; }
valid_latitude() { [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && awk -v v="$1" 'BEGIN { exit !(v >= -90 && v <= 90) }'; }
valid_longitude() { [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && awk -v v="$1" 'BEGIN { exit !(v >= -180 && v <= 180) }'; }

time_minutes() { printf '%s' "$((10#${1%%:*} * 60 + 10#${1##*:}))"; }

# Sunrise and sunset in local minutes since midnight. The NOAA approximation
# is accurate to a few minutes, which is enough for a blue-light filter.
sun_times() {
    awk -v lat="$latitude" -v lon="$longitude" -v doy="$(date +%j)" -v tz="$(date +%z)" '
        function acos(x) { return atan2(sqrt(1 - x * x), x) }
        function rad(x)  { return x * 3.14159265358979 / 180 }
        function deg(x)  { return x * 180 / 3.14159265358979 }
        function tan(x)  { return sin(x) / cos(x) }
        BEGIN {
            g = 2 * 3.14159265358979 / 365 * (doy - 1)
            eq = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) \
                 - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
            decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) \
                 - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g) \
                 - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
            c = cos(rad(90.833)) / (cos(rad(lat)) * cos(decl)) - tan(rad(lat)) * tan(decl)
            if (c < -1) c = -1
            if (c > 1) c = 1
            ha = deg(acos(c))
            sign = substr(tz, 1, 1)
            tzm = (substr(tz, 2, 2) + 0) * 60 + (substr(tz, 4, 2) + 0)
            if (sign == "-") tzm = -tzm
            rise = 720 - 4 * (lon + ha) - eq + tzm
            set  = 720 - 4 * (lon - ha) - eq + tzm
            rise = (rise % 1440 + 1440) % 1440
            set  = (set % 1440 + 1440) % 1440
            printf "%d %d\n", int(rise + 0.5) % 1440, int(set + 0.5) % 1440
        }'
}

daemon_running() { pgrep -x hyprsunset >/dev/null 2>&1; }

ensure_daemon() {
    daemon_running && return 0
    have hyprsunset ||
        die "hyprsunset is not installed; install it with: ./install.sh --modules nightlight"
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    local log="$STATE_DIR/hyprsunset.log" detail=""
    # setsid detaches the daemon from the menu that launched it; nohup is the
    # fallback on systems without util-linux.
    if have setsid; then
        (setsid hyprsunset >"$log" 2>&1 &)
    else
        (nohup hyprsunset >"$log" 2>&1 &)
    fi
    # The protocol socket appears a moment after the process; a command sent
    # too early fails and made the Control Center report a broken night light.
    for _ in {1..30}; do
        daemon_running && return 0
        sleep 0.05
    done
    [[ -r $log ]] && detail="$(tail -n 3 "$log" 2>/dev/null | tr '\n' ' ')"
    die "hyprsunset did not start${detail:+: $detail}"
}

apply() {
    have hyprctl || die "hyprctl is not available (is Hyprland running?)"
    ensure_daemon
    local out=""
    for _ in {1..20}; do
        if out="$(hyprctl hyprsunset temperature "$temperature" 2>&1)"; then
            return 0
        fi
        sleep 0.1
    done
    die "hyprctl could not set the temperature${out:+: $out}"
}

disable() {
    save_state
    daemon_running || return 0
    hyprctl hyprsunset identity >/dev/null 2>&1 || true
}

# The schedule only acts on a boundary crossing. A manual toggle therefore
# stays in effect until the next on/off time instead of being reverted by the
# next one-minute tick.
schedule_desired() {
    local now rise set on off
    now="$(time_minutes "$(date +%H:%M)")"
    case "$schedule" in
        times)
            on="$(time_minutes "$on_time")"
            off="$(time_minutes "$off_time")"
            ((on == off)) && { printf 'off'; return 0; }
            if ((on < off)); then
                ((now >= on && now < off)) && printf 'on' || printf 'off'
            else
                ((now >= on || now < off)) && printf 'on' || printf 'off'
            fi
            ;;
        sun)
            read -r rise set < <(sun_times)
            [[ $rise =~ ^[0-9]+$ && $set =~ ^[0-9]+$ ]] || { printf 'off'; return 0; }
            if ((set <= rise)); then
                # No night window (polar day); keep the filter off.
                printf 'off'
            elif ((now >= set || now < rise)); then
                printf 'on'
            else
                printf 'off'
            fi
            ;;
        *)
            printf 'off'
            ;;
    esac
}

set_enabled() {
    local value="$1"
    if [[ $value == 1 ]]; then
        # Apply first: a failed start must not leave enabled=1 on disk.
        apply
        enabled=1
        save_state
        notify "Night light on (${temperature} K)"
    else
        enabled=0
        save_state
        if daemon_running; then
            hyprctl hyprsunset identity >/dev/null 2>&1 || true
        fi
        notify "Night light off"
    fi
}

schedule_tick() {
    load_state
    [[ $schedule != off ]] || return 0
    local desired
    desired="$(schedule_desired)"
    [[ $desired == "$last_schedule" ]] && return 0

    if [[ $desired == on && $enabled != 1 ]]; then
        enabled=1
        last_schedule=on
        if apply; then
            save_state
            notify "Night light on (${temperature} K)"
        else
            enabled=0
            save_state
        fi
    elif [[ $desired == off && $enabled != 0 ]]; then
        enabled=0
        last_schedule=off
        disable
        notify "Night light off"
    else
        last_schedule="$desired"
        save_state
    fi
}

watch_loop() {
    mkdir -p "$STATE_DIR" || die "cannot create $STATE_DIR"
    if [[ -r $PID_FILE ]]; then
        local old
        old="$(<"$PID_FILE")"
        if [[ $old =~ ^[0-9]+$ ]] && kill -0 "$old" 2>/dev/null &&
            tr '\0' ' ' <"/proc/$old/cmdline" 2>/dev/null | grep -q 'nightlight.sh'; then
            return 0
        fi
    fi
    printf '%s\n' "$$" >"$PID_FILE"
    trap 'rm -f "$PID_FILE"' EXIT
    local out
    while :; do
        # A failed apply must not stop the watcher; retry on the next tick and
        # keep the reason where the user can find it.
        if ! out="$(schedule_tick 2>&1)"; then
            [[ -f $LOG_FILE ]] && (($(wc -c <"$LOG_FILE") > 65536)) && : >"$LOG_FILE"
            printf '%s %s\n' "$(date '+%F %T')" "${out:-schedule tick failed}" >>"$LOG_FILE" 2>/dev/null || true
        fi
        sleep "${NIGHTLIGHT_WATCH_INTERVAL:-60}"
    done
}

load_state

case "${1:-}" in
    on)
        set_enabled 1
        ;;
    off)
        set_enabled 0
        ;;
    toggle)
        if ((enabled)); then set_enabled 0; else set_enabled 1; fi
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
    schedule)
        mode="${2:-}"
        [[ $mode =~ ^(off|times|sun)$ ]] || die "schedule must be off, times or sun"
        schedule="$mode"
        last_schedule=""
        save_state
        [[ $schedule != off ]] && schedule_tick
        ;;
    on-time)
        valid_time "${2:-}" || die "time must be HH:MM (00:00..23:59)"
        on_time="$2"
        last_schedule=""
        save_state
        [[ $schedule == times ]] && schedule_tick
        ;;
    off-time)
        valid_time "${2:-}" || die "time must be HH:MM (00:00..23:59)"
        off_time="$2"
        last_schedule=""
        save_state
        [[ $schedule == times ]] && schedule_tick
        ;;
    location)
        location="${2:-}"
        [[ $location == *,* ]] || die "location must be latitude,longitude"
        lat="${location%%,*}"
        lon="${location#*,}"
        valid_latitude "$lat" || die "latitude must be between -90 and 90"
        valid_longitude "$lon" || die "longitude must be between -180 and 180"
        latitude="$lat"
        longitude="$lon"
        last_schedule=""
        save_state
        [[ $schedule == sun ]] && schedule_tick
        ;;
    get)
        case "${2:-}" in
            enabled) printf '%s\n' "$enabled" ;;
            schedule) printf '%s\n' "$schedule" ;;
            on-time) printf '%s\n' "$on_time" ;;
            off-time) printf '%s\n' "$off_time" ;;
            location) printf '%s,%s\n' "$latitude" "$longitude" ;;
            temperature) printf '%s\n' "$temperature" ;;
            *) die "unknown key: ${2:-}" ;;
        esac
        ;;
    tick)
        schedule_tick
        ;;
    watch)
        watch_loop
        ;;
    status)
        if ((enabled)); then
            printf 'night light: enabled, %s K\n' "$temperature"
        else
            printf 'night light: disabled\n'
        fi
        case "$schedule" in
            times) printf 'schedule: fixed times %s-%s\n' "$on_time" "$off_time" ;;
            sun) printf 'schedule: sunset to sunrise at %s,%s\n' "$latitude" "$longitude" ;;
            *) printf 'schedule: off\n' ;;
        esac
        ;;
    -h|--help)
        printf 'Usage: %s on|off|toggle|status|temp N|restore|schedule off|times|sun|on-time HH:MM|off-time HH:MM|location LAT,LON|get KEY|tick|watch\n' "$(basename "$0")"
        ;;
    '')
        printf 'Usage: %s on|off|toggle|status|temp N|restore|schedule off|times|sun|on-time HH:MM|off-time HH:MM|location LAT,LON|get KEY|tick|watch\n' "$(basename "$0")" >&2
        exit 2
        ;;
    *) die "unknown action: $1 (see --help)" ;;
esac
