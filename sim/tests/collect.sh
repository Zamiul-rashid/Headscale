#!/usr/bin/env bash
# One soak sample -> results/soak.csv (run hourly by the hs-sim-collect user timer).
# ts,nodes_total,nodes_online,hs_health,cert_hours_left,direct_share,enigma_tailnet_ok
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh
S=results/soak.csv; mkdir -p results
[ -s $S ] || echo "ts,nodes_total,nodes_online,hs_health,cert_hours_left,direct_share,enigma_tailnet_ok" > $S
J=$(hs nodes list -o json 2>/dev/null || echo null)
tot=$(jq '(. // []) | length' <<<"$J"); on=$(jq '[(. // [])[] | select(.online // false)] | length' <<<"$J")
health=fail
curl -sf -m 10 --cacert campus/root_ca.crt --resolve "$HS_FQDN:443:$IP_HS" "https://$HS_FQDN/health" >/dev/null && health=ok
end=$(echo | timeout 10 openssl s_client -connect "$IP_HS:443" -servername "$HS_FQDN" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
hours=$( [ -n "$end" ] && echo $(( ( $(date -d "$end" +%s) - $(date +%s) ) / 36 )) | awk '{printf "%.1f", $1/100}' || echo -1)
tests/connectivity_matrix.sh soak-latest >/dev/null 2>&1
share=$(awk -F, 'NR>1 && $3=="direct"{d++} NR>1 && $3 ~ /^derp/{r++} END{printf "%.2f", (d+r)?d/(d+r):0}' results/connectivity-soak-latest.csv 2>/dev/null || echo 0)
same() { [ "$(jq -r '.BackendState + " " + .CurrentTailnet.Name' <<<"$1")" = "$(jq -r '.BackendState + " " + .CurrentTailnet.Name' "$2")" ]; }
ok=0; same "$(tailscale status --json)" ledger/baseline/enigma-tailscale.json \
  && same "$(run_on laptop 'tailscale status --json')" ledger/baseline/laptop-tailscale.json && ok=1
echo "$(date -Is),$tot,$on,$health,$hours,$share,$ok" >> $S
