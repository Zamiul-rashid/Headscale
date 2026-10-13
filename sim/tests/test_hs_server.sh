#!/usr/bin/env bash
# Task 4: Headscale server in CT 101 behind Caddy with an ACME cert from the sim CA; hardened.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
C="--cacert campus/root_ca.crt --resolve $HS_FQDN:443:$IP_HS"
assert_contains "$(curl -s -m 10 $C https://$HS_FQDN/health)" pass "health"
assert_contains "$(echo | timeout 10 openssl s_client -connect $IP_HS:443 -servername $HS_FQDN -CAfile campus/root_ca.crt -verify_return_error 2>&1)" \
  "Verify return code: 0 (ok)" "cert chains to the sim root via ACME"
assert_fails sh -c "echo | timeout 10 openssl s_client -tls1_1 -connect $IP_HS:443 -servername $HS_FQDN 2>/dev/null | grep -q 'BEGIN CERT'"
assert_ok ct_exec server1 "$CT_HS" "sudo -u headscale headscale configtest"
assert_contains "$(ct_exec server1 "$CT_HS" 'headscale policy check -f /etc/headscale/policy.hujson' 2>&1)" "Policy is valid" "policy valid"
assert_eq "$(ct_exec server1 "$CT_LABB1" "nmap -Pn -T4 --max-retries 1 -p1-10000 --open -oG - $IP_HS" | grep -oE '[0-9]+/open' | sort -n | tr '\n' ' ')" \
  "80/open 443/open " "non-admin sees only 80,443"
assert_contains "$(nmap -Pn -p22 --open $IP_HS 2>&1 | grep -E "^22/|Note|down")" "22/tcp open" "admin IP gets SSH"
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "4	server1	vzdump" "original CT 101 backed up"
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "4	server1	backup-job	backup-weekly" "101 out of weekly job"
assert_eq "$(hs users list -o json | jq -r '(. // [])[].name' | sort | tr '\n' ' ')" "admin1 alice bob " "users"
assert_eq "$(ct_exec server1 "$CT_HS" 'dpkg-query -W -f="\${Version}" headscale')" "$HEADSCALE_VERSION" "pinned headscale"
t_done
