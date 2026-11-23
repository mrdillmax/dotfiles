#!/usr/bin/env bash
# Dotfiles update status from the cached GitHub check.
set -uo pipefail

CHECK="${DOTFILES_UPDATE_CHECK:-dotfiles-update-check.sh}"

if [[ ${1:-} == --click ]]; then
    status="$("$CHECK" --refresh 2>/dev/null || true)"
    [[ -n $status ]] || status="cannot check (offline)"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "dotfiles" "dotfiles: $status" >/dev/null 2>&1 || true
    else
        printf '%s\n' "dotfiles: $status"
    fi
    pkill -RTMIN+9 waybar 2>/dev/null || true
    exit 0
fi

json="$("$CHECK" --json 2>/dev/null || true)"
status="$(sed -n 's/.*"status":"\([a-z]*\)".*/\1/p' <<<"$json")"
behind="$(sed -n 's/.*"behind":\([0-9]*\).*/\1/p' <<<"$json")"
behind="${behind:-0}"

if [[ $status == behind ]] && ((behind > 0)); then
    printf '{"text":"\uf021 %d","alt":"behind","tooltip":"%d commit(s) behind. Click to check again.","class":"behind"}\n' \
        "$behind" "$behind"
else
    printf '{"text": ""}\n'
fi
