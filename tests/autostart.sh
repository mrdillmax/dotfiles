#!/usr/bin/env bash
# Tests for modules/autostart. Everything runs against a temporary home;
# no real application is started.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/autostart/home/.local/bin/autostart.sh"
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

mkdir -p "$home" "$state" "$bin"

state_file="$state/dotfiles/autostart.tsv"
log_file="$state/dotfiles/autostart.log"

run_auto() {
    env HOME="$home" XDG_STATE_HOME="$state" XDG_CONFIG_HOME="$home/.config" \
        PATH="$bin:$PATH" bash "$SCRIPT" "$@"
}

# 1. Help.
if run_auto --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help failed"
fi

# 2. The first list shows the defaults and writes nothing.
list_out="$(run_auto list)"
if grep -q '^\[x\] waybar' <<<"$list_out" \
    && grep -q '^\[x\] hypridle' <<<"$list_out" \
    && grep -q '^\[x\] monitor-profiles' <<<"$list_out"; then
    pass "list shows the built-in defaults as enabled"
else
    fail "list did not show the defaults"
    printf '%s\n' "$list_out"
fi
if [[ ! -e $state_file ]]; then
    pass "list does not create the state file"
else
    fail "list created the state file"
fi

# 3. Status explains that the defaults are not written yet.
status_out="$(run_auto status)"
if grep -q 'defaults, not written yet' <<<"$status_out" \
    && grep -qx 'entries: 16 enabled, 0 disabled' <<<"$status_out"; then
    pass "status reports the default entry counts"
else
    fail "status output is wrong"
    printf '%s\n' "$status_out"
fi

# 4. disable writes the state and keeps the other defaults.
run_auto disable waybar >/dev/null
if grep -qx $'0\twaybar\tuwsm app -- waybar' "$state_file"; then
    pass "disable stores the entry as disabled"
else
    fail "disable did not store the entry"
    cat "$state_file" 2>/dev/null
fi
after_disable="$(run_auto list)"
if grep -q '^\[ \] waybar' <<<"$after_disable" \
    && grep -q '^\[x\] dunst' <<<"$after_disable"; then
    pass "disable affects only the selected entry"
else
    fail "disable affected the wrong entries"
fi

# 5. enable and toggle.
run_auto enable waybar >/dev/null
if grep -qx $'1\twaybar\tuwsm app -- waybar' "$state_file"; then
    pass "enable turns the entry back on"
else
    fail "enable did not update the state"
fi

run_auto toggle dunst >/dev/null
if grep -qx $'0\tdunst\tuwsm app -- dunst' "$state_file"; then
    pass "toggle disables an enabled entry"
else
    fail "toggle did not disable the entry"
fi
run_auto toggle dunst >/dev/null
if grep -qx $'1\tdunst\tuwsm app -- dunst' "$state_file"; then
    pass "toggle re-enables a disabled entry"
else
    fail "toggle did not re-enable the entry"
fi

# 6. Unknown names are rejected without touching the state.
before_sum="$(sha256sum "$state_file" | awk '{print $1}')"
if run_auto disable does-not-exist >/dev/null 2>&1; then
    fail "an unknown entry was accepted"
else
    pass "an unknown entry is rejected"
fi
if [[ $before_sum == "$(sha256sum "$state_file" | awk '{print $1}')" ]]; then
    pass "a rejected name leaves the state unchanged"
else
    fail "a rejected name changed the state"
fi

# 7. Custom entries can be added and removed.
# shellcheck disable=SC2016
run_auto add marker 'touch "$HOME/marker"' >/dev/null
if grep -q $'^1\tmarker\ttouch' "$state_file"; then
    pass "add stores a custom entry"
else
    fail "add did not store the entry"
    cat "$state_file"
fi
if run_auto add marker 'true' >/dev/null 2>&1; then
    fail "a duplicate name was accepted"
else
    pass "a duplicate name is rejected"
fi
if run_auto add 'bad/name' 'true' >/dev/null 2>&1; then
    fail "an invalid name was accepted"
else
    pass "an invalid name is rejected"
fi
if run_auto add empty '' >/dev/null 2>&1; then
    fail "an empty command was accepted"
else
    pass "an empty command is rejected"
fi

run_auto remove marker >/dev/null
if grep -q $'\tmarker\t' "$state_file"; then
    fail "remove left the entry behind"
else
    pass "remove deletes the entry"
fi

# 8. Dry-run writes nothing and starts nothing.
rm -f "$state_file" "$home/marker"
dry_out="$(run_auto run --dry-run)"
if grep -q '\[dry-run\] would start waybar' <<<"$dry_out" \
    && [[ ! -e $state_file && ! -e $home/marker ]]; then
    pass "dry-run run writes no state and starts nothing"
else
    fail "dry-run run changed something"
    printf '%s\n' "$dry_out"
fi

# 9. run starts only the enabled entries and logs the output.
mkdir -p "$state/dotfiles"
{
    printf '# test fixture\n'
    # shellcheck disable=SC2016
    printf '1\tmarker\ttouch "$HOME/marker"\n'
    # shellcheck disable=SC2016
    printf '0\tmarker-off\ttouch "$HOME/marker-off"\n'
} >"$state_file"
run_out="$(run_auto run)"
if grep -q 'ok started 1 enabled entries' <<<"$run_out"; then
    pass "run reports the enabled entry count"
else
    fail "run count is wrong"
    printf '%s\n' "$run_out"
fi
for _ in $(seq 1 50); do
    [[ -e $home/marker ]] && break
    sleep 0.1
done
if [[ -e $home/marker ]]; then
    pass "run starts an enabled entry"
else
    fail "run did not start the enabled entry"
    cat "$log_file" 2>/dev/null
fi
if [[ ! -e $home/marker-off ]]; then
    pass "run skips a disabled entry"
else
    fail "run started a disabled entry"
fi
if grep -q 'autostart' "$log_file"; then
    pass "run writes a log header"
else
    fail "run wrote no log"
fi

# 9b. run skips entries whose command does not exist.
{
    printf '1\tmissing\tdefinitely-not-a-real-command --flag\n'
} >"$state_file"
missing_out="$(run_auto run 2>&1)"
if grep -q 'skip missing: command not found' <<<"$missing_out" \
    && ! grep -q 'start missing:' <<<"$missing_out"; then
    pass "run skips an autostart entry with a missing command"
else
    fail "run launched a missing autostart entry"
    printf '%s\n' "$missing_out"
fi

# 10. A malformed state line is ignored with a warning.
{
    printf '1\tgood\ttrue\n'
    printf 'maybe\tbad\ttrue\n'
    printf '1\tbad/name\ttrue\n'
} >"$state_file"
corrupt_out="$(run_auto list 2>&1)"
if grep -q 'ignoring malformed line' <<<"$corrupt_out" \
    && grep -q '^\[x\] good' <<<"$corrupt_out" \
    && ! grep -q '^\[.\][[:space:]]*bad/name' <<<"$corrupt_out"; then
    pass "a malformed state line is skipped"
else
    fail "a malformed state line was used"
    printf '%s\n' "$corrupt_out"
fi

# 11. reset restores every default.
run_auto reset >/dev/null
if grep -qx $'1\twaybar\tuwsm app -- waybar' "$state_file" \
    && [[ "$(grep -c $'^1\t' "$state_file")" == 16 ]]; then
    pass "reset restores all 16 defaults as enabled"
else
    fail "reset did not restore the defaults"
    grep -c $'^1\t' "$state_file" 2>/dev/null
fi

# 12. reset --dry-run changes nothing.
before_sum="$(sha256sum "$state_file" | awk '{print $1}')"
run_auto reset --dry-run >/dev/null
if [[ $before_sum == "$(sha256sum "$state_file" | awk '{print $1}')" ]]; then
    pass "dry-run reset keeps the state file"
else
    fail "dry-run reset wrote the state"
fi

# 13. Unknown commands and options are rejected.
if run_auto sideways >/dev/null 2>&1; then
    fail "an unknown command was accepted"
else
    pass "an unknown command is rejected"
fi
if run_auto list --nope >/dev/null 2>&1; then
    fail "an unknown option was accepted"
else
    pass "an unknown option is rejected"
fi

# 9. The pick menu can add a program, not only toggle existing entries.
AUTO="$ROOT/modules/autostart/home/.local/bin/autostart.sh"
if grep -q 'Add a program' "$AUTO" && grep -q '^ask_line()' "$AUTO"; then
    pass "the autostart picker can add a program"
else
    fail "the autostart picker cannot add a program"
fi
if grep -q 'Remove a program' "$AUTO" \
    && grep -q '^remove_fzf()' "$AUTO" \
    && grep -q 'fzf --multi --height=100%' "$AUTO"; then
    pass "the autostart picker removes programs through fzf"
else
    fail "the autostart picker cannot remove programs through fzf"
fi

if grep -q 'labels=("+ Add a program" "- Remove a program")' "$AUTO" \
    && grep -q '^choose_program()' "$AUTO" \
    && grep -q 'fzf --height=100%' "$AUTO"; then
    pass "add and remove are at the top, programs are chosen with fzf"
else
    fail "the autostart add flow does not use fzf"
fi

if grep -q 'Command...' "$AUTO" \
    && grep -q 'read -r answer_command' "$AUTO" \
    && grep -q '^add_fzf()' "$AUTO"; then
    pass "the autostart picker accepts a custom command"
else
    fail "the autostart picker only accepts desktop apps"
fi

if grep -q 'run_in_terminal_wait' "$AUTO" \
    && grep -q 'kitty --class dotfiles-control-center' "$AUTO"; then
    pass "add and remove open a floating terminal only when needed"
else
    fail "the autostart picker still opens a console before the rofi list"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
