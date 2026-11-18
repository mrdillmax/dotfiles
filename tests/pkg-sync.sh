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
present="$base/present"
installed="$base/installed"
group_members="$base/group-members"

mkdir -p "$repo/packages" "$repo/lib" "$home" "$state" "$bin"
: >"$present"
: >"$installed"
: >"$group_members"

cat >"$bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -Qq)  cat "$PKG_PRESENT" ;;
    -Qqe) cat "$PKG_INSTALLED" ;;
    -Sgq) cat "$PKG_GROUP_MEMBERS" ;;
    *)    exit 1 ;;
esac
EOF
chmod 0755 "$bin/pacman"
cat >"$bin/spicetify" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 0755 "$bin/spicetify"

local_file="$repo/packages/local.tsv"

run_sync() {
    env HOME="$home" XDG_STATE_HOME="$state" DOTFILES_DIR="$repo" \
        PATH="$bin:$PATH" PKG_SYNC_HOST="${PKG_SYNC_HOST:-desktop}" \
        PKG_SYNC_STAMP="$stamp" PKG_PRESENT="$present" \
        PKG_INSTALLED="$installed" PKG_GROUP_MEMBERS="$group_members" \
        bash "$SCRIPT" "$@"
}

write_catalog() {
    cat >"$repo/packages/catalog.tsv" <<'EOF'
# package	category	role	default	host	gpu	description
base	System	pkg	yes	any	any	base package
repo-only	System	pkg	yes	any	any	missing package
base-devel	System	pkg	yes	any	any	build group
gcc	System	pkg	yes	any	any	compiler
fakeroot	System	pkg	yes	any	any	fake root
desktop-pkg	Desktop	pkg	yes	desktop	any	desktop package
laptop-pkg	Session	pkg	yes	laptop	any	laptop package
alt-pkg	Terminal	alt	no	any	any	alternative package
optional-pkg	System	pkg	no	any	any	optional package
spicetify-cli	Music	main	yes	any	any	spicetify script
EOF
}

write_catalog

# Present and explicit sets: everything required on the desktop, minus
# repo-only, plus the base-devel group members.
printf '%s\n' base repo-only desktop-pkg gcc fakeroot >"$present"
printf '%s\n' base desktop-pkg gcc fakeroot >"$installed"
printf 'gcc\nfakeroot\n' >"$group_members"

# 1. Help.
if run_sync --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help failed"
fi

# 2. status reports no drift on the desktop and ignores laptop/optional rows.
: >"$stamp"
status_out="$(run_sync status)"
if grep -q 'host: desktop' <<<"$status_out" \
    && grep -qx 'drift: none' <<<"$status_out" \
    && ! grep -q 'laptop-pkg' <<<"$status_out" \
    && ! grep -q 'optional-pkg' <<<"$status_out"; then
    pass "status ignores host-specific and optional rows"
else
    fail "status drift output is wrong"
    printf '%s\n' "$status_out"
fi

# 3. check succeeds with no drift.
if run_sync check >/dev/null; then
    pass "check exits 0 when the catalog matches"
else
    fail "check failed without drift"
fi

# 4. check reports both directions and exits 1.
printf '%s\n' base desktop-pkg gcc fakeroot stray-pkg >"$present"
printf '%s\n' base desktop-pkg gcc fakeroot stray-pkg >"$installed"
drift_out="$(run_sync check)"
drift_rc=$?
if ((drift_rc == 1)) \
    && grep -q '^  - repo-only' <<<"$drift_out" \
    && grep -q '^  + stray-pkg' <<<"$drift_out"; then
    pass "check reports required-not-installed and installed-not-listed"
else
    fail "check drift output is wrong (rc=$drift_rc)"
    printf '%s\n' "$drift_out"
fi

# 5. --quiet prints nothing when there is no drift.
printf '%s\n' base repo-only desktop-pkg gcc fakeroot >"$present"
printf '%s\n' base desktop-pkg gcc fakeroot >"$installed"
quiet_out="$(run_sync check --quiet)"
if [[ -z $quiet_out ]]; then
    pass "--quiet is silent without drift"
else
    fail "--quiet printed output without drift"
    printf '%s\n' "$quiet_out"
fi

# 6. The group entry is satisfied only when every member is installed.
printf '%s\n' base desktop-pkg gcc >"$present"
group_out="$(run_sync check)"
if grep -q '^  - base-devel' <<<"$group_out"; then
    pass "a partially installed group is reported missing"
else
    fail "a partially installed group was accepted"
    printf '%s\n' "$group_out"
fi

# 7. The laptop host compares laptop rows and ignores desktop rows.
printf '%s\n' base repo-only desktop-pkg gcc fakeroot >"$present"
printf '%s\n' base desktop-pkg gcc fakeroot >"$installed"
laptop_out="$(PKG_SYNC_HOST=laptop run_sync status)"
if grep -q 'host: laptop' <<<"$laptop_out" \
    && grep -q 'drift: 1 required-not-installed' <<<"$laptop_out"; then
    pass "the laptop host uses only the laptop rows"
else
    fail "host-specific comparison is wrong"
    printf '%s\n' "$laptop_out"
fi

# 8. An optional package is not missing when absent, and is listed when present.
printf '%s\n' base repo-only desktop-pkg gcc fakeroot optional-pkg >"$present"
printf '%s\n' base desktop-pkg gcc fakeroot optional-pkg >"$installed"
optional_out="$(run_sync check)"
if ! grep -q 'optional-pkg' <<<"$optional_out" \
    && ! grep -q 'stray-pkg' <<<"$optional_out"; then
    pass "optional installed package counts as listed"
else
    fail "optional package comparison is wrong"
    printf '%s\n' "$optional_out"
fi

# 9. pull --dry-run writes nothing.
printf '%s\n' base repo-only desktop-pkg gcc fakeroot stray-pkg >"$present"
printf '%s\n' base desktop-pkg gcc fakeroot stray-pkg >"$installed"
dry_pull="$(run_sync pull --dry-run --yes)"
if grep -q '\[dry-run\] would append' <<<"$dry_pull" \
    && [[ ! -e $local_file ]]; then
    pass "pull --dry-run writes nothing"
else
    fail "pull --dry-run created local.tsv"
    printf '%s\n' "$dry_pull"
fi

# 10. pull --yes appends only the unlisted package.
run_sync pull --yes >/dev/null
pull_rc=$?
if ((pull_rc == 0)) && grep -q $'^stray-pkg\t' "$local_file"; then
    pass "pull --yes records the unlisted package"
else
    fail "pull did not record the package (rc=$pull_rc)"
    cat "$local_file" 2>/dev/null
fi
if grep -q 'repo-only' "$local_file"; then
    fail "pull added a required-not-installed package"
else
    pass "pull never adds required-not-installed packages"
fi
if run_sync check >/dev/null; then
    pass "the appended package clears the unlisted drift"
else
    fail "the appended package is still reported as drift"
fi

# 11. A second pull backs up the file and does not duplicate entries.
printf '%s\n' base repo-only desktop-pkg gcc fakeroot stray-pkg another-pkg >"$present"
printf '%s\n' base desktop-pkg gcc fakeroot stray-pkg another-pkg >"$installed"
run_sync pull --yes >/dev/null
if grep -q $'^another-pkg\t' "$local_file" \
    && [[ "$(grep -c $'^stray-pkg\t' "$local_file")" == 1 ]] \
    && compgen -G "$local_file.bak.*" >/dev/null; then
    pass "pull appends once and backs up the previous file"
else
    fail "pull duplicated an entry or skipped the backup"
    cat "$local_file"
fi

# 12. pull without a terminal and without --yes refuses to write.
printf '%s\n' base repo-only desktop-pkg gcc fakeroot third-pkg >"$present"
printf '%s\n' base desktop-pkg gcc fakeroot third-pkg >"$installed"
if run_sync pull </dev/null >/dev/null 2>"$base/err"; then
    fail "pull wrote without a terminal or --yes"
else
    if grep -q 'without a terminal' "$base/err" \
        && ! grep -q 'third-pkg' "$local_file"; then
        pass "pull refuses a non-interactive write"
    else
        fail "the non-interactive refusal is unclear"
        cat "$base/err"
    fi
fi

# 13. pull with only required-not-installed drift writes nothing.
rm -f "$local_file"
printf '%s\n' base desktop-pkg gcc fakeroot >"$present"
printf '%s\n' base desktop-pkg gcc fakeroot >"$installed"
pull_out="$(run_sync pull --yes 2>&1)"
if grep -q 'nothing to pull' <<<"$pull_out" \
    && [[ ! -e $local_file ]]; then
    pass "pull ignores required-not-installed drift"
else
    fail "pull wrote for required-not-installed drift"
    printf '%s\n' "$pull_out"
fi

# 14. The pacman hook helper and hook file exist and stay executable.
if [[ -x $MARKER && -r $HOOK ]]; then
    pass "pkg-sync hook files are present"
else
    fail "pkg-sync hook files are missing"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
