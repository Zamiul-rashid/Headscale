#!/usr/bin/env bash
# Install and start the hourly soak collector as a systemd user timer on enigma (ledgered).
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
U=$HOME/.config/systemd/user
ledger_add 11 enigma systemd-user-timer hs-sim-collect \
  "systemctl --user disable --now hs-sim-collect.timer 2>/dev/null; rm -f $U/hs-sim-collect.service $U/hs-sim-collect.timer; systemctl --user daemon-reload"
mkdir -p "$U"; cp tests/systemd/hs-sim-collect.service tests/systemd/hs-sim-collect.timer "$U/"
systemctl --user daemon-reload && systemctl --user enable --now hs-sim-collect.timer
log "soak collector enabled for $SOAK_DAYS days: $(systemctl --user list-timers hs-sim-collect.timer --no-legend | awk '{print $1, $2, $3}')"
