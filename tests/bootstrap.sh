#!/usr/bin/env bash
# Tests for bootstrap.sh. Uses stub pacman/sudo/installer tools and a temporary
# "Arch" marker; nothing on the real system is installed or changed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bootstrap.sh"
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

# new_case -> base path with bin/, arch-release, logs, installer stub.
new_case() {
    local base
    base="$(mktemp -d)"
    TMP_DIRS+=("$base")
    mkdir -p "$base/bin"
    : >"$base/arch-release"
    : >"$base/pacman.log"
    : >"$base/installer.log"

    cat >"$base/bin/id" <<'EOF'
#!/bin/bash
printf '%s\n' "${BOOTSTRAP_UID:-1000}"
EOF

    cat >"$base/bin/dirname" <<'EOF'
#!/bin/bash
printf '%s\n' "${1%/*}"
EOF

    cat >"$base/bin/cat" <<'EOF'
#!/bin/bash
exec /bin/cat "$@"
EOF

    cat >"$base/bin/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PACMAN_LOG"
exit "${PACMAN_RC:-0}"
EOF

    cat >"$base/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF

    cat >"$base/installer" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$INSTALLER_LOG"
for arg in "$@"; do
    if [[ $arg == --doctor ]]; then
        exit "${DOCTOR_RC:-0}"
    fi
done
exit "${INSTALLER_RC:-0}"
EOF
    chmod 0755 "$base/bin/id" "$base/bin/dirname" "$base/bin/cat" \
        "$base/bin/pacman" "$base/bin/sudo" \
        "$base/installer"

    printf '%s\n' "$base"
}

# add_tool <base> <name> [exit-code]
add_tool() {
    local base="$1" name="$2" rc="${3:-0}"
    cat >"$base/bin/$name" <<EOF
#!/bin/bash
exit $rc
EOF
    chmod 0755 "$base/bin/$name"
}

# run_bs <base> [args...]  (PATH contains only the stubs)
run_bs() {
    local base="$1"
    shift
    env -i PATH="$base/bin" HOME="$base" \
        BOOTSTRAP_ARCH_RELEASE="$base/arch-release" \
        BOOTSTRAP_INSTALLER="$base/installer" \
        PACMAN_LOG="$base/pacman.log" INSTALLER_LOG="$base/installer.log" \
        BOOTSTRAP_UID="${BOOTSTRAP_UID:-1000}" \
        PACMAN_RC="${PACMAN_RC:-0}" INSTALLER_RC="${INSTALLER_RC:-0}" \
        DOCTOR_RC="${DOCTOR_RC:-0}" CURL_RC="${CURL_RC:-0}" \
        "$BASH" "$SCRIPT" "$@"
}

# 1. Help works without touching anything.
base="$(new_case)"
if run_bs "$base" --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help failed"
fi

# 2. A non-Arch system is refused.
base="$(new_case)"
rm -f "$base/arch-release"
if run_bs "$base" --dry-run >/dev/null 2>"$base/err"; then
    fail "a missing Arch marker was accepted"
else
    if grep -q 'does not look like Arch' "$base/err"; then
        pass "a non-Arch system is refused"
    else
        fail "the non-Arch error is unclear"
        cat "$base/err"
    fi
fi

# 3. Running as root is refused.
base="$(new_case)"
if BOOTSTRAP_UID=0 run_bs "$base" --dry-run >/dev/null 2>"$base/err"; then
    fail "root was accepted"
else
    if grep -q 'not as root' "$base/err"; then
        pass "root is refused with an explanation"
    else
        fail "the root error is unclear"
        cat "$base/err"
    fi
fi

# 4. Unknown options are rejected.
base="$(new_case)"
if run_bs "$base" --sideways >/dev/null 2>&1; then
    fail "an unknown option was accepted"
else
    pass "an unknown option is rejected"
fi

# 5. Dry-run prints the commands and changes nothing.
base="$(new_case)"
add_tool "$base" curl
dry_out="$(run_bs "$base" --dry-run)"
if grep -q '^\[dry-run\] sudo pacman -S --needed --noconfirm' <<<"$dry_out" \
    && grep -q "^\\[dry-run\\] $base/installer" <<<"$dry_out" \
    && grep -q '^\[dry-run\].*--doctor' <<<"$dry_out" \
    && [[ ! -s $base/pacman.log && ! -s $base/installer.log ]]; then
    pass "dry-run prints pacman, installer and doctor without running them"
else
    fail "dry-run ran a command or missed one"
    printf '%s\n' "$dry_out"
fi

# 6. --yes installs the missing packages and runs install.sh --all --yes.
base="$(new_case)"
add_tool "$base" curl
yes_out="$(run_bs "$base" --yes -- --host laptop)"
if grep -q '^-S --needed --noconfirm base-devel git$' "$base/pacman.log"; then
    pass "--yes installs the missing bootstrap packages"
else
    fail "pacman was not called with the expected packages"
    cat "$base/pacman.log"
fi
if grep -q '^--all --yes --host laptop$' "$base/installer.log"; then
    pass "the installer receives --all --yes and forwarded options"
else
    fail "installer arguments are wrong"
    grep -v '^--doctor$' "$base/installer.log" 2>/dev/null
fi
if grep -qx -- '--doctor' "$base/installer.log"; then
    pass "the doctor pass runs after the installer"
else
    fail "the doctor pass did not run"
fi
if grep -q 'bootstrap finished' <<<"$yes_out"; then
    pass "bootstrap reports a successful finish"
else
    fail "the finish message is missing"
fi

# 7. A pacman failure stops before the installer.
base="$(new_case)"
add_tool "$base" curl
if PACMAN_RC=1 run_bs "$base" --yes >/dev/null 2>"$base/err"; then
    fail "a pacman failure was ignored"
else
    if [[ ! -s $base/installer.log ]] && grep -q 'pacman failed' "$base/err"; then
        pass "a pacman failure stops the bootstrap"
    else
        fail "a pacman failure still ran the installer"
        cat "$base/installer.log"
    fi
fi

# 8. --no-packages skips pacman but still runs the installer.
base="$(new_case)"
add_tool "$base" curl
run_bs "$base" --yes --no-packages >/dev/null
if [[ ! -s $base/pacman.log ]] && grep -q -- '--all --yes' "$base/installer.log"; then
    pass "--no-packages skips pacman and keeps the installer"
else
    fail "--no-packages still called pacman"
    cat "$base/pacman.log"
fi

# 9. An already provisioned machine needs no pacman call.
base="$(new_case)"
for tool in curl git makepkg gcc fakeroot paru; do
    add_tool "$base" "$tool"
done
present_out="$(run_bs "$base" --yes)"
if [[ ! -s $base/pacman.log ]] \
    && grep -q 'bootstrap packages already present' <<<"$present_out"; then
    pass "present packages skip the pacman step"
else
    fail "present packages still triggered pacman"
    cat "$base/pacman.log"
fi
if grep -q 'AUR helper found' <<<"$present_out"; then
    pass "an AUR helper is detected"
else
    fail "the AUR helper was not detected"
fi

# 10. A missing AUR helper is a warning, not a failure.
base="$(new_case)"
add_tool "$base" curl
warn_out="$(run_bs "$base" --yes 2>&1)"
if grep -q 'no AUR helper' <<<"$warn_out" \
    && grep -q -- '--all --yes' "$base/installer.log"; then
    pass "a missing AUR helper warns and continues"
else
    fail "a missing AUR helper stopped the bootstrap"
    printf '%s\n' "$warn_out"
fi

# 11. An installer failure propagates and skips the doctor.
base="$(new_case)"
add_tool "$base" curl
if INSTALLER_RC=3 run_bs "$base" --yes >/dev/null 2>&1; then
    fail "an installer failure was ignored"
else
    rc=$?
    if [[ $rc == 3 ]] && ! grep -qx -- '--doctor' "$base/installer.log"; then
        pass "an installer failure propagates and skips the doctor"
    else
        fail "the installer exit code was lost (rc=$rc)"
        cat "$base/installer.log"
    fi
fi

# 12. A failing doctor is advisory.
base="$(new_case)"
add_tool "$base" curl
if DOCTOR_RC=1 run_bs "$base" --yes >/dev/null 2>"$base/err"; then
    if grep -q 'doctor reported problems' "$base/err"; then
        pass "a failing doctor is advisory"
    else
        fail "a failing doctor gave no warning"
    fi
else
    fail "a failing doctor made bootstrap fail"
fi

# 13. A network failure stops a real run unless skipped.
base="$(new_case)"
add_tool "$base" curl 22
if run_bs "$base" --yes >/dev/null 2>"$base/err"; then
    fail "a network failure was ignored"
else
    if grep -q 'cannot reach archlinux.org' "$base/err"; then
        pass "a network failure is explained"
    else
        fail "the network error is unclear"
        cat "$base/err"
    fi
fi

base="$(new_case)"
add_tool "$base" curl 22
if run_bs "$base" --yes --skip-network >/dev/null 2>&1; then
    pass "--skip-network bypasses the reachability check"
else
    fail "--skip-network did not bypass the check"
fi

# 14. Dry-run skips the network check as well.
base="$(new_case)"
add_tool "$base" curl 22
if run_bs "$base" --dry-run >/dev/null 2>&1; then
    pass "dry-run skips the network check"
else
    fail "dry-run still required the network"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
