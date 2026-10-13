#!/usr/bin/env bash
# Task 5: scrape jobs + dashboard in the existing monitoring CT 110; restic backups for the Headscale CT.
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
M() { ct_exec server1 "$CT_MON" "$*"; }
H() { ct_exec server1 "$CT_HS" "$*"; }
push() { run_on server1 "cat > /tmp/hs-sim-push" < "$2"; run_on server1 "pct push $1 /tmp/hs-sim-push $3 ${4:-} && rm -f /tmp/hs-sim-push"; }
PROM=/opt/monitoring-stack/config/prometheus/prometheus.yml
DASH=/opt/monitoring-stack/config/grafana/dashboards/hs-sim-headscale.json

# Prometheus: back up, append our jobs, validate, hot-reload. Undo restores the exact original file.
if ! M "grep -q 'hs-sim BEGIN' $PROM"; then
  ledger_add 5 server1 prometheus-config "$PROM" \
    "pct exec $CT_MON -- bash -c 'cp -p $PROM.hs-sim.bak $PROM && rm -f $PROM.hs-sim.bak && curl -s -X POST localhost:9090/-/reload'"
  M "cp -p $PROM $PROM.hs-sim.bak"
  run_on server1 "cat > /tmp/hs-sim-job" < monitoring/prometheus-job.yml
  run_on server1 "pct exec $CT_MON -- bash -c 'cat >> $PROM' < /tmp/hs-sim-job && rm -f /tmp/hs-sim-job"
fi
M "docker exec prometheus promtool check config /etc/prometheus/prometheus.yml >/dev/null" \
  || { M "cp -p $PROM.hs-sim.bak $PROM"; die "promtool rejected the config; original restored"; }
M "curl -sf -X POST localhost:9090/-/reload"

# Grafana: file-provisioned dashboard (provider polls every 30s)
ledger_add 5 server1 grafana-dashboard "$DASH" "pct exec $CT_MON -- rm -f $DASH"
push "$CT_MON" monitoring/dashboard.json "$DASH" "--perms 644"
M "chown --reference=$(dirname $DASH) $DASH"

# Backups: a directory on storage1tb bind-mounted into CT 101 at /backup
BDIR=/mnt/$BACKUP_STORAGE/hs-sim-backup
if ! run_on server1 "test -d $BDIR"; then
  ledger_add 5 server1 backup-dir "$BDIR" "rm -rf $BDIR"
  run_on server1 "mkdir -p $BDIR && chown 100000:100000 $BDIR && chmod 700 $BDIR"
fi
run_on server1 "pct config $CT_HS | grep -q '^mp0:' || pct set $CT_HS -mp0 $BDIR,mp=/backup"
H "test -d /backup" || { run_on server1 "pct reboot $CT_HS"; sleep 15; }
mkdir -p secrets; [ -s secrets/restic.pass ] || (umask 077; openssl rand -base64 32 > secrets/restic.pass)
push "$CT_HS" secrets/restic.pass /root/.restic-pass "--perms 600"
push "$CT_HS" headscale/backup.sh /usr/local/sbin/hs-sim-backup "--perms 755"
push "$CT_HS" headscale/hs-sim-backup.service /etc/systemd/system/hs-sim-backup.service
push "$CT_HS" headscale/hs-sim-backup.timer /etc/systemd/system/hs-sim-backup.timer
H "systemctl daemon-reload && systemctl enable -q --now hs-sim-backup.timer"
log "monitoring + backups configured"
