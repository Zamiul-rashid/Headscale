#!/usr/bin/env bash
# Task 6: researcher/admin devices enrolled; Phase 1 "done when": two clients ping, netcheck sees campus DERP.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
ON=$(hs nodes list -o json | jq -r '(. // [])[] | select(.online // false) | .given_name' | sort | tr '\n' ' ')
for n in admin-enigma alice-laptop bob-enigma; do assert_contains "$ON" "$n" "$n online"; done
assert_contains "$(node_exec alice-laptop 'tailscale ping --c 3 admin-enigma' 2>&1)" "pong" "alice<->admin ping"
assert_contains "$(node_exec alice-laptop 'tailscale netcheck' 2>&1)" "campus" "campus DERP listed"
assert_eq "$(tailscale status --json | jq -r '.BackendState + " " + .CurrentTailnet.Name')" \
          "$(jq -r '.BackendState + " " + .CurrentTailnet.Name' ledger/baseline/enigma-tailscale.json)" "enigma hosted tailnet untouched"
assert_eq "$(run_on laptop 'tailscale status --json' | jq -r '.BackendState + " " + .CurrentTailnet.Name')" \
          "$(jq -r '.BackendState + " " + .CurrentTailnet.Name' ledger/baseline/laptop-tailscale.json)" "laptop hosted tailnet untouched"
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "6	laptop	package	docker.io" "laptop docker install ledgered"
assert_contains "$(cut -f2-5 ledger/ledger.tsv)" "6	enigma	docker-project	hs-sim" "enigma containers ledgered"
t_done
