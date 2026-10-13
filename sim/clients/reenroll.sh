#!/usr/bin/env bash
# Re-admit a containerised client after expiry/revocation: recreate its container with a fresh key
# (state volume kept, so it stays the same Headscale node).   clients/reenroll.sh <node>
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
node=${1:?}
case $node in
  alice-laptop) user=alice  svc=hs-sim-alice var=KEY_ALICE profile=laptop host=laptop ;;
  bob-enigma)   user=bob    svc=hs-sim-bob   var=KEY_BOB   profile=enigma host=enigma ;;
  admin-enigma) user=admin1 svc=hs-sim-admin var=KEY_ADMIN profile=enigma host=enigma ;;
  *) die "reenroll: $node is not a containerised client" ;;
esac
k=$(clients/mkkey.sh "$user")
if [ "$host" = laptop ]; then
  run_on laptop "cd ~/hs-sim-clients && sudo TS_VERSION=$TS_VERSION $var=$k docker compose --profile $profile up -d --force-recreate --no-build $svc" >/dev/null 2>&1
else
  env TS_VERSION="$TS_VERSION" "$var=$k" docker compose -f clients/enigma/compose.yaml --profile "$profile" up -d --force-recreate --no-build "$svc" >/dev/null 2>&1
fi
for _ in $(seq 45); do
  node_exec "$node" "tailscale status --json" 2>/dev/null | jq -e '.BackendState=="Running"' >/dev/null && { log "$node re-enrolled"; exit 0; }
  sleep 2
done
die "$node did not come back"
