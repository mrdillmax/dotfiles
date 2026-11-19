#!/usr/bin/env bash
# Repository assets: cursor theme and the first-run wallpaper.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# 1. The assets are in the repository.
if [[ -d $ROOT/assets/cursors/win11_concept_cursos ]]; then
    pass "the cursor theme is in the repository"
else
    fail "the cursor theme is missing from the repository"
fi
if [[ -f $ROOT/assets/wallpapers/example.jpg ]]; then
    pass "the example wallpaper is in the repository"
else
    fail "the example wallpaper is missing from the repository"
fi

# 2. A first run installs the wallpaper and records it.
base="$(mktemp -d)"
out="$(DOTFILES_DIR="$ROOT" REAL_HOME="$base" BACKUP_DIR="$base/backup" \
    DRY_RUN=0 ASSUME_YES=1 bash -c '
        source "$DOTFILES_DIR/lib/common.sh"
        source "$DOTFILES_DIR/lib/wallpaper.sh"
        install_default_wallpaper
    ' 2>&1)"
rc=$?
state="$base/.config/hypr/wallpaper.path"
target="$base/.local/share/wallpapers/dotfiles/example.jpg"
if [[ $rc -eq 0 && -f $target && -r $state ]] && grep -qx "$target" "$state"; then
    pass "a first run installs and records the default wallpaper"
else
    fail "the default wallpaper was not installed (rc $rc)"
    printf '%s\n' "$out"
fi

# 3. An existing choice is preserved.
mkdir -p "$base/.config/hypr"
printf '%s\n' "/keep/this.jpg" >"$state"
DOTFILES_DIR="$ROOT" REAL_HOME="$base" BACKUP_DIR="$base/backup" \
    DRY_RUN=0 ASSUME_YES=1 bash -c '
        source "$DOTFILES_DIR/lib/common.sh"
        source "$DOTFILES_DIR/lib/wallpaper.sh"
        install_default_wallpaper
    ' >/dev/null 2>&1
if grep -qx '/keep/this.jpg' "$state"; then
    pass "an existing wallpaper choice is preserved"
else
    fail "the default wallpaper replaced the user choice"
fi

# 4. The cursor installer prefers the repository copy.
curs="$(DOTFILES_DIR="$ROOT" REAL_HOME="$base" bash -c '
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/cursor.sh"
    CURSOR_THEME=win11_concept_cursos
    cursor_repo_theme_dir
' 2>&1)"
if [[ $curs == "$ROOT/assets/cursors/win11_concept_cursos" ]]; then
    pass "the cursor theme is installed from the repository"
else
    fail "the repository cursor theme is not detected (got: $curs)"
fi

rm -rf -- "$base"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
