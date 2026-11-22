#!/usr/bin/env bash
# Boot and swap settings are drop-ins, never replacements of pacman-owned
# files. Validation must reject a broken file so the installer can roll back.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# shellcheck source=/dev/null
DOTFILES_DIR="$ROOT"
export DOTFILES_DIR
source "$ROOT/lib/system.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

map_for() {
    local gpu="$1"
    DOTFILES_DIR="$ROOT" GPU_PROFILE="$gpu" DRY_RUN=1 bash -c '
        unset UNBOUND_PI_HOLE_CONF
        SYSTEM_COMPONENTS=()
        source "$DOTFILES_DIR/lib/system.sh"
        system_file_map
    ' 2>&1
}

nvidia_map="$(map_for nvidia)"
for dst in \
    /etc/default/grub.d/99-dotfiles.cfg \
    /etc/mkinitcpio.conf.d/99-dotfiles.conf \
    /etc/systemd/zram-generator.conf.d/99-dotfiles.conf; do
    if grep -q "$dst" <<<"$nvidia_map"; then
        pass "nvidia profile installs $dst"
    else
        fail "nvidia profile misses $dst"
    fi
done

if grep -Eq '/etc/default/grub[[:space:]]|/etc/mkinitcpio\.conf[[:space:]]|/etc/systemd/zram-generator\.conf[[:space:]]' <<<"$nvidia_map"; then
    fail "map still replaces a pacman-owned file"
else
    pass "map never replaces grub, mkinitcpio or zram-generator directly"
fi

amd_map="$(map_for amd)"
if grep -q '/etc/default/grub.d/' <<<"$amd_map" || grep -q '/etc/mkinitcpio.conf.d/' <<<"$amd_map"; then
    fail "non-NVIDIA profile installs NVIDIA boot settings"
else
    pass "non-NVIDIA profile skips the boot drop-ins"
fi
if grep -q '/etc/systemd/zram-generator.conf.d/99-dotfiles.conf' <<<"$amd_map"; then
    pass "zram drop-in is independent of the GPU profile"
else
    fail "zram drop-in is missing on a non-NVIDIA profile"
fi

# --- content stays minimal ------------------------------------------------
grub="$ROOT/system/grub/99-dotfiles.cfg"
if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT' "$grub" && ! grep -q 'mitigations=off' "$grub"; then
    pass "GRUB drop-in sets the cmdline without the unsafe flags"
else
    fail "GRUB drop-in is missing the cmdline or enables unsafe flags"
fi
if grep -q '^MODULES=' "$ROOT/system/mkinitcpio/99-dotfiles.conf" &&
    grep -q '^HOOKS=' "$ROOT/system/mkinitcpio/99-dotfiles.conf"; then
    pass "mkinitcpio drop-in sets MODULES and HOOKS"
else
    fail "mkinitcpio drop-in is incomplete"
fi
if grep -q '^\[zram0\]' "$ROOT/system/zram/99-dotfiles.conf"; then
    pass "zram drop-in keeps the [zram0] section"
else
    fail "zram drop-in has no [zram0] section"
fi

# --- validation rejects broken files -------------------------------------
printf 'if then\n' >"$work/bad.sh"
if system_conf_validate "$work/bad.sh"; then
    fail "broken script passed validation"
else
    pass "broken script is rejected"
fi
printf 'echo ok\n' >"$work/good.sh"
if system_conf_validate "$work/good.sh"; then
    pass "valid script passes validation"
else
    fail "valid script was rejected"
fi

printf '#!/bin/sh\nexit 1\n' >"$work/unbound-checkconf"
chmod +x "$work/unbound-checkconf"
mkdir -p "$work/etc/unbound"
printf 'server:\n    port: 5335\n' >"$work/etc/unbound/pi-hole.conf"
PATH="$work:$PATH"
if system_conf_validate "$work/etc/unbound/pi-hole.conf"; then
    fail "unbound-checkconf failure was ignored"
else
    pass "unbound-checkconf failure is reported"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
