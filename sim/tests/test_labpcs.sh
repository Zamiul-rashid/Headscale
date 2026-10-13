#!/usr/bin/env bash
# Task 7: lab PCs enrolled with tags, reconnect after reboot with nobody logged in, MagicDNS works.
# lab-a-01 (server0 host) is checked only once SERVER0_SSH is configured.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
LABS="lab-b-01 lab-b-02"; [ -n "$SERVER0_SSH" ] && LABS="lab-a-01 $LABS"
for id in $CT_LABB1 $CT_LABB2; do run_on server1 "pct reboot $id"; done
[ -n "$SERVER0_SSH" ] && run_on server0 "sudo systemctl restart tailscaled"   # don't reboot server0: it hosts other services
online() { hs nodes list -o json | jq -r --arg n "$1" '(. // [])[] | select(.given_name==$n) | (.online // false)'; }
for n in $LABS; do
  t=0; until [ "$(online $n)" = true ] || [ $t -ge 120 ]; do sleep 5; t=$((t+5)); done
  assert_eq "$(online $n)" true "$n online after reboot"
done
J=$(hs nodes list -o json)
assert_contains "$(jq -c '(. // [])[] | select(.given_name=="lab-b-02") | (.tags // [])' <<<"$J")" "tag:gpu" "lab-b-02 has tag:gpu"
assert_contains "$(jq -c '(. // [])[] | select(.given_name=="lab-b-01") | (.tags // [])' <<<"$J")" "tag:labpc" "lab-b-01 has tag:labpc"
assert_eq "$(awk -F, '/^lab-/{s+=$2;n++} END{print (n>0 && s/n<=600)?"ok":"slow-or-none"}' results/enrolment.csv)" ok "mean lab enrolment <= 10 min"
assert_eq "$(node_exec alice-laptop 'dig +short lab-b-01.lab.internal' | head -1)" "$(node_ip lab-b-01)" "MagicDNS from alice"
assert_contains "$(ct_exec server1 "$CT_LABB1" "ss -ltnp | grep :5900")" "iperf3" "iperf3 serves the VNC slot (5900) so researchers can run perf within the ACL"
for p in 22 3389 5900 8888 9999; do assert_ok ct_exec server1 "$CT_LABB1" "ss -ltn | grep -q ':$p '"; done
t_done
