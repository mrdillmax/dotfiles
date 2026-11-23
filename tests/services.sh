#!/usr/bin/env bash
# Syncthing is a user service: it must be enabled through the desktop user's
# systemd instance, and skipped when the package is absent.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# shellcheck source=/dev/null
source "$ROOT/lib/firewall.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/systemctl.log"\n' "$work" >"$work/bin/systemctl"
chmod +x "$work/bin/systemctl"
# `id` is the only external helper the function needs before systemctl.
ln -s "$(command -v id)" "$work/bin/id"
EXTERNAL_PATH="$PATH"
PATH="$work/bin"
XDG_RUNTIME_DIR="$work"
export XDG_RUNTIME_DIR

enable_syncthing_user_service
if [[ ! -s $work/systemctl.log ]]; then
    pass "no user service without syncthing"
else
    fail "systemctl ran without syncthing installed"
fi

printf '#!/bin/sh\nexit 0\n' >"$work/bin/syncthing"
/usr/bin/chmod +x "$work/bin/syncthing"
enable_syncthing_user_service
PATH="$EXTERNAL_PATH"
if grep -q -- '--user enable --now syncthing.service' "$work/systemctl.log"; then
    pass "syncthing user service is enabled and started"
else
    fail "syncthing user service was not enabled: $(cat "$work/systemctl.log")"
fi

mkdir -p "$work/repo/modules/demo" "$work/home/.config/systemd/user"
cat >"$work/repo/modules/demo/module.conf" <<'CONF'
DESCRIPTION="demo"
PACKAGES=()
SERVICES=(demo.service)
REQUIRES=()
OPTIONAL=1
CONF
: >"$work/home/.config/systemd/user/demo.service"
: >"$work/systemctl.log"
PATH="$work/bin:$EXTERNAL_PATH"
export DOTFILES_DIR="$work/repo" REAL_HOME="$work/home" DRY_RUN=0 ASSUME_YES=1
# shellcheck disable=SC2034 # read by enable_services
MODULES=(demo)
# shellcheck disable=SC2034
MODULES_ARG="demo"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/services.sh"
enable_services >/dev/null
if grep -q -- '--user enable --now demo.service' "$work/systemctl.log"; then
    pass "an explicitly named module starts its service"
else
    fail "enable_services did not start demo.service: $(cat "$work/systemctl.log")"
fi

: >"$work/systemctl.log"
# shellcheck disable=SC2034
MODULES_ARG=""
enable_services >/dev/null
if ! grep -q -- '--user enable --now' "$work/systemctl.log"; then
    pass "a non-interactive bulk install still skips services"
else
    fail "bulk install started services: $(cat "$work/systemctl.log")"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
