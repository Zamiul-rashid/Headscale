#!/usr/bin/env bash
# Disaster-recovery drill (proposal §5.6: RTO ≤ 2 h). The primary (CT 101) "dies"; a fresh CT 899 is
# built from the nightly restic backup, DNS is repointed, and every node must reconnect to it.
# Afterwards the primary is brought back and CT 899 is destroyed.   -> results/dr.csv
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh
online_on() { ct_exec server1 "$1" "headscale nodes list -o json" 2>/dev/null | jq '[(. // [])[] | select(.online // false)] | length'; }
total=$(online_on "$CT_HS")
ct_exec server1 "$CT_HS" "systemctl start hs-sim-backup.service"          # latest state into restic
back_to_primary() {
  campus/set-hs-ip.sh "$IP_HS" >/dev/null
  run_on server1 "pct start $CT_HS" >/dev/null 2>&1 || true
}
trap back_to_primary EXIT

t0=$(date +%s)
run_on server1 "pct stop $CT_HS"                                          # disaster
campus/set-hs-ip.sh "$IP_RESTORE" >/dev/null
headscale/install.sh "$CT_RESTORE" "$IP_RESTORE" --restore-from /backup/restic --task 10 >/dev/null 2>&1 \
  || { log "replacement server build failed"; exit 1; }
until [ "$(online_on "$CT_RESTORE")" -ge "$total" ] || [ $(( $(date +%s) - t0 )) -ge 7200 ]; do sleep 5; done
rto=$(( $(date +%s) - t0 )); back=$(online_on "$CT_RESTORE")
pass=no; [ "$back" -ge "$total" ] && [ "$rto" -le 7200 ] && pass=yes
mkdir -p results; printf 'rto_seconds,nodes_back,nodes_total,pass\n%s,%s,%s,%s\n' "$rto" "$back" "$total" "$pass" > results/dr.csv
log "DR: RTO ${rto}s, $back/$total nodes back on the restored server, pass=$pass"

# return to the primary, then remove the replacement
run_on server1 "pct stop $CT_RESTORE" >/dev/null
back_to_primary; trap - EXIT
t1=$(date +%s); until [ "$(online_on "$CT_HS")" -ge "$total" ] || [ $(( $(date +%s) - t1 )) -ge 300 ]; do sleep 5; done
[ "$(online_on "$CT_HS")" -ge "$total" ] || { log "nodes did not return to the primary"; pass=no; }
./teardown.sh --task 10 >/dev/null
[ "$pass" = yes ]
