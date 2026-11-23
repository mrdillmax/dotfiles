#!/usr/bin/env bash
# Config integrity: the Hyprland config compiles, every window rule explains
# itself, section dividers share one shape, and the matugen registry only
# points at templates that exist.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$ROOT/modules/hypr/home/.config/hypr/hyprland.lua"
MATUGEN="$ROOT/modules/matugen/home/.config/matugen"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# --- the config compiles ---------------------------------------------------
if command -v luac >/dev/null 2>&1; then
    if luac -p "$HYPR" 2>/dev/null; then
        pass "hyprland.lua compiles"
    else
        fail "hyprland.lua does not compile"
    fi
else
    pass "luac not installed; skipping the compile check"
fi

# --- every window rule carries a reason ------------------------------------
missing=()
while IFS=: read -r line _; do
    previous="$(sed -n "$((line - 1))p" "$HYPR")"
    if [[ $previous != --* ]]; then
        missing+=("$line")
    fi
done < <(grep -nE '(^|local [A-Za-z]+ = )hl\.window_rule\(' "$HYPR")
if ((${#missing[@]} == 0)); then
    pass "every window rule has a reason on the line above"
else
    fail "window rules without a reason: ${missing[*]}"
fi

# --- one divider shape -----------------------------------------------------
widths="$(grep -E '^-- --- [A-Z ]+ -+$' "$HYPR" | awk '{print length($0)}' | sort -u)"
if [[ -n $widths ]] && [[ $(wc -l <<<"$widths") == 1 ]]; then
    pass "section dividers share one shape"
else
    fail "section dividers differ in length"
fi

# --- the user's clipboard bind stays --------------------------------------
if grep -q 'hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("clipboard-menu.sh"))' "$HYPR"; then
    pass "SUPER + V still runs clipboard-menu.sh"
else
    fail "SUPER + V clipboard bind is missing"
fi

# --- matugen registry points at real templates -----------------------------
missing=()
while IFS= read -r template; do
    [[ -f $MATUGEN/$template ]] || missing+=("$template")
done < <(grep -oE "templates/[A-Za-z0-9._-]+" "$MATUGEN/config.toml.in" | sort -u)
if ((${#missing[@]} == 0)); then
    pass "every matugen template in config.toml.in exists"
else
    fail "missing matugen templates: ${missing[*]}"
fi

# --- every shipped template is registered ---------------------------------
registered="$(grep -oE "templates/[A-Za-z0-9._-]+" "$MATUGEN/config.toml.in" | sed 's#templates/##' | sort -u)"
unregistered=()
while IFS= read -r file; do
    base="$(basename "$file")"
    grep -qxF "$base" <<<"$registered" || unregistered+=("$base")
done < <(find "$MATUGEN/templates" -maxdepth 1 -type f | sort)
if ((${#unregistered[@]} == 0)); then
    pass "every template file is registered"
else
    fail "unregistered templates: ${unregistered[*]}"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
