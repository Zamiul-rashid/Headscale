#!/usr/bin/env bash
# Print a new pre-auth key.  clients/mkkey.sh <user|-> [--tags tag:a,tag:b] [--reusable] [--expiration 24h]
# "-" = no user (tagged key; lab PCs are owned by their tags). Default: single-use, 24h.
set -euo pipefail
cd "$(dirname "$0")/.."
. lib/common.sh
user=${1:?usage: $0 <user|-> [--tags ...] [--reusable] [--expiration 24h]}; shift
args="--expiration 24h"
while [ $# -gt 0 ]; do
  case $1 in --tags) args+=" --tags $2"; shift ;; --reusable) args+=" --reusable" ;; --expiration) args+=" --expiration $2"; shift ;; *) die "bad option $1" ;; esac
  shift
done
if [ "$user" != - ]; then
  id=$(hs users list -o json | jq -r --arg u "$user" '(. // [])[] | select(.name==$u) | .id')
  [ -n "$id" ] || die "no headscale user '$user'"
  args+=" --user $id"
fi
hs preauthkeys create $args -o json | jq -r .key
