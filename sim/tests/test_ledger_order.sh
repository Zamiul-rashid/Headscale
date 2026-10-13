#!/usr/bin/env bash
# Static checks on the real ledger: teardown must be able to finish what it starts.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
L=ledger/ledger.tsv
# teardown runs newest-first, so the row that removes our SSH key must be the OLDEST row for that host
for h in $(awk -F'\t' '$4=="authorized_key" {print $3}' $L | sort -u); do
  first=$(awk -F'\t' -v h="$h" '$3==h {print $4; exit}' $L)
  assert_eq "$first" authorized_key "$h: SSH key removal is undone last"
done
# on the laptop, entropy is not in the docker group: every docker call in an undo needs sudo
assert_eq "$(awk -F'\t' '$3=="laptop" {print $6}' $L | grep -cE '(^|[;|&] *|xargs -r +)docker ')" 0 "laptop undo commands use sudo docker"
# the base image pulled for the client build is cleaned up with the project
assert_contains "$(awk -F'\t' '$3=="enigma" && $4=="docker-project" {print $6}' $L)" "tailscale/tailscale:v" "base image removed on enigma"
t_done
