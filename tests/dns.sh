#!/usr/bin/env bash
# Tests for lib/dns.sh and the --system DNS gate. No real /etc file is written.
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

# make_stubs <dir>
make_stubs() {
    local dir="$1"

    cat >"$dir/systemctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    is-active)
        case "${2:-}" in
            pihole-FTL) [[ ${DNS_STUB_PIHOLE:-active} == active ]] && { echo active; exit 0; } ;;
            unbound)    [[ ${DNS_STUB_UNBOUND:-active} == active ]] && { echo active; exit 0; } ;;
        esac
        echo inactive
        exit 3
        ;;
    *) exit 0 ;;
esac
EOF

    cat >"$dir/dig" <<'EOF'
#!/usr/bin/env bash
port=53
while (($#)); do
    if [[ $1 == -p ]]; then
        port="$2"
        shift
    fi
    shift
done
if [[ ${DNS_STUB_FAIL_ALL:-} == 1 || ${DNS_STUB_FAIL_PORT:-} == "$port" ]]; then
    exit 0
fi
printf '198.51.100.7\n'
EOF

    chmod 0755 "$dir/systemctl" "$dir/dig"
}

# write_resolv <file> <ip>
write_resolv() {
    printf 'nameserver %s\n' "$2" >"$1"
}

# run_collect <stub> <resolv> [VAR=value ...]
run_collect() {
    local stub="$1" resolv="$2"
    shift 2
    (
        # shellcheck disable=SC2030,SC2031
        PATH="$stub:$PATH"
        DNS_RESOLV_CONF="$resolv"
        export PATH DNS_RESOLV_CONF
        local assignment
        for assignment in "$@"; do
            export "${assignment?}"
        done
        DOTFILES_DIR="$ROOT"
        # shellcheck source=lib/dns.sh
        source "$ROOT/lib/dns.sh"
        dns_collect
    )
}

run_chain_ok() {
    local stub="$1" resolv="$2"
    shift 2
    (
        # shellcheck disable=SC2030,SC2031
        PATH="$stub:$PATH"
        DNS_RESOLV_CONF="$resolv"
        export PATH DNS_RESOLV_CONF
        local assignment
        for assignment in "$@"; do
            export "${assignment?}"
        done
        DOTFILES_DIR="$ROOT"
        # shellcheck source=lib/dns.sh
        source "$ROOT/lib/dns.sh"
        dns_chain_ok
    )
}

base="$(mktemp -d)"
TMP_DIRS+=("$base")
stub="$base/stub"
mkdir -p "$stub"
make_stubs "$stub"
resolv_ok="$base/resolv.ok"
resolv_other="$base/resolv.other"
write_resolv "$resolv_ok" 127.0.0.1
write_resolv "$resolv_other" 1.1.1.1

# 1. Healthy chain.
out="$(run_collect "$stub" "$resolv_ok")"
if grep -q $'^OK\t' <<<"$out" && ! grep -q $'^FAIL\t' <<<"$out"; then
    pass "healthy chain reports no failures"
else
    fail "healthy chain was reported as broken"
    printf '%s\n' "$out"
fi
if run_chain_ok "$stub" "$resolv_ok"; then
    pass "dns_chain_ok accepts a healthy chain"
else
    fail "dns_chain_ok rejected a healthy chain"
fi

# 2. A non-loopback resolv.conf is a warning, not a failure.
out="$(run_collect "$stub" "$resolv_other")"
if grep -q $'^WARN\tresolv.conf' <<<"$out" && ! grep -q $'^FAIL\t' <<<"$out"; then
    pass "non-loopback resolv.conf is a warning"
else
    fail "non-loopback resolv.conf handling is wrong"
    printf '%s\n' "$out"
fi
if run_chain_ok "$stub" "$resolv_other"; then
    pass "a warning alone does not block installation"
else
    fail "a warning was treated as a failure"
fi

# 3. Inactive Pi-hole fails the chain.
out="$(run_collect "$stub" "$resolv_ok" DNS_STUB_PIHOLE=inactive)"
if grep -q $'^FAIL\tservices\tpihole-FTL' <<<"$out"; then
    pass "inactive Pi-hole is a failure"
else
    fail "inactive Pi-hole was not detected"
    printf '%s\n' "$out"
fi
if run_chain_ok "$stub" "$resolv_ok" DNS_STUB_PIHOLE=inactive; then
    fail "dns_chain_ok accepted an inactive Pi-hole"
else
    pass "dns_chain_ok rejects an inactive Pi-hole"
fi

# 4. A failing unbound query fails the chain.
out="$(run_collect "$stub" "$resolv_ok" DNS_STUB_FAIL_PORT=5335)"
if grep -q 'unbound cannot resolve' <<<"$out"; then
    pass "unbound probe failure is reported"
else
    fail "unbound probe failure was not detected"
    printf '%s\n' "$out"
fi
if run_chain_ok "$stub" "$resolv_ok" DNS_STUB_FAIL_PORT=5335; then
    fail "dns_chain_ok accepted a failing unbound probe"
else
    pass "dns_chain_ok rejects a failing unbound probe"
fi

# 5. A missing query tool fails closed.
tool_out="$(
    # shellcheck disable=SC2031,SC2016
    env PATH="$stub:$PATH" DNS_RESOLV_CONF="$resolv_ok" \
        DOTFILES_DIR="$ROOT" bash -c '
            source "$DOTFILES_DIR/lib/dns.sh"
            dns_tool() { return 1; }
            dns_collect
        '
)"
if grep -q 'fail closed' <<<"$tool_out"; then
    pass "missing dig/drill fails closed"
else
    fail "missing dig/drill did not fail closed"
    printf '%s\n' "$tool_out"
fi

# 6. DNS file classification.
dns_paths=(
    /etc/unbound/unbound.conf
    /etc/pihole/dnsmasq.conf
    /etc/pihole/pihole.toml
    /etc/NetworkManager/conf.d/dns.conf
    /etc/NetworkManager/conf.d/rc-manager.conf
    /etc/systemd/system/pihole-FTL.service.d/wait-iface.conf
)
non_dns_paths=(
    /etc/systemd/zram-generator.conf
    /etc/default/grub
    /etc/NetworkManager/conf.d/other.conf
)
classify="$(
    DOTFILES_DIR="$ROOT" bash -c '
        source "$DOTFILES_DIR/lib/dns.sh"
        for p in "$@"; do dns_is_dns_file "$p" && echo "dns $p" || echo "other $p"; done
    ' _ "${dns_paths[@]}" "${non_dns_paths[@]}"
)"
if ! grep -q '^other /etc/\(unbound\|pihole\)' <<<"$classify" \
    && ! grep -q '^other /etc/NetworkManager/conf.d/\(dns\|rc-manager\).conf' <<<"$classify" \
    && ! grep -q '^dns /etc/systemd/zram-generator.conf' <<<"$classify" \
    && ! grep -q '^dns /etc/default/grub' <<<"$classify" \
    && ! grep -q '^dns /etc/NetworkManager/conf.d/other.conf' <<<"$classify"; then
    pass "DNS file classification is correct"
else
    fail "DNS file classification is wrong"
    printf '%s\n' "$classify"
fi

# 7. The emergency instructions contain a usable resolver and a backup path.
help_out="$(
    DOTFILES_DIR="$ROOT" bash -c 'source "$DOTFILES_DIR/lib/dns.sh"; dns_emergency_help'
)"
if grep -q 'nameserver 1.1.1.1' <<<"$help_out" \
    && grep -q 'resolv.conf.before-dotfiles' <<<"$help_out"; then
    pass "emergency help shows both recovery paths"
else
    fail "emergency help is incomplete"
    printf '%s\n' "$help_out"
fi

# 8. --system dry-run skips only DNS files when the chain is broken.
#    No real file is written: DRY_RUN=1 and every confirmation is pre-answered.
home="$(mktemp -d)"
TMP_DIRS+=("$home")
system_out="$(
    (
        # shellcheck disable=SC2030,SC2031
        PATH="$stub:$PATH"
        DOTFILES_DIR="$ROOT"
        REAL_HOME="$home"
        BACKUP_DIR="$home/backups"
        TIMESTAMP="test"
        DRY_RUN=1
        ASSUME_YES=1
        DNS_RESOLV_CONF="$resolv_ok"
        DNS_STUB_PIHOLE=inactive
        DNS_STUB_FAIL_ALL=1
        export PATH DOTFILES_DIR REAL_HOME BACKUP_DIR TIMESTAMP DRY_RUN ASSUME_YES
        export DNS_RESOLV_CONF DNS_STUB_PIHOLE DNS_STUB_FAIL_ALL

        # shellcheck source=lib/common.sh
        source "$ROOT/lib/common.sh"
        # shellcheck source=lib/tui.sh
        source "$ROOT/lib/tui.sh"
        # shellcheck source=lib/dns.sh
        source "$ROOT/lib/dns.sh"
        # shellcheck source=lib/system.sh
        source "$ROOT/lib/system.sh"
        install_system_configs
    ) 2>&1
)"

if grep -q 'DNS chain is not healthy' <<<"$system_out"; then
    pass "--system warns about an unhealthy DNS chain"
else
    fail "--system did not warn about the DNS chain"
fi
if grep -q 'skipping DNS file /etc/unbound/unbound.conf' <<<"$system_out" \
    && grep -q 'skipping DNS file /etc/NetworkManager/conf.d/dns.conf' <<<"$system_out" \
    && grep -q 'skipping DNS file /etc/pihole/pihole.toml' <<<"$system_out"; then
    pass "--system skips DNS files only"
else
    fail "--system did not skip the expected DNS files"
    grep -n 'skipping DNS file' <<<"$system_out"
fi
if grep -q '\[dry-run\] install .*zram-generator.conf' <<<"$system_out" \
    && ! grep -q '\[dry-run\] install .*unbound.conf' <<<"$system_out"; then
    pass "--system still reviews non-DNS files"
else
    fail "--system stopped at the DNS files"
fi
if grep -q 'nameserver 1.1.1.1' <<<"$system_out"; then
    pass "--system prints the emergency command"
else
    fail "--system did not print the emergency command"
fi
if grep -q 'skipped [0-9]* DNS file(s)' <<<"$system_out"; then
    pass "--system reports how many DNS files were skipped"
else
    fail "--system did not summarize the skipped DNS files"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
