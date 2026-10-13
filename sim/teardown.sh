#!/usr/bin/env bash
# Undo everything recorded in ledger/ledger.tsv, newest first.
#   ./teardown.sh [--dry-run] [--task N]
# Rows already in ledger/done.tsv are skipped; failures are reported and the rest continues.
cd "$(dirname "$0")" || exit 1
. lib/common.sh
dry=0 only=
while [ $# -gt 0 ]; do
  case $1 in --dry-run) dry=1 ;; --task) only=$2; shift ;; *) die "usage: $0 [--dry-run] [--task N]" ;; esac
  shift
done
L=$LEDGER_DIR/ledger.tsv D=$LEDGER_DIR/done.tsv
[ -f "$L" ] || { log "no ledger, nothing to undo"; exit 0; }
touch "$D"
failed=()
mapfile -t rows < <(tac "$L")
for row in "${rows[@]}"; do
  IFS=$'\t' read -r _ts task host kind id undo <<<"$row"
  [ -n "$only" ] && [ "$task" != "$only" ] && continue
  key="$task	$host	$kind	$id"
  grep -qxF "$key" "$D" && continue
  if [ "$kind" = manual ]; then echo "MANUAL [$host] $id: $undo"; continue; fi
  if [ $dry -eq 1 ]; then echo "UNDO [task $task] [$host] $kind $id: $undo"; continue; fi
  log "undo [task $task] [$host] $kind $id"
  if run_on "$host" "$undo"; then echo "$key" >> "$D"; else failed+=("$key"); fi
done
if [ ${#failed[@]} -gt 0 ]; then
  printf 'FAILED undo:\n'; printf '  %s\n' "${failed[@]}"; exit 1
fi
