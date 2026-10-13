# hs-sim — Headscale pilot rehearsal on the home lab

> **Torn down on 2026-10-13.** The record of what was built, measured and removed is in `../records/`.

A reversible simulation of the lab Headscale pilot (`../README.md`), built from
`../docs/superpowers/plans/2026-10-13-headscale-home-sim.md`.

Every change made outside a simulation-owned container is recorded in
`ledger/ledger.tsv` together with its undo command. `ledger/baseline/` holds the
state of each machine before the simulation started.

## Topology

| Role | Where | Address | ID |
|---|---|---|---|
| Headscale + Caddy + embedded DERP ("university VM") | server1 CT | 192.168.1.201 (`hs.uni.home.arpa`) | 101 (your original CT 101 is archived and restored on teardown) |
| University DNS (dnsmasq) + ACME CA (step-ca) | server1 CT | 192.168.1.202 (`ca.uni.home.arpa`) | 802 |
| Campus firewall / NAT for lab room B | server1 CT | 192.168.1.203 + 10.20.0.1 on `vmbr2` | 803 |
| lab-b-01 (`tag:labpc`) | server1 CT, room B | 10.20.0.11 | 804 |
| lab-b-02 (`tag:labpc`, `tag:gpu`) | server1 CT, room B | 10.20.0.12 | 805 |
| lab-a-01 (`tag:labpc`) | server0 host, room A | 192.168.1.111 | pending server0 access |
| bob (researcher), admin1 (admin) | Docker on enigma | 192.168.2.101 | `hs-sim-bob`, `hs-sim-admin` |
| alice (researcher) | Docker on the laptop | 192.168.1.199 | `hs-sim-alice` |
| alice at home (off campus) | Docker on enigma, egress-filtered | 172.30.99.0/24 | `hs-sim-alice-home` |
| Metrics | existing CT 110 Prometheus/Grafana | 192.168.1.225 | jobs `hs-sim-*`, dashboard uid `hs-sim` |

Clients run in containers on enigma and the laptop because both hosts already run
`tailscaled` for a hosted tailnet; that tailnet is never touched.

## Build order

    SUDO_PW=... ./bootstrap-access.sh       # passwordless sudo for the scripts (ledgered)
    ./preflight.sh                           # checks + baseline (SKIP_SERVER0=1 until server0 is reachable)
    campus/setup-campus.sh                   # DNS + ACME CA
    campus/setup-roomb.sh                    # vmbr2, campus firewall, room B lab PCs
    headscale/replace-original-101.sh        # archive your CT 101 (protected), take it out of the weekly job
    headscale/install.sh 101 192.168.1.201 && headscale/users.sh
    monitoring/setup-monitoring.sh           # scrape jobs, dashboard, nightly restic
    clients/setup-devices.sh                 # bob, admin1 (enigma) and alice (laptop)
    clients/enroll-labpcs.sh                 # lab PCs + test listeners
    clients/offcampus.sh up strict           # optional: alice-home

## Tests

    tests/run.sh test_ledger test_campus test_roomb test_hs_server test_monitoring \
                 test_users_devices test_labpcs test_matrix_perf test_report test_collect test_offcampus
    tests/acl.sh            tests/revocation.sh
    tests/outage.sh --minutes 30            tests/dr_restore.sh
    tests/report.sh results                 # success-criteria table in results/report.md

Switch the campus firewall with `campus/fw-mode.sh open|udp-blocked|status`, and the
off-campus client with `clients/offcampus.sh mode strict|wg-allowed`.

Results are in `results/`; observations that matter for the real pilot are in
`results/notes.md`.

## Soak run

    tests/start-soak.sh         # hourly tests/collect.sh via a systemd user timer (ledgered)
    tests/report.sh results     # after SOAK_DAYS days

## Remove the simulation

    ./teardown.sh --dry-run                # review what will be undone
    ./teardown.sh --keep-access            # undo everything except sudo/SSH access, newest first
    tests/test_pristine.sh                 # compare every machine against ledger/baseline/
    ./teardown.sh --task 0                 # finally remove the sudoers drop-ins and enigma's key on the laptop

Rows of kind `manual` are printed, not executed; confirm those yourself.
