#!/usr/bin/env bash
# Runs INSIDE the Headscale CT (installed as /usr/local/sbin/hs-sim-backup). Proposal §5.6.
set -euo pipefail
export RESTIC_REPOSITORY=/backup/restic RESTIC_PASSWORD_FILE=/root/.restic-pass
mkdir -p /var/backups/headscale
sqlite3 /var/lib/headscale/db.sqlite ".backup '/var/backups/headscale/db.sqlite'"
restic snapshots >/dev/null 2>&1 || restic init >/dev/null
restic backup --quiet --tag hs-sim /var/backups/headscale/db.sqlite /var/lib/headscale/noise_private.key \
  /var/lib/headscale/derp_server_private.key /etc/headscale /etc/caddy/Caddyfile
restic forget --quiet --keep-daily 30 --prune
