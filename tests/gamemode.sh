#!/usr/bin/env bash
# Tests for modules/gamemode. Uses a stub hyprctl; no Hyprland session needed
# and nothing outside temporary directories is touched.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/gamemode/home/.local/bin/gamemode.sh"
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

# new_env -> prints "base<TAB>home<TAB>state<TAB>stub_state<TAB>log"
new_env() {
    local base
    base="$(mktemp -d)"
    TMP_DIRS+=("$base")

    mkdir -p "$base/bin" "$base/home" "$base/state"
    cat >"$base/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    getoption)
        key="${2:-}"
        line="$(awk -F'\t' -v k="$key" '$1 == k {print $2; exit}' "$HYPRCTL_STATE")"
        if [[ -z $line ]]; then
            printf 'no such option\n'
            exit 1
        fi
        printf '%s: %s\n' "${line%%:*}" "${line#*:}"
        printf 'set: true\n'
        ;;
    eval)
        printf '%s\n' "${2:-}" >>"$HYPRCTL_LOG"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod 0755 "$base/bin/hyprctl"

    cat >"$base/hyprctl.state" <<'EOF'
animations:enabled	bool:true
decoration:blur:enabled	bool:true
decoration:shadow:enabled	bool:true
decoration:rounding	int:10
EOF
    : >"$base/eval.log"

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$base" "$base/home" "$base/state" "$base/hyprctl.state" "$base/eval.log"
}

run_gm() {
    local home="$1" state="$2" hyprctl_state="$3" log="$4" bin="$5"
    shift 5
    env HOME="$home" XDG_STATE_HOME="$state" \
        PATH="$bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
        HYPRCTL_STATE="$hyprctl_state" HYPRCTL_LOG="$log" \
        bash "$SCRIPT" "$@"
}

IFS=$'\t' read -r base home state hyprctl_state log < <(new_env)
bin="$base/bin"
state_file="$state/dotfiles/gamemode.conf"

# 1. Help.
if run_gm "$home" "$state" "$hyprctl_state" "$log" "$bin" --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help failed"
fi

# 2. Status before enabling.
status_out="$(run_gm "$home" "$state" "$hyprctl_state" "$log" "$bin" status)"
if grep -qx 'gamemode: disabled' <<<"$status_out"; then
    pass "status reports disabled before the first enable"
else
    fail "status did not report disabled"
    printf '%s\n' "$status_out"
fi

# 3. Enable captures the originals and applies the gaming values.
if run_gm "$home" "$state" "$hyprctl_state" "$log" "$bin" on >/dev/null; then
    pass "on succeeds inside a Hyprland session"
else
    fail "on failed"
fi

if [[ -r $state_file ]] \
    && grep -qx $'animations:enabled\tbool:true' "$state_file" \
    && grep -qx $'decoration:blur:enabled\tbool:true' "$state_file" \
    && grep -qx $'decoration:shadow:enabled\tbool:true' "$state_file" \
    && grep -qx $'decoration:rounding\tint:10' "$state_file"; then
    pass "on captures the original values from getoption"
else
    fail "the original values were not captured"
    cat "$state_file" 2>/dev/null
fi

if grep -Fxq 'hl.config({ animations = { enabled = false } })' "$log" \
    && grep -Fxq 'hl.config({ decoration = { blur = { enabled = false } } })' "$log" \
    && grep -Fxq 'hl.config({ decoration = { shadow = { enabled = false } } })' "$log" \
    && grep -Fxq 'hl.config({ decoration = { rounding = 0 } })' "$log"; then
    pass "on disables animations, blur, shadow and rounding"
else
    fail "the gaming values were not applied"
    cat "$log"
fi

# 4. Re-enabling cannot overwrite the captured originals.
#    Simulate the live state after gamemode was applied, then enable again.
cat >"$hyprctl_state" <<'EOF'
animations:enabled	bool:false
decoration:blur:enabled	bool:false
decoration:shadow:enabled	bool:false
decoration:rounding	int:0
EOF
before_sum="$(sha256sum "$state_file" | awk '{print $1}')"
: >"$log"
reenable_out="$(run_gm "$home" "$state" "$hyprctl_state" "$log" "$bin" on 2>&1)"
after_sum="$(sha256sum "$state_file" | awk '{print $1}')"

if [[ $before_sum == "$after_sum" ]]; then
    pass "re-enabling preserves the captured originals"
else
    fail "re-enabling overwrote the captured originals"
    cat "$state_file"
fi
if grep -q 'already enabled' <<<"$reenable_out"; then
    pass "re-enabling says that gamemode is already on"
else
    fail "re-enabling gave no explanation"
    printf '%s\n' "$reenable_out"
fi
if grep -Fxq 'hl.config({ animations = { enabled = false } })' "$log"; then
    pass "re-enabling reapplies the gaming values"
else
    fail "re-enabling did not reapply the gaming values"
fi

# 5. Off restores the real originals, not the gaming values.
if run_gm "$home" "$state" "$hyprctl_state" "$log" "$bin" off >/dev/null; then
    pass "off succeeds while enabled"
else
    fail "off failed"
fi
if grep -Fxq 'hl.config({ animations = { enabled = true } })' "$log" \
    && grep -Fxq 'hl.config({ decoration = { blur = { enabled = true } } })' "$log" \
    && grep -Fxq 'hl.config({ decoration = { shadow = { enabled = true } } })' "$log" \
    && grep -Fxq 'hl.config({ decoration = { rounding = 10 } })' "$log"; then
    pass "off restores the pre-gamemode values"
else
    fail "off did not restore the captured values"
    cat "$log"
fi
if [[ ! -e $state_file ]]; then
    pass "off removes the state file"
else
    fail "off left the state file behind"
fi

# 6. Off is a safe no-op when gamemode is not enabled.
off_out="$(run_gm "$home" "$state" "$hyprctl_state" "$log" "$bin" off 2>&1)"
off_rc=$?
if ((off_rc == 0)) && grep -q 'not enabled' <<<"$off_out"; then
    pass "off without state is a no-op"
else
    fail "off without state behaved unexpectedly"
    printf 'rc=%s\n%s\n' "$off_rc" "$off_out"
fi

# 7. Dry-run changes nothing.
IFS=$'\t' read -r base2 home2 state2 hyprctl_state2 log2 < <(new_env)
bin2="$base2/bin"
state_file2="$state2/dotfiles/gamemode.conf"

dry_out="$(run_gm "$home2" "$state2" "$hyprctl_state2" "$log2" "$bin2" on --dry-run)"
if grep -q '\[dry-run\] hyprctl eval' <<<"$dry_out" \
    && grep -q 'enabled = false' <<<"$dry_out"; then
    pass "dry-run prints the commands"
else
    fail "dry-run output is incomplete"
    printf '%s\n' "$dry_out"
fi
if [[ ! -e $state_file2 && ! -s $log2 ]]; then
    pass "dry-run on writes no state and runs nothing"
else
    fail "dry-run on wrote state or ran hyprctl eval"
fi

# 8. Dry-run off keeps the state file.
run_gm "$home2" "$state2" "$hyprctl_state2" "$log2" "$bin2" on >/dev/null
before_sum="$(sha256sum "$state_file2" | awk '{print $1}')"
: >"$log2"
dry_off="$(run_gm "$home2" "$state2" "$hyprctl_state2" "$log2" "$bin2" off --dry-run)"
if [[ -r $state_file2 ]] && [[ $before_sum == "$(sha256sum "$state_file2" | awk '{print $1}')" ]] \
    && [[ ! -s $log2 ]] && grep -q 'would remove' <<<"$dry_off"; then
    pass "dry-run off keeps the state and restores nothing"
else
    fail "dry-run off changed state or ran commands"
fi

# 9. Status shows the captured values while enabled.
status_on="$(run_gm "$home2" "$state2" "$hyprctl_state2" "$log2" "$bin2" status)"
if grep -qx 'gamemode: enabled' <<<"$status_on" \
    && grep -q 'animations:enabled' <<<"$status_on" \
    && grep -q 'bool:true' <<<"$status_on"; then
    pass "status lists the captured values while enabled"
else
    fail "status is wrong while enabled"
    printf '%s\n' "$status_on"
fi

# 10. Toggle turns it off and then on again.
run_gm "$home2" "$state2" "$hyprctl_state2" "$log2" "$bin2" toggle >/dev/null
if [[ ! -e $state_file2 ]]; then
    pass "toggle disables gamemode when enabled"
else
    fail "toggle did not disable gamemode"
fi

# 11. Outside a Hyprland session the script refuses to act.
if env -u HYPRLAND_INSTANCE_SIGNATURE HOME="$home2" XDG_STATE_HOME="$state2" \
    PATH="$bin2:$PATH" HYPRCTL_STATE="$hyprctl_state2" HYPRCTL_LOG="$log2" \
    bash "$SCRIPT" on >/dev/null 2>"$base2/session.log"; then
    fail "on worked without a Hyprland session"
else
    if grep -q 'not inside a Hyprland session' "$base2/session.log"; then
        pass "a missing session is explained"
    else
        fail "missing session error is unclear"
        cat "$base2/session.log"
    fi
fi

# 12. Unknown commands and options are rejected.
if run_gm "$home2" "$state2" "$hyprctl_state2" "$log2" "$bin2" sideways >/dev/null 2>&1; then
    fail "an unknown command was accepted"
else
    pass "an unknown command is rejected"
fi
if run_gm "$home2" "$state2" "$hyprctl_state2" "$log2" "$bin2" status --nope >/dev/null 2>&1; then
    fail "an unknown option was accepted"
else
    pass "an unknown option is rejected"
fi

# 13. A corrupt state file fails closed before restoring anything.
printf 'animations:enabled\tbool:maybe\n' >"$state_file2"
: >"$log2"
if run_gm "$home2" "$state2" "$hyprctl_state2" "$log2" "$bin2" off >/dev/null 2>&1; then
    fail "a corrupt state file was accepted"
else
    pass "a corrupt state file is rejected"
fi
if [[ ! -s $log2 ]]; then
    pass "a corrupt state file restores nothing"
else
    fail "a corrupt state file still ran hyprctl eval"
    cat "$log2"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
