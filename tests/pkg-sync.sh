#!/usr/bin/env bash
# Tests for scripts/pkg-sync.sh and the pacman hook helper.
# Uses a stub pacman and a temporary repository; the real package database is
# never read and the real repository is never written.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/pkg-sync.sh"
MARKER="$ROOT/system/pkg-sync/dotfiles-pkg-sync-mark.sh"
HOOK="$ROOT/system/pacman/hooks/dotfiles-pkg-sync.hook"
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
repo="$base/repo"
home="$base/home"
state="$base/state"
bin="$base/bin"
stamp="$base/pkg-sync.stamp"
installed="$base/installed"
group_members="$base/group-members"

mkdir -p "$repo/packages" "$repo/lib" "$home" "$state" "$bin"
: >"$installed"
: >"$group_members"

cat >"$bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -Qqe) cat "$PKG_INSTALLED" ;;
    -Sgq) cat "$PKG_GROUP_MEMBERS" ;;
    *)    exit 1 ;;
esac
EOF
chmod 0755 "$bin/pacman"

extra_file="$repo/packages/extra-installed.txt"
last_check="$state/dotfiles/pkg-sync.last"

run_sync() {
    env HOME="$home" XDG_STATE_HOME="$state" DOTFILES_DIR="$repo" \
        PATH="$bin:$PATH" PKG_SYNC_HOST="${PKG_SYNC_HOST:-desktop}" \
        PKG_SYNC_STAMP="$stamp" PKG_INSTALLED="$installed" \
        PKG_GROUP_MEMBERS="$group_members" \
        bash "$SCRIPT" "$@"
}

write_repo() {
    cat >"$repo/packages/base.txt" <<'EOF'
# base packages
base
repo-only
base-devel
gcc
fakeroot
EOF
    cat >"$repo/packages/desktop.txt" <<'EOF'
desktop-pkg
EOF
    cat >"$repo/packages/laptop.txt" <<'EOF'
laptop-pkg
EOF
    cat >"$repo/packages/alternatives.txt" <<'EOF'
alt-pkg
EOF
}

write_repo

# Installed set: everything listed, plus the group members, minus repo-only.
set_installed() {
    printf '%s\n' base repo-only desktop-pkg gcc fakeroot >"$installed"
}
printf 'gcc\nfakeroot\n' >"$group_members"
set_installed

# 1. Help.
if run_sync --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help failed"
fi

# 2. status reports no drift on the desktop and ignores laptop/alternatives.
: >"$stamp"
status_out="$(run_sync status)"
if grep -q 'host: desktop' <<<"$status_out" \
    && grep -qx 'drift: none' <<<"$status_out" \
    && ! grep -q 'laptop-pkg' <<<"$status_out" \
    && ! grep -q 'alt-pkg' <<<"$status_out"; then
    pass "status ignores host-specific and alternative lists"
else
    fail "status drift output is wrong"
    printf '%s\n' "$status_out"
fi

# 3. check succeeds with no drift.
if run_sync check >/dev/null; then
    pass "check exits 0 when the lists match"
else
    fail "check failed without drift"
fi

# 4. check reports both directions and exits 1.
printf '%s\n' base desktop-pkg gcc fakeroot stray-pkg >"$installed"
drift_out="$(run_sync check)"
drift_rc=$?
if ((drift_rc == 1)) \
    && grep -q '^  - repo-only' <<<"$drift_out" \
    && grep -q '^  + stray-pkg' <<<"$drift_out"; then
    pass "check reports listed-not-installed and installed-not-listed"
else
    fail "check drift output is wrong (rc=$drift_rc)"
    printf '%s\n' "$drift_out"
fi

# 5. --quiet prints nothing when there is no drift.
set_installed
quiet_out="$(run_sync check --quiet)"
if [[ -z $quiet_out ]]; then
    pass "--quiet is silent without drift"
else
    fail "--quiet printed output without drift"
    printf '%s\n' "$quiet_out"
fi

# 6. The group entry is satisfied only when every member is installed.
printf '%s\n' base desktop-pkg gcc >"$installed"
group_out="$(run_sync check)"
if grep -q '^  - base-devel' <<<"$group_out"; then
    pass "a partially installed group is reported missing"
else
    fail "a partially installed group was accepted"
    printf '%s\n' "$group_out"
fi

# 7. The laptop host compares laptop.txt and ignores desktop.txt.
set_installed
laptop_out="$(PKG_SYNC_HOST=laptop run_sync status)"
if grep -q 'host: laptop' <<<"$laptop_out" \
    && grep -q 'drift: 1 listed-not-installed' <<<"$laptop_out"; then
    pass "the laptop host uses only the laptop list"
else
    fail "host-specific comparison is wrong"
    printf '%s\n' "$laptop_out"
fi

# 8. pull --dry-run writes nothing.
set_installed
printf '%s\n' stray-pkg >>"$installed"
dry_pull="$(run_sync pull --dry-run --yes)"
if grep -q '\[dry-run\] would append' <<<"$dry_pull" \
    && [[ ! -e $extra_file ]]; then
    pass "pull --dry-run writes nothing"
else
    fail "pull --dry-run created the extra file"
    printf '%s\n' "$dry_pull"
fi

# 9. pull --yes appends only the unlisted package.
run_sync pull --yes >/dev/null
pull_rc=$?
if ((pull_rc == 0)) && grep -qx 'stray-pkg' "$extra_file"; then
    pass "pull --yes records the unlisted package"
else
    fail "pull did not record the package (rc=$pull_rc)"
    cat "$extra_file" 2>/dev/null
fi
if grep -q 'repo-only' "$extra_file"; then
    fail "pull added a listed-not-installed package"
else
    pass "pull never adds listed-not-installed packages"
fi
if run_sync check >/dev/null; then
    pass "the appended package clears the unlisted drift"
else
    fail "the appended package is still reported as drift"
fi

# 10. A second pull backs up the file and does not duplicate entries.
printf '%s\n' another-pkg >>"$installed"
run_sync pull --yes >/dev/null
if grep -qx 'another-pkg' "$extra_file" \
    && [[ "$(grep -c '^stray-pkg$' "$extra_file")" == 1 ]] \
    && compgen -G "$extra_file.bak.*" >/dev/null; then
    pass "pull appends once and backs up the previous file"
else
    fail "pull duplicated an entry or skipped the backup"
    cat "$extra_file"
fi

# 11. pull without a terminal and without --yes refuses to write.
printf '%s\n' third-pkg >>"$installed"
if run_sync pull </dev/null >/dev/null 2>"$base/err"; then
    fail "pull wrote without a terminal or --yes"
else
    if grep -q 'without a terminal' "$base/err" \
        && ! grep -qx 'third-pkg' "$extra_file"; then
        pass "pull refuses a non-interactive write"
    else
        fail "the non-interactive refusal is unclear"
        cat "$base/err"
    fi
fi

# 12. pull with only listed-not-installed drift writes nothing.
rm -f "$extra_file"
printf '%s\n' base desktop-pkg gcc fakeroot >"$installed"
pull_missing="$(run_sync pull --yes 2>&1)"
if grep -q 'nothing to pull' <<<"$pull_missing" && [[ ! -e $extra_file ]]; then
    pass "pull ignores packages that are only missing locally"
else
    fail "pull wrote for a listed-not-installed package"
    printf '%s\n' "$pull_missing"
fi

# 13. The stamp marks a package change until the next check.
set_installed
run_sync check >/dev/null
last_check="$state/dotfiles/pkg-sync.last"
touch -d '2 minutes ago' "$last_check"
date +%s >"$stamp"
stale_out="$(run_sync status)"
if grep -q 'review: packages changed since the last check' <<<"$stale_out"; then
    pass "a newer pacman stamp asks for a review"
else
    fail "the newer stamp was not reported"
    printf '%s\n' "$stale_out"
fi
run_sync check >/dev/null
fresh_out="$(run_sync status)"
if grep -q 'review: up to date' <<<"$fresh_out"; then
    pass "checking clears the review marker"
else
    fail "the review marker was not cleared"
    printf '%s\n' "$fresh_out"
fi

# 14. Unknown options are rejected.
if run_sync --sideways >/dev/null 2>&1; then
    fail "an unknown option was accepted"
else
    pass "an unknown option is rejected"
fi

# 15. The pacman hook points at the marker helper.
if grep -qx 'Exec = /usr/local/bin/dotfiles-pkg-sync-mark.sh' "$HOOK" \
    && grep -q 'When = PostTransaction' "$HOOK"; then
    pass "the pacman hook runs the marker helper after a transaction"
else
    fail "the pacman hook is malformed"
    cat "$HOOK"
fi

# 16. The marker helper writes a stamp into the configured directory.
mark_dir="$base/mark"
if DOTFILES_PKG_SYNC_DIR="$mark_dir" bash "$MARKER" \
    && [[ -s $mark_dir/pkg-sync.stamp ]] \
    && [[ "$(<"$mark_dir/pkg-sync.stamp")" =~ ^[0-9]+$ ]]; then
    pass "the marker helper writes a numeric stamp"
else
    fail "the marker helper did not write a stamp"
fi

# 17. The system installer maps the hook and the helper.
map_out="$(DOTFILES_DIR="$ROOT" bash -c '
    source "$DOTFILES_DIR/lib/system.sh"
    system_file_map
' 2>/dev/null)"
if grep -q '/etc/pacman.d/hooks/dotfiles-pkg-sync.hook' <<<"$map_out" \
    && grep -q '/usr/local/bin/dotfiles-pkg-sync-mark.sh' <<<"$map_out"; then
    pass "the system map installs the hook and helper"
else
    fail "the system map is missing the pkg-sync files"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
