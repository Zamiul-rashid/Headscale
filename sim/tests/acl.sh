#!/usr/bin/env bash
# Check every row of tests/acl_expectations.tsv with a real TCP connect over the tailnet.
#   tests/acl.sh [expectations.tsv]  -> results/acl.csv ; exit 0 iff every checked row matches
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh
EXP=${1:-tests/acl_expectations.tsv}
online=$(hs nodes list -o json | jq -r '(. // [])[] | select(.online // false) | .given_name')
declare -A ip
# researcher/admin devices have no permanent listener on 9999: start one for this run only
listen()   { node_exec "$1" "socat TCP-LISTEN:9999,fork,reuseaddr EXEC:/bin/echo >/dev/null 2>&1 & echo \$! > /tmp/hs-sim-acl.pid"; }
unlisten() { node_exec "$1" 'kill $(cat /tmp/hs-sim-acl.pid) 2>/dev/null; rm -f /tmp/hs-sim-acl.pid'; }
devices=$(awk -F'\t' '!/^#/ && $2 ~ /^(alice|bob|admin)/ {print $2}' "$EXP" | sort -u)
for d in $devices; do grep -qxF "$d" <<<"$online" && listen "$d"; done
trap 'for d in $devices; do grep -qxF "$d" <<<"$online" && unlisten "$d"; done' EXIT
mkdir -p results; echo "src,dst,port,expect,got,pass" > results/acl.csv
fail=0 skipped=0
while IFS=$'\t' read -r src dst port expect <&3; do
  case $src in ''|\#*) continue ;; esac
  if ! grep -qxF "$src" <<<"$online" || ! grep -qxF "$dst" <<<"$online"; then
    skipped=$((skipped+1)); echo "$src,$dst,$port,$expect,skipped,skipped" >> results/acl.csv; continue
  fi
  [ -n "${ip[$dst]:-}" ] || ip[$dst]=$(node_ip "$dst")
  if node_exec "$src" "nc -z -w 3 ${ip[$dst]} $port" >/dev/null 2>&1; then got=allow; else got=deny; fi
  [ "$got" = "$expect" ] && pass=yes || { pass=NO; fail=$((fail+1)); }
  echo "$src,$dst,$port,$expect,$got,$pass" >> results/acl.csv
done 3< "$EXP"
checked=$(( $(wc -l < results/acl.csv) - 1 - skipped ))
log "ACL: $((checked-fail))/$checked as expected, $skipped skipped (node not enrolled)"
[ "$checked" -gt 0 ] || { log "no ACL row could be checked"; exit 1; }
[ "$fail" -eq 0 ]
