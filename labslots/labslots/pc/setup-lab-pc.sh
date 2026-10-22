#!/usr/bin/env bash
#
# Prepare one lab PC for slot switching by the labslots scheduler.
#
#   sudo bash setup-lab-pc.sh <admin-user> [<admin-user> ...] [--harden]
#
# What it does (idempotent, safe to re-run):
#   * creates the `labsched` account; only the scheduler key may log in, and
#     only from tailnet addresses (100.64.0.0/10)
#   * creates the groups `slot-active` (the group in its slot) and `lab-admins`,
#     and adds the admin users you name to lab-admins
#   * installs /usr/local/sbin/slot-switch, which `labsched` may run with sudo
#     (nothing else)
#   * with --harden: sshd only admits lab-admins, slot-active and labsched,
#     key-only, and (if ufw is active) SSH only on tailscale0.
#     Name at least one admin user, or you can lock yourself out.
#
set -euo pipefail

SCHEDULER_PUBKEY='__SCHEDULER_PUBKEY__'

[[ $EUID -eq 0 ]] || { echo "run as root (sudo)"; exit 1; }
HARDEN=0; ADMINS=()
for a in "$@"; do
  case "$a" in
    --harden) HARDEN=1 ;;
    -*) echo "unknown option $a"; exit 1 ;;
    *) id "$a" >/dev/null 2>&1 || { echo "no such user: $a"; exit 1; }; ADMINS+=("$a") ;;
  esac
done
[[ ${#ADMINS[@]} -gt 0 ]] || { echo "usage: sudo bash $0 <admin-user> [...] [--harden]"; exit 1; }
[[ "$SCHEDULER_PUBKEY" == ssh-* ]] || { echo "scheduler key missing: download this script from the labslots PCs page"; exit 1; }

getent group slot-active >/dev/null || groupadd slot-active
getent group lab-admins  >/dev/null || groupadd lab-admins
for u in "${ADMINS[@]}"; do usermod -aG lab-admins "$u"; done

id labsched >/dev/null 2>&1 || useradd --system --create-home --shell /bin/bash --comment "labslots scheduler" labsched
install -d -m 700 -o labsched -g labsched /home/labsched/.ssh
printf 'from="100.64.0.0/10,fd7a:115c:a1e0::/48",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty %s\n' \
  "$SCHEDULER_PUBKEY" > /home/labsched/.ssh/authorized_keys
chown labsched:labsched /home/labsched/.ssh/authorized_keys; chmod 600 /home/labsched/.ssh/authorized_keys

cat > /usr/local/sbin/slot-switch <<'HELPER'
#!/usr/bin/env bash
# slot-switch <grp-account|->   (authorized_keys for the account on stdin)
# Makes <account> the only member of slot-active, ends every other grp-*
# account's sessions and processes, and writes the account's SSH keys.
set -euo pipefail
IN="${1:-}"
[[ "$IN" == "-" || "$IN" =~ ^grp-[a-z0-9-]{1,28}$ ]] || { echo "bad account: $IN" >&2; exit 2; }
KEYS="$(cat || true)"

for u in $(getent passwd | cut -d: -f1 | grep -E '^grp-[a-z0-9-]+$' || true); do
  [[ "$u" == "$IN" ]] && continue
  gpasswd -d "$u" slot-active >/dev/null 2>&1 || true
  loginctl terminate-user "$u" >/dev/null 2>&1 || true
  pkill -KILL -u "$u" >/dev/null 2>&1 || true
done

if [[ "$IN" != "-" ]]; then
  id "$IN" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash --comment "thesis group account" "$IN"
  install -d -m 700 -o "$IN" -g "$IN" "/home/$IN/.ssh"
  printf '%s\n' "$KEYS" | grep -E '^(ssh-|ecdsa-|sk-)' > "/home/$IN/.ssh/authorized_keys.new" || true
  chown "$IN:$IN" "/home/$IN/.ssh/authorized_keys.new"; chmod 600 "/home/$IN/.ssh/authorized_keys.new"
  mv "/home/$IN/.ssh/authorized_keys.new" "/home/$IN/.ssh/authorized_keys"
  gpasswd -a "$IN" slot-active >/dev/null
fi
echo "slot-active=${IN} on $(hostname)"
HELPER
chmod 755 /usr/local/sbin/slot-switch; chown root:root /usr/local/sbin/slot-switch

echo 'labsched ALL=(root) NOPASSWD: /usr/local/sbin/slot-switch' > /etc/sudoers.d/labslots
chmod 440 /etc/sudoers.d/labslots
visudo -cf /etc/sudoers.d/labslots >/dev/null

if [[ $HARDEN -eq 1 ]]; then
  cat > /etc/ssh/sshd_config.d/50-labslots.conf <<'SSHD'
# labslots: only admins, the group in its slot, and the scheduler may log in.
AllowGroups lab-admins slot-active labsched
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
SSHD
  sshd -t
  systemctl reload ssh 2>/dev/null || systemctl reload sshd
  if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow in on tailscale0 to any port 22 proto tcp >/dev/null
    ufw delete allow 22/tcp >/dev/null 2>&1 || true
    ufw delete allow OpenSSH >/dev/null 2>&1 || true
  fi
  echo "sshd hardened. Check you can still log in from another terminal before closing this one."
fi

echo "Done. labsched, slot-active, lab-admins (${ADMINS[*]}) and /usr/local/sbin/slot-switch are ready."
