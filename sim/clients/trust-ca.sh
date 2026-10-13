#!/usr/bin/env bash
# Install the sim root CA on a non-CT host (ledgered).  clients/trust-ca.sh <host> <task>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
host=${1:?} task=${2:?}
F=/usr/local/share/ca-certificates/hs-sim-root.crt
ledger_add "$task" "$host" ca-cert "$F" "sudo rm -f $F && sudo update-ca-certificates --fresh >/dev/null"
run_on "$host" "sudo tee $F >/dev/null && sudo update-ca-certificates >/dev/null" < campus/root_ca.crt
