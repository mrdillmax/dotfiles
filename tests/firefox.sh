#!/usr/bin/env bash
# Firefox profile discovery. The chrome CSS only applies when the installer
# writes into the profile directory that actually exists; a made-up name is
# worse than a warning.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# shellcheck source=/dev/null
source "$ROOT/lib/firefox.sh"

tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

# 1. XDG layout used by Arch's firefox package.
mkdir -p "$tmp_home/xdg/.config/mozilla/firefox/abc123.default-release"
REAL_HOME="$tmp_home/xdg"
if [[ $(firefox_profile_dir) == abc123.default-release ]]; then
    pass "finds the XDG profile"
else
    fail "XDG profile missed"
fi
if [[ $(firefox_profile_root) == "$tmp_home/xdg/.config/mozilla/firefox" ]]; then
    pass "reports the XDG root"
else
    fail "XDG root is wrong"
fi

# 2. Classic ~/.mozilla layout.
mkdir -p "$tmp_home/classic/.mozilla/firefox/xyz.default"
REAL_HOME="$tmp_home/classic"
if [[ $(firefox_profile_dir) == xyz.default ]]; then
    pass "finds the classic profile"
else
    fail "classic profile missed"
fi

# 3. Flatpak layout.
mkdir -p "$tmp_home/flatpak/.var/app/org.mozilla.firefox/.mozilla/firefox/flat.default-release"
REAL_HOME="$tmp_home/flatpak"
if [[ $(firefox_profile_dir) == flat.default-release ]]; then
    pass "finds the Flatpak profile"
else
    fail "Flatpak profile missed"
fi

# 4. No profile: fail instead of inventing one.
mkdir -p "$tmp_home/empty"
REAL_HOME="$tmp_home/empty"
if firefox_profile_dir >/dev/null; then
    fail "invented a profile that does not exist"
else
    pass "warns when no profile exists"
fi

# 5. Prefer .default-release over .default in the same root.
mkdir -p "$tmp_home/both/.mozilla/firefox/b.default" "$tmp_home/both/.mozilla/firefox/c.default-release"
# shellcheck disable=SC2034  # read by the sourced helpers
REAL_HOME="$tmp_home/both"
if [[ $(firefox_profile_dir) == c.default-release ]]; then
    pass "prefers .default-release"
else
    fail "picked the wrong profile: $(firefox_profile_dir)"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
