#!/usr/bin/env bash
# Hypr tools replace the matching paths only when installed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="$ROOT/modules/control-center/home/.local/bin/dotfiles-control-center"
POWERMENU="$ROOT/modules/rofi/home/.local/bin/powermenu.sh"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

printf '#!/bin/sh\necho ran >"%s/hyprshutdown.ran"\n' "$work" >"$work/bin/hyprshutdown"
# Even if hyprshutdown disappears, logout must never reach the real session.
printf '#!/bin/sh\necho ran >"%s/uwsm.ran"\n' "$work" >"$work/bin/uwsm"
printf '#!/bin/sh\necho ran >"%s/hyprpwcenter.ran"\n' "$work" >"$work/bin/hyprpwcenter"
printf '#!/bin/sh\necho ran >"%s/hyprsysteminfo.ran"\n' "$work" >"$work/bin/hyprsysteminfo"
chmod +x "$work/bin"/*
PATH="$work/bin:$PATH"

(
    # shellcheck source=/dev/null
    source "$POWERMENU"
    # shellcheck disable=SC2329,SC2154 # called by run_cmd; yes comes from powermenu.sh
    confirm_exit() { printf '%s\n' "$yes"; }
    run_cmd --logout
)
if [[ -e $work/hyprshutdown.ran && ! -e $work/uwsm.ran ]]; then
    pass "logout prefers hyprshutdown and never reaches uwsm stop"
else
    fail "logout used the wrong path (uwsm stub: $(ls "$work/uwsm.ran" 2>/dev/null))"
fi

(
    # shellcheck source=/dev/null
    source "$CC"
    sound_page
)
for _ in {1..20}; do
    [[ -e $work/hyprpwcenter.ran ]] && break
    sleep 0.05
done
if [[ -e $work/hyprpwcenter.ran ]]; then
    pass "Sound prefers hyprpwcenter"
else
    fail "Sound did not run hyprpwcenter"
fi

(
    # shellcheck source=/dev/null
    source "$CC"
    # shellcheck disable=SC2329 # called by docs_page
    pick_icon() {
        [[ -e $work/picked-docs ]] && return 1
        : >"$work/picked-docs"
        printf '%s\n' "System info"
    }
    docs_page
)
for _ in {1..20}; do
    [[ -e $work/hyprsysteminfo.ran ]] && break
    sleep 0.05
done
if [[ -e $work/hyprsysteminfo.ran ]]; then
    pass "Docs lists and launches hyprsysteminfo"
else
    fail "Docs did not launch hyprsysteminfo"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
