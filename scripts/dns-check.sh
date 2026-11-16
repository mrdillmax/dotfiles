#!/usr/bin/env bash
# Read-only DNS chain check: resolv.conf -> Pi-hole -> unbound.
# Exit code is nonzero when any FAIL is reported.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR
export DRY_RUN=1
export ASSUME_YES=1

# shellcheck source=lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=lib/dns.sh
source "$DOTFILES_DIR/lib/dns.sh"

JSON=0
while (($#)); do
    case "$1" in
        --json) JSON=1 ;;
        -h|--help)
            cat <<'EOF'
Usage: scripts/dns-check.sh [--json]

Checks the resolver chain without changing anything:
  /etc/resolv.conf -> 127.0.0.1:53 (Pi-hole) -> 127.0.0.1:5335 (unbound)

Exit code is nonzero when a FAIL is reported. An unverifiable chain
(missing dig/drill or systemctl) is treated as a failure (fail closed).
EOF
            exit 0
            ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

if [[ -t 1 && $JSON -eq 0 ]]; then
    C_OK=$'\033[32m'
    C_WARN=$'\033[33m'
    C_FAIL=$'\033[31m'
    C_RESET=$'\033[0m'
else
    C_OK="" C_WARN="" C_FAIL="" C_RESET=""
fi

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

ok=0
warn=0
fail=0
json_rows=()

while IFS=$'\t' read -r level area message; do
    case "$level" in
        OK)   ok=$((ok + 1)) ;;
        WARN) warn=$((warn + 1)) ;;
        FAIL) fail=$((fail + 1)) ;;
    esac
    json_rows+=("$(printf '{"level":"%s","area":"%s","check":"%s"}' \
        "$(json_escape "$level")" "$(json_escape "$area")" "$(json_escape "$message")")")

    ((JSON)) && continue
    case "$level" in
        OK)   printf '%s%-5s%s %s\n' "$C_OK" "$level" "$C_RESET" "$message" ;;
        WARN) printf '%s%-5s%s %s\n' "$C_WARN" "$level" "$C_RESET" "$message" ;;
        FAIL) printf '%s%-5s%s %s\n' "$C_FAIL" "$level" "$C_RESET" "$message" ;;
    esac
done < <(dns_collect)

if ((JSON)); then
    printf '{"checks":[%s],"summary":{"ok":%d,"warn":%d,"fail":%d},"exit":%d}\n' \
        "$(IFS=,; printf '%s' "${json_rows[*]}")" \
        "$ok" "$warn" "$fail" "$((fail > 0 ? 1 : 0))"
else
    printf '\nSummary: %d OK, %d WARN, %d FAIL\n' "$ok" "$warn" "$fail"
    if ((fail > 0)); then
        dns_emergency_help
    fi
fi

((fail == 0)) || exit 1
