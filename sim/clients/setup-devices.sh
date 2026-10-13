#!/usr/bin/env bash
# Task 6: user devices. bob + admin1 as containers on enigma; alice as a container on the laptop
# (every host here already runs tailscaled for the hosted tailnet, so clients get their own netns).
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
headscale/users.sh
D=clients/enigma
export TS_VERSION
UNDO_PROJECT="docker ps -aq --filter label=com.docker.compose.project=hs-sim | xargs -r SUDO docker rm -f; docker volume ls -q --filter label=com.docker.compose.project=hs-sim | xargs -r SUDO docker volume rm; docker network ls -q --filter label=com.docker.compose.project=hs-sim | xargs -r SUDO docker network rm; SUDO docker image rm -f hs-sim-ts:$TS_VERSION >/dev/null 2>&1; true"

# --- enigma ---
ledger_add 6 enigma docker-project hs-sim "${UNDO_PROJECT//SUDO /}"
docker compose -f $D/compose.yaml --profile enigma build -q
for svc in bob:bob admin:admin1; do
  IFS=: read -r name user <<<"$svc"
  docker ps -q --filter name=^hs-sim-$name\$ | grep -q . && continue
  k=$(clients/mkkey.sh "$user")
  start=$(date +%s)
  env "KEY_${name^^}=$k" docker compose -f $D/compose.yaml --profile enigma up -d "hs-sim-$name" >/dev/null 2>&1
  until docker exec "hs-sim-$name" tailscale status --json 2>/dev/null | jq -e '.BackendState=="Running"' >/dev/null; do sleep 2; [ $(( $(date +%s) - start )) -lt 120 ] || die "hs-sim-$name did not come up"; done
  echo "$name-enigma,$(( $(date +%s) - start ))" >> results/enrolment.csv
done

# --- laptop: Docker (ledgered), then the same image via save/load ---
if ! run_on laptop "command -v docker" >/dev/null; then
  ledger_add 6 laptop package docker.io "sudo apt-get purge -y docker.io docker-compose-v2 containerd runc >/dev/null; sudo apt-get autoremove -y >/dev/null; sudo rm -rf /var/lib/docker /var/lib/containerd; sudo iptables -P FORWARD ACCEPT; sudo sysctl -qw net.ipv4.ip_forward=0"
  run_on laptop "sudo DEBIAN_FRONTEND=noninteractive apt-get -qq update && sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install -y docker.io docker-compose-v2 >/dev/null"
fi
ledger_add 6 laptop docker-project hs-sim "rm -rf ~/hs-sim-clients; ${UNDO_PROJECT//SUDO/sudo}"
docker save "hs-sim-ts:$TS_VERSION" | run_on laptop "sudo docker load -q"
tar -C $D -cf - compose.yaml | run_on laptop "mkdir -p ~/hs-sim-clients && tar -C ~/hs-sim-clients -xf -"
if ! run_on laptop "sudo docker ps -q --filter name=^hs-sim-alice\$" | grep -q .; then
  k=$(clients/mkkey.sh alice); start=$(date +%s)
  run_on laptop "cd ~/hs-sim-clients && sudo TS_VERSION=$TS_VERSION KEY_ALICE=$k docker compose --profile laptop up -d --no-build hs-sim-alice >/dev/null 2>&1"
  until node_exec alice-laptop "tailscale status --json" 2>/dev/null | jq -e '.BackendState=="Running"' >/dev/null; do sleep 2; [ $(( $(date +%s) - start )) -lt 120 ] || die "alice did not come up"; done
  echo "alice-laptop,$(( $(date +%s) - start ))" >> results/enrolment.csv
fi
log "devices enrolled"
