#!/usr/bin/env bash
# Package catalog defaults: Docker is gone, optional fonts stay opt-in, and
# every row keeps all of its columns.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT/packages/catalog.tsv"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

if awk -F'\t' '$1 ~ /^(docker|docker-compose|lazydocker)$/ {found=1} END{exit !found}' "$CATALOG"; then
    fail "Docker packages are still in the catalog"
else
    pass "Docker packages are gone"
fi

row="$(awk -F'\t' '$1 == "openssh" {print $1"|"$4}' "$CATALOG")"
if [[ $row == 'openssh|no' ]]; then
    pass "openssh is optional"
else
    fail "openssh row is missing or defaulted on: ${row:-none}"
fi

optional_fonts=(gnu-free-fonts ttf-croscore adwaita-fonts woff2-font-awesome)
for font in "${optional_fonts[@]}"; do
    row="$(awk -F'\t' -v name="$font" '$1 == name {print $4}' "$CATALOG")"
    if [[ $row == no ]]; then
        pass "$font is opt-in"
    else
        fail "$font defaults on (${row:-missing})"
    fi
done

required_fonts=(inter-font ttf-jetbrains-mono-nerd noto-fonts-emoji noto-fonts-cjk
    ttf-ms-fonts ttf-liberation ttf-dejavu ttf-roboto terminus-font hunspell-uk hyphen-uk)
for font in "${required_fonts[@]}"; do
    row="$(awk -F'\t' -v name="$font" '$1 == name {print $4}' "$CATALOG")"
    if [[ $row == yes ]]; then
        pass "$font stays default"
    else
        fail "$font should stay default (${row:-missing})"
    fi
done

if awk -F'\t' 'BEGIN{ok=1} /^#/ || NF==0 {next} $1=="" || $2=="" || $3=="" || $4=="" {ok=0} END{exit !ok}' "$CATALOG"; then
    pass "every catalog row has all required columns"
else
    fail "catalog has an empty required column"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
