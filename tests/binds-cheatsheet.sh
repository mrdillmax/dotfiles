#!/usr/bin/env bash
# Tests for modules/binds-cheatsheet. Parses both the repository config and
# synthetic fixtures; nothing outside a temporary directory is touched.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/binds-cheatsheet/home/.local/bin/binds-cheatsheet.sh"
REPO_CONFIG="$ROOT/modules/hypr/home/.config/hypr/hyprland.lua"
PASS=0
FAIL=0
TMP_DIRS=()

cleanup() {
    local d
    for d in "${TMP_DIRS[@]}"; do
        rm -rf -- "$d"
    done
}
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

base="$(mktemp -d)"
TMP_DIRS+=("$base")

run_binds() {
    bash "$SCRIPT" "$@"
}

# ---------------------------------------------------------------- repo file ---

# 1. Help.
if run_binds --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help failed"
fi

# 2. Plain table with resolved variables.
plain="$(run_binds --file "$REPO_CONFIG")"
if grep -q '^KEYBIND.*ACTION' <<<"$plain"; then
    pass "plain output has a header"
else
    fail "plain output has no header"
fi
if grep -qE '^SUPER \+ T[[:space:]]+exec: kitty$' <<<"$plain"; then
    pass "a variable resolves to its command (terminal=kitty)"
else
    fail "terminal variable was not resolved"
    grep 'SUPER + T' <<<"$plain"
fi
if grep -qE '^SUPER \+ Escape[[:space:]]+exec: .*/\.config/rofi/scripts/powermenu\.sh$' <<<"$plain"; then
    pass "an os.getenv(HOME) path is expanded"
else
    fail "the powermenu path was not expanded"
    grep 'SUPER + Escape' <<<"$plain"
fi

# 3. Markdown output.
markdown="$(run_binds --file "$REPO_CONFIG" --markdown)"
# shellcheck disable=SC2016
if grep -qx '| Keybind | Action |' <<<"$markdown" \
    && grep -qx '|---------|--------|' <<<"$markdown" \
    && grep -q '^| `SUPER + T` | exec: kitty |$' <<<"$markdown"; then
    pass "markdown output is a valid table"
else
    fail "markdown output is malformed"
    head -5 <<<"$markdown"
fi

# 4. JSON output parses and carries the expected fields.
json="$(run_binds --file "$REPO_CONFIG" --json)"
if jq -e 'type == "array" and length > 20' <<<"$json" >/dev/null 2>&1; then
    pass "JSON output is a non-empty array"
else
    fail "JSON output does not parse"
    printf '%s\n' "$json" | head -c 300
fi
if jq -e 'any(.[]; .keybind == "SUPER + T" and .action == "exec: kitty" and .dynamic == false)' \
    <<<"$json" >/dev/null 2>&1; then
    pass "JSON entries carry keybind, action and dynamic"
else
    fail "JSON entries are missing fields"
fi

# 5. The real config has no duplicate binds (SUPER + H used to be bound twice).
dup_out="$(run_binds --file "$REPO_CONFIG" --duplicates 2>&1)"
dup_rc=$?
if ((dup_rc == 0)) && grep -q 'No duplicate keybinds' <<<"$dup_out"; then
    pass "--duplicates reports a clean real config"
else
    fail "--duplicates reported a duplicate in the real config"
    printf 'rc=%s\n%s\n' "$dup_rc" "$dup_out"
fi

# ------------------------------------------------------------ synthetic files ---

cat >"$base/clean.lua" <<'EOF'
local terminal = "kitty"
local mainMod = "SUPER"

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
EOF

cat >"$base/duplicate.lua" <<'EOF'
local mainMod = "SUPER"
hl.bind(mainMod .. " + H", hl.dsp.window.close())
hl.bind(mainMod .. " + H", hl.dsp.window.float())
EOF

cat >"$base/dynamic.lua" <<'EOF'
local mainMod = "SUPER"

for i = 1, 5 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end
EOF

cat >"$base/empty.lua" <<'EOF'
-- no bindings here
local mainMod = "SUPER"
EOF

# 6. A clean fixture has no duplicates.
clean_out="$(run_binds --file "$base/clean.lua" --duplicates 2>&1)"
clean_rc=$?
if ((clean_rc == 0)) && grep -q 'No duplicate keybinds' <<<"$clean_out"; then
    pass "a clean fixture reports no duplicates"
else
    fail "a clean fixture was reported as having duplicates"
    printf 'rc=%s\n%s\n' "$clean_rc" "$clean_out"
fi

# 7. Duplicates are detected in a synthetic file.
dup2_out="$(run_binds --file "$base/duplicate.lua" --duplicates 2>&1)"
dup2_rc=$?
if ((dup2_rc == 1)) && grep -qx '  SUPER + H' <<<"$dup2_out"; then
    pass "synthetic duplicates are detected"
else
    fail "synthetic duplicates were missed"
    printf 'rc=%s\n%s\n' "$dup2_rc" "$dup2_out"
fi

# 8. Dynamic binds are labelled and excluded from duplicate checks.
dynamic_json="$(run_binds --file "$base/dynamic.lua" --json)"
if jq -e 'length == 2 and all(.[]; .dynamic == true and (.keybind | endswith("<dynamic>")))' \
    <<<"$dynamic_json" >/dev/null 2>&1; then
    pass "dynamic binds are marked <dynamic>"
else
    fail "dynamic binds are not marked correctly"
    printf '%s\n' "$dynamic_json"
fi
dynamic_dup="$(run_binds --file "$base/dynamic.lua" --duplicates 2>&1)"
dynamic_dup_rc=$?
if ((dynamic_dup_rc == 0)); then
    pass "dynamic binds are skipped by duplicate detection"
else
    fail "dynamic binds were treated as duplicates"
    printf '%s\n' "$dynamic_dup"
fi

# 9. A missing file is a clear error.
if run_binds --file "$base/missing.lua" >/dev/null 2>"$base/error.log"; then
    fail "a missing config was accepted"
else
    if grep -q 'cannot read config' "$base/error.log"; then
        pass "a missing config is explained"
    else
        fail "missing config error is unclear"
        cat "$base/error.log"
    fi
fi

# 10. A config without bindings is not silently accepted.
if run_binds --file "$base/empty.lua" >/dev/null 2>"$base/empty.log"; then
    fail "an empty config was accepted"
else
    if grep -q 'no hl.bind() lines found' "$base/empty.log"; then
        pass "a config without bindings is explained"
    else
        fail "empty config error is unclear"
        cat "$base/empty.log"
    fi
fi

# 10b. --add appends a working bind and returns its line.
cp "$base/clean.lua" "$base/add.lua"
add_out="$(run_binds --file "$base/add.lua" --add "SHIFT + X" "notify-send added" 2>/dev/null)"
add_line="${add_out##*:}"
if [[ $add_line =~ ^[0-9]+$ ]] \
    && sed -n "${add_line}p" "$base/add.lua" | grep -q 'mainMod .. " + SHIFT + X"' \
    && sed -n "${add_line}p" "$base/add.lua" | grep -q 'notify-send added'; then
    pass "--add appends a bind and returns its line"
else
    fail "--add did not append the bind"
    cat "$base/add.lua"
fi
if run_binds --file "$base/add.lua" --add "SHIFT + X" "other" >/dev/null 2>&1; then
    fail "a duplicate keybind was accepted"
else
    pass "adding a duplicate keybind is rejected"
fi
if grep -q 'Add keybind' "$SCRIPT" && grep -q 'add_bind_prompt' "$SCRIPT"; then
    pass "the rofi editor offers Add keybind"
else
    fail "the rofi editor cannot add keybinds"
fi

# 11. Rofi mode falls back to the plain table without a display.
rofi_out="$(env -u WAYLAND_DISPLAY -u DISPLAY bash "$SCRIPT" --file "$base/clean.lua" --rofi)"
if grep -q '^KEYBIND' <<<"$rofi_out" && grep -qE '^SUPER \+ T[[:space:]]+exec: kitty$' <<<"$rofi_out"; then
    pass "--rofi falls back to the plain table without a display"
else
    fail "--rofi did not fall back"
    printf '%s\n' "$rofi_out"
fi

# 12. Unknown options are rejected.
if run_binds --file "$base/clean.lua" --nope >/dev/null 2>&1; then
    fail "an unknown option was accepted"
else
    pass "an unknown option is rejected"
fi

# 12b. The editor picker uses a real Nerd Font glyph, not a literal escape.
if ! grep -q '\\uf11c' "$SCRIPT" && grep -qF "$(printf '%b' '\uf11c')" "$SCRIPT"; then
    pass "the editor picker shows its icon"
else
    fail "the editor picker shows a literal escape"
fi

# 13. The desktop entry launches rofi mode.
desktop="$ROOT/modules/binds-cheatsheet/home/.local/share/applications/binds-cheatsheet.desktop"
if grep -qx 'Exec=binds-cheatsheet.sh --rofi' "$desktop" \
    && grep -qx 'Type=Application' "$desktop"; then
    pass "the desktop entry launches rofi mode"
else
    fail "the desktop entry is invalid"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
