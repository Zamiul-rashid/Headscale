#!/usr/bin/env bash
# Create the pilot users (idempotent). Lab PCs are tag-owned and need no user (headscale >= 0.28).
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
have=$(hs users list -o json | jq -r '(. // [])[].name')
for u in admin1 alice bob; do
  grep -qx "$u" <<<"$have" || hs users create "$u" >/dev/null
done
log "users: $(hs users list -o json | jq -r '(. // [])[].name' | tr '\n' ' ')"
