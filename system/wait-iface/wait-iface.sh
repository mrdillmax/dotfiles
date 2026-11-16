#!/bin/sh
# Wait until a network interface exists (used by pihole-FTL ordering).
# Usage: wait-iface.sh [interface]
#
# Without an argument the interface of the default route is used, falling back
# to the first non-loopback interface. This keeps the unit independent of the
# machine's NIC name (enp9s0, wlan0, ...).
set -eu

IFACE="${1:-}"
if [ -z "$IFACE" ]; then
    IFACE="$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')"
fi
if [ -z "$IFACE" ]; then
    for path in /sys/class/net/*; do
        name="${path##*/}"
        [ "$name" = "lo" ] && continue
        IFACE="$name"
        break
    done
fi
[ -n "$IFACE" ] || exit 1

for _ in $(seq 1 30); do
    [ -d "/sys/class/net/$IFACE" ] && exit 0
    sleep 1
done
exit 1
