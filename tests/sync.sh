#!/usr/bin/env bash
# Tests for scripts/sync.sh. Everything happens in temporary repositories and
# temporary home directories; the real $HOME is never touched.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# fixture -> prints "repo<TAB>home<TAB>state"
fixture() {
    local base repo home state
    base="$(mktemp -d)"
    TMP_DIRS+=("$base")
    repo="$base/repo"
    home="$base/home"
    state="$base/state"

    mkdir -p "$repo/scripts" "$repo/lib" "$repo/modules/alpha/home/.config/alpha" \
        "$repo/modules/hypr/home/.config/hypr" "$repo/packages" \
        "$home/.config/alpha" "$home/.config/mozilla/firefox/a1b2.default-release" \
        "$home/Obsidian/Notes"

    cp -a "$ROOT/scripts/sync.sh" "$repo/scripts/sync.sh"
    cp -a "$ROOT"/lib/*.sh "$repo/lib/"
    chmod 0755 "$repo/scripts/sync.sh"

    cat >"$repo/modules/alpha/home/.config/alpha/settings.conf.in" <<'EOF'
home=@HOME@
profile=@FIREFOX_PROFILE_DIR@
vault=@OBSIDIAN_VAULT@
name=alpha
EOF

    printf 'generated-colors\n' \
        >"$repo/modules/hypr/home/.config/hypr/colors.lua"

    cat >"$repo/packages/catalog.tsv" <<'EOF'
# package	category	role	default	host	gpu	description
alpha	System	pkg	yes	any	any	alpha package
beta	System	pkg	yes	any	any	beta package
gamma	Terminal	alt	no	any	any	gamma package
EOF

    printf '%s\n' "$repo"$'\t'"$home"$'\t'"$state"
}

write_live() {
    local home="$1" name="${2:-beta}"
    cat >"$home/.config/alpha/settings.conf" <<EOF
home=$home
profile=a1b2.default-release
vault=Notes
name=$name
EOF
}

run_sync() {
    local repo="$1" home="$2" state="$3"
    shift 3
    DOTFILES_SYNC_HOME="$home" XDG_STATE_HOME="$state" \
        bash "$repo/scripts/sync.sh" "$@"
}

# 1. status reports a modified template and skips generated output.
IFS=$'\t' read -r repo home state < <(fixture)
write_live "$home" beta

status_out="$(run_sync "$repo" "$home" "$state" status)"
if grep -q 'alpha' <<<"$status_out" && grep -q 'modified' <<<"$status_out"; then
    pass "status reports the modified template"
else
    fail "status did not report the modified template"
    printf '%s\n' "$status_out"
fi

if grep -q 'colors.lua' <<<"$status_out"; then
    fail "status included generated matugen output"
else
    pass "status skips generated matugen output"
fi

# 2. diff shows the changed line.
diff_out="$(run_sync "$repo" "$home" "$state" diff)"
if grep -q '^-name=alpha' <<<"$diff_out" && grep -q '^+name=beta' <<<"$diff_out"; then
    pass "diff shows repository and live sides"
else
    fail "diff output is missing the changed line"
    printf '%s\n' "$diff_out"
fi

# 3. dry-run pull changes nothing and creates no backup.
before_repo="$(cat "$repo/modules/alpha/home/.config/alpha/settings.conf.in")"
dry_out="$(run_sync "$repo" "$home" "$state" pull --dry-run)"
if [[ "$(cat "$repo/modules/alpha/home/.config/alpha/settings.conf.in")" == "$before_repo" ]]; then
    pass "dry-run pull leaves the repository unchanged"
else
    fail "dry-run pull modified the repository"
fi
if find "$state" -path '*/sync-backup/*' -name manifest.tsv 2>/dev/null | grep -q .; then
    fail "dry-run pull created a backup"
else
    pass "dry-run pull creates no backup"
fi
if grep -q 'dry-run' <<<"$dry_out"; then
    pass "dry-run pull explains what it would do"
else
    fail "dry-run pull printed no explanation"
fi

# 4. pull writes reverse-rendered content, keeps the live file and backs up the repo.
live_before="$(cat "$home/.config/alpha/settings.conf")"
pull_out="$(run_sync "$repo" "$home" "$state" pull --yes)"
pull_rc=$?

if ((pull_rc == 0)); then
    pass "pull --yes succeeds"
else
    fail "pull --yes failed"
    printf '%s\n' "$pull_out"
fi

pulled="$repo/modules/alpha/home/.config/alpha/settings.conf.in"
if grep -qx 'home=@HOME@' "$pulled" \
    && grep -qx 'profile=@FIREFOX_PROFILE_DIR@' "$pulled" \
    && grep -qx 'vault=@OBSIDIAN_VAULT@' "$pulled" \
    && grep -qx 'name=beta' "$pulled"; then
    pass "pull restores all placeholders"
else
    fail "pull did not restore the placeholders"
    cat "$pulled"
fi

if [[ "$(cat "$home/.config/alpha/settings.conf")" == "$live_before" ]]; then
    pass "pull leaves the live file unchanged"
else
    fail "pull modified the live file"
fi

manifest="$(find "$state" -path '*/sync-backup/*/manifest.tsv' -print -quit 2>/dev/null)"
if [[ -n $manifest ]] && grep -q 'settings.conf.in' "$manifest"; then
    backup_file="$(awk -F'\t' 'NR == 2 {print $2}' "$manifest")"
    if grep -q 'name=alpha' "$backup_file" 2>/dev/null; then
        pass "pull backs up the previous repository content"
    else
        fail "pre-pull backup does not contain the old content"
    fi
else
    fail "pull did not create a backup manifest"
fi

# 5. A second pull is a no-op.
second_out="$(run_sync "$repo" "$home" "$state" pull --yes)"
if grep -q 'in sync' <<<"$second_out"; then
    pass "pull is idempotent"
else
    fail "second pull did not report an in-sync state"
    printf '%s\n' "$second_out"
fi

# 6. Secrets block the pull and leave the repository untouched.
IFS=$'\t' read -r repo home state < <(fixture)
write_live "$home" beta
printf '%s\n' 'api_key = "abcdefghijklmnopqrst"' >>"$home/.config/alpha/settings.conf"
before_repo="$(cat "$repo/modules/alpha/home/.config/alpha/settings.conf.in")"

secret_out="$(run_sync "$repo" "$home" "$state" pull --yes 2>&1)"
secret_rc=$?
if ((secret_rc != 0)); then
    pass "pull refuses a proposed file with a secret"
else
    fail "pull accepted a proposed file with a secret"
fi
if [[ "$(cat "$repo/modules/alpha/home/.config/alpha/settings.conf.in")" == "$before_repo" ]]; then
    pass "secret refusal leaves the repository unchanged"
else
    fail "secret refusal still modified the repository"
fi
if grep -q 'secret' <<<"$secret_out"; then
    pass "secret refusal names the reason"
else
    fail "secret refusal is unexplained"
    printf '%s\n' "$secret_out"
fi

# 7. An unknown module is rejected.
IFS=$'\t' read -r repo home state < <(fixture)
if run_sync "$repo" "$home" "$state" status does-not-exist >/dev/null 2>&1; then
    fail "unknown module was accepted"
else
    pass "unknown module is rejected"
fi

# 8. Package comparison reports drift in both directions.
IFS=$'\t' read -r repo home state < <(fixture)
bin="$(mktemp -d)"
TMP_DIRS+=("$bin")
cat >"$bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -Qqe) printf 'alpha\ndelta\n' ;;
    -Qq)  [[ ${2:-} == alpha ]] && exit 0 || exit 1 ;;
esac
EOF
chmod 0755 "$bin/pacman"

packages_out="$(export PATH="$bin:$PATH"; run_sync "$repo" "$home" "$state" packages 2>&1)"
packages_rc=$?
if ((packages_rc != 0)); then
    pass "packages exits nonzero when lists drift"
else
    fail "packages accepted drifting lists"
fi
if grep -q 'delta' <<<"$packages_out"; then
    pass "packages reports installed-but-unlisted packages"
else
    fail "packages missed an installed-but-unlisted package"
fi
if grep -q 'beta' <<<"$packages_out"; then
    pass "packages reports listed-but-missing packages"
else
    fail "packages missed a listed-but-missing package"
fi
if grep -q 'gamma' <<<"$packages_out"; then
    fail "packages treated an alternative as a required package"
else
    pass "packages ignores alternatives for the installed check"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
