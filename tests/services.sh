#!/usr/bin/env bash
# System step: selected services start and follow-up commands run.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# 1. Selected services are enabled and started in one command.
if grep -q 'systemctl enable --now "\$service"' "$ROOT/lib/system.sh"; then
    pass "selected services are enabled and started"
else
    fail "selected services are only enabled"
fi

# 2. The installer no longer prints commands for the user to run.
if grep -q 'Not run automatically' "$ROOT/lib/system.sh"; then
    fail "the system step still prints manual commands"
else
    pass "the system step does not defer commands to the user"
fi

for command in 'systemctl daemon-reload' 'cpupower' 'grub-mkconfig' 'mkinitcpio -P'; do
    if grep -q -- "$command" "$ROOT/lib/system.sh"; then
        pass "the system step runs $command"
    else
        fail "the system step never runs $command"
    fi
done

# 3. Bootloader and initramfs rebuilds only follow a changed file.
if grep -q 'boot_changed' "$ROOT/lib/system.sh"; then
    pass "boot rebuilds are gated on changed files"
else
    fail "boot rebuilds are unconditional"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
