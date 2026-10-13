#!/usr/bin/env bash
# Task 3: lab room B (10.20.0.0/24 on vmbr2) behind campus-fw CT 803; udp-blocked mode persists across reboot.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
B() { ct_exec server1 "$CT_LABB1" "$*"; }
campus/fw-mode.sh open
assert_contains "$(B 'ip route')" "default via $ROOMB_GW" "room B gateway"
assert_ok B "dig +short +time=2 +tries=1 @1.1.1.1 example.com | grep -qE '^[0-9.]+\$'"
assert_ok B "curl -sfI -m 10 https://pkgs.tailscale.com"
campus/fw-mode.sh udp-blocked
assert_fails B "dig +short +time=2 +tries=1 @1.1.1.1 example.com | grep -qE '^[0-9.]+\$'"
assert_ok    B "dig +tcp +short +time=3 @1.1.1.1 example.com | grep -qE '^[0-9.]+\$'"
assert_eq "$(B "dig +short +time=2 +tries=1 @$IP_CAMPUS $HS_FQDN")" "$IP_HS" "campus DNS allowed"
run_on server1 "pct reboot $CT_FW"; sleep 20
assert_eq "$(campus/fw-mode.sh status)" udp-blocked "mode survives reboot"
assert_fails B "dig +short +time=2 +tries=1 @1.1.1.1 example.com | grep -qE '^[0-9.]+\$'"
assert_ok    B "curl -sfI -m 10 https://pkgs.tailscale.com"
campus/fw-mode.sh open
t_done
