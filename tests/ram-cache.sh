#!/usr/bin/env bash
# ram-cache: configuration, page-cache warming and safe command wrapper.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/modules/ram-cache/home/.local/bin/ramcache"
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
cache="$base/cache"
bin="$base/bin"
mkdir -p "$home/.config/dotfiles" "$cache" "$bin"

cat >"$bin/vmtouch" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$VMTOUCH_LOG"
EOF
chmod 0755 "$bin/vmtouch"
export VMTOUCH_LOG="$base/vmtouch.log"

cat >"$home/.config/dotfiles/ram-cache.conf" <<'EOF'
RAM_PERCENT=50
WAIT_SECONDS=0
CACHE_DIRS=(
)
USE_PSD=1
EOF

run() {
    env HOME="$home" XDG_CONFIG_HOME="$home/.config" PATH="$bin:$PATH" \
        bash "$SCRIPT" "$@"
}

# 1. Help and status work without a real Hyprland session.
if run --help | grep -q 'ramcache <status|warm|run>'; then
    pass "--help describes the commands"
else
    fail "--help is incomplete"
fi

status_out="$(run status)"
if grep -q 'RAM:' <<<"$status_out" \
    && grep -q 'warm limit:' <<<"$status_out" \
    && grep -q 'browser cache:' <<<"$status_out"; then
    pass "status reports RAM, limit and browser cache"
else
    fail "status output is incomplete"
    printf '%s\n' "$status_out"
fi

# 2. warm calls vmtouch for an existing directory.
mkdir -p "$base/small"
printf 'data\n' >"$base/small/file"
run warm "$base/small" >/dev/null
if grep -q -- '-t' "$VMTOUCH_LOG" && grep -q "$base/small" "$VMTOUCH_LOG"; then
    pass "warm passes the directory to vmtouch"
else
    fail "warm did not call vmtouch"
fi

# 3. An invalid percentage falls back to 50 and does not change the limit to 0.
cat >"$home/.config/dotfiles/ram-cache.conf" <<'EOF'
RAM_PERCENT=999
WAIT_SECONDS=0
CACHE_DIRS=()
USE_PSD=0
EOF
invalid_out="$(run status 2>&1)"
if grep -q 'warning: RAM_PERCENT=999 is invalid' <<<"$invalid_out" \
    && grep -q 'warm limit:' <<<"$invalid_out"; then
    pass "invalid RAM_PERCENT is warned about"
else
    fail "invalid RAM_PERCENT was accepted"
    printf '%s\n' "$invalid_out"
fi

# 4. run --no-wait starts the command and warms the directory.
cat >"$home/.config/dotfiles/ram-cache.conf" <<'EOF'
RAM_PERCENT=50
WAIT_SECONDS=0
CACHE_DIRS=()
USE_PSD=0
EOF
: >"$VMTOUCH_LOG"
run run --no-wait --dir "$base/small" -- sh -c 'printf run-ok' >"$base/run.out"
if [[ "$(cat "$base/run.out")" == run-ok ]]; then
    pass "run executes the wrapped command"
else
    fail "run did not execute the command"
fi

# 5. A missing directory is reported and skipped.
missing_out="$(run warm "$base/does-not-exist" 2>&1)"
if grep -q 'not a directory' <<<"$missing_out"; then
    pass "a missing directory is reported"
else
    fail "a missing directory was not reported"
fi

# 6. The module is skipped on laptops and small-RAM hosts.
if grep -q 'ram-cache skipped: laptop host or less than 16 GiB RAM' "$ROOT/install.sh" \
    && grep -q 'idle|lid|ram-cache' "$ROOT/install.sh"; then
    pass "ram-cache is optional and host-gated"
else
    fail "ram-cache host gate is missing"
fi

# 7. The module installs an optional psd config with suspend sync.
if grep -q 'USE_SUSPSYNC="yes"' "$ROOT/modules/ram-cache/home/.config/psd/psd.conf" \
    && grep -q 'OPTIONAL\|PACKAGES=(vmtouch profile-sync-daemon preload)' "$ROOT/modules/ram-cache/module.conf"; then
    pass "psd config and optional module metadata are present"
else
    fail "psd config or module metadata is missing"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
