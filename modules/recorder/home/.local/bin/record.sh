#!/usr/bin/env bash
# Screen recorder built on wf-recorder.
#
# Usage: record.sh start|stop|toggle|status
set -uo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
PID_FILE="$RUNTIME/dotfiles-record.pid"
OUT_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"

die() { printf 'record: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

notify() {
    if have notify-send; then
        notify-send -a "Recorder" "$*" >/dev/null 2>&1 || true
    else
        printf '%s\n' "$*"
    fi
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

start() {
    running && die "already recording ($file)"
    have slurp || die "slurp is not installed"
    have wf-recorder || die "wf-recorder is not installed"

    local region
    region="$(slurp)" || die "region selection cancelled"
    [[ -n $region ]] || die "region selection cancelled"

    mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
    file="$OUT_DIR/rec-$(date +%Y%m%d-%H%M%S).mp4"

    wf-recorder -g "$region" -f "$file" >/dev/null 2>&1 &
    pid=$!
    printf '%s\n%s\n' "$pid" "$file" >"$PID_FILE"

    sleep 0.2
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f -- "$PID_FILE"
        die "wf-recorder did not start"
    fi

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
