# hs-sim — Headscale pilot rehearsal on the home lab

A reversible simulation of the lab Headscale pilot (`../README.md`), built from
`../docs/superpowers/plans/2026-10-13-headscale-home-sim.md`.

Every change made outside a simulation-owned container is recorded in
`ledger/ledger.tsv` together with its undo command. To remove the simulation:

    ./teardown.sh --dry-run     # review what will be undone
    ./teardown.sh               # undo everything, newest first
    tests/test_pristine.sh      # compare against ledger/baseline/

Setup order: `SUDO_PW=... ./bootstrap-access.sh`, then `./preflight.sh`.
