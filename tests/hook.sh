#!/usr/bin/env bash
# Tests for hooks/pre-commit. Plain bash; no bats dependency.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/pre-commit"
PASS=0
FAIL=0
TMP_DIRS=()

cleanup() {
    local d
    for d in "${TMP_DIRS[@]}"; do
        rm -rf -- "$d"
    done
}
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

new_repo() {
    local d
    d="$(mktemp -d)"
    TMP_DIRS+=("$d")
    git -C "$d" init -q
    git -C "$d" config user.email test@example.invalid
    git -C "$d" config user.name test
    printf '%s\n' "$d"
}

run_hook() {
    local d="$1"
    if command -v setsid >/dev/null 2>&1; then
        (cd "$d" && setsid -w "$HOOK") </dev/null >"$d/hook.log" 2>&1
    else
        (cd "$d" && "$HOOK") </dev/null >"$d/hook.log" 2>&1
    fi
}

expect_blocked() {
    local desc="$1" d="$2" pattern="$3"
    if run_hook "$d"; then
        fail "$desc: hook unexpectedly passed"
        return
    fi
    if grep -q -- "$pattern" "$d/hook.log"; then
        pass "$desc"
    else
        fail "$desc: output does not mention '$pattern'"
        sed 's/^/    /' "$d/hook.log"
    fi
}

expect_passed() {
    local desc="$1" d="$2"
    if run_hook "$d"; then
        pass "$desc"
    else
        fail "$desc: hook unexpectedly blocked"
        sed 's/^/    /' "$d/hook.log"
    fi
}

# 1. Forbidden secret path.
d="$(new_repo)"
printf 'x\n' >"$d/pihole.toml"
git -C "$d" add pihole.toml
expect_blocked "blocks pihole.toml" "$d" "forbidden secret path"

# 2. personal/ is forbidden.
d="$(new_repo)"
mkdir -p "$d/personal"
printf 'x\n' >"$d/personal/notes"
git -C "$d" add personal/notes
expect_blocked "blocks personal/" "$d" "forbidden secret path"

# 3. Secret value in a staged config.
d="$(new_repo)"
printf 'api_key = "abcdefghijklmnopqrst"\n' >"$d/credentials.conf"
git -C "$d" add credentials.conf
expect_blocked "blocks api_key values" "$d" "secret patterns"

# 4. Generated matugen output.
d="$(new_repo)"
mkdir -p "$d/modules/hypr/home/.config/hypr"
printf '%s\n' 'return {}' >"$d/modules/hypr/home/.config/hypr/colors.lua"
git -C "$d" add modules/hypr/home/.config/hypr/colors.lua
expect_blocked "blocks generated colors.lua" "$d" "generated matugen output"

# 5. shellcheck errors in staged scripts.
if command -v shellcheck >/dev/null 2>&1; then
    d="$(new_repo)"
    printf '#!/usr/bin/env bash\nif true; then\n' >"$d/broken.sh"
    git -C "$d" add broken.sh
    expect_blocked "blocks shellcheck errors" "$d" "shellcheck errors"
else
    printf 'SKIP shellcheck is not installed\n'
fi

# 6. A clean script passes.
d="$(new_repo)"
printf '#!/usr/bin/env bash\nprintf "ok\\n"\n' >"$d/good.sh"
git -C "$d" add good.sh
expect_passed "allows a clean script" "$d"

# 7. The pihole example is allowed (empty values are not secrets).
d="$(new_repo)"
printf 'pwhash = ""\ntotp_secret = ""\ncli_pw = false\n' >"$d/pihole.toml.example"
git -C "$d" add pihole.toml.example
expect_passed "allows pihole.toml.example" "$d"

# 8. Machine-specific paths block a non-interactive commit.
if command -v setsid >/dev/null 2>&1; then
    d="$(new_repo)"
    printf 'path=/home/alice/Projects\n' >"$d/notes.txt"
    git -C "$d" add notes.txt
    expect_blocked "warns about hardcoded home paths" "$d" "machine-specific"
else
    printf 'SKIP setsid is not installed\n'
fi

# 9. Repository-relative ".../home/..." segments are not user home paths.
d="$(new_repo)"
printf 'see modules/hypr/home/.config/hypr/theme.lua\n' >"$d/notes.conf"
git -C "$d" add notes.conf
expect_passed "ignores repo-relative home segments" "$d"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
