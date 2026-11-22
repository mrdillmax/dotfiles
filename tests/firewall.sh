#!/usr/bin/env bash
# Firewall policy: only installed services get an inbound rule, and applying
# the same policy twice adds nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# shellcheck source=/dev/null
source "$ROOT/lib/firewall.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- rules reflect installed services -------------------------------------
# Only builtins are needed, so an empty PATH proves absence even on a machine
# where sshd and syncthing are installed system-wide.
mkdir -p "$work/bin"
PATH="$work/bin"
EXTERNAL_PATH="/usr/bin:/bin"
if [[ -z $(firewall_rules) ]]; then
    pass "no rules without sshd or syncthing"
else
    fail "rules appeared without a service: $(firewall_rules | tr '\n' ' ')"
fi

printf '#!/bin/sh\nexit 0\n' >"$work/bin/sshd"
/usr/bin/chmod +x "$work/bin/sshd"
if [[ $(firewall_rules) == "22/tcp" ]]; then
    pass "sshd opens only 22/tcp"
else
    fail "sshd rules are wrong: $(firewall_rules | tr '\n' ' ')"
fi

printf '#!/bin/sh\nexit 0\n' >"$work/bin/syncthing"
/usr/bin/chmod +x "$work/bin/syncthing"
rules="$(firewall_rules)"
if [[ $rules == *22000/tcp* && $rules == *22000/udp* ]]; then
    pass "syncthing opens 22000/tcp and 22000/udp"
else
    fail "syncthing rules are wrong: ${rules//$'\n'/ }"
fi
if [[ $rules != *"53/"* && $rules != *"5335/"* && $rules != *"8384/"* && $rules != *"631/"* ]]; then
    pass "local-only services stay closed"
else
    fail "a local-only service was opened: ${rules//$'\n'/ }"
fi

# --- apply is idempotent ---------------------------------------------------
PATH="$work:$EXTERNAL_PATH"
cat >"$work/ufw" <<'STUB'
#!/bin/sh
calls="$UFW_CALLS"
added="$UFW_ADDED"
status="$UFW_STATUS"
printf '%s\n' "$*" >>"$calls"
case "$1 $2" in
    "show added")   cat "$added" 2>/dev/null ;;
    "status verbose") cat "$status" 2>/dev/null ;;
esac
case "$*" in
    "default deny incoming")
        printf 'Status: active\nDefault: deny (incoming), allow (outgoing), disabled (routed)\n' >"$status"
        ;;
    "default allow outgoing")
        printf 'Status: active\nDefault: deny (incoming), allow (outgoing), disabled (routed)\n' >"$status"
        ;;
    "allow "*) printf 'ufw allow %s\n' "$2" >>"$added" ;;
esac
exit 0
STUB
chmod +x "$work/ufw"

UFW_BIN="$work/ufw"
UFW_CALLS="$work/calls"
UFW_ADDED="$work/added"
UFW_STATUS="$work/status"
export UFW_BIN UFW_CALLS UFW_ADDED UFW_STATUS
: >"$UFW_CALLS"
: >"$UFW_ADDED"
printf 'Status: active\n' >"$UFW_STATUS"

firewall_apply "22/tcp
22000/tcp
22000/udp" || fail "first apply failed"
firewall_apply "22/tcp
22000/tcp
22000/udp" || fail "second apply failed"

if [[ $(grep -c '^default deny incoming$' "$UFW_CALLS") == 1 ]]; then
    pass "default deny incoming is set once"
else
    fail "default deny incoming ran $(grep -c '^default deny incoming$' "$UFW_CALLS") times"
fi
if [[ $(grep -c '^default allow outgoing$' "$UFW_CALLS") == 1 ]]; then
    pass "default allow outgoing is set once"
else
    fail "default allow outgoing ran $(grep -c '^default allow outgoing$' "$UFW_CALLS") times"
fi
for rule in 22/tcp 22000/tcp 22000/udp; do
    if [[ $(grep -c "^allow $rule$" "$UFW_CALLS") == 1 ]]; then
        pass "$rule is allowed once"
    else
        fail "$rule was allowed $(grep -c "^allow $rule$" "$UFW_CALLS") times"
    fi
done
if [[ $(grep -c '^--force enable$' "$UFW_CALLS") == 2 ]]; then
    pass "ufw is enabled on every run"
else
    fail "ufw enable count is wrong"
fi

deny_line="$(grep -n '^default deny incoming$' "$UFW_CALLS" | cut -d: -f1 | head -n1)"
allow_line="$(grep -n '^allow 22/tcp$' "$UFW_CALLS" | cut -d: -f1 | head -n1)"
enable_line="$(grep -n '^--force enable$' "$UFW_CALLS" | cut -d: -f1 | head -n1)"
if ((deny_line < allow_line && allow_line < enable_line)); then
    pass "defaults run before rules and enable runs last"
else
    fail "firewall steps are out of order"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
