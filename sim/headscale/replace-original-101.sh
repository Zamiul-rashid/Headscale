#!/usr/bin/env bash
# Task 4 step 3: take the user's original CT 101 out of service so the sim can rebuild it.
# Ledgered so teardown restores it exactly: weekly-job membership, protected vzdump, the CT itself.
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
if run_on server1 "pct config $CT_HS" 2>/dev/null | grep -q '^tags:.*hs-sim'; then log "CT $CT_HS is already the sim server"; exit 0; fi
run_on server1 "pct status $CT_HS" >/dev/null 2>&1 || die "CT $CT_HS not found and not ledgered; refusing to guess"
mkdir -p results; run_on server1 "pct config $CT_HS" > results/original-ct101-config.txt

jobs=$(run_on server1 "pvesh get /cluster/backup/backup-weekly --output-format json" | jq -r .vmid)
if grep -qw "$CT_HS" <<<"${jobs//,/ }"; then
  new=$(tr ',' '\n' <<<"$jobs" | grep -vx "$CT_HS" | paste -sd,)
  ledger_add 4 server1 backup-job backup-weekly "pvesh set /cluster/backup/backup-weekly --vmid $jobs"
  run_on server1 "pvesh set /cluster/backup/backup-weekly --vmid $new"
fi

find_archive() {
  run_on server1 "pvesh get /nodes/$PVE1_NODE/storage/$BACKUP_STORAGE/content --content backup --vmid $CT_HS --output-format json" \
    | jq -r '[.[] | select(.protected==1 and (.notes//"" | test("hs-sim")))] | sort_by(.ctime) | last | .volid // empty'
}
volid=$(find_archive)
if [ -z "$volid" ]; then
  run_on server1 "vzdump $CT_HS --storage $BACKUP_STORAGE --mode stop --compress zstd --protected 1 --notes-template 'hs-sim: original CT 101 before simulation'" >/dev/null
  volid=$(find_archive)
fi
[ -n "$volid" ] || die "could not find the protected vzdump archive"
ledger_add 4 server1 vzdump "$volid" "if pct config $CT_HS 2>/dev/null | grep -q '^tags:.*hs-sim' || ! pct config $CT_HS >/dev/null 2>&1; then echo 'CT $CT_HS is not the restored original; keeping $volid' >&2; exit 1; fi; pvesh set /nodes/$PVE1_NODE/storage/$BACKUP_STORAGE/content/$volid --protected 0 && pvesm free $volid"
ledger_add 4 server1 ct-original "$CT_HS" "if pct status $CT_HS >/dev/null 2>&1; then pct stop $CT_HS >/dev/null 2>&1; pct destroy $CT_HS --purge; fi; pct restore $CT_HS $volid --storage local-lvm >/dev/null"
run_on server1 "pct destroy $CT_HS"
log "original CT $CT_HS archived as $volid (protected) and removed"
