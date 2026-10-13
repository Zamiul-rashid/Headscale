#!/usr/bin/env bash
# Pure-function checks (no hosts touched).
cd "$(dirname "$0")/.." || exit 1
. tests/lib/assert.sh
. lib/common.sh
# server0 may only be enrolled natively if it has NO tailscale at all; any installed tailscaled
# (running, stopped or logged out) belongs to the user's hosted tailnet and must not be re-pointed
assert_eq "$(server0_mode '{"BackendState":"NotInstalled"}')" native "no tailscale -> native"
assert_eq "$(server0_mode '{"BackendState":"Running"}')" docker "running hosted tailscale -> docker"
assert_eq "$(server0_mode '{"BackendState":"Stopped"}')" docker "stopped hosted tailscale -> docker"
assert_eq "$(server0_mode '{"BackendState":"NeedsLogin"}')" docker "logged-out tailscale -> docker"
t_done
