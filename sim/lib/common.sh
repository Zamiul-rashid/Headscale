# Shared helpers for every hs-sim script. Source it; it does not set shell options.
SIM_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$SIM_ROOT/config/sim.env"
[ -f "$SIM_ROOT/config/versions.env" ] && . "$SIM_ROOT/config/versions.env"
LEDGER_DIR=${LEDGER_DIR:-$SIM_ROOT/ledger}
SSH_OPTS=(-o BatchMode=yes -o IdentitiesOnly=yes -i "$HOME/.ssh/id_ed25519" -o ConnectTimeout=10)

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# run_on <host> <cmd>: run a shell command on enigma (local), server1, server0 or the laptop.
run_on() {
  local host=$1; shift
  case $host in
    enigma)  bash -c "$*" ;;
    server1) ssh "${SSH_OPTS[@]}" "$PVE1" "$*" ;;
    server0) [ -n "$SERVER0_SSH" ] || die "SERVER0_SSH is not set in config/sim.env"
             # shellcheck disable=SC2086
             ssh "${SSH_OPTS[@]}" $SERVER0_SSH_OPTS "$SERVER0_SSH" "$*" ;;
    laptop)  ssh "${SSH_OPTS[@]}" "$LAPTOP_SSH" "$*" ;;
    *) die "run_on: unknown host '$host'" ;;
  esac
}

# ct_exec <pve-host> <vmid> <cmd>: run a command inside a Proxmox CT.
ct_exec() { local host=$1 vmid=$2; shift 2; run_on "$host" "pct exec $vmid -- bash -lc $(printf %q "$*")"; }

# node_exec <node> <cmd>: run a command on a tailnet node, dispatched by config/nodes.tsv.
node_exec() {
  local node=$1; shift
  local exec target
  read -r exec target < <(awk -F'\t' -v n="$node" '$1==n {print $3, $4}' "$SIM_ROOT/config/nodes.tsv")
  [ -n "$exec" ] || die "node_exec: unknown node '$node'"
  case $exec in
    pct)    ct_exec "${target%%:*}" "${target#*:}" "$*" ;;
    ssh)    run_on "$target" "$*" ;;
    docker) if [[ $target == *:* ]]; then
              run_on "${target%%:*}" "sudo -n docker exec ${target#*:} sh -c $(printf %q "$*")"
            else
              docker exec "$target" sh -c "$*"
            fi ;;
    *) die "node_exec: bad exec '$exec' for $node" ;;
  esac
}

node_ip() { node_exec "$1" "tailscale ip -4" | head -1; }

hs() { ct_exec server1 "$CT_HS" "headscale $*"; }

# ledger_add <task> <host> <kind> <id> <undo_cmd>: record a created resource and how to undo it.
ledger_add() {
  local task=$1 host=$2 kind=$3 id=$4 undo=$5
  mkdir -p "$LEDGER_DIR"; touch "$LEDGER_DIR/ledger.tsv"
  # re-creating something teardown already undid makes its row active again
  if [ -f "$LEDGER_DIR/done.tsv" ]; then
    grep -vxF "$task	$host	$kind	$id" "$LEDGER_DIR/done.tsv" > "$LEDGER_DIR/done.tsv.tmp" || true
    mv "$LEDGER_DIR/done.tsv.tmp" "$LEDGER_DIR/done.tsv"
  fi
  awk -F'\t' -v t="$task" -v h="$host" -v k="$kind" -v i="$id" \
    '$2==t && $3==h && $4==k && $5==i {f=1} END {exit !f}' "$LEDGER_DIR/ledger.tsv" && return 0
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -Is)" "$task" "$host" "$kind" "$id" "$undo" >> "$LEDGER_DIR/ledger.tsv"
}

# grafana_has_dashboard <uid>: prints yes/no by reading CT 110's Grafana database read-only.
grafana_has_dashboard() {
  ct_exec server1 "$CT_MON" "python3 -c \"import sqlite3,sys; c=sqlite3.connect('file:/opt/monitoring-stack/data/grafana/grafana.db?mode=ro', uri=True); print('yes' if c.execute('select 1 from dashboard where uid=?', ('$1',)).fetchone() else 'no')\""
}
