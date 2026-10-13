#!/usr/bin/env bash
# Task 11: report.sh turns result CSVs into the proposal §11 success-criteria table (fixture data).
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
F=tests/fixtures; rm -f $F/report.md
tests/report.sh $F >/dev/null; R=$F/report.md
row() { grep -i "^| $1" "$R"; }
assert_contains "$(row Uptime)" "99.5" "uptime computed (199/200)"
assert_contains "$(row Uptime)" "PASS" "99.5 >= 99"
assert_contains "$(row Throughput)" "0.65" "worst throughput ratio"
assert_contains "$(row Throughput)" "FAIL" "0.65 < 0.70"
assert_contains "$(row 'Added latency')" "1.5" "worst added latency"
assert_contains "$(row 'Added latency')" "PASS" "1.5 <= 5"
assert_contains "$(row 'Direct')" "85" "17/20 reachable pairs direct"
assert_contains "$(row 'Direct')" "PASS" "85% >= 80%"
assert_contains "$(row 'Mean enrolment')" "207" "mean of lab-* rows only (620/3)"
assert_contains "$(row 'ACL')" "100" "ACL pass rate"
assert_contains "$(row 'Revocation')" "6" "worst revocation time"
assert_contains "$(row 'Backup restore')" "63" "RTO"
assert_contains "$(row 'TLS certificate')" "FAIL" "an expired-cert sample fails the cert row"
assert_contains "$(cat $R)" "cert_hours_left" "expired-cert sample listed"
assert_contains "$(row 'User satisfaction')" "N/A" "survey not simulated"
assert_contains "$(row 'Hosted tailnets')" "PASS" "enigma tailnet never changed"
assert_contains "$(cat $R)" "Windows" "gaps listed"
assert_contains "$(cat $R)" "relayed-session-loss-pct" "outage findings included"
assert_eq "$(row Throughput | grep -c '0\.09')" 0 "same-room bridge pair is not graded"
assert_contains "$(cat $R)" "same-room" "same-room pair shown as informational"
assert_contains "$(row 'ACL')" "3 skipped" "skipped ACL rows are visible"
assert_contains "$(row 'Soak coverage')" "200 samples" "soak sample count"
assert_contains "$(row 'Soak coverage')" "PASS" "199 h span, no gaps, >= 7 days * 0.9"
t_done
