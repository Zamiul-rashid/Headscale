#!/usr/bin/env bash
# Builds the stress lab inside a fresh Docker host (CT 190): test CA, Headscale, the labslots hub, slot
# agent and scheduler sidecar, the seeded schedule (70 PCs, 57 groups, 80 students) and the PC image.
# Run from /root/stress with the labslots source in ./src.   Then: python3 run.py
set -euo pipefail
cd "$(dirname "$0")"
HS_IMAGE=headscale/headscale:0.29.3
CT_IP=$(ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1)
grep -q 'hs-stress.test' /etc/hosts || echo "$CT_IP hs-stress.test" >> /etc/hosts
mkdir -p certs hs/config hs/data hs/run hub-data agent-data ts-state secrets/agent secrets/tailscale results

# --- test CA and Headscale's TLS certificate --------------------------------------------------------
if [ ! -f certs/hs.crt ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=stress-lab test CA" \
    -keyout certs/ca.key -out certs/ca.crt 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -subj "/CN=hs-stress.test" -keyout certs/hs.key -out certs/hs.csr 2>/dev/null
  printf "subjectAltName=DNS:hs-stress.test,IP:%s\n" "$CT_IP" > certs/san.ext
  openssl x509 -req -in certs/hs.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial -days 30 \
    -extfile certs/san.ext -out certs/hs.crt 2>/dev/null
  chmod 644 certs/*.crt certs/hs.key
fi

# --- Headscale --------------------------------------------------------------------------------------
sed "s/__CT_IP__/$CT_IP/" headscale.yaml > hs/config/config.yaml
docker rm -f stress-hs >/dev/null 2>&1 || true
docker run -d --name stress-hs --network host --restart unless-stopped \
  -v "$PWD/hs/config:/etc/headscale" -v "$PWD/hs/data:/var/lib/headscale" -v "$PWD/hs/run:/var/run/headscale" \
  -v "$PWD/certs:/certs:ro" "$HS_IMAGE" serve >/dev/null
for i in $(seq 1 60); do docker exec stress-hs headscale users list >/dev/null 2>&1 && break; sleep 1; done
docker exec stress-hs headscale version
hs() { docker exec stress-hs headscale "$@"; }
[ -s secrets/agent/headscale_api_key ] || hs apikeys create -e 30d | tail -1 > secrets/agent/headscale_api_key

# --- labslots hub, seeded schedule, slot agent --------------------------------------------------------
docker build -q -t labslots:stress src >/dev/null
chown -R 10001 hub-data agent-data
docker compose -f core-compose.yml up -d hub
for i in $(seq 1 60); do curl -sf http://127.0.0.1:3100/slots/healthz >/dev/null && break; sleep 1; done
python3 run.py seed
docker exec stress-hub python -c "
from labslots.db import DB; from labslots.hub import add_server
print(add_server(DB('/data/labslots.db'), 'hs1'))" | tail -1 > secrets/agent/agent_token
chown -R 10001 secrets/agent && chmod 500 secrets/agent && chmod 400 secrets/agent/*
docker compose -f core-compose.yml up -d agent
echo "waiting for the agent to write the first policy (tag owners for the PCs and the scheduler)"
for i in $(seq 1 60); do hs policy get 2>/dev/null | grep -q 'tag:pc-70' && break; sleep 2; done
hs policy get | grep -c '"tag:pc-' | sed 's/^/policy tags for PCs: /'

# --- scheduler sidecar (tag:scheduler) --------------------------------------------------------------
if [ ! -s secrets/tailscale/ts_authkey ]; then
  hs preauthkeys create --tags tag:scheduler --reusable -e 24h -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])' \
    > secrets/tailscale/ts_authkey
  chmod 700 secrets/tailscale && chmod 600 secrets/tailscale/ts_authkey
fi
docker compose -f core-compose.yml up -d ts-scheduler

# --- the simulated lab PC image, with this agent's SSH key built into setup-lab-pc.sh -----------------
for i in $(seq 1 30); do [ -s agent-data/ssh/id_ed25519.pub ] && break; sleep 1; done
# Simulation only: in Tailscale's userspace mode the PC's sshd sees connections from 127.0.0.1, not from the
# tailnet address, so the key's from="100.64.0.0/10,..." restriction also has to allow localhost here.
sed -e "s|__SCHEDULER_PUBKEY__|$(cat agent-data/ssh/id_ed25519.pub)|" -e 's|from="100.64.0.0/10,|from="127.0.0.1,100.64.0.0/10,|' \
  src/labslots/pc/setup-lab-pc.sh > pc/setup-lab-pc.sh
grep -q 'from="127.0.0.1,' pc/setup-lab-pc.sh || { echo "could not adapt the key restriction"; exit 1; }
docker build -q -t stress-pc pc >/dev/null
docker pull -q tailscale/tailscale:v1.102.3 >/dev/null
echo "stress lab ready: Headscale at https://hs-stress.test:8443 ($CT_IP), hub on :3100"
