# hs-sim pilot rehearsal — success criteria (proposal §11)

| Metric | Target | Measured | Result |
|---|---|---|---|
| Nodes online (last soak sample) | all | 5/5 | PASS |
| Mean enrolment time per lab PC | ≤ 600 s | 11 s | PASS |
| Uptime (control server health checks) | ≥ 99 % | 100.0 % | PASS |
| TLS certificate valid in every sample | 0 expired | 0 expired | PASS |
| Hosted tailnets untouched (enigma) | every sample | 0 changed | PASS |
| Direct (non-relayed) peer pairs, open mode | ≥ 80 % | 44 % | FAIL |
| Added latency, tailnet vs LAN (worst pair) | ≤ 5 ms | 0.268 ms | PASS |
| Throughput, tailnet / LAN (worst pair) | ≥ 0.70 | 0.09 | FAIL |
| ACL tests passed | 100 % | 100 % | PASS |
| Revocation time (worst case) | ≤ 60 s | 5 s | PASS |
| Backup restore RTO | ≤ 7200 s | 63 s | PASS |
| User satisfaction (survey) | ≥ 4.0 | N/A (not simulated) | N/A |
| Security incidents | 0 | 0 | PASS |

## Flagged soak samples

## Control-plane outage and reboot

| Case | Metric | Value | Result |
|---|---|---|---|
| setup | direct-pair-path | 10.20.0.12:41641 | recorded |
| setup | relayed-pair-path | DERP(sin) | recorded |
| outage | new-enrolment-blocked | NeedsLogin | yes |
| recovery | enrolment-after-restart | ok | yes |
| outage | direct-session-loss-pct | 0 | yes |
| outage | relayed-session-loss-pct | 91.8831 | recorded |
| reboot | health-seconds | 5 | yes |
| reboot | nodes-online | 5/5 | yes |

## Not covered by the simulation
- Windows lab PCs (MSI + `--unattended`): no Windows device in the home lab.
- 15-PC scale: 3 lab PCs (lab-a-01 on server0, lab-b-01/02 in room B).
- University SSO (OIDC), subnet router, client/server upgrade rehearsal, Phase 0 approvals.
- User satisfaction survey; 4-week pilot shortened to a soak run.
- Researcher clients run in Docker on hosts that already use a hosted tailnet (extra NAT hop).

## Findings


## 2026-10-13 — connectivity (Task 8, 5 nodes; lab-a-01 pending server0 access)
- Open mode: 8 direct / 10 DERP / 2 no-peer of 20 ordered pairs → direct share 44 % of reachable pairs (target ≥ 80 %).
- Every client reports `MappingVariesByDestIP: true`. Two causes:
  1. lab-b-01 and lab-b-02 both use UDP 41641 behind one NAT (campus-fw). Whichever maps first keeps 41641;
     the other gets a random port per destination. A real lab with many PCs behind one campus NAT will see the same.
  2. The researcher clients run in Docker (their hosts already run hosted-tailnet tailscaled), adding a Docker
     MASQUERADE hop. This is a simulation artifact: a native client would not have it.
- udp-blocked mode: every pair crossing the room-B firewall falls back to DERP (campus region) and keeps working;
  same-room pairs stay direct. Relayed latency on campus is 1–4 ms.
- Implication for the real pilot: ask IT (U5) whether the lab NAT is endpoint-independent; consider per-PC
  `--port` values or a NAT-PMP/UPnP-capable gateway if the direct share comes in low.

## Throughput caveat
- same-room pair (lab-b-01→lab-b-02) compares a Proxmox in-memory bridge (~54 Gbit/s) with WireGuard (~4.9 Gbit/s):
  ratio 0.09 is a CPU/bridge artifact, not a LAN comparison. The meaningful "≥ 70 % of LAN" pairs are
  cross-subnet (bob-enigma→lab-a-01) and laptop (alice-laptop→lab-a-01) over physical 1 GbE, pending lab-a-01.

## 2026-10-13 — control-plane outage (Task 10)
- Existing **direct** sessions survive a Headscale outage with 0 % loss (proposal claim holds).
- Existing **relayed** sessions do NOT simply survive: the campus DERP is embedded in Headscale, so stopping
  Headscale also stops the relay. In the first 2-minute run, bob→lab-b-01 (relayed via campus DERP) lost
  ~62 s of traffic (ping seq 4–34), then recovered through Tailscale's *public* DERP at 100–130 ms.
  If IT removes the public DERP fallback (U6), relayed sessions stay down for the whole outage.
  Recommendation for the real pilot: run the campus DERP as a separate `derper` service (or on a second host)
  so a Headscale restart/upgrade does not cut relayed traffic.
- Clients do pick public DERP regions: before the 30-minute run the relayed pair was going through
  **DERP(sin)** (Singapore). With the public fallback enabled, campus-to-campus relayed traffic can leave the
  country (encrypted, but latency + data-residency question for IT, U6).
- New enrolment during the outage fails cleanly (NeedsLogin / container exits) and succeeds after restart.
- Server reboot: health back in ~5 s, all nodes online again.
- DR drill: replacement CT built from the nightly restic backup, DNS repointed, all 5 nodes reconnected —
  RTO 63 s from scratch (target ≤ 2 h). Restore must use `restic --no-lock` against a read-only repo.
- **30-minute outage (proposal duration):** direct pair lab-b-01→lab-b-02 lost 0 %. Relayed pair bob→lab-b-01,
  which was on public DERP(sin) at the start, lost 91.9 %: no replies from seconds after the stop until ~26 min
  in (ping seq 4–771). So during a long outage relayed sessions are effectively down even with the public DERP
  fallback. The success criterion "existing sessions keep working" should be scoped to direct paths, and the
  direct-path share (see connectivity) becomes a resilience metric, not only a performance one.
