#!/usr/bin/env bash
# Screen recorder built on wf-recorder.
#
# Settings live in ~/.config/dotfiles/record.conf (written by the control
# center): audio mode, frame rate and an optional output directory.
#
# Usage: record.sh start|stop|toggle|status
set -uo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
PID_FILE="$RUNTIME/dotfiles-record.pid"
LOG_FILE="$RUNTIME/dotfiles-record.log"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/record.conf"

AUDIO=system
FPS=60
NO_DMABUF=0
OUTPUT=""

die() { printf 'record: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

notify() {
    if have notify-send; then
        notify-send -a "Recorder" "$*" >/dev/null 2>&1 || true
    else
        printf '%s\n' "$*"
    fi
}

load_config() {
    [[ -r $CONFIG ]] || return 0
    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            AUDIO)    AUDIO="$value" ;;
            FPS)      FPS="$value" ;;
            NO_DMABUF) NO_DMABUF="$value" ;;
            OUTPUT)   OUTPUT="$value" ;;
        esac
    done <"$CONFIG"
}

videos_dir() {
    local dir=""
    if [[ -n ${XDG_VIDEOS_DIR:-} ]] && [[ ${XDG_VIDEOS_DIR} != "$HOME" ]]; then
        printf '%s' "$XDG_VIDEOS_DIR"
        return 0
    fi
    if have xdg-user-dir; then
        dir="$(xdg-user-dir VIDEOS 2>/dev/null || true)"
    fi
    # xdg-user-dir prints HOME when the directory is not configured.
    [[ -n $dir && $dir != "$HOME" ]] || dir="$HOME/Videos"
    printf '%s' "$dir"
}

output_dir() {
    if [[ -n $OUTPUT ]]; then
        printf '%s' "${OUTPUT/#\~/$HOME}"
    else
        printf '%s/Recordings' "$(videos_dir)"
    fi
}

audio_args() {
    local mode="$1" sink="" source=""
    case "$mode" in
        off|"") return 0 ;;
        system)
            have pactl && sink="$(pactl get-default-sink 2>/dev/null || true)"
            if [[ -n $sink ]]; then
                printf -- '-a%s.monitor\n' "$sink"
            else
                printf -- '-a\n'
            fi
            ;;
        mic)
            have pactl && source="$(pactl get-default-source 2>/dev/null || true)"
            if [[ -n $source ]]; then
                printf -- '-a%s\n' "$source"
            else
                printf -- '-a\n'
            fi
            ;;
        both)
            have pactl && source="$(pactl get-default-source 2>/dev/null || true)"
            have pactl && sink="$(pactl get-default-sink 2>/dev/null || true)"
            [[ -n $source ]] && printf -- '-a%s\n' "$source"
            if [[ -n $sink ]]; then
                printf -- '-a%s.monitor\n' "$sink"
            elif [[ -z $source ]]; then
                printf -- '-a\n'
            fi
            ;;
    esac
}

read_state() {
    pid=""
    file=""
    [[ -r $PID_FILE ]] || return 1
    { read -r pid; read -r file; } <"$PID_FILE"
    [[ $pid =~ ^[0-9]+$ ]]
}

running() {
    read_state || return 1
    kill -0 "$pid" 2>/dev/null
}

# Build the argument list for one attempt. $1 is the audio mode.
recorder_args() {
    local mode="$1" region="$2" file="$3" device
    printf -- '-g\n%s\n-f\n%s\n' "$region" "$file"
    printf -- '-c\nlibx264\n-x\nyuv420p\n-r\n%s\n' "$FPS"
    ((NO_DMABUF)) && printf -- '--no-dmabuf\n'
    while IFS= read -r device; do
        [[ -n $device ]] && printf '%s\n' "$device"
    done < <(audio_args "$mode")
}

spawn() {
    local region="$1" file="$2" mode="$3"
    local -a args=()
    mapfile -t args < <(recorder_args "$mode" "$region" "$file")
    : >"$LOG_FILE" 2>/dev/null || true
    wf-recorder "${args[@]}" >"$LOG_FILE" 2>&1 &
    pid=$!
}

start() {
    running && die "already recording ($file)"
    have slurp || die "slurp is not installed"
    have wf-recorder || die "wf-recorder is not installed"

    load_config

    local region dir
    region="$(slurp)" || die "region selection cancelled"
    [[ -n $region ]] || die "region selection cancelled"

    dir="$(output_dir)"
    mkdir -p "$dir" || die "cannot create $dir"
    file="$dir/rec-$(date +%Y%m%d-%H%M%S).mp4"

    spawn "$region" "$file" "$AUDIO"
    sleep 0.4

    # Recording both sources fails on builds that accept a single --audio
    # device. Fall back to system audio instead of losing the whole take.
    if ! kill -0 "$pid" 2>/dev/null && [[ $AUDIO == both ]]; then
        spawn "$region" "$file" system
        sleep 0.4
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f -- "$PID_FILE"
        local detail=""
        [[ -r $LOG_FILE ]] && detail="$(tail -n 3 "$LOG_FILE" | tr '\n' ' ')"
        die "wf-recorder did not start${detail:+: $detail}"
    fi

    printf '%s\n%s\n' "$pid" "$file" >"$PID_FILE"
    notify "Recording started: $file"
    printf '%s\n' "$file"
}

stop() {
    running || { rm -f -- "$PID_FILE"; die "not recording"; }

    kill -INT "$pid" 2>/dev/null || true
    for _ in {1..50}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    rm -f -- "$PID_FILE"
    notify "Recording saved: $file"
    printf '%s\n' "$file"
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    toggle)
        if running; then
            stop
        else
            start
        fi
        ;;
    status)
        if running; then
            printf 'recording: %s\n' "$file"
        else
            printf 'recording: off\n'
        fi
        ;;
    -h|--help)
        printf 'Usage: %s start|stop|toggle|status\n' "$(basename "$0")"
        ;;
    *)
        printf 'Usage: %s start|stop|toggle|status\n' "$(basename "$0")" >&2
        exit 2
        ;;
esac
