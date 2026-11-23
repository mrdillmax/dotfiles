#!/usr/bin/env bash
# Repository style: generated docs stay current, modules keep the documented
# key order, hand-written configs carry a title, and scripts are kebab-case.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# Files edited by hand. Generated output and third-party copies are excluded.
CONFIGS=(
    modules/hypr/home/.config/hypr/hyprland.lua
    modules/waybar/home/.config/waybar/config.jsonc
    modules/waybar/home/.config/waybar/style.css
    modules/rofi/home/.config/rofi/config.rasi
    modules/rofi/home/.config/rofi/launcher.rasi
    modules/rofi/home/.config/rofi/powermenu.rasi
    modules/idle/home/.config/hypr/hypridle.conf
    modules/idle/home/.config/hypr/hyprlock.conf.in
    modules/fish/home/.config/fish/config.fish
    modules/matugen/home/.config/matugen/config.toml.in
    modules/matugen/home/.config/matugen/templates/hyprlock.conf
    modules/matugen/home/.config/matugen/templates/fastfetch.jsonc
    system/grub/99-dotfiles.cfg
    system/mkinitcpio/99-dotfiles.conf
    system/unbound/pi-hole.conf
    system/pihole/dotfiles-dnsmasq.conf
    system/zram/99-dotfiles.conf
)

# --- generated module table -----------------------------------------------
if "$ROOT/scripts/modules-doc.sh" --check >/dev/null 2>&1; then
    pass "docs/modules.md matches module.conf"
else
    fail "docs/modules.md is stale; run scripts/modules-doc.sh"
fi

# --- module.conf key order ------------------------------------------------
expected=(DESCRIPTION PACKAGES SERVICES REQUIRES)
for conf in "$ROOT"/modules/*/module.conf; do
    name="$(basename "$(dirname "$conf")")"
    mapfile -t keys < <(sed -n 's/^\([A-Z_]*\)=.*/\1/p' "$conf")
    position=0
    order_ok=1
    for key in "${keys[@]}"; do
        [[ $key == SYMLINKS ]] && continue
        index=-1
        for i in "${!expected[@]}"; do
            [[ ${expected[$i]} == "$key" ]] && index=$i
        done
        if ((index < position)); then
            order_ok=0
            break
        fi
        position=$index
    done
    if ((order_ok)) && ((${#keys[@]} >= 4)); then
        pass "$name/module.conf keeps the documented key order"
    else
        fail "$name/module.conf keys are missing or out of order"
    fi
done

# --- headers and whitespace ----------------------------------------------
for rel in "${CONFIGS[@]}"; do
    file="$ROOT/$rel"
    if [[ ! -r $file ]]; then
        fail "missing config: $rel"
        continue
    fi

    # fastfetch rejects comments in its JSON config, so it has no title line.
    if [[ $rel == *fastfetch.jsonc ]]; then
        pass "fastfetch.jsonc stays valid JSON (no comment header)"
    else
        first="$(head -n1 "$file")"
        if [[ $first =~ ^(\#|//|/\*|--) ]]; then
            pass "$(basename "$rel") starts with a comment"
        else
            fail "$(basename "$rel") does not start with a comment"
        fi

        if head -n5 "$file" | grep -q '—'; then
            pass "$(basename "$rel") title names the file"
        else
            fail "$(basename "$rel") title has no em dash"
        fi
    fi

    if grep -qE '[[:space:]]+$' "$file"; then
        fail "$(basename "$rel") has trailing whitespace"
    else
        pass "$(basename "$rel") has no trailing whitespace"
    fi

    if [[ -s $file && -n $(tail -c1 "$file") ]]; then
        fail "$(basename "$rel") has no final newline"
    else
        pass "$(basename "$rel") ends with a newline"
    fi
done

# --- script names ---------------------------------------------------------
kebab='^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+)?$'
for dir in "$ROOT"/modules/*/home/.local/bin "$ROOT/scripts"; do
    [[ -d $dir ]] || continue
    while IFS= read -r file; do
        base="$(basename "$file")"
        if [[ $base =~ $kebab ]]; then
            pass "$base is kebab-case"
        else
            fail "$base is not kebab-case (${file#"$ROOT"/})"
        fi
    done < <(find "$dir" -maxdepth 1 -type f | sort)
done

# --- no executables under .config ----------------------------------------
found=0
while IFS= read -r file; do
    [[ -x $file ]] || continue
    fail "executable under .config: ${file#"$ROOT"/}"
    found=1
done < <(find "$ROOT/modules" -path '*/.config/*' -type f)
((found)) || pass "no executables under .config"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
