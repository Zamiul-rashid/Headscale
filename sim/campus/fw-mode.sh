#!/usr/bin/env bash
# Switch the campus firewall policy for lab room B.
#   campus/fw-mode.sh open          all outbound allowed (NAT only)
#   campus/fw-mode.sh udp-blocked   outbound UDP dropped except DNS to the campus resolver
#   campus/fw-mode.sh status
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
F=/etc/nftables.d/mode.nft
case ${1:-} in
  status) ct_exec server1 "$CT_FW" "sed -n 's/^# mode: //p' $F" ;;
  open)   rules="" ;;
  udp-blocked) rules="    ip daddr $IP_CAMPUS udp dport 53 accept\n    meta l4proto udp drop" ;;
  *) die "usage: $0 open|udp-blocked|status" ;;
esac
[ "${1}" = status ] && exit 0
ct_exec server1 "$CT_FW" "printf '# mode: $1\ntable inet hs_sim_fw {\n  chain mode {\n$rules\n  }\n}\n' > $F.tmp && mv $F.tmp $F && nft -f /etc/nftables.conf && conntrack -F 2>/dev/null"   # drop flows opened under the old mode
log "campus-fw mode: $1"
