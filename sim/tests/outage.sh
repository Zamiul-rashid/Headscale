#!/usr/bin/env bash
# Control-plane outage + server reboot (proposal Phase 3).
#   tests/outage.sh [--minutes 30]  -> results/outage.csv ; exit 0 iff all pass
# During the outage: existing tailnet traffic keeps flowing; a new enrolment fails cleanly; after it, enrolment works.
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh
min=30; [ "${1:-}" = --minutes ] && min=$2
mkdir -p results; echo "case,metric,value,pass" > results/outage.csv
fail=0; rec() { echo "$1,$2,$3,$4" >> results/outage.csv; [ "$4" = no ] && fail=1; log "$1 $2=$3 pass=$4"; }
CF="-f clients/enigma/compose.yaml --profile tmp"; export TS_VERSION
health() { curl -sf -m 5 --cacert campus/root_ca.crt --resolve "$HS_FQDN:443:$IP_HS" "https://$HS_FQDN/health" >/dev/null; }
online_count() { hs nodes list -o json 2>/dev/null | jq '[(. // [])[] | select(.online // false)] | length'; }
tmp_state() { docker exec hs-sim-tmp tailscale status --json 2>/dev/null | jq -r '.BackendState // empty'; }
tmp_clean() { docker compose $CF rm -sfv hs-sim-tmp >/dev/null 2>&1; local id; id=$(hs nodes list -o json | jq -r '(. // [])[] | select(.given_name=="hs-sim-tmp") | .id'); [ -n "$id" ] && hs nodes delete -i "$id" --force >/dev/null; true; }
trap 'ct_exec server1 "$CT_HS" "systemctl start headscale" >/dev/null 2>&1; tmp_clean' EXIT

before=$(online_count)
key=$(clients/mkkey.sh bob)                         # minted while the server is up
# two probes: a DIRECT pair (proposal criterion) and a RELAYED pair (the campus DERP is embedded in headscale)
deadline=$(( min*60 + 90 ))
ping_start() { node_exec "$1" "ping -i 2 -w $deadline $(node_ip "$2") > /tmp/hs-sim-outage-ping.txt 2>&1 &"; }
ping_loss()  { local t0=$(date +%s) l; until l=$(node_exec "$1" "cat /tmp/hs-sim-outage-ping.txt" | sed -nE 's/.* ([0-9.]+)% packet loss.*/\1/p'); [ -n "$l" ] || [ $(( $(date +%s) - t0 )) -ge $(( deadline + 60 )) ]; do sleep 5; done; echo "${l:-none}"; }
path_of() { node_exec "$1" "tailscale ping --c 10 --timeout 3s $(node_ip "$2")" 2>&1 | grep 'pong from' | tail -1 | sed -E 's/.* via ([^ ]+) in .*/\1/'; }
rec setup direct-pair-path "$(path_of lab-b-01 lab-b-02)" recorded
rec setup relayed-pair-path "$(path_of bob-enigma lab-b-01)" recorded
ping_start lab-b-01 lab-b-02      # direct, same room
ping_start bob-enigma lab-b-01    # relayed via campus DERP
sleep 5
ct_exec server1 "$CT_HS" "systemctl stop headscale"
log "headscale stopped for $min min"
KEY_TMP=$key docker compose $CF up -d hs-sim-tmp >/dev/null 2>&1; sleep 60
st=$(tmp_state); [ "$st" != Running ] && rec outage new-enrolment-blocked "${st:-exited}" yes || rec outage new-enrolment-blocked "$st" no
docker compose $CF rm -sfv hs-sim-tmp >/dev/null 2>&1
sleep $(( min*60 - 65 > 0 ? min*60 - 65 : 0 ))
ct_exec server1 "$CT_HS" "systemctl start headscale"
t0=$(date +%s); until health || [ $(( $(date +%s) - t0 )) -ge 120 ]; do sleep 2; done
KEY_TMP=$key docker compose $CF up -d hs-sim-tmp >/dev/null 2>&1
t1=$(date +%s); until [ "$(tmp_state)" = Running ] || [ $(( $(date +%s) - t1 )) -ge 90 ]; do sleep 3; done
[ "$(tmp_state)" = Running ] && rec recovery enrolment-after-restart ok yes || rec recovery enrolment-after-restart failed no
tmp_clean
loss=$(ping_loss lab-b-01)
awk -v l="$loss" 'BEGIN{exit !(l != "none" && l<=1)}' && rec outage direct-session-loss-pct "$loss" yes || rec outage direct-session-loss-pct "$loss" no
rec outage relayed-session-loss-pct "$(ping_loss bob-enigma)" recorded   # finding, not a pass/fail criterion

# server (CT) reboot
run_on server1 "pct reboot $CT_HS"
t0=$(date +%s); sleep 5; until health || [ $(( $(date +%s) - t0 )) -ge 120 ]; do sleep 2; done
h=$(( $(date +%s) - t0 )); [ "$h" -lt 120 ] && rec reboot health-seconds "$h" yes || rec reboot health-seconds "$h" no
until [ "$(online_count)" -ge "$before" ] || [ $(( $(date +%s) - t0 )) -ge 180 ]; do sleep 3; done
n=$(online_count); [ "$n" -ge "$before" ] && rec reboot nodes-online "$n/$before" yes || rec reboot nodes-online "$n/$before" no
exit $fail
