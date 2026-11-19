#!/usr/bin/env bash
# Kernel AUR installs must point gpg at a keyserver that serves build keys.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

base="$(mktemp -d)"
TMP_DIRS+=("$base")
mkdir -p "$base/bin"
: >"$base/yay.log"

cat >"$base/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -Si) exit 1 ;;
    *)   exit 0 ;;
esac
EOF
cat >"$base/bin/yay" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$YAY_LOG"
EOF
chmod 0755 "$base/bin/pacman" "$base/bin/yay"

DOTFILES_DIR="$ROOT" DRY_RUN=0 ASSUME_YES=0
export DOTFILES_DIR DRY_RUN ASSUME_YES
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/kernel.sh
source "$ROOT/lib/kernel.sh"
YAY_LOG="$base/yay.log" bash -c '
    export PATH="$1/bin:$PATH" YAY_LOG="$2"
    source "$3/lib/common.sh"
    source "$3/lib/kernel.sh"
    kernel_install_package test-kernel
' _ "$base" "$base/yay.log" "$ROOT"

if grep -q -- '--gpgflags --keyserver hkps://keyserver.ubuntu.com --keyserver hkps://pgp.surf.nl -S --needed --noconfirm test-kernel' "$base/yay.log"; then
    pass "kernel AUR install imports keys from a working keyserver"
else
    fail "kernel AUR install does not configure the keyserver"
    cat "$base/yay.log"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
