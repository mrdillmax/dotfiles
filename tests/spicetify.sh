#!/usr/bin/env bash
# Spicetify installer: dry-run output and the upstream download path.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/install-spicetify.sh"
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

# 1. Help and dry-run do not touch the network.
if "$SCRIPT" --help | grep -q 'official Spicetify installer'; then
    pass "--help describes the upstream installer"
else
    fail "--help is incomplete"
fi

dry="$(PATH="/nonexistent:$PATH" "$SCRIPT" --dry-run)"
if grep -q 'curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh' <<<"$dry"; then
    pass "dry-run prints the official command"
else
    fail "dry-run command is wrong"
    printf '%s\n' "$dry"
fi

# 2. The installer downloads to a temporary file and runs sh.
base="$(mktemp -d)"
TMP_DIRS+=("$base")
bin="$base/bin"
mkdir -p "$bin"
cat >"$bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '#!/bin/sh\nprintf "installed\\n" >"$SPICETIFY_MARK"\n' >"$4"
EOF
chmod 0755 "$bin/curl"
mark="$base/mark"
if env PATH="$bin:$PATH" SPICETIFY_MARK="$mark" "$SCRIPT" --yes >/dev/null; then
    if [[ -r $mark && "$(cat "$mark")" == installed ]]; then
        pass "the downloaded installer runs"
    else
        fail "the downloaded installer did not run"
    fi
else
    fail "installer failed with a stub curl"
fi

# 3. The installer is reachable through install.sh.
if "$ROOT/install.sh" --spicetify --dry-run 2>/dev/null \
    | grep -q 'raw.githubusercontent.com/spicetify/cli'; then
    pass "install.sh --spicetify forwards to the installer"
else
    fail "install.sh --spicetify is not wired"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
