#!/usr/bin/env bash
# Task 2: CT 802 "university IT": dnsmasq (uni.home.arpa) + step-ca ACME server on :443.
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
: "${STEPCA_DEB_URL:?versions.env missing STEPCA_DEB_URL}" "${STEPCLI_DEB_URL:?versions.env missing STEPCLI_DEB_URL}"
C() { ct_exec server1 "$CT_CAMPUS" "$*"; }

hosts/make-ct.sh server1 "$CT_CAMPUS" campus vmbr0 "$IP_CAMPUS/24" "$LAN_GW" 1 512 --nameserver "$LAN_GW" --task 2

C "export DEBIAN_FRONTEND=noninteractive; apt-get -qq update && apt-get -qq install -y dnsmasq curl jq >/dev/null"
run_on server1 "cat > /tmp/hs-sim-dnsmasq.conf" < campus/dnsmasq.conf
run_on server1 "pct push $CT_CAMPUS /tmp/hs-sim-dnsmasq.conf /etc/dnsmasq.d/hs-sim.conf && rm /tmp/hs-sim-dnsmasq.conf"
C "sed -i 's/^#\?IGNORE_RESOLVCONF=.*/IGNORE_RESOLVCONF=yes/' /etc/default/dnsmasq; grep -q IGNORE_RESOLVCONF /etc/default/dnsmasq || echo IGNORE_RESOLVCONF=yes >> /etc/default/dnsmasq"
campus/set-hs-ip.sh "$IP_HS"
C "systemctl enable -q dnsmasq"
# the CA must resolve hs.uni.home.arpa for ACME HTTP-01, so the CT now uses its own dnsmasq
run_on server1 "pct set $CT_CAMPUS --nameserver $IP_CAMPUS"
C "printf 'nameserver $IP_CAMPUS\nsearch $UNI_DOMAIN\n' > /etc/resolv.conf"

mkdir -p secrets; [ -s secrets/stepca.pass ] || (umask 077; openssl rand -base64 32 > secrets/stepca.pass)
C "test -x /usr/bin/step-ca || { cd /tmp && curl -fsSLo ca.deb '$STEPCA_DEB_URL' && curl -fsSLo cli.deb '$STEPCLI_DEB_URL' && apt-get -qq install -y ./cli.deb ./ca.deb >/dev/null; }"
C "id step >/dev/null 2>&1 || useradd --system --home /etc/step-ca --shell /usr/sbin/nologin step; install -d -o step -m 700 /etc/step-ca"
run_on server1 "pct exec $CT_CAMPUS -- bash -c 'umask 077; cat > /etc/step-ca/password.txt; chown step /etc/step-ca/password.txt'" < secrets/stepca.pass
C "test -f /etc/step-ca/config/ca.json || sudo -u step env STEPPATH=/etc/step-ca step ca init --deployment-type standalone \
     --name 'hs-sim University CA' --dns $CA_FQDN --dns $IP_CAMPUS --address :443 \
     --provisioner admin@$UNI_DOMAIN --password-file /etc/step-ca/password.txt --acme >/dev/null"
C "cat > /etc/systemd/system/step-ca.service <<'UNIT'
[Unit]
Description=hs-sim step-ca (simulated university ACME CA)
After=network-online.target
Wants=network-online.target
[Service]
User=step
Environment=STEPPATH=/etc/step-ca
ExecStart=/usr/bin/step-ca /etc/step-ca/config/ca.json --password-file /etc/step-ca/password.txt
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable -q --now step-ca"
C "cat /etc/step-ca/certs/root_ca.crt" > campus/root_ca.crt
log "campus services up; root CA saved to campus/root_ca.crt"
