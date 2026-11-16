#!/usr/bin/env bash
# Tests for modules/theme-menu. Uses a temporary $HOME and stub matugen/awww.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/theme-menu/home/.local/bin/theme-menu.sh"
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

home="$base/home"
state="$base/state"
bin="$base/bin"
matugen_log="$base/matugen.log"
awww_log="$base/awww.log"
wall="$base/wall.png"
wall2="$base/wall2.jpg"

mkdir -p "$home/.config/matugen" "$state" "$bin"
: >"$home/.config/matugen/config.toml"
printf 'png\n' >"$wall"
printf 'jpg\n' >"$wall2"
: >"$matugen_log"
: >"$awww_log"

cat >"$bin/matugen" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MATUGEN_LOG"
EOF

cat >"$bin/awww" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AWWW_LOG"
EOF
chmod 0755 "$bin/matugen" "$bin/awww"

run_theme() {
    env HOME="$home" XDG_STATE_HOME="$state" \
        PATH="$bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
        MATUGEN_LOG="$matugen_log" AWWW_LOG="$awww_log" \
        bash "$SCRIPT" "$@"
}

state_file="$state/dotfiles/theme.conf"

# 1. Help and type listing.
if run_theme --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help failed"
fi

types_out="$(run_theme --list-types)"
if grep -qx 'scheme-tonal-spot' <<<"$types_out" \
    && grep -qx 'scheme-vibrant' <<<"$types_out"; then
    pass "--list-types prints the matugen schemes"
else
    fail "--list-types output is incomplete"
fi

# 2. Defaults are usable without a state file.
defaults="$(run_theme --print)"
if grep -qx 'mode=dark' <<<"$defaults" \
    && grep -qx 'type=scheme-tonal-spot' <<<"$defaults" \
    && grep -qx 'wallpaper=' <<<"$defaults"; then
    pass "defaults are dark + scheme-tonal-spot"
else
    fail "defaults are wrong"
    printf '%s\n' "$defaults"
fi

# 3. Recording settings does not run matugen or awww.
run_theme --wallpaper "$wall" --mode light --type scheme-vibrant >/dev/null
if [[ -r $state_file ]] \
    && grep -qx "wallpaper=$wall" "$state_file" \
    && grep -qx 'mode=light' "$state_file" \
    && grep -qx 'type=scheme-vibrant' "$state_file"; then
    pass "settings are stored outside the repository"
else
    fail "settings were not stored correctly"
    cat "$state_file" 2>/dev/null
fi
if [[ ! -s $matugen_log && ! -s $awww_log ]]; then
    pass "recording settings does not apply anything"
else
    fail "recording settings ran matugen or awww"
fi

# 4. Apply uses the stored values.
run_theme --apply >/dev/null
if grep -q "image $wall --mode light --type scheme-vibrant --config $home/.config/matugen/config.toml" "$matugen_log"; then
    pass "--apply runs matugen with the stored settings"
else
    fail "matugen was not called correctly"
    cat "$matugen_log"
fi
if grep -qx "img $wall" "$awww_log"; then
    pass "--apply applies the wallpaper"
else
    fail "awww was not called correctly"
    cat "$awww_log"
fi

# 5. A partial update keeps the other stored values.
run_theme --mode dark >/dev/null
if grep -qx 'mode=dark' "$state_file" \
    && grep -qx "wallpaper=$wall" "$state_file" \
    && grep -qx 'type=scheme-vibrant' "$state_file"; then
    pass "a partial update keeps the other settings"
else
    fail "a partial update overwrote the other settings"
    cat "$state_file"
fi

# 6. --wallpaper-only applies without regenerating colors.
: >"$matugen_log"
: >"$awww_log"
run_theme --wallpaper "$wall2" --wallpaper-only >/dev/null
if [[ ! -s $matugen_log ]] && grep -qx "img $wall2" "$awww_log"; then
    pass "--wallpaper-only skips matugen"
else
    fail "--wallpaper-only behaviour is wrong"
fi

# 7. Dry-run changes nothing.
: >"$matugen_log"
: >"$awww_log"
before_state="$(cat "$state_file")"
dry_out="$(run_theme --mode smart --apply --dry-run)"
if grep -q '\[dry-run\] matugen' <<<"$dry_out" \
    && grep -q '\[dry-run\] awww' <<<"$dry_out"; then
    pass "dry-run prints the commands"
else
    fail "dry-run output is incomplete"
    printf '%s\n' "$dry_out"
fi
if [[ "$(cat "$state_file")" == "$before_state" && ! -s $matugen_log && ! -s $awww_log ]]; then
    pass "dry-run changes nothing"
else
    fail "dry-run wrote state or ran commands"
fi

# 8. Invalid values are rejected.
if run_theme --mode purple >/dev/null 2>&1; then
    fail "invalid mode was accepted"
else
    pass "invalid mode is rejected"
fi
if run_theme --type scheme-nope >/dev/null 2>&1; then
    fail "invalid scheme type was accepted"
else
    pass "invalid scheme type is rejected"
fi
if run_theme --wallpaper "$base/missing.png" >/dev/null 2>&1; then
    fail "a missing wallpaper was accepted"
else
    pass "a missing wallpaper is rejected"
fi

# 9. A missing matugen config is a clear error.
home2="$base/home2"
state2="$base/state2"
mkdir -p "$home2" "$state2"
if env HOME="$home2" XDG_STATE_HOME="$state2" PATH="$bin:$PATH" \
    HYPRLAND_INSTANCE_SIGNATURE=test MATUGEN_LOG="$matugen_log" AWWW_LOG="$awww_log" \
    bash "$SCRIPT" --wallpaper "$wall" --apply >/dev/null 2>"$base/error.log"; then
    fail "missing matugen config was accepted"
else
    if grep -q 'missing matugen config' "$base/error.log"; then
        pass "missing matugen config is explained"
    else
        fail "missing matugen config error is unclear"
        cat "$base/error.log"
    fi
fi

# 10. The desktop entry points at the installed command.
desktop="$ROOT/modules/theme-menu/home/.local/share/applications/theme-menu.desktop"
if grep -qx 'Exec=theme-menu.sh' "$desktop" \
    && grep -qx 'Type=Application' "$desktop"; then
    pass "the desktop entry launches theme-menu.sh"
else
    fail "the desktop entry is invalid"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
