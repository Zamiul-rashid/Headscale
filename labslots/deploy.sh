#!/usr/bin/env bash
# Deploy labslots on this host (run in /opt/labslots, after the new source is in place):
#
#   ./deploy.sh             build a new image from this folder, switch to it, roll back if unhealthy
#   ./deploy.sh rollback    switch back to the image that ran before the last deploy
#   ./deploy.sh status      show the running tag, the kept images and container health
#
# Every build is tagged labslots:<date-time> and the running tag is kept in .env as LABSLOTS_TAG,
# so a rollback is just pointing the containers at the previous tag. The last 5 images are kept.
set -euo pipefail
cd "$(dirname "$0")"

SERVICES=(labslots labslots-agent backup)
CHECKED=(labslots labslots-agent)          # services with a healthcheck that must pass
KEEP=5

current_tag() { grep -oP '^LABSLOTS_TAG=\K.*' .env 2>/dev/null || echo local; }
set_tag() {
  touch .env
  sed -i '/^LABSLOTS_TAG=/d' .env
  echo "LABSLOTS_TAG=$1" >> .env
  if [ -n "${2:-}" ]; then sed -i '/^LABSLOTS_PREV_TAG=/d' .env; echo "LABSLOTS_PREV_TAG=$2" >> .env; fi
}
health() { docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }

wait_healthy() {
  local deadline=$((SECONDS + 150))
  while [ $SECONDS -lt $deadline ]; do
    local ok=1
    for c in "${CHECKED[@]}"; do
      case "$(health "$c")" in
        healthy) ;;
        unhealthy|exited|dead|missing) echo "  $c: $(health "$c")"; return 1 ;;
        *) ok=0 ;;
      esac
    done
    [ $ok = 1 ] && return 0
    sleep 5
  done
  for c in "${CHECKED[@]}"; do echo "  $c: $(health "$c")"; done
  return 1
}

switch_to() {
  set_tag "$1" "${2:-}"
  LABSLOTS_TAG="$1" docker compose up -d --no-build "${SERVICES[@]}"
}

case "${1:-deploy}" in
  deploy)
    prev=$(current_tag)
    new=$(date +%Y%m%d-%H%M%S)
    echo "building labslots:$new (running: $prev)"
    docker build -q -t "labslots:$new" . >/dev/null
    switch_to "$new" "$prev"
    echo "waiting for health checks"
    if wait_healthy; then
      echo "deployed labslots:$new"
    else
      echo "labslots:$new is unhealthy; rolling back to $prev"
      docker logs --tail 30 labslots 2>&1 | sed 's/^/  labslots: /'
      switch_to "$prev"
      wait_healthy && echo "rolled back to labslots:$prev" || echo "rollback also unhealthy: check docker logs"
      exit 1
    fi
    # keep the newest images, never the ones in use
    docker images labslots --format '{{.Tag}}' | grep -E '^[0-9]{8}-[0-9]{6}$' | sort -r | tail -n +$((KEEP + 1)) |
      while read -r t; do [ "$t" != "$prev" ] && docker rmi -f "labslots:$t" >/dev/null 2>&1 || true; done
    ;;
  rollback)
    prev=$(grep -oP '^LABSLOTS_PREV_TAG=\K.*' .env 2>/dev/null || true)
    [ -n "$prev" ] || { echo "no previous tag recorded"; exit 1; }
    cur=$(current_tag)
    echo "rolling back labslots:$cur -> labslots:$prev"
    switch_to "$prev" "$cur"
    wait_healthy && echo "running labslots:$prev"
    ;;
  status)
    echo "running tag: $(current_tag)   previous: $(grep -oP '^LABSLOTS_PREV_TAG=\K.*' .env 2>/dev/null || echo none)"
    docker images labslots --format '  {{.Tag}}  {{.CreatedSince}}'
    for c in labslots labslots-agent labslots-backup ts-scheduler; do echo "  $c: $(health "$c")"; done
    [ -f backups/.last-ok ] && echo "  last backup: $(cat backups/.last-ok)"
    ;;
  *) echo "usage: $0 [deploy|rollback|status]"; exit 2 ;;
esac
