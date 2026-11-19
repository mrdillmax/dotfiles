#!/usr/bin/env bash
# Spicetify installer: non-interactive CLI install, no spicetify commands.
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
if "$SCRIPT" --help | grep -q 'Spicetify CLI'; then
    pass "--help describes the CLI install"
else
    fail "--help is incomplete"
fi

dry="$(PATH="/nonexistent:$PATH" "$SCRIPT" --dry-run)"
if grep -q 'github.com/spicetify/cli/releases' <<<"$dry"; then
    pass "dry-run prints the release location"
else
    fail "dry-run output is wrong"
    printf '%s\n' "$dry"
fi

# A release asset that contains one executable named "spicetify".
base="$(mktemp -d)"
TMP_DIRS+=("$base")
archive_dir="$base/archive"
mkdir -p "$archive_dir"
printf '#!/bin/sh\nexit 0\n' >"$archive_dir/spicetify"
chmod 0755 "$archive_dir/spicetify"
tar -czf "$base/spicetify.tar.gz" -C "$archive_dir" spicetify

bin="$base/bin"
mkdir -p "$bin"
cat >"$bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *api.github.com*) printf '{"tag_name":"v9.9.9"}\n'; exit 0 ;;
esac
out=""
prev=""
for arg in "$@"; do
    [[ $prev == -o ]] && out="$arg"
    prev="$arg"
done
[[ -n $out ]] || exit 1
cp -- "$SPICETIFY_FIXTURE" "$out"
EOF
chmod 0755 "$bin/curl"

# 2. A fresh install extracts the release without running spicetify. Spotify
# may not be initialised yet, so any spicetify command would fail the setup.
home="$base/home"
mkdir -p "$home"
marker="$base/spicetify-called"
cat >"$bin/spicetify" <<EOF
#!/usr/bin/env bash
printf 'called\\n' >"$marker"
exit 1
EOF
chmod 0755 "$bin/spicetify"
out="$(env HOME="$home" PATH="$bin:/usr/bin:/bin" SPICETIFY_FIXTURE="$base/spicetify.tar.gz" \
    "$SCRIPT" --yes 2>&1)"
rc=$?
if [[ $rc -eq 0 && -x "$home/.spicetify/spicetify" ]]; then
    pass "a fresh install places the CLI in ~/.spicetify"
else
    fail "a fresh install failed (rc $rc)"
    printf '%s\n' "$out"
fi
if [[ ! -e $marker ]]; then
    pass "the installer never runs spicetify commands"
else
    fail "the installer ran spicetify, which needs an initialised Spotify"
fi

# 3. An existing CLI is left alone: no download, no update.
home2="$base/home2"
mkdir -p "$home2/.spicetify"
printf '#!/bin/sh\nexit 0\n' >"$home2/.spicetify/spicetify"
chmod 0755 "$home2/.spicetify/spicetify"
cat >"$bin/curl-nope" <<'EOF'
#!/usr/bin/env bash
printf 'curl must not run\n' >&2
exit 1
EOF
chmod 0755 "$bin/curl-nope"
mkdir -p "$base/bin2"
cp "$bin/curl-nope" "$base/bin2/curl"
out="$(env HOME="$home2" PATH="$base/bin2:/usr/bin:/bin" "$SCRIPT" --yes 2>&1)"
rc=$?
if [[ $rc -eq 0 && $out == *'already installed'* ]]; then
    pass "an existing CLI is reported without an update"
else
    fail "an existing CLI was reinstalled or updated (rc $rc)"
    printf '%s\n' "$out"
fi

# 4. install.sh --spicetify forwards to the installer.
if "$ROOT/install.sh" --spicetify --dry-run 2>/dev/null \
    | grep -q 'github.com/spicetify/cli/releases'; then
    pass "install.sh --spicetify forwards to the installer"
else
    fail "install.sh --spicetify is not wired"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
