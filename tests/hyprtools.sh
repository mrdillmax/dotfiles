#!/usr/bin/env bash
# Hypr tools and the working fallbacks: logout, sound and system info.
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
printf '#!/bin/sh\necho ran >"%s/pavucontrol.ran"\n' "$work" >"$work/bin/pavucontrol"
printf '#!/bin/sh\necho ran >"%s/fastfetch.ran"\n' "$work" >"$work/bin/fastfetch"
chmod +x "$work/bin"/*
PATH="$work/bin:$PATH"

(
    # shellcheck source=/dev/null
    source "$POWERMENU"
    # shellcheck disable=SC2329,SC2154 # called by run_cmd; yes comes from powermenu.sh
    confirm_exit() { printf '%s\n' "$yes"; }
    run_cmd --logout
)
if [[ -e $work/uwsm.ran && ! -e $work/hyprshutdown.ran ]]; then
    pass "logout uses uwsm even when hyprshutdown is installed"
else
    fail "logout used the wrong path (hyprshutdown: $(ls "$work/hyprshutdown.ran" 2>/dev/null))"
fi

(
    # shellcheck source=/dev/null
    source "$CC"
    sound_page
)
for _ in {1..20}; do
    [[ -e $work/pavucontrol.ran ]] && break
    sleep 0.05
done
if [[ -e $work/pavucontrol.ran && ! -e $work/hyprpwcenter.ran ]]; then
    pass "Sound prefers pavucontrol even when hyprpwcenter is installed"
else
    fail "Sound used the wrong tool (hyprpwcenter: $(ls "$work/hyprpwcenter.ran" 2>/dev/null))"
fi

(
    # shellcheck source=/dev/null
    source "$CC"
    # shellcheck disable=SC2329
    run_terminal() { printf '%s\n' "$*" >"$work/terminal.cmd"; }
    # shellcheck disable=SC2329
    pick_icon() {
        [[ -e $work/picked-docs ]] && return 1
        : >"$work/picked-docs"
        printf '%s\n' "System info"
    }
    docs_page
)
if grep -q -- '--hold fastfetch' "$work/terminal.cmd" 2>/dev/null; then
    pass "System info opens fastfetch in a terminal"
else
    fail "System info did not run fastfetch: $(cat "$work/terminal.cmd" 2>/dev/null)"
fi

# Fallbacks when the Hypr tools are absent: only uwsm and pavucontrol exist.
mkdir -p "$work/fallback"
for tool in uptime sed readlink dirname mktemp basename cat; do
    ln -s "$(command -v "$tool")" "$work/fallback/$tool"
done
printf '#!/bin/sh\necho ran >"%s/fallback/uwsm.ran"\n' "$work" >"$work/fallback/uwsm"
printf '#!/bin/sh\necho ran >"%s/fallback/pavucontrol.ran"\n' "$work" >"$work/fallback/pavucontrol"
chmod +x "$work/fallback/uwsm" "$work/fallback/pavucontrol"

(
    # shellcheck disable=SC2123 # deliberately a one-directory PATH
    PATH="$work/fallback"
    # shellcheck source=/dev/null
    source "$POWERMENU"
    # shellcheck disable=SC2329,SC2154
    confirm_exit() { printf '%s\n' "$yes"; }
    run_cmd --logout
)
if [[ -e $work/fallback/uwsm.ran ]]; then
    pass "logout falls back to uwsm stop"
else
    fail "logout did not reach the uwsm fallback"
fi

(
    # shellcheck disable=SC2123
    PATH="$work/fallback"
    # shellcheck source=/dev/null
    source "$CC"
    sound_page
)
for _ in {1..20}; do
    [[ -e $work/fallback/pavucontrol.ran ]] && break
    sleep 0.05
done
if [[ -e $work/fallback/pavucontrol.ran ]]; then
    pass "Sound works without the Hypr tools"
else
    fail "Sound did not reach the pavucontrol fallback"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
