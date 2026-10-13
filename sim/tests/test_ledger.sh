#!/usr/bin/env bash
# Ledger + teardown engine, exercised locally against host "enigma" in a temp ledger.
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
T=$(mktemp -d); export LEDGER_DIR=$T/ledger; mkdir -p "$LEDGER_DIR"
trap 'rm -rf "$T"' EXIT
. lib/common.sh

ledger_add 1 enigma file a "echo 1 >> $T/order"; ledger_add 1 enigma file a "echo 1 >> $T/order"
assert_eq "$(wc -l < "$LEDGER_DIR/ledger.tsv")" 1 "duplicate add is a no-op"
ledger_add 2 enigma file b "echo 2 >> $T/order"; ledger_add 2 enigma file c "false"
ledger_add 3 enigma file d "echo 3 >> $T/order"
assert_eq "$(./teardown.sh --dry-run | grep -c UNDO)" 4 "dry-run lists 4"
assert_fails test -e "$T/order"
./teardown.sh --task 3 >/dev/null; assert_eq "$(cat "$T/order")" "3" "--task 3 only"
assert_fails ./teardown.sh                    # row c fails...
assert_eq "$(tr '\n' ' ' < "$T/order")" "3 2 1 " "...but the rest ran, reverse order"
assert_fails ./teardown.sh
assert_eq "$(tr '\n' ' ' < "$T/order")" "3 2 1 " "re-run only retries the failed row"
ledger_add 4 enigma manual router "Remove port-forward X"
assert_contains "$(./teardown.sh --task 4)" "MANUAL" "manual rows are printed, not run"
# a resource re-created after its undo ran must be undone again by the next teardown
ledger_add 3 enigma file d "echo 3 >> $T/order"
assert_eq "$(./teardown.sh --dry-run --task 3 | grep -c UNDO)" 1 "re-created resource is active again"
./teardown.sh --task 3 >/dev/null
assert_eq "$(tail -1 "$T/order")" "3" "and gets undone again"
# scripts run ledger_add under set -e; an empty done.tsv must not abort them
: > "$LEDGER_DIR/done.tsv"
assert_ok bash -c "set -euo pipefail; LEDGER_DIR=$LEDGER_DIR; . lib/common.sh; ledger_add 5 enigma file e true; echo reached" 
assert_contains "$(cut -f2-5 "$LEDGER_DIR/ledger.tsv")" "5	enigma	file	e" "row added under set -e"
# re-creating with a NEW undo (e.g. a new archive name) must replace the stale row and move it to the end
./teardown.sh --task 3 >/dev/null
ledger_add 3 enigma file d "echo 33 >> $T/order"
assert_eq "$(tail -1 "$LEDGER_DIR/ledger.tsv" | cut -f6)" "echo 33 >> $T/order" "re-created row carries the new undo and is newest"
assert_eq "$(awk -F'\t' '$2==3 && $5=="d"' "$LEDGER_DIR/ledger.tsv" | wc -l)" 1 "no duplicate row for the re-created resource"
# --keep-access leaves task 0 (sudo/SSH access) rows for a separate final step
ledger_add 0 enigma sudoers zz "echo 0 >> $T/order"
out=$(./teardown.sh --dry-run --keep-access 2>&1)
assert_eq "$(grep -c 'task 0' <<<"$out")" 0 "--keep-access skips task 0 rows"
assert_ok test "$(grep -c UNDO <<<"$out")" -ge 1
assert_eq "$(./teardown.sh --dry-run | grep -c 'task 0')" 1 "plain teardown includes task 0"
t_done
