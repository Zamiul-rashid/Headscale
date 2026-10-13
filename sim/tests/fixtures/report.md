# hs-sim pilot rehearsal — success criteria (proposal §11)

| Metric | Target | Measured | Result |
|---|---|---|---|
| Nodes online (last soak sample) | all | 6/6 | PASS |
| Mean enrolment time per lab PC | ≤ 600 s | 207 s | PASS |
| Uptime (control server health checks) | ≥ 99 % | 99.5 % | PASS |
| TLS certificate valid in every sample | 0 expired | 1 expired | FAIL |
| Hosted tailnets untouched (enigma) | every sample | 0 changed | PASS |
| Direct (non-relayed) peer pairs, open mode | ≥ 80 % | 85 % | PASS |
| Added latency, tailnet vs LAN (worst pair) | ≤ 5 ms | 1.5 ms | PASS |
| Throughput, tailnet / LAN (worst pair) | ≥ 0.70 | 0.65 | FAIL |
| ACL tests passed | 100 % | 100 % | PASS |
| Revocation time (worst case) | ≤ 60 s | 6 s | PASS |
| Backup restore RTO | ≤ 7200 s | 63 s | PASS |
| User satisfaction (survey) | ≥ 4.0 | N/A (not simulated) | N/A |
| Security incidents | 0 | 0 | PASS |

## Flagged soak samples
- 2026-10-16T09:00:00+06:00: hs_health=fail
- 2026-10-19T00:00:00+06:00: cert_hours_left=-1

## Control-plane outage and reboot

| Case | Metric | Value | Result |
|---|---|---|---|
| outage | direct-session-loss-pct | 0 | yes |
| outage | relayed-session-loss-pct | 34 | recorded |

## Not covered by the simulation
- Windows lab PCs (MSI + `--unattended`): no Windows device in the home lab.
- 15-PC scale: 3 lab PCs (lab-a-01 on server0, lab-b-01/02 in room B).
- University SSO (OIDC), subnet router, client/server upgrade rehearsal, Phase 0 approvals.
- User satisfaction survey; 4-week pilot shortened to a soak run.
- Researcher clients run in Docker on hosts that already use a hosted tailnet (extra NAT hop).
