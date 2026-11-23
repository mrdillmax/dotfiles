#!/usr/bin/env bash
# Desktop caches are refreshed and mpv only fills an empty video association.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
# shellcheck disable=SC2016 # the stub expands $1 at its own runtime
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/xdg.log"\ncase "$1" in query) exit 0 ;; esac\n' "$work" >"$work/bin/xdg-mime"
# shellcheck disable=SC2016 # the stub expands $1 at its own runtime
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/update.log"\n' "$work" >"$work/bin/update-desktop-database"
# shellcheck disable=SC2016 # the stub expands $1 at its own runtime
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/sycoca.log"\n' "$work" >"$work/bin/kbuildsycoca6"
printf '#!/bin/sh\nexit 0\n' >"$work/bin/mpv"
chmod +x "$work/bin"/*
PATH="$work/bin:$PATH"
REAL_HOME="$work/home"
DRY_RUN=0
export PATH REAL_HOME DRY_RUN

# shellcheck source=/dev/null
source "$ROOT/lib/desktop.sh"

refresh_desktop_database
if grep -q 'default mpv.desktop video/mp4' "$work/xdg.log"; then
    pass "an empty video/mp4 association is filled with mpv"
else
    fail "mpv default was not set: $(cat "$work/xdg.log" 2>/dev/null)"
fi
if grep -q -- '--noincremental' "$work/sycoca.log" && [[ -s $work/update.log ]]; then
    pass "desktop and KDE caches are refreshed"
else
    fail "desktop caches were not refreshed"
fi

: >"$work/xdg.log"
# shellcheck disable=SC2016
printf '#!/bin/sh\ncase "$1" in query) echo firefox.desktop ;; esac\n' >"$work/bin/xdg-mime"
chmod +x "$work/bin/xdg-mime"
refresh_desktop_database
if ! grep -q 'default' "$work/xdg.log"; then
    pass "an existing default is left alone"
else
    fail "an existing default was overwritten: $(cat "$work/xdg.log")"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
