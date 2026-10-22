#!/bin/bash
# Simulated lab PC: sshd on localhost, Tailscale in userspace mode (incoming tailnet TCP is forwarded to
# localhost, so the slot agent's SSH reaches sshd exactly as on a real PC).
set -e
/usr/sbin/sshd
tailscaled --tun=userspace-networking --statedir=/var/lib/tailscale --socket=/tmp/tailscaled.sock --port=0 &
for i in $(seq 1 50); do [ -S /tmp/tailscaled.sock ] && break; sleep 0.2; done
# The tag (tag:pc-N) comes with the pre-auth key; asking for it again with --advertise-tags is refused.
tailscale --socket=/tmp/tailscaled.sock up --login-server="$TS_LOGIN" --authkey="$TS_AUTHKEY" \
  --hostname="$TS_HOSTNAME" --accept-dns=false
wait
