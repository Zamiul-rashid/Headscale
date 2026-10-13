#!/usr/bin/env bash
# One-time access setup (task 0 ledger rows, undone last by teardown):
#  - passwordless sudo for entropy on enigma and the laptop (/etc/sudoers.d/hs-sim)
#  - record enigma's key in the laptop's authorized_keys (added 2026-10-13 with ssh-copy-id)
# Usage: SUDO_PW=... ./bootstrap-access.sh   (the password is never written anywhere)
cd "$(dirname "$0")" || exit 1
. lib/common.sh
LINE='entropy ALL=(ALL) NOPASSWD:ALL'
# oldest row for the laptop = undone last, so teardown keeps SSH access until it is finished there
KEY=$(cut -d' ' -f2 "$HOME/.ssh/id_ed25519.pub")
ledger_add 0 laptop authorized_key "enigma id_ed25519" "sed -i '\\#$KEY#d' ~/.ssh/authorized_keys"
INSTALL='t=$(mktemp); echo "'"$LINE"'" > $t; visudo -cf $t >/dev/null && install -m 0440 $t /etc/sudoers.d/hs-sim; rc=$?; rm -f $t; exit $rc'
for host in enigma laptop; do
  if run_on "$host" "sudo -n true" 2>/dev/null; then log "$host: sudo already passwordless"; else
    [ -n "${SUDO_PW:-}" ] || die "SUDO_PW is required to set up sudo on $host"
    ledger_add 0 "$host" sudoers /etc/sudoers.d/hs-sim "sudo rm -f /etc/sudoers.d/hs-sim"
    printf '%s\n' "$SUDO_PW" | run_on "$host" "sudo -S -p '' bash -c $(printf %q "$INSTALL")" || die "$host: sudoers install failed"
    run_on "$host" "sudo -n true" || die "$host: sudo still needs a password"
  fi
done
log "access bootstrap done"
