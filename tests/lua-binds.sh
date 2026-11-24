#!/usr/bin/env bash
# Optional Lua files run in the global environment: their binds must work
# without hyprland.lua's chunk locals.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

if ! command -v lua >/dev/null 2>&1; then
    pass "lua is not installed; optional bind execution skipped"
    printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
    exit 0
fi

harness() {
    lua - "$1" <<'LUA'
local file = arg[1]
local binds, cmds = {}, {}
hl = {
    bind = function(key) binds[#binds + 1] = key end,
    exec_cmd = function(cmd) cmds[#cmds + 1] = cmd end,
    dsp = { exec_cmd = function(cmd) return cmd end },
    config = function(t)
        if t.gestures then
            for k, v in pairs(t.gestures) do print("CONFIG\t" .. k .. "\t" .. tostring(v)) end
        end
    end,
    gesture = function(t)
        local action = t.action
        if type(action) == "table" then action = "table" end
        print("GESTURE\t" .. tostring(t.fingers) .. "\t" .. tostring(t.direction) .. "\t" .. tostring(action))
    end,
}
local ok, err = pcall(dofile, file)
if not ok then
    io.stderr:write(tostring(err) .. "\n")
    os.exit(2)
end
for _, key in ipairs(binds) do print("BIND\t" .. key) end
for _, cmd in ipairs(cmds) do print("CMD\t" .. cmd) end
LUA
}

check() {
    local name="$1" file="$2" want="$3"
    local out
    if ! out="$(harness "$file" 2>&1)"; then
        fail "$name does not execute: $out"
        return
    fi
    if [[ $out == *"$want"* ]]; then
        pass "$name registers: $want"
    else
        fail "$name is missing: $want (got: $out)"
    fi
}

reject() {
    local name="$1" file="$2" unwanted="$3"
    local out
    if ! out="$(harness "$file" 2>&1)"; then
        fail "$name does not execute: $out"
        return
    fi
    if [[ $out == *"$unwanted"* ]]; then
        fail "$name still registers: $unwanted"
    else
        pass "$name leaves the daemon to the helper"
    fi
}

check "emoji.lua" "$ROOT/modules/emoji/home/.config/hypr/emoji.lua" $'BIND\tSUPER + period'
check "recorder.lua" "$ROOT/modules/recorder/home/.config/hypr/recorder.lua" $'BIND\tSUPER + ALT + R'
check "osd.lua" "$ROOT/modules/osd/home/.config/hypr/osd.lua" $'BIND\tXF86AudioRaiseVolume'
# Starting hyprsunset here raced nightlight.sh restore and could leave two
# daemons on the same IPC socket; the helper owns the daemon lifecycle.
reject "nightlight.lua daemon" "$ROOT/modules/nightlight/home/.config/hypr/nightlight.lua" $'CMD\thyprsunset'
check "nightlight.lua restore" "$ROOT/modules/nightlight/home/.config/hypr/nightlight.lua" $'CMD\tnightlight.sh restore'
check "nightlight.lua watch" "$ROOT/modules/nightlight/home/.config/hypr/nightlight.lua" $'CMD\tnightlight.sh watch'
check "input.lua" "$ROOT/hosts/desktop/input.lua" $'GESTURE\t3\thorizontal\tworkspace'
check "input.lua window move" "$ROOT/hosts/laptop/input.lua" $'GESTURE\t4\thorizontal\ttable'
check "input.lua distance" "$ROOT/hosts/desktop/input.lua" $'CONFIG\tworkspace_swipe_distance\t300'

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
