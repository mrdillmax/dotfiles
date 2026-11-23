# shellcheck shell=bash
# Read-only DNS chain checks shared by --system, --dns-check and tests.
#
# The expected chain is:
#   /etc/resolv.conf -> 127.0.0.1:53 (Pi-hole) -> 127.0.0.1:5335 (unbound)
#
# dns_collect prints one "LEVEL<TAB>AREA<TAB>MESSAGE" line per check.
# dns_chain_ok returns 0 only when no FAIL was reported (fail closed: an
# unverifiable chain is treated as unhealthy).
[[ -n ${_DOTFILES_DNS:-} ]] && return 0
_DOTFILES_DNS=1

DNS_RESOLV_CONF="${DNS_RESOLV_CONF:-/etc/resolv.conf}"
DNS_PIHOLE_SERVER="${DNS_PIHOLE_SERVER:-127.0.0.1}"
DNS_PIHOLE_PORT="${DNS_PIHOLE_PORT:-53}"
DNS_UNBOUND_SERVER="${DNS_UNBOUND_SERVER:-127.0.0.1}"
DNS_UNBOUND_PORT="${DNS_UNBOUND_PORT:-5335}"
DNS_PROBE_NAME="${DNS_PROBE_NAME:-archlinux.org}"

dns_tool() {
    command -v dig 2>/dev/null || command -v drill 2>/dev/null
}

dns_query() {
    local server="$1" port="$2" name="$3" tool
    tool="$(dns_tool)" || return 1

    # dig exits 9 when the server answers REFUSED/NXDOMAIN or is unreachable.
    # That is a normal probe result here, not an installer error, so every
    # branch ends with `|| true` and the function always reports success.
    case "${tool##*/}" in
        dig)
            dig +short +time=2 +tries=1 -p "$port" "$name" "@$server" 2>/dev/null \
                | awk 'NF {print; exit}' || true
            ;;
        drill)
            drill -p "$port" "$name" "@$server" 2>/dev/null \
                | awk '/IN[[:space:]]+A[[:space:]]/ {print $NF; exit}' || true
            ;;
        *) return 1 ;;
    esac
    return 0
}

dns_resolv_nameservers() {
    awk '$1 == "nameserver" {print $2}' "$DNS_RESOLV_CONF" 2>/dev/null | tr '\n' ' '
}

dns_collect() {
    local nameservers state answer entry server port label tool

    nameservers="$(dns_resolv_nameservers)"
    if [[ -z $nameservers ]]; then
        printf 'FAIL\tresolv.conf\t%s is missing or has no nameserver\n' "$DNS_RESOLV_CONF"
    elif [[ $nameservers == *127.0.0.1* ]]; then
        printf 'OK\tresolv.conf\tpoints to the local resolver (%s)\n' "$nameservers"
    else
        printf 'WARN\tresolv.conf\tdoes not use 127.0.0.1 (found: %s)\n' "$nameservers"
    fi

    tool="$(dns_tool || true)"
    if [[ -z $tool ]]; then
        printf 'WARN\tquery tool\tneither dig nor drill is installed\n'
        printf 'FAIL\tprobe\tcannot verify the resolver chain (fail closed)\n'
        return 0
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        printf 'WARN\tservices\tsystemctl is not available\n'
        printf 'FAIL\tservices\tcannot verify pihole-FTL and unbound (fail closed)\n'
    else
        for service in pihole-FTL unbound; do
            state="$(systemctl is-active "$service" 2>/dev/null || true)"
            if [[ $state == active ]]; then
                printf 'OK\tservices\t%s is active\n' "$service"
            else
                printf 'FAIL\tservices\t%s is %s\n' "$service" "${state:-unknown}"
            fi
        done
    fi

    for entry in \
        "$DNS_PIHOLE_SERVER:$DNS_PIHOLE_PORT:Pi-hole" \
        "$DNS_UNBOUND_SERVER:$DNS_UNBOUND_PORT:unbound"; do
        IFS=: read -r server port label <<<"$entry"
        answer="$(dns_query "$server" "$port" "$DNS_PROBE_NAME" || true)"
        if [[ -n $answer ]]; then
            printf 'OK\tprobe\t%s resolves %s via %s:%s\n' \
                "$label" "$DNS_PROBE_NAME" "$server" "$port"
        else
            printf 'FAIL\tprobe\t%s cannot resolve %s via %s:%s\n' \
                "$label" "$DNS_PROBE_NAME" "$server" "$port"
        fi
    done
}

# Returns 0 when the chain is healthy, 1 otherwise.
dns_chain_ok() {
    local level _rest

    while IFS=$'\t' read -r level _rest; do
        [[ $level == FAIL ]] && return 1
    done < <(dns_collect)

    return 0
}

dns_failures() {
    awk -F'\t' '$1 == "FAIL" {print $2 ": " $3}' < <(dns_collect)
}

dns_warnings() {
    awk -F'\t' '$1 == "WARN" {print $2 ": " $3}' < <(dns_collect)
}

# Paths that must not be replaced while the resolver chain is unhealthy.
dns_is_dns_file() {
    case "$1" in
        /etc/unbound/*|\
        /etc/dnsmasq.d/*|\
        /etc/pihole/*|\
        /etc/NetworkManager/conf.d/dns.conf|\
        /etc/NetworkManager/conf.d/rc-manager.conf|\
        /etc/resolv.conf|\
        /etc/systemd/system/pihole-FTL.service.d/*)
            return 0
            ;;
    esac
    return 1
}

dns_emergency_help() {
    cat <<'EOF'

DNS safety net:
  Only DNS files will be skipped; every other system file is still reviewed.
  If DNS breaks while you work, restore a resolver immediately in another terminal:

    printf 'nameserver 1.1.1.1\n' | sudo tee /etc/resolv.conf

  Or restore the backup made before this installation:

    sudo cp -a /etc/resolv.conf.before-dotfiles /etc/resolv.conf

  Then fix the chain and re-run: sudo ./install.sh --system
EOF
}
