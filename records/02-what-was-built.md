# 02 — What was built

## How the proposal mapped onto the home lab

| Proposal | Rehearsal |
|---|---|
| Headscale on a university VM | CT 101 on server1 (your original CT 101 was archived first and restored afterwards) |
| `hs.[uni-domain]` + university DNS | `hs.uni.home.arpa`, served by dnsmasq in CT 802 |
| Let's Encrypt certificate | A real ACME flow: Caddy got and renewed its certificate from step-ca in CT 802 |
| Lab rooms on different subnets | Room B = 10.20.0.0/24 behind a firewall CT on a new isolated bridge `vmbr2`; enigma and the laptop on other subnets |
| Campus firewall blocking UDP | `campus/fw-mode.sh udp-blocked` on the firewall CT |
| 15 lab PCs | 2 lab PCs (lab-b-01, lab-b-02 with `tag:gpu`); lab-a-01 on server0 never joined |
| Pilot users | admin1 and bob (containers on enigma), alice (container on the laptop) |
| Off-campus access | "alice-home": a container on enigma that could reach only the internet and the server's public ports, with 30 ms added latency |
| Prometheus + Grafana | Two scrape jobs and one dashboard added to the existing CT 110 |
| Backups to department storage | Nightly restic backups to a folder on `storage1tb` |

## Containers on server1

| CT | Name | Address | Purpose |
|---|---|---|---|
| 101 | hs-101 | 192.168.1.201 | Headscale 0.29.3 + Caddy 2.11.4 + embedded DERP relay, ufw-hardened |
| 802 | campus | 192.168.1.202 | dnsmasq (DNS for `uni.home.arpa`) + step-ca 0.30.2 (ACME) |
| 803 | campus-fw | 192.168.1.203 / 10.20.0.1 | NAT and firewall for room B (nftables) |
| 804 | lab-b-01 | 10.20.0.11 | Lab PC, `tag:labpc` |
| 805 | lab-b-02 | 10.20.0.12 | Lab PC, `tag:labpc`, `tag:gpu` |
| 899 | (temporary) | 192.168.1.205 | Replacement server for the disaster-recovery drill; destroyed afterwards |

All were unprivileged Ubuntu 24.04 containers tagged `hs-sim`.

## Versions

Each was the newest stable release at least 14 days old on 2026-10-13: Headscale 0.29.3,
Tailscale client 1.102.4, step-ca 0.30.2 (step-cli 0.30.6), Caddy 2.11.4.

## Access policy

The proposal's policy, unchanged: admins reach everything; researchers reach lab PCs on 22, 3389, 5900
and 8888 only; lab PCs reach each other on any port. Everything else is denied.

## Tracking

Every change made outside a simulation container was written to `../sim/ledger/ledger.tsv`, together
with the command that undoes it. Teardown replays those commands newest-first.
