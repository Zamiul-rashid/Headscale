#!/usr/bin/env bash
# Point hs.uni.home.arpa at <ip> (used by the DR drill), then reload dnsmasq in CT 802.
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
ip=${1:?usage: $0 <ip>}
ct_exec server1 "$CT_CAMPUS" "printf 'host-record=$HS_FQDN,$ip\nhost-record=$CA_FQDN,$IP_CAMPUS\n' > /etc/dnsmasq.d/hs-sim-records.conf && systemctl restart dnsmasq"
log "$HS_FQDN -> $ip"
