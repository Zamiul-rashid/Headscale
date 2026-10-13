#!/usr/bin/env bash
# Check the home lab is ready for the simulation and capture the pre-simulation baseline.
# Baseline files are write-once: a re-run never overwrites the original state.
# SKIP_SERVER0=1 defers all server0 checks/baseline until its login is known.
cd "$(dirname "$0")" || exit 1
. lib/common.sh
B=$LEDGER_DIR/baseline; mkdir -p "$B"
mine() { grep -qF "	$1	" "$LEDGER_DIR/ledger.tsv" 2>/dev/null; }   # resource already created by the sim?
snap() { local f=$B/$1; shift; [ -e "$f" ] && return 0; "$@" > "$f.tmp" && mv "$f.tmp" "$f" || { rm -f "$f.tmp"; die "baseline $(basename "$f") failed"; }; }

if [ -z "${SKIP_SERVER0:-}" ]; then
  [ -n "$SERVER0_SSH" ] || die "SERVER0_SSH is empty in config/sim.env (or run with SKIP_SERVER0=1)"
  run_on server0 true || die "cannot ssh to server0 ($SERVER0_SSH)"
  run_on server0 "sudo -n true" || die "server0: $SERVER0_SSH needs passwordless sudo"
fi
run_on server1 true || die "cannot ssh to server1"
run_on laptop true  || die "cannot ssh to laptop ($LAPTOP_SSH)"
sudo -n true && run_on laptop "sudo -n true" || die "passwordless sudo missing: run SUDO_PW=... ./bootstrap-access.sh"

sim_ct() { run_on server1 "pct config $1 2>/dev/null | grep -q '^tags:.*hs-sim'"; }   # CT exists and is ours
for pair in "$IP_HS:$CT_HS" "$IP_CAMPUS:$CT_CAMPUS" "$IP_FW:$CT_FW" "$IP_RESTORE:$CT_RESTORE"; do
  ip=${pair%%:*}; sim_ct "${pair#*:}" && continue
  run_on server1 "ping -c2 -W1 $ip >/dev/null 2>&1; ip neigh show $ip | grep -q lladdr" && die "IP $ip is already in use on the LAN"
done
for id in "$CT_CAMPUS" "$CT_FW" "$CT_LABB1" "$CT_LABB2" "$CT_RESTORE"; do
  mine "$id" && continue
  run_on server1 "pct status $id >/dev/null 2>&1 || qm status $id >/dev/null 2>&1" && die "VMID $id is already in use on server1"
done
mine vmbr2 || ! run_on server1 "ip link show vmbr2 >/dev/null 2>&1" || die "vmbr2 already exists on server1"
run_on server1 "pvesm list ${TEMPLATE%%:*} --content vztmpl | grep -qF '$TEMPLATE'" || die "template $TEMPLATE missing"

PROM=/opt/monitoring-stack/config/prometheus/prometheus.yml
snap enigma-tailscale.json tailscale status --json
snap server1-pct.txt         run_on server1 "pct list"
snap server1-qm.txt          run_on server1 "qm list"
snap server1-network.json    run_on server1 "pvesh get /nodes/$PVE1_NODE/network --output-format json | jq -S ."
snap server1-backup-jobs.json run_on server1 "pvesh get /cluster/backup --output-format json | jq -S ."
snap ct110-prometheus.sha256 ct_exec server1 "$CT_MON" "sha256sum $PROM"
snap laptop-tailscale.json   run_on laptop "tailscale status --json"
snap laptop-packages.txt     run_on laptop "dpkg-query -W"
snap laptop-ca-certs.txt     run_on laptop "ls -1 /usr/local/share/ca-certificates/; echo"
snap laptop-resolved.d.txt   run_on laptop "ls -1 /etc/systemd/resolved.conf.d/ 2>/dev/null; echo"
if [ -z "${SKIP_SERVER0:-}" ]; then
  snap server0-tailscale.json run_on server0 "tailscale status --json 2>/dev/null || echo '{\"BackendState\":\"NotInstalled\"}'"
  snap server0-packages.txt   run_on server0 "dpkg-query -W"
  snap server0-ca-certs.txt   run_on server0 "ls -1 /usr/local/share/ca-certificates/; echo"
  snap server0-resolved.d.txt run_on server0 "ls -1 /etc/systemd/resolved.conf.d/ 2>/dev/null; echo"
  [ -s config/server0-mode ] || server0_mode "$(cat "$B/server0-tailscale.json")" > config/server0-mode
else
  log "server0 deferred (SKIP_SERVER0=1): capture its baseline before Task 7"
fi
log "preflight ok; baseline in $B"
