#!/usr/bin/env bash
# Simulated off-campus client "alice-home" on enigma.
#   clients/offcampus.sh up [strict|wg-allowed]   start/enrol it, add home-ISP latency, apply the egress filter
#   clients/offcampus.sh mode strict|wg-allowed   strict: internet + 192.168.1.201 tcp/443, udp/3478 only
#                                                 wg-allowed: also UDP to campus LANs (campus lets WireGuard in)
#   clients/offcampus.sh status | down
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
export TS_VERSION
NET=172.30.99.0/24 CH=HS-SIM-HOME
CF="-f clients/enigma/compose.yaml --profile home"
ipt() { sudo -n iptables "$@"; }
apply_mode() {
  ipt -N $CH 2>/dev/null || ipt -F $CH
  ipt -C DOCKER-USER -s $NET -j $CH 2>/dev/null || ipt -I DOCKER-USER -s $NET -j $CH
  ipt -A $CH -d "$IP_HS" -p tcp --dport 443 -j RETURN
  ipt -A $CH -d "$IP_HS" -p udp --dport 3478 -j RETURN
  [ "$1" = wg-allowed ] && ipt -A $CH -d 192.168.0.0/16 -p udp -j RETURN
  for n in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do ipt -A $CH -d $n -j DROP; done
  ipt -A $CH -m comment --comment "hs-sim mode: $1" -j RETURN
  log "off-campus mode: $1"
}
case ${1:-} in
  up)
    ledger_add 12 enigma iptables-chain $CH "sudo iptables -D DOCKER-USER -s $NET -j $CH 2>/dev/null; sudo iptables -F $CH 2>/dev/null; sudo iptables -X $CH 2>/dev/null; true"
    apply_mode "${2:-strict}"
    if ! docker ps -q --filter name=^hs-sim-alice-home\$ | grep -q .; then
      KEY_ALICE_HOME=$(clients/mkkey.sh alice) docker compose $CF up -d --no-build hs-sim-alice-home >/dev/null 2>&1
      for _ in $(seq 45); do docker exec hs-sim-alice-home tailscale status --json 2>/dev/null | jq -e '.BackendState=="Running"' >/dev/null && break; sleep 2; done
    fi
    docker exec hs-sim-alice-home tc qdisc replace dev eth0 root netem delay 30ms 5ms
    log "alice-home up" ;;
  mode)   apply_mode "${2:?strict|wg-allowed}" ;;
  status) ipt -S $CH 2>/dev/null | sed -nE 's/.*hs-sim mode: ([a-z-]+).*/\1/p' ;;
  down)
    docker compose $CF rm -sfv hs-sim-alice-home >/dev/null 2>&1 || true
    id=$(hs nodes list -o json | jq -r '(. // [])[] | select(.given_name=="alice-home") | .id'); [ -n "$id" ] && hs nodes delete -i "$id" --force >/dev/null
    ipt -D DOCKER-USER -s $NET -j $CH 2>/dev/null; ipt -F $CH 2>/dev/null; ipt -X $CH 2>/dev/null; true ;;
  *) die "usage: $0 up [mode] | mode strict|wg-allowed | status | down" ;;
esac
