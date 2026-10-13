#!/usr/bin/env bash
# Revocation timing (proposal §11: ≤ 1 min). Cases: node-expire, group-remove, expired-key.
#   tests/revocation.sh -> results/revocation.csv ; exit 0 iff all pass. Leaves access as it found it.
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh
POL=/etc/headscale/policy.hujson
tgt=$(node_ip lab-b-01)
can() { node_exec "$1" "nc -z -w 3 $tgt 22" >/dev/null 2>&1; }
node_id() { hs nodes list -o json | jq -r --arg n "$1" '(. // [])[] | select(.given_name==$n) | .id'; }
# wait_until <timeout-s> <cmd...>: seconds until cmd succeeds, or "timeout"
wait_until() { local t0=$(date +%s) lim=$1; shift; until "$@"; do [ $(( $(date +%s) - t0 )) -ge "$lim" ] && { echo timeout; return 1; }; sleep 2; done; echo $(( $(date +%s) - t0 )); }
cannot() { ! can "$1"; }
restore_policy() { ct_exec server1 "$CT_HS" "test -f $POL.hs-sim-orig && mv $POL.hs-sim-orig $POL && systemctl reload headscale" >/dev/null 2>&1 || true; }
trap restore_policy EXIT
mkdir -p results; echo "case,seconds,pass" > results/revocation.csv
fail=0; rec() { local p=no; [ "$2" != timeout ] && [ "$2" -le 60 ] && p=yes; [ $p = yes ] || fail=1; echo "$1,$2,$p" >> results/revocation.csv; log "$1: ${2}s pass=$p"; }

# 1. node-expire: alice's laptop is expired by an admin
can alice-laptop || { log "precondition: alice cannot reach lab-b-01:22"; exit 1; }
hs nodes expire -i "$(node_id alice-laptop)" >/dev/null
rec node-expire "$(wait_until 120 cannot alice-laptop)"
clients/reenroll.sh alice-laptop >/dev/null 2>&1   # what an admin does to re-admit an expired device
wait_until 90 can alice-laptop >/dev/null || { log "alice did not regain access"; fail=1; }

# 2. group-remove: bob leaves group:researchers (policy file edit + SIGHUP)
can bob-enigma || { log "precondition: bob cannot reach lab-b-01:22"; exit 1; }
ct_exec server1 "$CT_HS" "cp -p $POL $POL.hs-sim-orig && sed -i 's/\"group:researchers\": \[\"alice@\", \"bob@\"\]/\"group:researchers\": [\"alice@\"]/' $POL && grep -q '\"group:researchers\": \[\"alice@\"\]' $POL && headscale policy check -f $POL >/dev/null && systemctl reload headscale"
rec group-remove "$(wait_until 120 cannot bob-enigma)"
restore_policy
wait_until 90 can bob-enigma >/dev/null || { log "bob did not regain access"; fail=1; }

# 3. expired-key: a key past its expiry cannot enrol a new device
k=$(clients/mkkey.sh bob --expiration 1s); sleep 3
KEY_TMP=$k TS_VERSION=$TS_VERSION docker compose -f clients/enigma/compose.yaml --profile tmp up -d hs-sim-tmp >/dev/null 2>&1
sleep 25
why=$(docker logs hs-sim-tmp 2>&1 | grep -o 'authkey expired' | head -1)
TS_VERSION=$TS_VERSION docker compose -f clients/enigma/compose.yaml --profile tmp rm -sfv hs-sim-tmp >/dev/null 2>&1
id=$(node_id hs-sim-tmp); [ -n "$id" ] && hs nodes delete -i "$id" --force >/dev/null
if [ "$why" = "authkey expired" ] && [ -z "$id" ]; then echo "expired-key,0,yes" >> results/revocation.csv; log "expired-key: rejected by control ($why)"
else echo "expired-key,0,no" >> results/revocation.csv; fail=1; log "expired-key: not rejected as expected (log: '$why', node id: '$id')"; fi
exit $fail
