#!/usr/bin/env bash
# Lock the session and put the panel back after it is unlocked.
#
# hyprlock is the preferred helper; swaylock and loginctl are fallbacks. The
# wrapper matters because hyprlock does not turn the panel back on when it
# exits: a DPMS-off listener can leave the screen black after unlocking.
#
# Usage: lock-screen.sh [lock|resume|unlocked] [--from-idle]
#   lock       start the locker and restore DPMS/brightness when it exits
#   resume     post-suspend fix-up: DPMS on, restore brightness, reset idle
#   unlocked   post-unlock fix-up only
set -uo pipefail

ACTION="lock"
FROM_IDLE=0
for arg in "$@"; do
    case "$arg" in
        lock|resume|unlocked|can-dpms-off|can-suspend) ACTION="$arg" ;;
        --from-idle) FROM_IDLE=1 ;;
    esac
done

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
RESUME_STAMP="$STATE_DIR/resumed-at"

have() { command -v "$1" >/dev/null 2>&1; }

dpms_on() {
    have hyprctl || return 0
    hyprctl dispatch 'hl.dsp.dpms("on")' >/dev/null 2>&1 || true
}

restore_dim() {
    have idle-dim.sh || return 0
    idle-dim.sh restore >/dev/null 2>&1 || true
}

restore_session() {
    dpms_on
    restore_dim
}

stamp_resume() {
    mkdir -p -- "$STATE_DIR" 2>/dev/null || return 0
    date +%s >"$RESUME_STAMP" 2>/dev/null || true
}

# hypridle's listeners can fire on idle time that was counted just before a
# resume. Within the grace period after a wake-up, keep the panel on and skip
# the suspend stage; the next input starts a fresh idle cycle.
recently_resumed() {
    [[ -r $RESUME_STAMP ]] || return 1
    local resumed now
    resumed="$(<"$RESUME_STAMP")"
    [[ $resumed =~ ^[0-9]+$ ]] || return 1
    now="$(date +%s)"
    ((now - resumed < 30))
}

can_dpms_off() {
    ! recently_resumed
}

can_suspend() {
    ! recently_resumed
}

run_locker() {
    # Avoid stacking a second locker on top of the first one.
    if pgrep -x hyprlock >/dev/null 2>&1; then
        return 0
    fi
    if have hyprlock; then
        hyprlock
        restore_session
        return 0
    fi
    if have swaylock; then
        swaylock
        restore_session
        return 0
    fi
    # Never call loginctl from hypridle's lock_cmd: the Lock signal would run
    # lock_cmd again and loop.
    if ((FROM_IDLE == 0)) && have loginctl; then
        loginctl lock-session
        return 0
    fi
    if have notify-send; then
        notify-send -a "Lock screen" "No lock screen helper is installed" >/dev/null 2>&1 || true
    fi
    printf 'lock-screen: install hyprlock (idle module) or swaylock\n' >&2
    return 1
}

case "$ACTION" in
    resume)
        stamp_resume
        restore_session
        ;;
    can-dpms-off)
        can_dpms_off
        ;;
    can-suspend)
        can_suspend
        ;;
    unlocked)
        restore_session
        ;;
    lock)
        run_locker
        ;;
esac
