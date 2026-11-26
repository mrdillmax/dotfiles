#!/usr/bin/env bash
# The optional greeter module locks at startup and always clears its marker.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/greeter/home/.local/bin/greeter.sh"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

if [[ -r $ROOT/modules/greeter/module.conf ]] && grep -qx 'OPTIONAL=1' "$ROOT/modules/greeter/module.conf"; then
    pass "greeter is an optional module"
else
    fail "greeter/module.conf missing or not optional"
fi

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
if [[ -e $work/locked && ! -e $marker ]]; then
    pass "greeter locks and clears the marker after unlock"
else
    fail "greeter: locked=$([[ -e $work/locked ]] && echo yes) marker=$([[ -e $marker ]] && echo yes)"
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

# The Lua include registers the start handler and creates the marker before
# autostart can race it.
if command -v lua >/dev/null 2>&1; then
    out="$(HOME="$work" XDG_CONFIG_HOME="$work/config" XDG_RUNTIME_DIR="$work/run" \
        GREETER_LUA="$ROOT/modules/greeter/home/.config/hypr/greeter.lua" lua - <<'LUA'
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

if grep -q 'dotfiles-greeter.lock' "$ROOT/modules/autostart/home/.local/bin/autostart.sh" &&
    grep -q 'greeter.lua' "$ROOT/modules/autostart/home/.local/bin/autostart.sh"; then
    pass "autostart waits for the greeter module to unlock"
else
    fail "autostart does not wait for the greeter module"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
