#!/usr/bin/env bash
# Run named hs-sim tests in order; stop at the first failing file.
#   tests/run.sh test_ledger test_preflight
cd "$(dirname "$0")" || exit 1
for t in "$@"; do
  echo "== $t"; bash "./$t.sh" || { echo "== $t FAILED"; exit 1; }
done
