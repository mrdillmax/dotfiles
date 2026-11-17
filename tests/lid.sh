#!/usr/bin/env bash
# Tests for modules/lid. Stubs hyprctl and systemctl; no real monitor or
# suspend is ever touched.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/lid/home/.local/bin/lid-handler.sh"
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

new_env() {
    local base
    base="$(mktemp -d)"
    TMP_DIRS+=("$base")

    mkdir -p "$base/bin" "$base/home" "$base/state"

    cat >"$base/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    monitors)
        if [[ ${2:-} == all ]]; then
            cat "$LID_MONITORS_ALL"
        else
            cat "$LID_MONITORS"
        fi
        ;;
    eval)
        printf '%s\n' "${2:-}" >>"$LID_LOG"
        ;;
    *)
        exit 1
        ;;
esac
EOF

    cat >"$base/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == suspend ]]; then
    printf 'suspend\n' >>"$LID_SUSPEND_LOG"
    exit 0
fi
exit 1
EOF
    chmod 0755 "$base/bin/hyprctl" "$base/bin/systemctl"

    : >"$base/monitors.json"
    : >"$base/monitors-all.json"
    : >"$base/eval.log"
    : >"$base/suspend.log"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$base" "$base/home" "$base/state" "$base/monitors.json" \
        "$base/monitors-all.json" "$base/eval.log" "$base/suspend.log" "$base/bin"
}

run_lid() {
    local home="$1" state="$2" mon="$3" all="$4" log="$5" suspend_log="$6" bin="$7"
    shift 7
    env HOME="$home" XDG_STATE_HOME="$state" XDG_CONFIG_HOME="$home/.config" \
        PATH="$bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
        LID_MONITORS="$mon" LID_MONITORS_ALL="$all" \
        LID_LOG="$log" LID_SUSPEND_LOG="$suspend_log" \
        bash "$SCRIPT" "$@"
}

write_monitors() {
    local file="$1" kind="$2"
    case "$kind" in
        dock)
            cat >"$file" <<'EOF'
[{"name":"eDP-1","width":1920,"height":1200,"refreshRate":60.0,"scale":1.5,"x":0,"y":0},
 {"name":"DP-1","width":2560,"height":1440,"refreshRate":60.0,"scale":1.0,"x":1280,"y":0}]
EOF
            ;;
        laptop)
            cat >"$file" <<'EOF'
[{"name":"eDP-1","width":1920,"height":1200,"refreshRate":60.0,"scale":1.5,"x":0,"y":0}]
EOF
            ;;
        desktop)
            cat >"$file" <<'EOF'
[{"name":"DP-1","width":2560,"height":1440,"refreshRate":60.0,"scale":1.0,"x":0,"y":0}]
EOF
            ;;
        two-internal)
            cat >"$file" <<'EOF'
[{"name":"eDP-1","width":1920,"height":1200,"refreshRate":60.0,"scale":1.5,"x":0,"y":0},
 {"name":"eDP-2","width":1920,"height":1200,"refreshRate":60.0,"scale":1.5,"x":1280,"y":0}]
EOF
            ;;
    esac
}

write_all() {
    local file="$1"
    cat >"$file" <<'EOF'
[{"name":"eDP-1","width":1920,"height":1200,"refreshRate":60.0,"scale":1.5,"x":0,"y":0,"disabled":true},
 {"name":"DP-1","width":2560,"height":1440,"refreshRate":60.0,"scale":1.0,"x":0,"y":0,"disabled":false}]
EOF
}

IFS=$'\t' read -r base home state mon all log suspend_log bin < <(new_env)
state_file="$state/dotfiles/lid.conf"

# 1. Help.
if run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help failed"
fi

# 2. Closed with an external monitor: disable eDP and remember its state.
write_monitors "$mon" dock
run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" closed >/dev/null
closed_rc=$?
if ((closed_rc == 0)); then
    pass "closed succeeds with an external monitor"
else
    fail "closed failed with an external monitor"
fi
if grep -Fq 'output = "eDP-1", disabled = true' "$log"; then
    pass "closed disables the internal panel"
else
    fail "closed did not disable the internal panel"
    cat "$log"
fi
if [[ ! -s $suspend_log ]]; then
    pass "closed does not suspend while an external monitor is active"
else
    fail "closed suspended despite an external monitor"
fi
if [[ -r $state_file ]] && grep -q $'eDP-1\t1920x1200@60\t0x0\t1.5' "$state_file"; then
    pass "closed saves the internal mode, position and scale"
else
    fail "closed did not save the internal panel state"
    cat "$state_file" 2>/dev/null
fi

# 3. Opening the lid restores the saved panel state and clears the file.
write_all "$all"
: >"$log"
run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" open >/dev/null
if grep -Fq 'output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1.5' "$log"; then
    pass "open restores the saved internal panel state"
else
    fail "open did not restore the saved state"
    cat "$log"
fi
if [[ ! -e $state_file ]]; then
    pass "open removes the saved state file"
else
    fail "open left the state file behind"
fi

# 4. Closed without an external monitor suspends.
: >"$log"
: >"$suspend_log"
write_monitors "$mon" laptop
run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" closed >/dev/null
if grep -qx 'suspend' "$suspend_log"; then
    pass "closed without an external monitor suspends"
else
    fail "closed without an external monitor did not suspend"
fi
if [[ ! -s $log ]]; then
    pass "closed without an external monitor changes no monitor"
else
    fail "closed without an external monitor still ran hyprctl eval"
    cat "$log"
fi
if [[ ! -e $state_file ]]; then
    pass "a suspend leaves no lid state"
else
    fail "a suspend wrote lid state"
fi

# 5. Opening without saved state re-enables a disabled internal panel.
write_all "$all"
: >"$log"
run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" open >/dev/null
if grep -Fq 'output = "eDP-1", mode = "preferred", position = "auto", scale = auto' "$log"; then
    pass "open without state re-enables the panel with auto settings"
else
    fail "open without state did not re-enable the panel"
    cat "$log"
fi

# 6. A desktop with no internal panel is left alone.
write_monitors "$mon" desktop
: >"$log"
: >"$suspend_log"
desktop_out="$(run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" closed)"
if grep -q 'no internal panel' <<<"$desktop_out" \
    && [[ ! -s $log ]] && [[ ! -s $suspend_log ]]; then
    pass "closed on a desktop changes nothing"
else
    fail "closed on a desktop changed something"
    printf '%s\n' "$desktop_out"
fi

# 7. Dry-run closed with an external monitor writes nothing.
write_monitors "$mon" dock
: >"$log"
rm -f "$state_file"
dry_closed="$(run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" closed --dry-run)"
if grep -q '\[dry-run\] hyprctl eval' <<<"$dry_closed" \
    && [[ ! -s $log ]] && [[ ! -e $state_file ]]; then
    pass "dry-run closed changes nothing"
else
    fail "dry-run closed ran commands or wrote state"
    printf '%s\n' "$dry_closed"
fi

# 8. Dry-run closed without an external monitor skips suspend.
write_monitors "$mon" laptop
: >"$suspend_log"
dry_suspend="$(run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" closed --dry-run)"
if grep -q '\[dry-run\] systemctl suspend' <<<"$dry_suspend" && [[ ! -s $suspend_log ]]; then
    pass "dry-run reports suspend without calling it"
else
    fail "dry-run called systemctl suspend"
fi

# 9. Two internal panels are both saved and disabled.
write_monitors "$mon" two-internal
# Add an external output so the disable branch is taken.
cat >"$mon" <<'EOF'
[{"name":"eDP-1","width":1920,"height":1200,"refreshRate":60.0,"scale":1.5,"x":0,"y":0},
 {"name":"eDP-2","width":1920,"height":1200,"refreshRate":60.0,"scale":1.5,"x":1280,"y":0},
 {"name":"DP-1","width":2560,"height":1440,"refreshRate":60.0,"scale":1.0,"x":2560,"y":0}]
EOF
: >"$log"
run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" closed >/dev/null
if grep -Fq 'output = "eDP-1", disabled = true' "$log" \
    && grep -Fq 'output = "eDP-2", disabled = true' "$log"; then
    pass "closed disables every internal panel"
else
    fail "closed missed an internal panel"
    cat "$log"
fi

# 10. Status shows the saved state and active monitors.
write_monitors "$mon" dock
status_out="$(run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" status)"
if grep -q 'saved:' <<<"$status_out" \
    && grep -q 'active: eDP-1' <<<"$status_out" \
    && grep -q '(internal)' <<<"$status_out" \
    && grep -q '(external)' <<<"$status_out"; then
    pass "status shows saved and active monitors"
else
    fail "status output is incomplete"
    printf '%s\n' "$status_out"
fi

# 11. A missing Hyprland session is rejected.
if env -u HYPRLAND_INSTANCE_SIGNATURE HOME="$home" XDG_STATE_HOME="$state" \
    XDG_CONFIG_HOME="$home/.config" PATH="$bin:$PATH" \
    LID_MONITORS="$mon" LID_MONITORS_ALL="$all" LID_LOG="$log" \
    LID_SUSPEND_LOG="$suspend_log" \
    bash "$SCRIPT" closed >/dev/null 2>"$base/session.log"; then
    fail "closed worked without a Hyprland session"
else
    if grep -q 'not inside a Hyprland session' "$base/session.log"; then
        pass "a missing session is explained"
    else
        fail "missing session error is unclear"
        cat "$base/session.log"
    fi
fi

# 12. Unknown commands are rejected.
if run_lid "$home" "$state" "$mon" "$all" "$log" "$suspend_log" "$bin" sideways >/dev/null 2>&1; then
    fail "an unknown command was accepted"
else
    pass "an unknown command is rejected"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
