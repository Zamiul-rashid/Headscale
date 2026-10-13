#!/usr/bin/env bash
# Task 11: one collect.sh run appends one well-formed soak sample.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
S=results/soak.csv
before=$( [ -f $S ] && wc -l < $S || echo 0 )
tests/collect.sh >/dev/null 2>&1
after=$(wc -l < $S 2>/dev/null || echo 0)
[ "$before" -eq 0 ] && before=1   # header is written on the first run
assert_eq "$after" "$((before+1))" "one row appended"
assert_eq "$(head -1 $S)" "ts,nodes_total,nodes_online,hs_health,cert_hours_left,direct_share,enigma_tailnet_ok" "header"
assert_ok sh -c "tail -1 $S | grep -qE '^[0-9T:+-]+,[0-9]+,[0-9]+,(ok|fail),-?[0-9.]+,[0-9.]+,[01]\$'"
assert_eq "$(tail -1 $S | cut -d, -f4)" ok "health ok"
assert_eq "$(tail -1 $S | cut -d, -f7)" 1 "hosted tailnets untouched"
t_done
