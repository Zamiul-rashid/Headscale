#!/usr/bin/env bash
# Task 7: enrol lab PCs with single-use tagged keys (tag-owned nodes, no user) + test listeners.
# lab-a-01 runs on the server0 host and is skipped until SERVER0_SSH is configured.
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
enrolled() { hs nodes list -o json | jq -e --arg n "$1" '(. // [])[] | select(.given_name==$n)' >/dev/null; }
for node in lab-a-01 lab-b-01 lab-b-02; do
  if [ "$node" = lab-a-01 ]; then
    [ -n "$SERVER0_SSH" ] || { log "lab-a-01 skipped: SERVER0_SSH not set"; continue; }
    [ -s ledger/baseline/server0-tailscale.json ] && [ -s config/server0-mode ] \
      || die "capture server0's baseline first: ./preflight.sh (without SKIP_SERVER0)"
    [ "$(cat config/server0-mode)" = native ] || die "server0 runs a hosted tailscaled; container mode for lab-a-01 not implemented yet"
    clients/trust-ca.sh server0 7; clients/resolved-dropin.sh server0 7
  fi
  tags=$(awk -F'\t' -v n="$node" '$1==n {print $5}' config/nodes.tsv)
  enrolled "$node" || clients/enroll-linux.sh "$node" "$(clients/mkkey.sh - --tags "$tags")" --task 7
  clients/labpc-listeners.sh "$node" --task 7
done
