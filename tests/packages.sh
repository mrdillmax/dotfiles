#!/usr/bin/env bash
# Package selection: all categories on, host-agnostic apps, conflicts survive.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
# shellcheck disable=SC2016 # the stub expands its own $1
printf '#!/bin/sh\ncase "$1" in\n  -Qq) exit 1 ;;\n  -Slq) echo fake-pkg ;;\n  -S) printf "%%s\\n" "$*" >>"%s/pacman.log"; echo ":: fake-pkg conflicts" >&2; exit 1 ;;\n  *) exit 0 ;;\nesac\n' "$work" >"$work/bin/pacman"
printf '#!/bin/sh\nexec "$@"\n' >"$work/bin/sudo"
chmod +x "$work/bin/pacman" "$work/bin/sudo"
PATH="$work/bin:$PATH"

export DOTFILES_DIR="$ROOT" DRY_RUN=0 ASSUME_YES=1 HOST_NAME=laptop GPU_PROFILE=amd

# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/tui.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/packages.sh"

# shellcheck disable=SC2034 # read by install_packages
SELECTED_APPLICATIONS=(fake-pkg)

if catalog_applicable desktop any; then
    pass "desktop applications stay available on a laptop"
else
    fail "the host column still hides desktop applications"
fi
if ! catalog_applicable any nvidia; then
    pass "GPU-specific packages are still filtered"
else
    fail "an NVIDIA package was offered on AMD"
fi

out="$(install_packages 2>/dev/null)"
rc=$?
if ((rc == 0)) && [[ $out == *"did not finish"* ]]; then
    pass "a pacman conflict or declined removal does not abort the install"
else
    fail "install_packages did not survive the conflict: $out"
fi
if [[ -f $work/pacman.log ]] && ! grep -q -- '--noconfirm' "$work/pacman.log"; then
    pass "pacman keeps its own conflict prompts"
else
    fail "pacman was run non-interactively: $(cat "$work/pacman.log" 2>/dev/null)"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
