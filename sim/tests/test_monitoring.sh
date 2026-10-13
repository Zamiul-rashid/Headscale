#!/usr/bin/env bash
# Task 5: CT 110 Prometheus scrapes headscale + node_exporter; Grafana has the hs-sim dashboard; nightly restic backup.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
P="http://$(ct_exec server1 "$CT_MON" "hostname -I | cut -d' ' -f1"):9090"
q() { curl -s -m 10 "$P/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] // "none"'; }
assert_eq "$(q 'up{job="hs-sim-headscale"}')" 1 "headscale scraped"
assert_eq "$(q 'up{job="hs-sim-node"}')" 1 "node_exporter scraped"
assert_eq "$(grafana_has_dashboard hs-sim)" yes "grafana dashboard provisioned"
ct_exec server1 "$CT_HS" "systemctl start hs-sim-backup.service"
assert_contains "$(ct_exec server1 "$CT_HS" 'restic -r /backup/restic --password-file /root/.restic-pass ls latest')" "db.sqlite" "backup contains db"
assert_contains "$(ct_exec server1 "$CT_HS" 'restic -r /backup/restic --password-file /root/.restic-pass ls latest')" "noise_private.key" "backup contains noise key"
assert_ok ct_exec server1 "$CT_HS" "systemctl is-enabled hs-sim-backup.timer"
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "5	server1	prometheus-config" "prometheus edit ledgered"
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "5	server1	backup-dir" "backup dir ledgered"
t_done
