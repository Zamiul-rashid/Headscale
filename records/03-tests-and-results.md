# 03 — Tests and results

## Against the proposal's success criteria (§11)

| Metric | Target | Result | |
|---|---|---|---|
| Lab PCs online after reboot | all | 2/2 (lab-a-01 never joined) | PASS |
| Mean enrolment time per lab PC | ≤ 10 min | 11 s (excludes the first package download) | PASS |
| Control-server uptime | ≥ 99 % | 100 % (5 hourly samples only) | PASS, thin data |
| Direct (non-relayed) peer pairs | ≥ 80 % | 44–58 % | **FAIL** (see findings) |
| Added latency vs LAN | ≤ 5 ms | not measurable without lab-a-01 | NO DATA |
| Throughput vs LAN | ≥ 70 % | not measurable without lab-a-01 | NO DATA |
| ACL tests | 100 % | 13/13 (3 needing lab-a-01 skipped) | PASS |
| Time to revoke access | ≤ 1 min | 3–5 s | PASS |
| Backup restore (RTO) | ≤ 2 h | 63 s, 5/5 nodes back | PASS |
| User satisfaction | ≥ 4.0 | not simulated | N/A |
| Security incidents | 0 | 0 | PASS |

The planned 7-day soak run was stopped after about 3 hours, when we chose to tear down early.

## Tests that were run

| Area | What was checked | Outcome |
|---|---|---|
| Campus DNS + CA | DNS records, ACME directory | Pass; teardown and rebuild of this CT also proven |
| Room B firewall | Gateway, UDP blocked except campus DNS, mode survives a firewall reboot | Pass |
| Headscale server | Health, cert from the simulated CA, TLS 1.1 refused, only 80/443 open to non-admins | Pass |
| Monitoring + backups | Prometheus scraping, Grafana dashboard, restic snapshot with DB and keys | Pass |
| Enrolment | All devices online, peer ping, campus DERP visible, hosted tailnets unchanged | Pass |
| Lab PCs | Online after reboot, tags, MagicDNS, test listeners | Pass |
| Connectivity matrix | Direct vs relayed for every pair, open and UDP-blocked | Recorded; UDP-blocked correctly forced relaying across room B |
| ACLs | 13 allow/deny cases, plus a deliberately wrong expectation to prove the test can fail | Pass |
| Revocation | Node expiry 3 s, removal from group 5 s, expired key rejected | Pass |
| Control-server outage (30 min) | Direct session 0 % loss; new enrolment blocked, then works after restart | Pass |
| Outage, relayed session | Lost 92 % during the outage | Finding (see 04) |
| Server reboot | Healthy in 5 s, all nodes back | Pass |
| Disaster recovery | New server from backup, DNS repointed, all nodes reconnected in 63 s | Pass |
| Off campus | No LAN access, only public ports; ACLs hold; relayed via campus DERP at 27–37 ms | Pass |

Raw data: `../sim/results/*.csv`, full report `../sim/results/report.md`.
