#!/usr/bin/env bash
# `--add` must write valid Lua: `--` comments and the new bind inside the binds
# section, not after the window rules.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/binds-cheatsheet/home/.local/bin/binds-cheatsheet.sh"
SOURCE="$ROOT/modules/hypr/home/.config/hypr/hyprland.lua"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cfg="$work/hyprland.lua"
cp "$SOURCE" "$cfg"
HOME="$work"
export HOME

last_bind_before="$(grep -n 'hl\.bind(' "$cfg" | tail -n1 | cut -d: -f1)"
rules_before="$(grep -c 'window_rule' "$cfg")"

if "$SCRIPT" --file "$cfg" --add "SHIFT + X" "notify-send hello" >"$work/out" 2>"$work/err"; then
    pass "add exits successfully"
else
    fail "add failed: $(cat "$work/err")"
fi

new_line="$(grep -n 'hl\.bind(mainMod .. " + SHIFT + X"' "$cfg" | cut -d: -f1)"
if [[ -n $new_line && $new_line == "$((last_bind_before + 2))" ]]; then
    pass "bind lands right after the last existing bind"
else
    fail "bind at ${new_line:-nowhere}, expected $((last_bind_before + 2))"
fi

if [[ $(sed -n "$((last_bind_before + 1))p" "$cfg") == '-- Added by binds-cheatsheet'* ]]; then
    pass "comment uses Lua syntax"
else
    fail "comment is not a Lua comment: $(sed -n "$((last_bind_before + 1))p" "$cfg")"
fi

if grep -q '^#' "$cfg"; then
    fail "file contains '#' comments, which Lua rejects"
else
    pass "no '#' comments in the config"
fi

if [[ $(grep -c 'window_rule' "$cfg") == "$rules_before" ]]; then
    pass "window rules untouched"
else
    fail "window rules changed"
fi

if "$SCRIPT" --file "$cfg" --add "SHIFT + X" "true" >/dev/null 2>"$work/err2"; then
    fail "duplicate bind was accepted"
else
    pass "duplicate bind is rejected"
fi

if [[ $(grep -c 'Added by binds-cheatsheet' "$cfg") == 1 ]]; then
    pass "rejected duplicate did not write"
else
    fail "a rejected duplicate still wrote to the file"
fi

if command -v luac >/dev/null 2>&1; then
    if luac -p "$cfg" 2>/dev/null; then
        pass "config is valid Lua"
    else
        fail "luac rejected the config"
    fi
fi

# Optional module files next to the main config are part of the cheatsheet.
mkdir -p "$work/.config/hypr"
cp "$SOURCE" "$work/.config/hypr/hyprland.lua"
printf 'hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("swayosd-client --output-volume raise"))\n' \
    >"$work/.config/hypr/osd.lua"
json="$(HOME="$work" "$SCRIPT" --json)"
if [[ $json == *XF86AudioRaiseVolume* ]]; then
    pass "binds from optional module files are listed"
else
    fail "optional module binds are missing from the cheatsheet"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
