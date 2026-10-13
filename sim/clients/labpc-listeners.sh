#!/usr/bin/env bash
# Stand-in services on a lab PC for ACL/perf tests: sshd (22), socat listeners for RDP 3389,
# Jupyter 8888 and a forbidden port 9999; the VNC slot 5900 is an iperf3 server so researchers
# can measure throughput without widening the ACL.
#   clients/labpc-listeners.sh <node> [--task N]   (non-CT nodes get ledger rows)
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
node=${1:?}; task=${3:-7}
exec_kind=$(awk -F'\t' -v n="$node" '$1==n {print $3}' config/nodes.tsv)
S=sudo; [ "$exec_kind" = pct ] && S=
if [ "$exec_kind" != pct ]; then
  target=$(awk -F'\t' -v n="$node" '$1==n {print $4}' config/nodes.tsv)
  ledger_add "$task" "$target" systemd-units hs-sim-listen "sudo systemctl disable --now 'hs-sim-listen@*' hs-sim-iperf3 2>/dev/null; sudo rm -f /etc/systemd/system/hs-sim-listen@.service /etc/systemd/system/hs-sim-iperf3.service; sudo systemctl daemon-reload"
fi
node_exec "$node" "export DEBIAN_FRONTEND=noninteractive
  command -v socat >/dev/null && command -v iperf3 >/dev/null || $S apt-get -qq install -y socat iperf3 openssh-server >/dev/null
  printf '[Unit]\nDescription=hs-sim test listener on %%i\n[Service]\nExecStart=/usr/bin/socat TCP-LISTEN:%%i,fork,reuseaddr EXEC:/bin/echo\nRestart=always\n[Install]\nWantedBy=multi-user.target\n' | $S tee /etc/systemd/system/hs-sim-listen@.service >/dev/null
  printf '[Unit]\nDescription=hs-sim iperf3 server\n[Service]\nExecStart=/usr/bin/iperf3 -s -p 5900\nRestart=always\n[Install]\nWantedBy=multi-user.target\n' | $S tee /etc/systemd/system/hs-sim-iperf3.service >/dev/null
  $S systemctl daemon-reload
  $S systemctl disable -q --now hs-sim-listen@5900 2>/dev/null; $S systemctl enable -q ssh hs-sim-listen@3389 hs-sim-listen@8888 hs-sim-listen@9999 hs-sim-iperf3
  $S systemctl restart ssh hs-sim-listen@3389 hs-sim-listen@8888 hs-sim-listen@9999 hs-sim-iperf3"
log "$node listeners up"
