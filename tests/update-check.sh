#!/usr/bin/env bash
# Update check: exact counts, six-hour cache, --refresh and offline handling.
# The API is stubbed; nothing here touches the network or the real repository.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/modules/control-center/home/.local/bin/dotfiles-update-check.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A real repository is only used to provide a HEAD sha.
DOTFILES_REPO="$work/repo"
git init -q "$DOTFILES_REPO"
git -C "$DOTFILES_REPO" -c user.email=test@example.test -c user.name=test \
    commit -q --allow-empty -m initial
LOCAL_SHA="$(git -C "$DOTFILES_REPO" rev-parse HEAD)"
REMOTE_SHA="1111111111111111111111111111111111111111"

cat >"$work/curl" <<'STUB'
#!/bin/sh
out="" hdr="" url="" method=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out=$2; shift 2 ;;
        -D) hdr=$2; shift 2 ;;
        -w) shift 2 ;;
        -H) shift 2 ;;
        *) url=$1; shift ;;
    esac
done
printf '%s\n' "$url" >>"$CURL_CALLS"
[ "$STUB_MODE" = offline ] && exit 7

case "$url" in
    *"/commits"*)
        if [ "$STUB_MODE" = not-modified ] && [ -s "$UPDATE_CACHE" ]; then
            printf 'HTTP/2 304\r\nETag: "cached-etag"\r\n\r\n' >"$hdr"
            printf '304'
        else
            printf 'HTTP/2 200\r\nETag: "fresh-etag"\r\n\r\n' >"$hdr"
            printf '[\n  {\n    "sha": "%s",\n    "node_id": "abc"\n  }\n]\n' "$REMOTE_SHA" >"$out"
            printf '200'
        fi
        ;;
    *"/compare/"*)
        if [ "$STUB_COMPARE" = 404 ]; then
            printf '{"message":"Not Found"}\n' >"$out"
            printf '404'
        else
            printf '{\n  "ahead_by": %s,\n  "behind_by": %s,\n  "total_commits": 9\n}\n' "$STUB_BEHIND" "$STUB_AHEAD" >"$out"
            printf '200'
        fi
        ;;
    *) printf '500' ;;
esac
STUB
chmod +x "$work/curl"

CURL_BIN="$work/curl"
CURL_CALLS="$work/calls"
UPDATE_CACHE="$work/cache"
STUB_MODE="online"
STUB_BEHIND=3
STUB_AHEAD=0
STUB_COMPARE=200
export CURL_BIN CURL_CALLS UPDATE_CACHE REMOTE_SHA STUB_MODE STUB_BEHIND STUB_AHEAD STUB_COMPARE

run_check() {
    DOTFILES_REPO="$DOTFILES_REPO" GITHUB_REPO="owner/repo" "$CHECK" "$@"
}

: >"$CURL_CALLS"
out="$(run_check)"
if [[ $out == "3 commits behind" ]]; then
    pass "reports the exact behind count"
else
    fail "unexpected output: $out"
fi
if [[ $(wc -l <"$CURL_CALLS") == 2 ]]; then
    pass "latest commit and compare are both requested"
else
    fail "expected 2 API calls, got $(wc -l <"$CURL_CALLS")"
fi

: >"$CURL_CALLS"
out="$(run_check)"
if [[ $out == "3 commits behind" && ! -s $CURL_CALLS ]]; then
    pass "a fresh cache is reused without a request"
else
    fail "cache was not reused (calls: $(wc -l <"$CURL_CALLS"))"
fi

STUB_MODE="not-modified"
: >"$CURL_CALLS"
out="$(run_check --refresh)"
if [[ $out == "3 commits behind" && $(wc -l <"$CURL_CALLS") == 2 ]]; then
    pass "--refresh bypasses the cache and handles 304"
else
    fail "--refresh failed: $out ($(wc -l <"$CURL_CALLS") calls)"
fi

out="$(run_check --json)"
if grep -qE '"status":"behind"' <<<"$out" && grep -qE '"behind":3' <<<"$out" &&
    grep -qE '"local":"[0-9a-f]{40}"' <<<"$out"; then
    pass "--json carries status and count"
else
    fail "--json payload is wrong: $out"
fi

STUB_MODE="online"
STUB_BEHIND=0
STUB_AHEAD=2
rm -f "$UPDATE_CACHE"
out="$(run_check)"
if [[ $out == "2 commits ahead" ]]; then
    pass "reports local commits that GitHub does not have"
else
    fail "unexpected ahead output: $out"
fi

STUB_MODE="online"
STUB_BEHIND=0
STUB_AHEAD=0
REMOTE_SHA="$LOCAL_SHA"
export REMOTE_SHA
rm -f "$UPDATE_CACHE"
out="$(run_check)"
if [[ $out == "up to date" ]]; then
    pass "equal commits are up to date"
else
    fail "unexpected current output: $out"
fi

REMOTE_SHA="1111111111111111111111111111111111111111"
STUB_MODE="online"
STUB_COMPARE=404
export REMOTE_SHA STUB_MODE STUB_COMPARE
rm -f "$UPDATE_CACHE"
out="$(run_check)"
if [[ $out == "local commits not pushed" ]]; then
    pass "an unpushed local commit is named, not called offline"
else
    fail "unexpected unpushed output: $out"
fi

STUB_COMPARE=200
STUB_MODE="offline"
export STUB_MODE STUB_COMPARE
rm -f "$UPDATE_CACHE"
out="$(run_check)"
if [[ $out == "cannot check (offline)" ]]; then
    pass "offline is reported clearly"
else
    fail "unexpected offline output: $out"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
