#!/usr/bin/env bash
# Route uni.home.arpa lookups to the campus DNS on a non-CT host (ledgered).  clients/resolved-dropin.sh <host> <task>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
host=${1:?} task=${2:?}
F=/etc/systemd/resolved.conf.d/hs-sim.conf
ledger_add "$task" "$host" resolved-dropin "$F" "sudo rm -f $F && sudo systemctl restart systemd-resolved"
printf '[Resolve]\nDNS=%s\nDomains=~%s\n' "$IP_CAMPUS" "$UNI_DOMAIN" | run_on "$host" "sudo mkdir -p /etc/systemd/resolved.conf.d && sudo tee $F >/dev/null && sudo systemctl restart systemd-resolved"
