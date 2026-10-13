#!/usr/bin/env bash
# Task 12: simulated off-campus client (alice-home): no LAN path, internet + the server's "public" ports only.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
clients/offcampus.sh up strict >/dev/null
H() { docker exec hs-sim-alice-home sh -c "$*"; }
assert_fails H "nc -z -w 3 192.168.1.111 22"                    # LAN hosts unreachable, like being at home
assert_fails H "nc -z -w 3 $IP_CAMPUS 53"
assert_ok    H "nc -z -w 3 $IP_HS 443"                           # the server's "public" port
assert_ok    H "wget -q -T 10 -O /dev/null https://pkgs.tailscale.com"
assert_ok    H "ping -c 5 1.1.1.1 | grep -qE 'time=([3-9][0-9]|[1-9][0-9]{2})'"   # netem adds ≥ 30 ms
tgt=$(node_ip lab-b-01)
assert_contains "$(H "tailscale ping --c 5 --until-direct=false --timeout 3s $tgt" 2>&1)" "via DERP(" "strict: relayed"
assert_ok    H "nc -z -w 3 $tgt 22"                              # ACL still lets alice SSH
assert_fails H "nc -z -w 3 $tgt 9999"
assert_eq "$(clients/offcampus.sh status)" strict "mode reported"
if [ -n "$SERVER0_SSH" ]; then
  clients/offcampus.sh mode wg-allowed >/dev/null
  assert_contains "$(H "tailscale ping --c 10 --timeout 3s $(node_ip lab-a-01)" 2>&1)" "via 192.168.1.111" "wg-allowed: direct to lab-a-01"
  clients/offcampus.sh mode strict >/dev/null
fi
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "12	enigma	iptables-chain	HS-SIM-HOME" "egress filter ledgered"
t_done
