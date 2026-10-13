#!/usr/bin/env bash
# Run between `./teardown.sh --keep-access` and `./teardown.sh --task 0`: every machine matches
# ledger/baseline/ and nothing named hs-sim is left. Expected to FAIL while the simulation exists.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
B=ledger/baseline
ids()  { awk 'NR>1 {print $1, $NF}' | sort; }                      # pct list: VMID + name (status may legitimately change)
pkgs() { cut -f1 | sort; }
ts()   { jq -r '.BackendState + " " + (.CurrentTailnet.Name // "")'; }

# server1 (Proxmox)
assert_eq "$(run_on server1 'pct list' | ids)" "$(ids < $B/server1-pct.txt)" "server1 containers as before (CT 101 restored, sim CTs gone)"
assert_eq "$(run_on server1 'qm list' | ids)" "$(ids < $B/server1-qm.txt)" "server1 VMs as before"
assert_eq "$(run_on server1 "pvesh get /nodes/$PVE1_NODE/network --output-format json" | jq -r '.[].iface' | sort)" \
          "$(jq -r '.[].iface' $B/server1-network.json | sort)" "server1 network interfaces as before (no vmbr2)"
assert_eq "$(run_on server1 'pvesh get /cluster/backup --output-format json' | jq -r '.[] | .id + " " + .vmid')" \
          "$(jq -r '.[] | .id + " " + .vmid' $B/server1-backup-jobs.json)" "weekly backup job covers CT 101 again"
assert_eq "$(ct_exec server1 "$CT_MON" 'sha256sum /opt/monitoring-stack/config/prometheus/prometheus.yml')" "$(cat $B/ct110-prometheus.sha256)" "prometheus.yml byte-identical"
assert_eq "$(grafana_has_dashboard hs-sim)" no "grafana dashboard removed"
assert_fails run_on server1 "test -e /mnt/$BACKUP_STORAGE/hs-sim-backup"
archive_exists() { run_on server1 "pvesm path $1" >/dev/null 2>&1; }
for v in $(awk -F'\t' '$4=="vzdump" {print $5}' ledger/ledger.tsv); do assert_fails archive_exists "$v"; done

# enigma
assert_eq "$(tailscale status --json | ts)" "$(ts < $B/enigma-tailscale.json)" "enigma hosted tailnet unchanged"
assert_eq "$(docker ps -aq --filter label=com.docker.compose.project=hs-sim | wc -l)" 0 "no hs-sim containers on enigma"
assert_eq "$(docker volume ls -q --filter label=com.docker.compose.project=hs-sim | wc -l)" 0 "no hs-sim volumes on enigma"
assert_eq "$(docker images -q 'hs-sim-ts' | wc -l)" 0 "no hs-sim image on enigma"
assert_fails sudo -n iptables -S HS-SIM-HOME
assert_fails test -e "$HOME/.config/systemd/user/hs-sim-collect.timer"

# laptop (fail loudly if it can't be reached: every check below would otherwise be meaningless)
assert_ok run_on laptop true
assert_eq "$(run_on laptop 'tailscale status --json' | ts)" "$(ts < $B/laptop-tailscale.json)" "laptop hosted tailnet unchanged"
assert_eq "$(run_on laptop 'dpkg-query -W' | pkgs)" "$(pkgs < $B/laptop-packages.txt)" "laptop package set as before (docker removed)"
assert_eq "$(run_on laptop 'ls -1 /usr/local/share/ca-certificates/; echo')" "$(cat $B/laptop-ca-certs.txt)" "laptop CA store as before"
assert_fails run_on laptop "test -e ~/hs-sim-clients"
assert_eq "$(run_on laptop 'ls -1 /etc/systemd/resolved.conf.d/ 2>/dev/null; echo')" "$(cat $B/laptop-resolved.d.txt)" "laptop resolved.conf.d as before"

# server0 (only once it has been part of the simulation)
if [ -n "$SERVER0_SSH" ] && [ ! -e $B/server0-tailscale.json ]; then
  assert_ok test -e $B/server0-tailscale.json            # server0 configured but never baselined: can't verify
fi
if [ -e $B/server0-tailscale.json ]; then
  assert_ok run_on server0 true
  assert_eq "$(run_on server0 'tailscale status --json 2>/dev/null || echo {\"BackendState\":\"NotInstalled\"}' | ts)" "$(ts < $B/server0-tailscale.json)" "server0 tailscale as before"
  assert_eq "$(run_on server0 'dpkg-query -W' | pkgs)" "$(pkgs < $B/server0-packages.txt)" "server0 package set as before"
  assert_eq "$(run_on server0 'ls -1 /usr/local/share/ca-certificates/; echo')" "$(cat $B/server0-ca-certs.txt)" "server0 CA store as before"
  assert_eq "$(run_on server0 'ls -1 /etc/systemd/resolved.conf.d/ 2>/dev/null; echo')" "$(cat $B/server0-resolved.d.txt)" "server0 resolved.conf.d as before"
fi

# ledger: everything undone except task-0 access rows (next step) and manual rows (printed for the user)
assert_eq "$(awk -F'\t' '$4!="manual" && $2!="0" {print $2"\t"$3"\t"$4"\t"$5}' ledger/ledger.tsv | sort -u | grep -vxFf ledger/done.tsv | wc -l)" 0 "every ledger row undone (except task-0 access)"
echo "  NEXT: ./teardown.sh --task 0   (removes the sudoers drop-ins and enigma's SSH key on the laptop)"
awk -F'\t' '$4=="manual" {print "  MANUAL (confirm yourself): " $6}' ledger/ledger.tsv
t_done
