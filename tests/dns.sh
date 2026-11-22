#!/usr/bin/env bash
# DNS configuration behavior: Pi-hole settings via the official CLI, adlists in
# the gravity database, and an unbound drop-in that rolls back when invalid.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# shellcheck source=/dev/null
source "$ROOT/lib/dns.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/dns_config.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [[ $(dns_unbound_conf_path) == /etc/unbound/unbound.conf.d/pi-hole.conf ]]; then
    pass "unbound drop-in lives under conf.d"
else
    fail "unexpected unbound drop-in path: $(dns_unbound_conf_path)"
fi

UNBOUND_PI_HOLE_CONF="$work/pi-hole.conf"
export UNBOUND_PI_HOLE_CONF
if [[ $(dns_unbound_conf_path) == "$work/pi-hole.conf" ]]; then
    pass "unbound drop-in path can be overridden"
else
    fail "UNBOUND_PI_HOLE_CONF was ignored"
fi

# dig exits 9 on REFUSED; under set -e and an ERR trap that must not abort.
printf '#!/bin/sh\nexit 9\n' >"$work/dig"
chmod +x "$work/dig"
if (
    set -euo pipefail
    trap 'echo err-trap >&2; exit 99' ERR
    PATH="$work:$PATH"
    answer="$(dns_query 127.0.0.1 53 example.test || true)"
    [[ -z $answer ]]
); then
    pass "dns_query survives dig exit 9"
else
    fail "dig exit 9 escaped dns_query"
fi

# 1. Pi-hole settings go through pihole-FTL --config.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/ftl.log"\n' "$work" >"$work/pihole-FTL"
chmod +x "$work/pihole-FTL"
PIHOLE_FTL_BIN="$work/pihole-FTL"
export PIHOLE_FTL_BIN

dns_pihole_apply
dns_pihole_apply

if grep -q -- '--config dns.upstreams \["127.0.0.1#5335"\]' "$work/ftl.log"; then
    pass "upstream points at unbound on 5335"
else
    fail "upstream is not set to 127.0.0.1#5335"
fi
if grep -q -- '--config dns.port 53' "$work/ftl.log"; then
    pass "Pi-hole listens on port 53"
else
    fail "Pi-hole port is not set"
fi
if grep -q -- '--config misc.etc_dnsmasq_d true' "$work/ftl.log"; then
    pass "dnsmasq drop-ins are enabled"
else
    fail "dnsmasq drop-ins are not enabled"
fi
head -n 3 "$work/ftl.log" >"$work/first"
dns_pihole_apply
tail -n 3 "$work/ftl.log" >"$work/last"
if cmp -s "$work/first" "$work/last"; then
    pass "apply is repeatable"
else
    fail "repeated apply issued different commands"
fi

# 2. Adlists are inserted once, with a real sqlite database.
db="$work/gravity.db"
sqlite3 "$db" 'CREATE TABLE adlist (id INTEGER PRIMARY KEY AUTOINCREMENT, address TEXT NOT NULL UNIQUE, enabled BOOLEAN NOT NULL DEFAULT 1, comment TEXT);'
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/pihole.log"\n' "$work" >"$work/pihole"
chmod +x "$work/pihole"
PIHOLE_BIN="$work/pihole"
DNS_SQLITE_BIN=sqlite3
export PIHOLE_BIN DNS_SQLITE_BIN
cat >"$work/adlists.txt" <<'EOF'
# One URL per line.
https://example.test/one.txt
https://example.test/two.txt
EOF

dns_adlists_sync "$work/adlists.txt" "$db"
dns_adlists_sync "$work/adlists.txt" "$db"

rows="$(sqlite3 "$db" 'SELECT count(*) FROM adlist;')"
if [[ $rows == 2 ]]; then
    pass "adlists inserted once, not duplicated"
else
    fail "expected 2 adlists, found $rows"
fi
if [[ $(grep -c -- '-g' "$work/pihole.log") == 1 ]]; then
    pass "gravity rebuild runs only when the list changed"
else
    fail "gravity rebuild count is wrong: $(cat "$work/pihole.log")"
fi

# 3. Unbound drop-in: a failing check restores the previous file.
printf 'server:\n    port: 5335\n' >"$work/pi-hole.conf"
printf 'server:\n    port: 53\n' >"$work/unbound.conf"
printf '#!/bin/sh\nexit 1\n' >"$work/unbound-checkconf"
chmod +x "$work/unbound-checkconf"
UNBOUND_CHECKCONF="$work/unbound-checkconf"
export UNBOUND_CHECKCONF

if dns_write_unbound "$work/pi-hole.conf" "$work/unbound.conf" >/dev/null 2>&1; then
    fail "invalid unbound config was accepted"
else
    pass "invalid unbound config is rejected"
fi
if grep -q 'port: 53' "$work/unbound.conf"; then
    pass "previous unbound config is restored"
else
    fail "previous unbound config was lost"
fi

# 4. A passing check installs the drop-in.
printf '#!/bin/sh\nexit 0\n' >"$work/unbound-checkconf"
chmod +x "$work/unbound-checkconf"
dns_write_unbound "$work/pi-hole.conf" "$work/unbound.conf" >/dev/null 2>&1 || true
if grep -q 'port: 5335' "$work/unbound.conf"; then
    pass "valid unbound config is installed"
else
    fail "valid unbound config was not installed"
fi

# 5. Root hints are validated before they replace the live file.
# shellcheck disable=SC2016 # $out is expanded by the stub, not by this shell.
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do case $1 in -o) out=$2; shift 2 ;; *) shift ;; esac; done\necho "ERROR" >"$out"\n' >"$work/curl-bad"
chmod +x "$work/curl-bad"
printf '; old hints\n' >"$work/root.hints"
CURL_BIN="$work/curl-bad"
export CURL_BIN
if dns_root_hints_install "https://example.test/named.root" "$work/root.hints" >/dev/null 2>&1; then
    fail "invalid root hints were accepted"
else
    pass "invalid root hints are rejected"
fi
if grep -q 'old hints' "$work/root.hints"; then
    pass "previous root hints survive a bad download"
else
    fail "previous root hints were overwritten"
fi

# shellcheck disable=SC2016 # $out is expanded by the stub, not by this shell.
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do case $1 in -o) out=$2; shift 2 ;; *) shift ;; esac; done\necho ".                        3600000  NS    A.ROOT-SERVERS.NET." >"$out"\n' >"$work/curl-good"
chmod +x "$work/curl-good"
CURL_BIN="$work/curl-good"
export CURL_BIN
dns_root_hints_install "https://example.test/named.root" "$work/root.hints" >/dev/null 2>&1 || true
if grep -q 'A.ROOT-SERVERS.NET' "$work/root.hints"; then
    pass "valid root hints are installed"
else
    fail "valid root hints were not installed"
fi

# 6. The system map installs drop-ins and never the stock/generated files.
map="$(DOTFILES_DIR="$ROOT" DRY_RUN=1 bash -c '
    unset UNBOUND_PI_HOLE_CONF
    SYSTEM_COMPONENTS=()
    source "$DOTFILES_DIR/lib/system.sh"
    system_file_map
' 2>&1)"
if grep -q '/etc/unbound/unbound.conf.d/pi-hole.conf' <<<"$map"; then
    pass "map installs the unbound drop-in"
else
    fail "map does not install the unbound drop-in"
fi
if grep -q '/etc/dnsmasq.d/dotfiles.conf' <<<"$map"; then
    pass "map installs the dnsmasq drop-in"
else
    fail "map does not install the dnsmasq drop-in"
fi
if grep -Eq '/etc/unbound/unbound\.conf[[:space:]]|/etc/pihole/dnsmasq\.conf' <<<"$map"; then
    fail "map still overwrites a stock or generated file"
else
    pass "map leaves the stock and generated files alone"
fi
if grep -q 'unmapped system file' <<<"$map"; then
    fail "map has an unmapped system file"
else
    pass "every system file is mapped or skipped on purpose"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
