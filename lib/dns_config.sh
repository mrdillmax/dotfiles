# shellcheck shell=bash
# Pi-hole + unbound configuration helpers.
#
# Everything here is idempotent: the Pi-hole options are set through the
# official CLI, adlists are inserted only when missing, and the unbound drop-in
# is validated before it replaces a working file.
[[ -n ${_DOTFILES_DNS_CONFIG:-} ]] && return 0
_DOTFILES_DNS_CONFIG=1

# Use the installer's `run` when it exists (so --dry-run stays safe), otherwise
# call the command directly so the helpers stay testable on their own.
dns_cmd() {
    if declare -F run >/dev/null 2>&1; then
        run "$@"
    else
        "$@"
    fi
}

# The installer provides these; tests source this file on its own.
if ! declare -F warn >/dev/null 2>&1; then
    warn() { printf 'dns: %s\n' "$*" >&2; }
fi
if ! declare -F ok >/dev/null 2>&1; then
    ok() { printf 'dns: %s\n' "$*"; }
fi
if ! declare -F log >/dev/null 2>&1; then
    log() { printf '%s\n' "$*"; }
fi
: "${C_DIM:=}"
: "${C_RESET:=}"

# Single source of truth for the drop-in path. The stock unbound.conf stays
# untouched; every setting this repository owns lives in this one file.
dns_unbound_conf_path() {
    printf '%s\n' "${UNBOUND_PI_HOLE_CONF:-/etc/unbound/unbound.conf.d/pi-hole.conf}"
}

# Upstream chain: Pi-hole listens on 53 and forwards to unbound on 5335.
# misc.etc_dnsmasq_d lets FTL read /etc/dnsmasq.d without editing the generated
# /etc/pihole/dnsmasq.conf.
dns_pihole_apply() {
    local ftl="${PIHOLE_FTL_BIN:-pihole-FTL}"

    dns_cmd "$ftl" --config dns.upstreams '["127.0.0.1#5335"]'
    dns_cmd "$ftl" --config dns.port 53
    dns_cmd "$ftl" --config misc.etc_dnsmasq_d true
}

# Insert every URL from FILE into the gravity database when it is not there
# yet. One `pihole -g` runs only when something was added.
dns_adlists_sync() {
    local file="$1"
    local db="${2:-${DNS_GRAVITY_DB:-/etc/pihole/gravity.db}}"
    local pihole="${PIHOLE_BIN:-pihole}"
    local url sql changed
    local -a sqlite_cmd

    if [[ ! -r $file ]]; then
        warn "adlist file not found: $file"
        return 1
    fi

    if [[ -n ${DNS_SQLITE_BIN:-} ]]; then
        sqlite_cmd=("$DNS_SQLITE_BIN")
    else
        sqlite_cmd=("${PIHOLE_FTL_BIN:-pihole-FTL}" sqlite3)
    fi

    if [[ ! -e $db ]] && (( ! ${DRY_RUN:-0} )); then
        warn "gravity database not found: $db (install Pi-hole first)"
        return 1
    fi

    sql=""
    while IFS= read -r url; do
        [[ -z $url || $url == \#* ]] && continue
        url="${url//\'/\'\'}"
        sql+="INSERT INTO adlist (address, enabled, comment) SELECT '$url', 1, 'dotfiles' WHERE NOT EXISTS (SELECT 1 FROM adlist WHERE address = '$url');"$'\n'
    done <"$file"
    [[ -n $sql ]] || return 0
    sql+='SELECT total_changes();'

    if (( ${DRY_RUN:-0} )); then
        log "${C_DIM}[dry-run]${C_RESET} add adlists from $file to $db"
        return 0
    fi

    changed="$(dns_cmd "${sqlite_cmd[@]}" "$db" "$sql" | tail -n1)"
    changed="${changed//[!0-9]/}"
    if [[ -z $changed || $changed == 0 ]]; then
        ok "adlists already present"
        return 0
    fi

    ok "added $changed adlist(s)"
    dns_cmd "$pihole" -g
}

# Write the unbound drop-in, check it, and put the old file back on failure.
dns_write_unbound() {
    local src="$1" dst="$2" prev="" bin
    bin="${UNBOUND_CHECKCONF:-unbound-checkconf}"

    if (( ${DRY_RUN:-0} )); then
        log "${C_DIM}[dry-run]${C_RESET} install $src -> $dst"
        return 0
    fi

    if [[ -e $dst ]]; then
        prev="$(mktemp)"
        cp -a -- "$dst" "$prev"
    fi

    mkdir -p -- "$(dirname -- "$dst")"
    install -m 0644 -- "$src" "$dst"

    if [[ -x $bin ]] || command -v "$bin" >/dev/null 2>&1; then
        if ! "$bin" "$dst" >/dev/null 2>&1; then
            warn "unbound-checkconf rejected $dst; restoring the previous file"
            if [[ -n $prev ]]; then
                cp -a -- "$prev" "$dst"
            else
                rm -f -- "$dst"
            fi
            [[ -n $prev ]] && rm -f -- "$prev"
            return 1
        fi
    else
        warn "unbound-checkconf not found; $dst was not validated"
    fi

    [[ -n $prev ]] && rm -f -- "$prev"
    ok "installed $dst"
}

# Download the root server hints, reject an obviously broken file, then install
# it. The previous hints stay in place when the download fails.
dns_root_hints_install() {
    local url="$1"
    local dst="${2:-/etc/unbound/root.hints}"
    local curl="${CURL_BIN:-curl}"
    local tmp

    if (( ${DRY_RUN:-0} )); then
        log "${C_DIM}[dry-run]${C_RESET} download root hints: $url -> $dst"
        return 0
    fi

    tmp="$(mktemp)"
    if ! "$curl" -fsSL --max-time 30 --retry 2 -o "$tmp" "$url"; then
        warn "could not download root hints from $url"
        rm -f -- "$tmp"
        return 1
    fi
    if ! grep -q 'ROOT-SERVERS\.NET\.' "$tmp"; then
        warn "downloaded root hints look invalid; keeping the current file"
        rm -f -- "$tmp"
        return 1
    fi

    mkdir -p -- "$(dirname -- "$dst")"
    install -m 0644 -- "$tmp" "$dst"
    rm -f -- "$tmp"
    ok "root hints updated: $dst"
}
