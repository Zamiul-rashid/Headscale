#!/usr/bin/env bash
# Build a complete Headscale server in a fresh CT on server1.
#   headscale/install.sh <vmid> <ip> [--restore-from <restic-repo-path-inside-ct>] [--task N]
# Headscale (pinned .deb) behind Caddy (pinned, ACME cert from the sim CA), embedded DERP, ufw hardening.
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
vmid=${1:?usage} ip=${2:?usage}; shift 2
restore= task=4
while [ $# -gt 0 ]; do case $1 in --restore-from) restore=$2 ;; --task) task=$2 ;; *) die "bad option $1" ;; esac; shift 2; done
C() { ct_exec server1 "$vmid" "$*"; }
push() { run_on server1 "cat > /tmp/hs-sim-push" < "$1"; run_on server1 "pct push $vmid /tmp/hs-sim-push $2 ${3:-} && rm -f /tmp/hs-sim-push"; }
MON_IP=$(ct_exec server1 "$CT_MON" "hostname -I | cut -d' ' -f1")

hosts/make-ct.sh server1 "$vmid" "hs-$vmid" vmbr0 "$ip/24" "$LAN_GW" 2 2048 --disk 16 --task "$task"
push campus/root_ca.crt /usr/local/share/ca-certificates/hs-sim-root.crt
C "update-ca-certificates >/dev/null"
C "export DEBIAN_FRONTEND=noninteractive; apt-get -qq update && apt-get -qq install -y curl jq gnupg sqlite3 ufw fail2ban unattended-upgrades prometheus-node-exporter restic openssh-server >/dev/null"
C "install -d -m 700 /root/.ssh"; push "$HOME/.ssh/id_ed25519.pub" /root/.ssh/authorized_keys "--perms 600"

C "dpkg-query -W -f='\${Version}' headscale 2>/dev/null | grep -qx '$HEADSCALE_VERSION' || { cd /tmp && curl -fsSLo hs.deb '$HEADSCALE_DEB_URL' && apt-get -qq install -y ./hs.deb >/dev/null && apt-mark hold headscale >/dev/null; }"
push headscale/config.yaml /etc/headscale/config.yaml
push headscale/policy.hujson /etc/headscale/policy.hujson
C "chown root:headscale /etc/headscale/*.yaml /etc/headscale/*.hujson && chmod 640 /etc/headscale/*.yaml /etc/headscale/*.hujson"

if [ -n "$restore" ]; then
  push secrets/restic.pass /root/.restic-pass "--perms 600"
  C "systemctl stop headscale 2>/dev/null; restic -r $restore --password-file /root/.restic-pass restore latest --target / --include /var/backups/headscale --include /var/lib/headscale --include /etc/headscale >/dev/null \
     && cp /var/backups/headscale/db.sqlite /var/lib/headscale/db.sqlite && rm -f /var/lib/headscale/db.sqlite-wal /var/lib/headscale/db.sqlite-shm \
     && chown -R headscale:headscale /var/lib/headscale"
fi

C "test -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg || curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
C "echo 'deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main' > /etc/apt/sources.list.d/caddy-stable.list"
C "export DEBIAN_FRONTEND=noninteractive; dpkg-query -W -f='\${Version}' caddy 2>/dev/null | grep -qx '$CADDY_VERSION' || { apt-get -qq update && apt-get -qq install -y --allow-change-held-packages caddy=$CADDY_VERSION >/dev/null && apt-mark hold caddy >/dev/null; }"
push campus/root_ca.crt /etc/caddy/sim-root.crt
push headscale/Caddyfile /etc/caddy/Caddyfile

push headscale/harden.sh /root/hs-sim-harden.sh
C "bash /root/hs-sim-harden.sh $ENIGMA_LAN_IP $MON_IP"
C "systemctl enable -q headscale caddy && systemctl restart headscale && systemctl reload-or-restart caddy"
for _ in $(seq 60); do
  curl -sf -m 5 --cacert campus/root_ca.crt --resolve "$HS_FQDN:443:$ip" "https://$HS_FQDN/health" >/dev/null && { log "headscale healthy on $ip"; exit 0; }
  sleep 3
done
die "headscale on $ip not healthy after 180s (check: pct exec $vmid -- journalctl -u caddy -u headscale)"
