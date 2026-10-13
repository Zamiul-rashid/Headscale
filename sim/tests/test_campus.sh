#!/usr/bin/env bash
# Task 2: simulated university IT — dnsmasq for uni.home.arpa + step-ca ACME in CT 802.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
assert_eq "$(dig +short +time=2 +tries=1 @$IP_CAMPUS $HS_FQDN)" "$IP_HS" "hs record"
assert_eq "$(dig +short +time=2 +tries=1 @$IP_CAMPUS $CA_FQDN)" "$IP_CAMPUS" "ca record"
assert_ok sh -c "dig +short +time=2 +tries=1 @$IP_CAMPUS pkgs.tailscale.com | grep -qE '^[0-9]+(\.[0-9]+){3}$'"   # forwards upstream
assert_contains "$(curl -s -m 10 --cacert campus/root_ca.crt --resolve $CA_FQDN:443:$IP_CAMPUS \
  https://$CA_FQDN/acme/acme/directory)" newOrder "ACME directory up"
assert_contains "$(run_on server1 "pct config $CT_CAMPUS" 2>/dev/null)" "tags: hs-sim" "tagged"
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "2	server1	ct	$CT_CAMPUS" "ledgered"
t_done
