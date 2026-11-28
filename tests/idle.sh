#!/usr/bin/env bash
# hypridle runs as a user service, and screen-off uses the Hyprland 0.57 Lua
# dispatcher instead of the removed `dpms off` string form.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/idle/home/.local/bin/idle-tune.sh"
STATIC="$ROOT/modules/idle/home/.config/hypr/hypridle.conf.in"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home" "$work/config" "$work/state" "$work/run"
printf '#!/bin/sh\nprintf "started\\n" >>"%s/direct-hypridle"\n' "$work" >"$work/bin/hypridle"
chmod +x "$work/bin/hypridle"

cat >"$work/bin/systemctl" <<'SYSTEMCTL'
#!/bin/sh
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
case "$*" in
    *list-unit-files*)
        [[ ${UNIT_EXISTS:-1} == 1 ]] || exit 1
        printf 'hypridle.service enabled\n'
        ;;
    *is-enabled*) [[ ${SERVICE_ENABLED:-1} == 1 ]] ;;
    *is-active*)  [[ ${SERVICE_ACTIVE:-1} == 1 ]] ;;
    *) exit 0 ;;
esac
SYSTEMCTL
chmod +x "$work/bin/systemctl"

# `pgrep` / `pkill` are used by `idle-tune.sh` (is_running / fallback kill).
# Stub early so they never touch the real process table.
cat >"$work/bin/pgrep" <<'PGREP'
#!/bin/sh
printf '%s\n' "$*" >>"$PGREP_LOG"
exit 0
PGREP
cat >"$work/bin/pkill" <<'PKILL'
#!/bin/sh
printf '%s\n' "$*" >>"$PKILL_LOG"
exit 0
PKILL
chmod +x "$work/bin/pgrep" "$work/bin/pkill"
export PGREP_LOG="$work/pgrep.log"
export PKILL_LOG="$work/pkill.log"

export PATH="$work/bin:$PATH"
export HOME="$work/home"
export XDG_CONFIG_HOME="$work/config"
export XDG_STATE_HOME="$work/state"
export XDG_RUNTIME_DIR="$work/run"
export IDLE_POWER=battery
export SYSTEMCTL_LOG="$work/systemctl.log"
export UNIT_EXISTS=1
export SERVICE_ENABLED=1
export SERVICE_ACTIVE=1

run_idle() { "$SCRIPT" "$@" >/dev/null 2>&1; }

# --- rendered configuration -------------------------------------------------

if grep -q 'on-timeout = lock-screen.sh screen-off' "$STATIC" &&
    grep -q 'on-resume = lock-screen.sh unlocked' "$STATIC" &&
    grep -q 'on-timeout = lock-screen.sh suspend' "$STATIC" &&
    ! grep -Eq 'dpms\("|hyprctl dispatch dpms' "$STATIC"; then
    pass "screen-off and suspend go through the guarded helper"
else
    fail "the shipped template bypasses the resume guard"
fi
static_dim="$(sed -n '/timeout = 150/,/^}/p' "$STATIC")"
if [[ $static_dim == *'idle-dim.sh dim'* && $static_dim == *'idle-dim.sh restore'* &&
    $static_dim != *'screen-off'* ]]; then
    pass "the dim stage lowers brightness instead of powering the panel off"
else
    fail "the dim stage still uses DPMS: $static_dim"
fi

if grep -q 'before_sleep_cmd = loginctl lock-session' "$STATIC" &&
    grep -q 'after_sleep_cmd = lock-screen.sh resume' "$STATIC" &&
    grep -q 'unlock_cmd = lock-screen.sh unlocked' "$STATIC" &&
    ! grep -q 'on_unlock_cmd' "$STATIC" &&
    grep -q 'inhibit_sleep = 3' "$STATIC" &&
    grep -q 'on-timeout = loginctl lock-session' "$STATIC" &&
    grep -q 'condition_cmd = lock-screen.sh can-dpms-off' "$STATIC" &&
    grep -q 'condition_cmd = lock-screen.sh can-suspend' "$STATIC"; then
    pass "the shipped template locks through logind and restores the panel on resume"
else
    fail "the shipped template does not use the logind lock path"
fi

run_idle apply --profile battery
config="$XDG_CONFIG_HOME/hypr/hypridle.conf"
if grep -q 'on-timeout = lock-screen.sh screen-off' "$config" &&
    grep -q 'on-timeout = lock-screen.sh suspend' "$config" &&
    grep -q 'lock-screen.sh unlocked' "$config" &&
    ! grep -Eq 'dpms\("|hyprctl dispatch dpms|on_unlock_cmd' "$config"; then
    pass "idle-tune renders the guarded screen-off and suspend commands"
else
    fail "rendered config bypasses the guarded helper"
fi
rendered_dim="$(sed -n '/timeout = 150/,/^}/p' "$config")"
if [[ $rendered_dim == *'idle-dim.sh dim'* &&
    $rendered_dim == *'idle-dim.sh restore'* &&
    $rendered_dim != *'screen-off'* ]] &&
    grep -q 'after_sleep_cmd = lock-screen.sh resume' "$config" &&
    grep -q 'condition_cmd = lock-screen.sh can-suspend' "$config" &&
    grep -q 'inhibit_sleep = 3' "$config"; then
    pass "idle-tune renders a brightness dim and restores the panel after sleep"
else
    fail "rendered dim stage: $rendered_dim"
fi

# A checkout from before the .in rename linked this path into the repository.
# Rendering must replace the link, not edit the tracked file through it.
printf 'tracked\n' >"$work/repo-hypridle.conf"
rm -f "$config"
ln -s "$work/repo-hypridle.conf" "$config"
run_idle apply --profile battery
if [[ ! -L $config && $(<"$work/repo-hypridle.conf") == tracked ]]; then
    pass "idle-tune replaces a legacy symlink instead of writing through it"
else
    fail "idle-tune wrote through the repository symlink"
fi

# --- service control -------------------------------------------------------

if grep -qx 'SERVICES=(hypridle.service)' "$ROOT/modules/idle/module.conf"; then
    pass "the idle module declares hypridle.service"
else
    fail "the idle module does not enable hypridle.service"
fi

: >"$SYSTEMCTL_LOG"
SERVICE_ENABLED=0 run_idle enable
if grep -q -- '--user enable --now hypridle.service' "$SYSTEMCTL_LOG" &&
    grep -qx 'ENABLED=1' "$XDG_STATE_HOME/dotfiles/idle.conf"; then
    pass "enable starts the user service"
else
    fail "enable did not start the service: $(cat "$SYSTEMCTL_LOG")"
fi

: >"$SYSTEMCTL_LOG"
SERVICE_ENABLED=1 run_idle disable
if grep -q -- '--user disable --now hypridle.service' "$SYSTEMCTL_LOG" &&
    grep -qx 'ENABLED=0' "$XDG_STATE_HOME/dotfiles/idle.conf"; then
    pass "disable stops the user service"
else
    fail "disable did not stop the service: $(cat "$SYSTEMCTL_LOG")"
fi

# Re-enable for the autostart checks below.
SERVICE_ENABLED=0 run_idle enable

: >"$SYSTEMCTL_LOG"
rm -f "$work/direct-hypridle"
SERVICE_ENABLED=1 SERVICE_ACTIVE=0 run_idle run
if grep -q -- '--user start hypridle.service' "$SYSTEMCTL_LOG" &&
    [[ ! -e $work/direct-hypridle ]]; then
    pass "autostart starts the unit and not a second daemon"
else
    fail "autostart started a duplicate hypridle: $(cat "$SYSTEMCTL_LOG")"
fi

# A machine upgrading from the autostart-only setup has the unit disabled.
: >"$SYSTEMCTL_LOG"
SERVICE_ENABLED=0 run_idle run
if grep -q -- '--user enable --now hypridle.service' "$SYSTEMCTL_LOG" &&
    [[ ! -e $work/direct-hypridle ]]; then
    pass "autostart enables a disabled unit instead of forking hypridle"
else
    fail "autostart did not migrate to the unit: $(cat "$SYSTEMCTL_LOG")"
fi

# Without the packaged unit the old direct start still works.
: >"$SYSTEMCTL_LOG"
rm -f "$work/direct-hypridle"
UNIT_EXISTS=0 run_idle run
if [[ -e $work/direct-hypridle ]] &&
    ! grep -Eq -- '--user (enable|start|restart|disable)' "$SYSTEMCTL_LOG"; then
    pass "autostart falls back to running hypridle directly"
else
    fail "direct fallback did not run: $(cat "$SYSTEMCTL_LOG")"
fi

# Applying a profile restarts an active unit so it reloads the new timers.
: >"$SYSTEMCTL_LOG"
UNIT_EXISTS=1 SERVICE_ACTIVE=1 run_idle apply --profile ac
if grep -q -- '--user restart hypridle.service' "$SYSTEMCTL_LOG"; then
    pass "applying a profile restarts the service"
else
    fail "apply did not restart the service: $(cat "$SYSTEMCTL_LOG")"
fi

# --- resume guard -----------------------------------------------------------

LOCK="$ROOT/modules/hypr/home/.local/bin/lock-screen.sh"
mkdir -p "$work/lock-state/dotfiles"
date +%s >"$work/lock-state/dotfiles/resumed-at"
if ! XDG_STATE_HOME="$work/lock-state" "$LOCK" can-dpms-off; then
    pass "the DPMS-off listener is skipped just after a resume"
else
    fail "can-dpms-off allowed an immediate screen-off after resume"
fi
printf '%s\n' "$(($(date +%s) - 60))" >"$work/lock-state/dotfiles/resumed-at"
if XDG_STATE_HOME="$work/lock-state" "$LOCK" can-dpms-off; then
    pass "the DPMS-off listener works again after the resume guard expires"
else
    fail "can-dpms-off stayed blocked a minute after resume"
fi
date +%s >"$work/lock-state/dotfiles/resumed-at"
if ! XDG_STATE_HOME="$work/lock-state" "$LOCK" can-suspend; then
    pass "the suspend listener is skipped just after a resume"
else
    fail "can-suspend allowed an immediate re-suspend after resume"
fi
printf '%s\n' "$(($(date +%s) - 60))" >"$work/lock-state/dotfiles/resumed-at"
if XDG_STATE_HOME="$work/lock-state" "$LOCK" can-suspend; then
    pass "the suspend listener works again after the resume guard expires"
else
    fail "can-suspend stayed blocked a minute after resume"
fi

mkdir -p "$work/lock-bin"
printf '#!/bin/sh\nexit 0\n' >"$work/lock-bin/hyprlock"
printf '#!/bin/sh\nexit 1\n' >"$work/lock-bin/pgrep"
printf '#!/bin/sh\nprintf "hyprctl %%s\\n" "$*" >>"%s/lock-calls"\n' "$work" >"$work/lock-bin/hyprctl"
printf '#!/bin/sh\nprintf "idle-dim %%s\\n" "$*" >>"%s/lock-calls"\n' "$work" >"$work/lock-bin/idle-dim.sh"
chmod +x "$work/lock-bin"/*
XDG_STATE_HOME="$work/lock-state" PATH="$work/lock-bin:$PATH" "$LOCK" lock
if grep -q 'hyprctl dispatch hl.dsp.dpms({ action = "on" })' "$work/lock-calls" &&
    grep -q 'idle-dim restore' "$work/lock-calls"; then
    pass "unlocking restores DPMS and the backlight"
else
    fail "the locker did not restore the panel: $(cat "$work/lock-calls" 2>/dev/null)"
fi

# The Lua dispatcher treats a bare string as "toggle"; the helper must force
# the action, or the post-unlock restore turns the panel off instead of on.
if grep -q 'dpms("on")' "$LOCK"; then
    fail "the locker still passes a bare string to hl.dsp.dpms"
else
    pass "the locker forces the DPMS action instead of toggling"
fi

: >"$work/lock-calls"
date +%s >"$work/lock-state/dotfiles/resumed-at"
XDG_STATE_HOME="$work/lock-state" PATH="$work/lock-bin:$PATH" "$LOCK" screen-off
if [[ ! -s $work/lock-calls ]]; then
    pass "screen-off is skipped just after a resume"
else
    fail "screen-off fired right after a resume: $(cat "$work/lock-calls")"
fi
printf '%s\n' "$(($(date +%s) - 60))" >"$work/lock-state/dotfiles/resumed-at"
XDG_STATE_HOME="$work/lock-state" PATH="$work/lock-bin:$PATH" "$LOCK" screen-off
if grep -q 'hyprctl dispatch hl.dsp.dpms({ action = "off" })' "$work/lock-calls"; then
    pass "screen-off powers the panel off once the guard expires"
else
    fail "screen-off did not power the panel off: $(cat "$work/lock-calls")"
fi

: >"$SYSTEMCTL_LOG"
date +%s >"$work/lock-state/dotfiles/resumed-at"
XDG_STATE_HOME="$work/lock-state" PATH="$work/lock-bin:$PATH" "$LOCK" suspend
if ! grep -qx suspend "$SYSTEMCTL_LOG"; then
    pass "suspend is skipped just after a resume"
else
    fail "suspend fired right after a resume"
fi
printf '%s\n' "$(($(date +%s) - 60))" >"$work/lock-state/dotfiles/resumed-at"
XDG_STATE_HOME="$work/lock-state" PATH="$work/lock-bin:$PATH" "$LOCK" suspend
if grep -qx suspend "$SYSTEMCTL_LOG"; then
    pass "suspend works once the guard expires"
else
    fail "suspend did not run after the guard expired"
fi

# --- brightness dim ---------------------------------------------------------

DIM="$ROOT/modules/idle/home/.local/bin/idle-dim.sh"
mkdir -p "$work/dim-bin" "$work/dim-state" "$work/empty-bin"
ln -s "$(command -v bash)" "$work/empty-bin/bash"
cat >"$work/dim-bin/brightnessctl" <<'DIMSTUB'
#!/bin/sh
printf '%s\n' "$*" >>"$DIM_CALLS"
case "$1" in
    -m) printf 'intel_backlight,backlight,0,%s%%,1000\n' "${BRIGHT_CURRENT:-50}" ;;
esac
DIMSTUB
export DIM_CALLS="$work/dim-calls"
chmod +x "$work/dim-bin/brightnessctl"
BRIGHT_CURRENT=50 XDG_STATE_HOME="$work/dim-state" PATH="$work/dim-bin:$PATH" "$DIM" dim
if grep -q -- '-s set 15%' "$work/dim-calls" &&
    [[ -e $work/dim-state/dotfiles/idle-dim ]]; then
    pass "dim saves and lowers the backlight"
else
    fail "dim calls: $(cat "$work/dim-calls" 2>/dev/null)"
fi
XDG_STATE_HOME="$work/dim-state" PATH="$work/dim-bin:$PATH" "$DIM" restore
if grep -q -- '-r' "$work/dim-calls" &&
    [[ ! -e $work/dim-state/dotfiles/idle-dim ]]; then
    pass "restore returns to the saved backlight"
else
    fail "restore calls: $(cat "$work/dim-calls" 2>/dev/null)"
fi
rm -f "$work/dim-calls"
XDG_STATE_HOME="$work/dim-state" PATH="$work/empty-bin" "$DIM" dim
if [[ ! -e $work/dim-calls && ! -e $work/dim-state/dotfiles/idle-dim ]]; then
    pass "dim is a no-op without brightnessctl"
else
    fail "dim ran without brightnessctl"
fi

rm -f "$work/dim-calls" "$work/dim-state/dotfiles/idle-dim"
BRIGHT_CURRENT=10 XDG_STATE_HOME="$work/dim-state" PATH="$work/dim-bin:$PATH" "$DIM" dim
if ! grep -q -- '-s set' "$work/dim-calls" &&
    [[ ! -e $work/dim-state/dotfiles/idle-dim ]]; then
    pass "dim does not brighten a panel that is already darker"
else
    fail "dim raised a 10% panel: $(cat "$work/dim-calls" 2>/dev/null)"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
