# Runs INSIDE the Headscale CT (pushed and executed by install.sh). Args: <admin-ip> <monitor-ip>
set -euo pipefail
admin=$1 mon=$2
sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication no/; s/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart ssh 2>/dev/null || systemctl restart sshd
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null; ufw default allow outgoing >/dev/null
ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; ufw allow 3478/udp >/dev/null
ufw allow from "$admin" to any port 22 proto tcp >/dev/null
ufw allow from "$mon" to any port 9090 proto tcp >/dev/null
ufw allow from "$mon" to any port 9100 proto tcp >/dev/null
ufw --force enable >/dev/null
systemctl enable -q --now fail2ban unattended-upgrades
