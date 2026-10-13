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
t_done
