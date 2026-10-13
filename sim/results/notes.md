# Simulation findings (pilot observations, not harness bugs)

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
