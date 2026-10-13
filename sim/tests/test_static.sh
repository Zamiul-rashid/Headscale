#!/usr/bin/env bash
# Static checks on code and the real ledger: teardown/rebuild must be safe (no hosts touched).
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
L=ledger/ledger.tsv
undo() { awk -F'\t' -v k="$1" '$4==k {print $6}' $L; }
# original CT 101 archive: correct API, and only freed once the user's CT 101 is back
assert_contains "$(undo vzdump)" "pvesh set /nodes/proxmox/storage/storage1tb/content/" "archive unprotect uses the storage-content API"
assert_contains "$(undo vzdump)" "hs-sim" "archive freed only when CT 101 is no longer the sim CT"
assert_contains "$(grep -c 'vzdump' headscale/replace-original-101.sh) $(grep -c 'pvesh set /nodes/\$PVE1_NODE/storage' headscale/replace-original-101.sh)" " 1" "replace-original-101.sh writes the same undo"
# rebuild after teardown: the client image must carry the CURRENT root CA
assert_ok cmp -s campus/root_ca.crt clients/enigma/root_ca.crt
assert_ok grep -q 'cp campus/root_ca.crt clients/enigma/root_ca.crt' clients/setup-devices.sh
# idempotent undos
assert_contains "$(undo bridge)" "pvesh get" "vmbr2 undo checks existence and always applies"
assert_contains "$(undo prometheus-config)" "hs-sim BEGIN" "prometheus undo falls back to removing the marked block"
assert_eq "$(grep -c "hs-sim-listen@\*" clients/labpc-listeners.sh)" 0 "listener undo names units explicitly"
assert_ok grep -q 'apt-mark unhold tailscale' clients/enroll-linux.sh
# laptop: no blanket autoremove; leftover docker iptables chains need a reboot (manual row)
assert_eq "$(awk -F'\t' '$3=="laptop"' $L | grep -c autoremove)" 0 "laptop undo has no system-wide autoremove"
assert_ok sh -c "awk -F'\t' '\$3==\"laptop\" && \$4==\"manual\"' $L | grep -qi reboot"
# pristine must not run after access is gone, and must fail loudly when a host is unreachable
assert_ok grep -q -- '--keep-access' README.md
assert_ok grep -q 'resolved.d' tests/test_pristine.sh
assert_ok grep -q 'assert_ok run_on laptop true' tests/test_pristine.sh
# server0 must not be touched without its baseline
assert_ok grep -q 'server0-tailscale.json' clients/enroll-labpcs.sh
t_done
