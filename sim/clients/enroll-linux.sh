#!/usr/bin/env bash
# Install the pinned Tailscale client on a node and join the sim tailnet; append timing to results/enrolment.csv.
#   clients/enroll-linux.sh <node> <key> [--task N]
# CT nodes need no ledger (destroying the CT removes it); other hosts get an uninstall row.
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
node=${1:?} key=${2:?}; task=${4:-7}
exec_kind=$(awk -F'\t' -v n="$node" '$1==n {print $3}' config/nodes.tsv)
S=sudo; [ "$exec_kind" = pct ] && S=
if [ "$exec_kind" != pct ]; then
  target=$(awk -F'\t' -v n="$node" '$1==n {print $4}' config/nodes.tsv)
  ledger_add "$task" "$target" package tailscale "sudo tailscale logout 2>/dev/null; sudo apt-mark unhold tailscale >/dev/null; sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y tailscale >/dev/null; sudo rm -f /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg; sudo rm -rf /var/lib/tailscale; ! dpkg -s tailscale >/dev/null 2>&1"
fi
start=$(date +%s)
# CT nodes: trust the sim root inside the CT (destroyed with it). Other hosts use clients/trust-ca.sh (ledgered).
[ "$exec_kind" = pct ] && node_exec "$node" "cat > /usr/local/share/ca-certificates/hs-sim-root.crt && update-ca-certificates >/dev/null" < campus/root_ca.crt
node_exec "$node" "export DEBIAN_FRONTEND=noninteractive
  . /etc/os-release
  $S curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/\$VERSION_CODENAME.noarmor.gpg | $S tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
  echo \"deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu \$VERSION_CODENAME main\" | $S tee /etc/apt/sources.list.d/tailscale.list >/dev/null
  $S apt-get -qq update && $S apt-get -qq install -y --allow-change-held-packages tailscale=$TS_VERSION >/dev/null && $S apt-mark hold tailscale >/dev/null
  $S systemctl enable -q tailscaled && $S systemctl restart tailscaled
  $S tailscale up --login-server https://$HS_FQDN --authkey $key --hostname $node --accept-dns=true --timeout 120s"
for _ in $(seq 30); do
  [ "$(node_exec "$node" "tailscale status --json" | jq -r .BackendState)" = Running ] && break; sleep 2
done
secs=$(( $(date +%s) - start ))
mkdir -p results; echo "$node,$secs" >> results/enrolment.csv
log "$node enrolled in ${secs}s"
