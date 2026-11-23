#!/usr/bin/env bash
# The startup lock only runs when enabled and always clears its marker.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/idle/home/.local/bin/greeter.sh"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/config/dotfiles" "$work/run"
printf '#!/bin/sh\necho locked >"%s/locked"\nexit 0\n' "$work" >"$work/bin/hyprlock"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/notify"\n' "$work" >"$work/bin/notify-send"
chmod +x "$work/bin"/*
PATH="$work/bin:$PATH"
XDG_CONFIG_HOME="$work/config"
XDG_RUNTIME_DIR="$work/run"
export PATH XDG_CONFIG_HOME XDG_RUNTIME_DIR
marker="$work/run/dotfiles-greeter.lock"

: >"$marker"
"$SCRIPT" >/dev/null 2>&1
if [[ ! -e $work/locked && ! -e $marker ]]; then
    pass "a disabled greeter does nothing and clears the marker"
else
    fail "disabled greeter ran hyprlock or kept the marker"
fi

printf 'enabled=1\n' >"$work/config/dotfiles/greeter-on"
: >"$marker"
"$SCRIPT" >/dev/null 2>&1
if [[ -e $work/locked && ! -e $marker ]]; then
    pass "an enabled greeter locks and clears the marker after unlock"
else
    fail "enabled greeter: locked=$([[ -e $work/locked ]] && echo yes) marker=$([[ -e $marker ]] && echo yes)"
fi

printf '#!/bin/sh\nexit 1\n' >"$work/bin/hyprlock"
chmod +x "$work/bin/hyprlock"
: >"$marker"
"$SCRIPT" >/dev/null 2>&1
if [[ ! -e $marker ]] && grep -q 'hyprlock failed' "$work/notify" 2>/dev/null; then
    pass "a failing hyprlock clears the marker and notifies"
else
    fail "failing hyprlock left the session blocked or silent"
fi

# The Lua include registers the start handler only when enabled and creates
# the marker before autostart can race it.
if command -v lua >/dev/null 2>&1; then
    printf 'enabled=1\n' >"$work/config/dotfiles/greeter-on"
    out="$(HOME="$work" XDG_CONFIG_HOME="$work/config" XDG_RUNTIME_DIR="$work/run" \
        GREETER_LUA="$ROOT/modules/idle/home/.config/hypr/greeter.lua" lua - <<'LUA'
HOME = os.getenv("HOME")
local starts = 0
hl = {
    on = function(event) if event == "hyprland.start" then starts = starts + 1 end end,
    exec_cmd = function(cmd) print("EXEC\t" .. cmd) end,
}
dofile(os.getenv("GREETER_LUA"))
print("STARTS\t" .. starts)
LUA
)"
    if [[ $out == *$'STARTS\t1'* && -e $marker ]]; then
        pass "greeter.lua registers the start handler and writes the marker"
    else
        fail "greeter.lua: $out marker=$([[ -e $marker ]] && echo yes)"
    fi
fi

if grep -q 'dotfiles-greeter.lock' "$ROOT/modules/autostart/home/.local/bin/autostart.sh"; then
    pass "autostart waits for the greeter to unlock"
else
    fail "autostart does not wait for the greeter"
fi

# The installer flag writes to GREETER_STATE_DIR so the test stays off $HOME.
if GREETER_STATE_DIR="$work/state" DOTFILES_DIR="$ROOT" "$ROOT/install.sh" --greeter on >/dev/null 2>&1 &&
    [[ -e $work/state/greeter-on ]]; then
    pass "--greeter on creates the marker"
else
    fail "--greeter on did not create the marker"
fi
if GREETER_STATE_DIR="$work/state" DOTFILES_DIR="$ROOT" "$ROOT/install.sh" --greeter off >/dev/null 2>&1 &&
    [[ ! -e $work/state/greeter-on ]]; then
    pass "--greeter off removes the marker"
else
    fail "--greeter off did not remove the marker"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
