#!/usr/bin/env bash
# Optional modules stay out of --all and are marked in the generated docs.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

for module in ram-cache workspaces-split; do
    if grep -qx 'OPTIONAL=1' "$ROOT/modules/$module/module.conf"; then
        pass "$module is marked optional in module.conf"
    else
        fail "$module/module.conf has no OPTIONAL=1"
    fi
done

if grep -Eq '\| .*ram-cache.* \| .*\(optional\)' "$ROOT/docs/modules.md" &&
    grep -Eq '\| .*workspaces-split.* \| .*\(optional\)' "$ROOT/docs/modules.md"; then
    pass "the generated module table marks optional modules"
else
    fail "docs/modules.md does not mark optional modules"
fi

if "$ROOT/scripts/modules-doc.sh" --check >/dev/null 2>&1; then
    pass "docs/modules.md is current"
else
    fail "docs/modules.md is stale"
fi

osd="$ROOT/modules/osd"
if [[ -r $osd/module.conf ]] && grep -qx 'OPTIONAL=1' "$osd/module.conf"; then
    pass "osd is optional"
else
    fail "osd module missing or required"
fi
if luac -p "$osd/home/.config/hypr/osd.lua" 2>/dev/null; then
    pass "osd.lua compiles"
else
    fail "osd.lua does not compile"
fi
for key in XF86AudioRaiseVolume XF86AudioMute XF86MonBrightnessUp; do
    if grep -q "$key" "$osd/home/.config/hypr/osd.lua"; then
        pass "osd binds $key"
    else
        fail "osd does not bind $key"
    fi
done
if grep -q 'ExecStart=/usr/bin/swayosd-server' \
    "$osd/home/.config/systemd/user/swayosd-server.service"; then
    pass "the swayosd unit starts the server"
else
    fail "swayosd unit is missing ExecStart"
fi
if awk -F'\t' '$1 == "swayosd" {found=1} END{exit !found}' "$ROOT/packages/catalog.tsv"; then
    pass "swayosd is in the catalog"
else
    fail "swayosd has no catalog row"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
