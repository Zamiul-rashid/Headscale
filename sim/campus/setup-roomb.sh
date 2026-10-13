#!/usr/bin/env bash
# Task 3: isolated bridge vmbr2, campus-fw CT 803 (NAT + mode switch), lab room B CTs 804/805.
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
N=/nodes/$PVE1_NODE/network

if ! run_on server1 "ip link show vmbr2" >/dev/null 2>&1; then
  ledger_add 3 server1 bridge vmbr2 "if pvesh get $N/vmbr2 >/dev/null 2>&1; then pvesh delete $N/vmbr2; fi; pvesh set $N"
  run_on server1 "pvesh create $N --iface vmbr2 --type bridge --autostart 1 --comments 'hs-sim lab room B (no uplink)' && pvesh set $N"
fi

hosts/make-ct.sh server1 "$CT_FW" campus-fw vmbr0 "$IP_FW/24" "$LAN_GW" 1 256 --nic2 "vmbr2,$ROOMB_GW/24" --task 3
F() { ct_exec server1 "$CT_FW" "$*"; }
F "export DEBIAN_FRONTEND=noninteractive; apt-get -qq update && apt-get -qq install -y nftables conntrack >/dev/null"
F "echo net.ipv4.ip_forward=1 > /etc/sysctl.d/99-hs-sim.conf && sysctl -q -p /etc/sysctl.d/99-hs-sim.conf"
F "mkdir -p /etc/nftables.d; test -f /etc/nftables.d/mode.nft || printf '# mode: open\n' > /etc/nftables.d/mode.nft"
run_on server1 "cat > /tmp/hs-sim-nft.conf" < campus/nftables.conf
run_on server1 "pct push $CT_FW /tmp/hs-sim-nft.conf /etc/nftables.conf && rm /tmp/hs-sim-nft.conf"
mode=$(campus/fw-mode.sh status 2>/dev/null || true)
campus/fw-mode.sh "${mode:-open}"          # rewrites mode.nft, then loads the full ruleset
F "systemctl enable -q nftables"

for pair in "$CT_LABB1:lab-b-01:$IP_LABB1" "$CT_LABB2:lab-b-02:$IP_LABB2"; do
  IFS=: read -r id name ip <<<"$pair"
  hosts/make-ct.sh server1 "$id" "$name" vmbr2 "$ip/24" "$ROOMB_GW" 1 512 --task 3
  ct_exec server1 "$id" "export DEBIAN_FRONTEND=noninteractive; apt-get -qq update && apt-get -qq install -y dnsutils curl nmap netcat-openbsd iperf3 socat jq >/dev/null"
done
log "room B ready"
