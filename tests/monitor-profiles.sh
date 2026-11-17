#!/usr/bin/env bash
# Tests for modules/monitor-profiles and lib/dock.sh.
# Uses stub hyprctl data and temporary homes; no real monitor is touched.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/monitor-profiles/home/.local/bin/monitor-profiles.sh"
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

# new_env -> base<TAB>home<TAB>state<TAB>json<TAB>log<TAB>bin
new_env() {
    local base
    base="$(mktemp -d)"
    TMP_DIRS+=("$base")

    mkdir -p "$base/bin" "$base/home/.config/hypr" "$base/state" "$base/home/.local/state"

    cat >"$base/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    monitors)
        cat "$MON_JSON"
        ;;
    eval)
        printf '%s\n' "${2:-}" >>"$MON_LOG"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod 0755 "$base/bin/hyprctl"

    cat >"$base/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MON_NOTIFY_LOG"
EOF
    chmod 0755 "$base/bin/notify-send"

    printf 'DOCK_LAYOUT=right\n' >"$base/home/.config/hypr/monitor-profiles.conf"
    : >"$base/monitors.json"
    : >"$base/eval.log"
    : >"$base/notify.log"

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$base" "$base/home" "$base/state" "$base/monitors.json" "$base/eval.log" "$base/bin"
}

laptop_only() {
    cat >"$1" <<'EOF'
[{"name":"eDP-1","width":1920,"height":1200,"refreshRate":60.0,"scale":1.5}]
EOF
}

laptop_dock() {
    cat >"$1" <<'EOF'
[{"name":"eDP-1","width":1920,"height":1200,"refreshRate":60.0,"scale":1.5},
 {"name":"DP-1","width":2560,"height":1440,"refreshRate":60.0,"scale":1.0}]
EOF
}

desktop_only() {
    cat >"$1" <<'EOF'
[{"name":"DP-1","width":2560,"height":1440,"refreshRate":60.0,"scale":1.0},
 {"name":"HDMI-A-1","width":1920,"height":1080,"refreshRate":60.0,"scale":1.0}]
EOF
}

run_mp() {
    local home="$1" state="$2" json="$3" log="$4" bin="$5"
    shift 5
    env HOME="$home" XDG_STATE_HOME="$state" XDG_CONFIG_HOME="$home/.config" \
        PATH="$bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
        MON_JSON="$json" MON_LOG="$log" \
        MON_NOTIFY_LOG="${MON_NOTIFY_LOG:-$base/notify.log}" \
        bash "$SCRIPT" "$@"
}

set_layout() {
    printf 'DOCK_LAYOUT=%s\n' "$2" >"$1"
}

IFS=$'\t' read -r base home state json log bin < <(new_env)
live_conf="$home/.config/hypr/monitor-profiles.conf"

# 1. Help.
if run_mp "$home" "$state" "$json" "$log" "$bin" --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help failed"
fi

# 2. Status classifies a laptop and a dock output.
laptop_dock "$json"
status_out="$(run_mp "$home" "$state" "$json" "$log" "$bin" status)"
if grep -qx 'layout: right' <<<"$status_out" \
    && grep -q 'monitor: eDP-1[[:space:]]*internal' <<<"$status_out" \
    && grep -q 'monitor: DP-1[[:space:]]*external' <<<"$status_out"; then
    pass "status classifies internal and external monitors"
else
    fail "status classification is wrong"
    printf '%s\n' "$status_out"
fi

# 3. Single laptop panel is placed at the origin.
laptop_only "$json"
single_out="$(run_mp "$home" "$state" "$json" "$log" "$bin" apply --dry-run)"
if grep -Fq 'output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1.5' <<<"$single_out"; then
    pass "a single internal panel is placed at 0x0"
else
    fail "the internal panel was not positioned correctly"
    printf '%s\n' "$single_out"
fi

# 4. Right layout puts the dock to the right of the logical panel width.
laptop_dock "$json"
right_out="$(run_mp "$home" "$state" "$json" "$log" "$bin" apply --dry-run)"
if grep -Fq 'output = "DP-1", mode = "2560x1440@60", position = "1280x0", scale = 1' <<<"$right_out"; then
    pass "right layout uses the internal logical width (1280)"
else
    fail "right layout position is wrong"
    printf '%s\n' "$right_out"
fi

# 5. Left layout uses a negative position.
set_layout "$live_conf" left
left_out="$(run_mp "$home" "$state" "$json" "$log" "$bin" apply --dry-run)"
if grep -Fq 'output = "DP-1", mode = "2560x1440@60", position = "-2560x0", scale = 1' <<<"$left_out"; then
    pass "left layout places the dock at a negative x"
else
    fail "left layout position is wrong"
    printf '%s\n' "$left_out"
fi

# 6. Mirror clones the internal mode at 0x0.
set_layout "$live_conf" mirror
mirror_out="$(run_mp "$home" "$state" "$json" "$log" "$bin" apply --dry-run)"
if grep -Fq 'output = "DP-1", mode = "1920x1200@60", position = "0x0", scale = 1.5' <<<"$mirror_out"; then
    pass "mirror clones the internal mode and scale"
else
    fail "mirror layout is wrong"
    printf '%s\n' "$mirror_out"
fi

# 7. Ask changes nothing and explains why.
set_layout "$live_conf" ask
ask_out="$(run_mp "$home" "$state" "$json" "$log" "$bin" apply --dry-run)"
if grep -q 'DOCK_LAYOUT=ask' <<<"$ask_out" && ! grep -q 'hyprctl eval' <<<"$ask_out" \
    && [[ ! -s $base/notify.log ]]; then
    pass "ask leaves the layout untouched without notifying in a dry-run"
else
    fail "ask still changed the monitors"
    printf '%s\n' "$ask_out"
fi

# 8. A desktop without an internal panel is left alone.
desktop_only "$json"
desktop_out="$(run_mp "$home" "$state" "$json" "$log" "$bin" apply --dry-run)"
if grep -q 'desktop layout left unchanged' <<<"$desktop_out" && [[ ! -s $log ]]; then
    pass "a desktop layout is left unchanged"
else
    fail "the desktop layout was modified"
    printf '%s\n' "$desktop_out"
    cat "$log"
fi

# 9. A real apply backs up the pre-apply monitor state.
laptop_dock "$json"
set_layout "$live_conf" right
: >"$log"
run_mp "$home" "$state" "$json" "$log" "$bin" apply >/dev/null
backup_file="$(find "$state/dotfiles/monitor-profiles" -name 'monitors-*.json' -print -quit 2>/dev/null)"
if [[ -n $backup_file ]] && grep -q 'DP-1' "$backup_file" && grep -q 'eDP-1' "$backup_file"; then
    pass "a real apply stores the pre-apply monitor state"
else
    fail "no pre-apply monitor backup was written"
fi
if grep -Fq 'output = "DP-1"' "$log" && grep -Fq 'output = "eDP-1"' "$log"; then
    pass "a real apply runs hyprctl eval for both monitors"
else
    fail "the real apply did not call hyprctl eval"
    cat "$log"
fi

# 10. Dry-run writes no backup.
IFS=$'\t' read -r base2 home2 state2 json2 log2 bin2 < <(new_env)
laptop_dock "$json2"
run_mp "$home2" "$state2" "$json2" "$log2" "$bin2" apply --dry-run >/dev/null
if [[ ! -d $state2/dotfiles/monitor-profiles ]]; then
    pass "dry-run creates no monitor backup"
else
    fail "dry-run created a monitor backup"
fi

# 11. set-layout writes the live preference; dry-run does not.
run_mp "$home2" "$state2" "$json2" "$log2" "$bin2" set-layout left >/dev/null
if grep -qx 'DOCK_LAYOUT=left' "$home2/.config/hypr/monitor-profiles.conf"; then
    pass "set-layout stores the live preference"
else
    fail "set-layout did not store the preference"
fi

rm -f "$home2/.config/hypr/monitor-profiles.conf"
dry_set="$(run_mp "$home2" "$state2" "$json2" "$log2" "$bin2" set-layout right --dry-run)"
if [[ ! -e $home2/.config/hypr/monitor-profiles.conf ]] && grep -q '\[dry-run\]' <<<"$dry_set"; then
    pass "dry-run set-layout changes nothing"
else
    fail "dry-run set-layout wrote the config"
fi

# 12. Invalid layouts and a missing session are rejected.
if run_mp "$home2" "$state2" "$json2" "$log2" "$bin2" set-layout sideways >/dev/null 2>&1; then
    fail "an invalid layout was accepted"
else
    pass "an invalid layout is rejected"
fi
if env -u HYPRLAND_INSTANCE_SIGNATURE HOME="$home2" XDG_STATE_HOME="$state2" \
    PATH="$bin2:$PATH" MON_JSON="$json2" MON_LOG="$log2" \
    bash "$SCRIPT" apply >/dev/null 2>"$base2/session.log"; then
    fail "apply worked without a Hyprland session"
else
    if grep -q 'not inside a Hyprland session' "$base2/session.log"; then
        pass "a missing session is explained"
    else
        fail "missing session error is unclear"
        cat "$base2/session.log"
    fi
fi

# 13. Watcher debounce: a burst of events yields one apply, and a later
#     burst yields another. Non-monitor events are ignored.
counter="$base2/apply.count"
: >"$counter"
(
    printf 'monitoradded>>DP-1\n'
    sleep 0.1
    printf 'monitorremoved>>DP-1\n'
    sleep 0.6
    printf 'workspace>>2\n'
    sleep 0.8
    printf 'monitoradded>>DP-1\n'
    sleep 0.7
    printf 'activewindow>>kitty\n'
    sleep 0.7
) | MONITOR_PROFILES_DEBOUNCE=0.3 MONITOR_PROFILES_SOURCE_ONLY=1 COUNTER="$counter" \
    bash -c '
        source "$1"
        apply_profile() { printf "apply\n" >>"$COUNTER"; }
        watch_stream
    ' _ "$SCRIPT"

applies="$(wc -l <"$counter")"
if [[ $applies == 2 ]]; then
    pass "watcher debounces monitor events into two applies"
else
    fail "watcher debounce produced $applies applies (expected 2)"
fi

# 14. lib/dock.sh stores the choice in the repo and copies it live.
dock_base="$(mktemp -d)"
TMP_DIRS+=("$dock_base")
mkdir -p "$dock_base/repo/hosts/laptop" "$dock_base/home" "$dock_base/state"
dock_repo="$dock_base/repo/hosts/laptop/monitor-profiles.conf"
dock_live="$dock_base/home/.config/hypr/monitor-profiles.conf"

(
    DOTFILES_DIR="$dock_base/repo"
    REAL_HOME="$dock_base/home"
    XDG_CONFIG_HOME="$dock_base/home/.config"
    HOST_NAME=laptop
    DRY_RUN=0
    ASSUME_YES=1
    BACKUP_DIR="$dock_base/backup"
    STATE_FILE="$dock_base/state/managed.tsv"
    TIMESTAMP="test"
    export DOTFILES_DIR REAL_HOME XDG_CONFIG_HOME HOST_NAME DRY_RUN ASSUME_YES \
        BACKUP_DIR STATE_FILE TIMESTAMP
    # shellcheck source=lib/common.sh
    source "$ROOT/lib/common.sh"
    # shellcheck source=lib/tui.sh
    source "$ROOT/lib/tui.sh"
    # shellcheck source=lib/dock.sh
    source "$ROOT/lib/dock.sh"
    write_dock_layout left
) >/dev/null

if grep -qx 'DOCK_LAYOUT=left' "$dock_repo" && grep -qx 'DOCK_LAYOUT=left' "$dock_live"; then
    pass "the dock choice is stored in hosts/<host> and copied live"
else
    fail "the dock choice was not stored correctly"
    cat "$dock_repo" 2>/dev/null
fi

# 15. A dry-run does not create the repository file or the live copy.
dock_base2="$(mktemp -d)"
TMP_DIRS+=("$dock_base2")
mkdir -p "$dock_base2/repo/hosts/laptop" "$dock_base2/home" "$dock_base2/state"
# shellcheck disable=SC2030
dry_dock_out="$(
    DOTFILES_DIR="$dock_base2/repo"
    REAL_HOME="$dock_base2/home"
    XDG_CONFIG_HOME="$dock_base2/home/.config"
    HOST_NAME=laptop
    DRY_RUN=1
    ASSUME_YES=1
    BACKUP_DIR="$dock_base2/backup"
    STATE_FILE="$dock_base2/state/managed.tsv"
    TIMESTAMP="test"
    export DOTFILES_DIR REAL_HOME XDG_CONFIG_HOME HOST_NAME DRY_RUN ASSUME_YES \
        BACKUP_DIR STATE_FILE TIMESTAMP
    # shellcheck source=lib/common.sh
    source "$ROOT/lib/common.sh"
    # shellcheck source=lib/tui.sh
    source "$ROOT/lib/tui.sh"
    # shellcheck source=lib/dock.sh
    source "$ROOT/lib/dock.sh"
    write_dock_layout mirror
) 2>&1"
if [[ ! -e $dock_base2/repo/hosts/laptop/monitor-profiles.conf ]] \
    && [[ ! -e $dock_base2/home/.config/hypr/monitor-profiles.conf ]] \
    && grep -q '\[dry-run\]' <<<"$dry_dock_out"; then
    pass "a dry-run dock write changes nothing"
else
    fail "a dry-run dock write created files"
fi

# 16. Default and invalid stored values fall back to right.
default_layout="$(
    DOTFILES_DIR="$dock_base2/repo"
    HOST_NAME=laptop
    export DOTFILES_DIR HOST_NAME
    # shellcheck source=lib/dock.sh
    source "$ROOT/lib/dock.sh"
    read_dock_layout
)"
if [[ $default_layout == right ]]; then
    pass "read_dock_layout defaults to right"
else
    fail "read_dock_layout returned '$default_layout'"
fi

printf 'DOCK_LAYOUT=sideways\n' >"$dock_base2/repo/hosts/laptop/monitor-profiles.conf"
invalid_layout="$(
    DOTFILES_DIR="$dock_base2/repo"
    HOST_NAME=laptop
    export DOTFILES_DIR HOST_NAME
    # shellcheck source=lib/dock.sh
    source "$ROOT/lib/dock.sh"
    read_dock_layout
)"
if [[ $invalid_layout == right ]]; then
    pass "an invalid stored layout falls back to right"
else
    fail "invalid layout returned '$invalid_layout'"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
