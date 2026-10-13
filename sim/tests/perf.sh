#!/usr/bin/env bash
# LAN vs tailnet throughput (iperf3, 10 s) and latency (20 pings) for fixed node pairs.
#   tests/perf.sh <label> [--src <node>]   -> results/perf-<label>.csv
# iperf3 runs on the lab PCs' VNC slot (5900), which the ACL lets researchers reach.
# A pair whose destination has no LAN path from the source (room B is behind NAT) gets lan_* = NA.
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh
label=${1:?usage: $0 <label> [--src node]}; only=
[ "${2:-}" = --src ] && only=$3
# pair-name  src  dst  dst-LAN-ip(or -)
PAIRS="same-room lab-b-01 lab-b-02 $IP_LABB2
cross-subnet bob-enigma lab-a-01 $IP_LABA1
laptop alice-laptop lab-a-01 $IP_LABA1
laptop-roomb alice-laptop lab-b-01 -
home alice-home lab-a-01 -"
online=$(hs nodes list -o json | jq -r '(. // [])[] | select(.online // false) | .given_name')
mbps() { node_exec "$1" "iperf3 -c $2 -p 5900 -t 10 -J" 2>/dev/null | jq -r '.end.sum_received.bits_per_second / 1e6 | . * 10 | round / 10' 2>/dev/null; }
rtt()  { node_exec "$1" "ping -c 20 -i 0.2 -q $2" 2>/dev/null | sed -nE 's#.*= [0-9.]+/([0-9.]+)/.*#\1#p'; }
out=results/perf-$label.csv; mkdir -p results
echo "pair,lan_mbps,ts_mbps,ratio,lan_ms,ts_ms,added_ms" > "$out"
while read -r pair s d lan <&3; do
  [ -n "$only" ] && [ "$s" != "$only" ] && continue
  grep -qxF "$s" <<<"$online" && grep -qxF "$d" <<<"$online" || { log "skip $pair: $s or $d not online"; continue; }
  tsip=$(node_ip "$d"); tm=$(mbps "$s" "$tsip"); tl=$(rtt "$s" "$tsip")
  if [ "$lan" = - ]; then lm=NA ll=NA ratio=NA add=NA; else
    lm=$(mbps "$s" "$lan"); ll=$(rtt "$s" "$lan")
    ratio=$(awk -v a="$tm" -v b="$lm" 'BEGIN{printf "%.2f", (b>0)?a/b:0}')
    add=$(awk -v a="$tl" -v b="$ll" 'BEGIN{printf "%.3f", a-b}')
  fi
  echo "$pair,$lm,$tm,$ratio,$ll,$tl,$add" >> "$out"
done 3<<<"$PAIRS"
log "$out written"
