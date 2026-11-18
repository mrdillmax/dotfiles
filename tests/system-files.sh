#!/usr/bin/env bash
# Tests for GPU-specific system file mapping.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

map_for() {
    GPU_PROFILE="$1" DOTFILES_DIR="$ROOT" bash -c '
        source "$DOTFILES_DIR/lib/system.sh"
        system_file_map
    '
}

amd="$(map_for amd)"

# 1. NVIDIA and hybrid profiles get the boot and initramfs files.
for profile in nvidia hybrid; do
    map="$(map_for "$profile")"
    if grep -q '/etc/default/grub' <<<"$map" \
        && grep -q '/etc/mkinitcpio.conf' <<<"$map" \
        && grep -q '/etc/modprobe.d/nvidia.conf' <<<"$map"; then
        pass "$profile maps the NVIDIA boot files"
    else
        fail "$profile is missing the NVIDIA boot files"
    fi
done

# 2. Other GPU profiles do not overwrite boot or initramfs configuration.
if ! grep -q '/etc/default/grub' <<<"$amd" \
    && ! grep -q '/etc/mkinitcpio.conf' <<<"$amd" \
    && ! grep -q '/etc/modprobe.d/nvidia.conf' <<<"$amd"; then
    pass "amd skips the NVIDIA boot files"
else
    fail "amd still maps the NVIDIA boot files"
fi

# 3. Generic system files remain available on every profile.
if grep -q '/etc/systemd/zram-generator.conf' <<<"$amd" \
    && grep -q '/etc/modprobe.d/no-watchdog.conf' <<<"$amd"; then
    pass "generic system files are mapped for amd"
else
    fail "generic system files disappeared for amd"
fi

# 4. The hybrid map is not empty.
hybrid_map="$(map_for hybrid)"
if [[ -n $hybrid_map ]]; then
    pass "the hybrid map is not empty"
else
    fail "the hybrid map is empty"
fi

# 5. --system-components narrows the map to one component.
component_map() {
    SYSTEM_COMPONENTS="$1" GPU_PROFILE="$2" DOTFILES_DIR="$ROOT" bash -c '
        source "$DOTFILES_DIR/lib/system.sh"
        IFS=, read -r -a SYSTEM_COMPONENTS <<<"$SYSTEM_COMPONENTS"
        system_file_map
    '
}

dns_map="$(component_map dns amd)"
if grep -q '/etc/unbound/unbound.conf' <<<"$dns_map" \
    && ! grep -q '/etc/systemd/zram-generator.conf' <<<"$dns_map"; then
    pass "dns selects only DNS files"
else
    fail "dns component leaked other files"
fi

zram_map="$(component_map zram amd)"
if grep -q '/etc/systemd/zram-generator.conf' <<<"$zram_map" \
    && ! grep -q '/etc/unbound/unbound.conf' <<<"$zram_map"; then
    pass "zram selects only zram files"
else
    fail "zram component leaked other files"
fi

grub_map="$(component_map grub nvidia)"
if grep -q '/etc/default/grub' <<<"$grub_map" \
    && ! grep -q '/etc/unbound/unbound.conf' <<<"$grub_map"; then
    pass "grub selects only boot files"
else
    fail "grub component leaked other files"
fi

# 6. services selects the pacman hook helper, not boot or DNS files.
services_map="$(component_map services amd)"
if grep -q '/usr/local/bin/dotfiles-pkg-sync-mark.sh' <<<"$services_map" \
    && ! grep -q '/etc/default/grub' <<<"$services_map"; then
    pass "services selects only unit and hook files"
else
    fail "services component leaked other files"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
