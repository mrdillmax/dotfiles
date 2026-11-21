#!/usr/bin/env bash
# hyprlock and fastfetch follow the generated palette. The checks render the
# templates with stand-in colours and validate the result.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/modules/matugen/home/.config/matugen/templates"
CONFIG="$ROOT/modules/matugen/home/.config/matugen/config.toml.in"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

render() {
    sed -E 's/\{\{colors\.[a-z0-9_]+\.default\.hex_stripped\}\}/112233/g; s/\{\{colors\.[a-z0-9_]+\.default\.hex\}\}/#112233/g' "$1"
}

for tpl in hyprlock.conf fastfetch.jsonc; do
    if [[ -r $TPL/$tpl ]]; then
        pass "$tpl template exists"
    else
        fail "missing template: $tpl"
        continue
    fi

    count="$(grep -o '{{colors\.' "$TPL/$tpl" | wc -l)"
    if ((count >= 3)); then
        pass "$tpl uses the palette ($count placeholders)"
    else
        fail "$tpl has too few palette placeholders ($count)"
    fi
done

if grep -q '\[templates\.hyprlock\]' "$CONFIG"; then
    pass "hyprlock is registered in matugen"
else
    fail "hyprlock is not registered in matugen"
fi
if grep -q '\[templates\.fastfetch\]' "$CONFIG"; then
    pass "fastfetch is registered in matugen"
else
    fail "fastfetch is not registered in matugen"
fi

if grep -q 'Inter' "$TPL/hyprlock.conf"; then
    pass "hyprlock uses Inter"
else
    fail "hyprlock does not use Inter"
fi

if [[ -r $TPL/fastfetch.jsonc ]]; then
    rendered="$(render "$TPL/fastfetch.jsonc" | sed 's#^[[:space:]]*//.*$##')"
    if printf '%s\n' "$rendered" | jq empty >/dev/null 2>&1; then
        pass "rendered fastfetch config is valid JSON"
    else
        fail "rendered fastfetch config is not valid JSON"
    fi
fi

if [[ -r $TPL/hyprlock.conf ]]; then
    if render "$TPL/hyprlock.conf" | grep -q 'rgb(112233)'; then
        pass "hyprlock colours render to rgb() syntax"
    else
        fail "hyprlock colours are not in rgb() syntax"
    fi
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
