#!/usr/bin/env bash
# Report whether the installed dotfiles are behind GitHub.
#
# Read-only: this never fetches and never touches the working tree. It asks the
# public API for the latest commit, caches the answer for six hours, and uses
# the compare endpoint for an exact count.
#
# Usage: dotfiles-update-check.sh [--refresh] [--json]
set -uo pipefail

GITHUB_REPO="${GITHUB_REPO:-mrdillmax/dotfiles}"
CACHE_TTL="${UPDATE_CACHE_TTL:-21600}"
CACHE="${UPDATE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/update-check}"
CURL="${CURL_BIN:-curl}"
GIT="${GIT_BIN:-git}"

REFRESH=0
JSON=0
while (($#)); do
    case "$1" in
        --refresh) REFRESH=1 ;;
        --json)    JSON=1 ;;
        -h|--help)
            printf 'Usage: %s [--refresh] [--json]\n' "$(basename "$0")"
            printf 'Prints: up to date | N commits behind | N commits ahead | cannot check (offline)\n'
            exit 0
            ;;
        *)
            printf 'unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO="${DOTFILES_REPO:-$("$GIT" -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)}"

cache_fetched="" cache_etag="" cache_local="" cache_remote=""
cache_result="" cache_behind="" cache_ahead="" cache_status=""
local_sha="" remote_sha="" behind=0 ahead=0 result="" status=""

emit() {
    if ((JSON)); then
        printf '{"status":"%s","behind":%d,"ahead":%d,"local":"%s","remote":"%s","cached":%s}\n' \
            "${status:-error}" "$behind" "$ahead" "$local_sha" "$remote_sha" \
            "${CACHED:-false}"
    else
        printf '%s\n' "${result:-cannot check (offline)}"
    fi
}

give_up() {
    status="offline"
    result="cannot check (offline)"
    emit
    exit 0
}

load_cache() {
    [[ -r $CACHE ]] || return 1
    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            fetched) cache_fetched="$value" ;;
            etag)    cache_etag="$value" ;;
            local)   cache_local="$value" ;;
            remote)  cache_remote="$value" ;;
            result)  cache_result="$value" ;;
            behind)  cache_behind="$value" ;;
            ahead)   cache_ahead="$value" ;;
            status)  cache_status="$value" ;;
        esac
    done <"$CACHE"
}

save_cache() {
    local dir tmp
    dir="$(dirname "$CACHE")"
    mkdir -p "$dir" || return 1
    tmp="$(mktemp "$CACHE.XXXXXX")" || return 1
    {
        printf 'fetched=%s\n' "${cache_fetched:-0}"
        printf 'etag=%s\n' "$cache_etag"
        printf 'local=%s\n' "$local_sha"
        printf 'remote=%s\n' "$remote_sha"
        printf 'behind=%s\n' "$behind"
        printf 'ahead=%s\n' "$ahead"
        printf 'status=%s\n' "$status"
        printf 'result=%s\n' "$result"
    } >"$tmp"
    mv -f "$tmp" "$CACHE"
}

set_result() {
    if ((behind > 0)); then
        local noun=commits
        ((behind == 1)) && noun=commit
        result="$behind $noun behind"
        status="behind"
    elif ((ahead > 0)); then
        local noun=commits
        ((ahead == 1)) && noun=commit
        result="$ahead $noun ahead"
        status="ahead"
    else
        result="up to date"
        status="current"
    fi
}

local_sha="$("$GIT" -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
[[ -n $local_sha ]] || give_up

load_cache
now="$(date +%s)"
if ((!REFRESH)) && [[ -n $cache_result && $cache_local == "$local_sha" ]] &&
    [[ $cache_fetched =~ ^[0-9]+$ ]] && ((now - cache_fetched < CACHE_TTL)); then
    result="$cache_result"
    behind="${cache_behind:-0}"
    ahead="${cache_ahead:-0}"
    remote_sha="$cache_remote"
    status="${cache_status:-error}"
    if [[ $status == error ]]; then
        case "$result" in
            "up to date") status=current ;;
            *" ahead")    status=ahead ;;
            *" behind")   status=behind ;;
        esac
    fi
    CACHED=true
    emit
    exit 0
fi

body="$(mktemp)"
headers="$(mktemp)"
trap 'rm -f "$body" "$headers"' EXIT

fetch() {
    # $1 = URL; prints the HTTP status (empty when the request failed).
    local url="$1"
    shift
    "$CURL" -sS -L --max-time 10 -o "$body" -D "$headers" \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: dotfiles-update-check' \
        "$@" -w '%{http_code}' "$url" 2>/dev/null || true
}

etag_args=()
[[ -n $cache_etag ]] && etag_args=(-H "If-None-Match: $cache_etag")

# The two responses are small and flat, so sed reads them. That keeps the
# checker free of a JSON dependency.
json_sha() {
    sed -nE 's/.*"sha"[[:space:]]*:[[:space:]]*"([0-9a-fA-F]{40})".*/\1/p' "$1" | head -n1
}

json_int() {
    sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/p" "$2" | head -n1
}

code="$(fetch "https://api.github.com/repos/$GITHUB_REPO/commits?per_page=1" "${etag_args[@]}")"
case "$code" in
    304)
        remote_sha="$cache_remote"
        [[ -n $remote_sha ]] || give_up
        ;;
    200)
        remote_sha="$(json_sha "$body")"
        cache_etag="$(awk 'BEGIN{IGNORECASE=1} /^etag:/{sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit}' "$headers")"
        [[ -n $remote_sha ]] || give_up
        ;;
    *) give_up ;;
esac

if [[ $remote_sha == "$local_sha" ]]; then
    behind=0
    ahead=0
else
    code="$(fetch "https://api.github.com/repos/$GITHUB_REPO/compare/$local_sha...$remote_sha")"
    case "$code" in
        200)
            behind="$(json_int ahead_by "$body")"
            ahead="$(json_int behind_by "$body")"
            [[ $behind =~ ^[0-9]+$ ]] || behind=0
            [[ $ahead =~ ^[0-9]+$ ]] || ahead=0
            ;;
        404)
            # The compare endpoint 404s when GitHub does not know the local
            # commit: there are local commits that were never pushed.
            status=unpushed
            result="local commits not pushed"
            emit
            exit 0
            ;;
        *) give_up ;;
    esac
fi

set_result
cache_fetched="$now"
cache_local="$local_sha"
cache_remote="$remote_sha"
CACHED=false
save_cache || true
emit
