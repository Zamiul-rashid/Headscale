#!/usr/bin/env bash
# Task 8: connectivity matrix (open vs udp-blocked) + LAN-vs-tailnet performance.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
campus/fw-mode.sh open;        tests/connectivity_matrix.sh open;  tests/perf.sh open
campus/fw-mode.sh udp-blocked; tests/connectivity_matrix.sh udp-blocked
campus/fw-mode.sh open
O=results/connectivity-open.csv U=results/connectivity-udp-blocked.csv
path() { awk -F, -v s="$2" -v d="$3" '$1==s && $2==d {print $3}' "$1"; }
n=$(tail -n +2 "$O" | cut -d, -f1 | sort -u | wc -l)
assert_ok test "$n" -ge 5
assert_eq "$(head -1 "$O")" "src,dst,path,latency_ms" "header"
assert_eq "$(tail -n +2 "$O" | wc -l)" "$((n*(n-1)))" "every ordered pair of $n nodes"
assert_eq "$(path "$U" lab-b-01 lab-b-02)" direct "udp-blocked: same room stays direct"
assert_eq "$(awk -F, 'NR>1 && (($1 ~ /^lab-b/) != ($2 ~ /^lab-b/)) && $3=="direct"' "$U" | wc -l)" 0 "udp-blocked: no direct path crosses the room-B firewall"
assert_eq "$(tail -n +2 "$O" | cut -d, -f4 | grep -cvE '^([0-9.]+)?$')" 0 "latencies parse as numbers"
assert_eq "$(path "$O" alice-laptop bob-enigma)" no-peer "ACL hides researcher laptops from each other"
if [ -n "$SERVER0_SSH" ]; then assert_eq "$(path "$O" alice-laptop lab-a-01)" direct "open: laptop->lab-a-01 direct"; fi
assert_eq "$(head -1 results/perf-open.csv)" "pair,lan_mbps,ts_mbps,ratio,lan_ms,ts_ms,added_ms" "perf header"
assert_ok sh -c "grep -qE '^same-room,[0-9.]+,[0-9.]+,[0-9.]+,' results/perf-open.csv"
assert_ok sh -c "grep -qE '^laptop-roomb,NA,[0-9.]+,NA,NA,[0-9.]+,NA$' results/perf-open.csv"   # every pair whose nodes are online gets a row
t_done
