#!/usr/bin/env bash
# preflight.sh: refuses without server0 (unless SKIP_SERVER0=1), checks free IPs/VMIDs, writes the baseline.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
B=ledger/baseline

out=$(SERVER0_SSH= SKIP_SERVER0= ./preflight.sh 2>&1); rc=$?
assert_eq "$rc" 1 "refuses with empty SERVER0_SSH"
assert_contains "$out" "SERVER0_SSH" "message names SERVER0_SSH"

if [ -z "$SERVER0_SSH" ]; then export SKIP_SERVER0=1; fi
assert_ok ./preflight.sh
assert_ok test -e "$B/server1-qm.txt"   # empty is valid: server1 has no VMs
for f in enigma-tailscale.json server1-pct.txt server1-network.json server1-backup-jobs.json \
         ct110-prometheus.sha256 laptop-tailscale.json laptop-packages.txt laptop-ca-certs.txt laptop-resolved.d.txt; do
  assert_ok test -s "$B/$f"
done
if [ -z "${SKIP_SERVER0:-}" ]; then
  for f in server0-tailscale.json server0-ca-certs.txt server0-resolved.d.txt server0-packages.txt; do
    assert_ok test -s "$B/$f"; done
  assert_ok test -s config/server0-mode
fi
assert_eq "$(jq -r .BackendState $B/enigma-tailscale.json)" Running "enigma hosted tailnet captured"
assert_ok sudo -n true
assert_ok run_on laptop "sudo -n true"
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "0	laptop	sudoers	/etc/sudoers.d/hs-sim" "laptop sudoers ledgered"
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "0	enigma	sudoers	/etc/sudoers.d/hs-sim" "enigma sudoers ledgered"
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "0	laptop	authorized_key" "laptop key ledgered"
t_done
