#!/usr/bin/env bash
# Path (direct / derp:<region> / no-peer / fail) and latency for every ordered pair of enrolled nodes.
#   tests/connectivity_matrix.sh <label> [--src <node>]   -> results/connectivity-<label>.csv
cd "$(dirname "$0")/.." || exit 1
. lib/common.sh
label=${1:?usage: $0 <label> [--src node]}; only=
[ "${2:-}" = --src ] && only=$3
online=$(hs nodes list -o json | jq -r '(. // [])[] | select(.online // false) | .given_name')
nodes=$(cut -f1 config/nodes.tsv | grep -xF "$online")
# tailscale prints Go durations (0s, 512µs, 3ms, 1.2s); convert to milliseconds
to_ms() {
  sed -E 's/.* in ([0-9.]+)(ns|µs|us|ms|s)$/\1 \2/' <<<"$1" |
    awk '{m = ($2=="ns") ? 1e-6 : ($2=="µs" || $2=="us") ? 1e-3 : ($2=="ms") ? 1 : 1000; printf "%.3f", $1*m}'
}
declare -A ip; for n in $nodes; do ip[$n]=$(node_ip "$n"); done
out=results/connectivity-$label.csv; mkdir -p results
echo "src,dst,path,latency_ms" > "$out"
for s in $nodes; do
  [ -n "$only" ] && [ "$s" != "$only" ] && continue
  for d in $nodes; do
    [ "$s" = "$d" ] && continue
    # default mode keeps pinging (max 10) until a direct path is up, so the last pong is the settled path
    r=$(node_exec "$s" "tailscale ping --c 10 --timeout 3s ${ip[$d]}" 2>&1 | grep -E 'pong from|no matching peer' | tail -1)
    case $r in
      *"no matching peer"*) p=no-peer ms= ;;
      *"via DERP("*) p="derp:$(sed -E 's/.*via DERP\(([^)]*)\).*/\1/' <<<"$r")"; ms=$(to_ms "$r") ;;
      *"pong from"*) p=direct; ms=$(to_ms "$r") ;;
      *) p=fail ms= ;;
    esac
    echo "$s,$d,$p,$ms" >> "$out"
  done
done
log "$out: $(tail -n +2 "$out" | cut -d, -f3 | sed 's/:.*//' | sort | uniq -c | tr '\n' ' ')"
