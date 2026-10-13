# 01 — Environment

## Machines

| Machine | What it is | Address | Role in the rehearsal |
|---|---|---|---|
| enigma | Workstation, Ubuntu 26.04 | wired 192.168.2.101, Wi-Fi 192.168.3.x | Control machine; ran the bob, admin and "alice at home" clients in Docker |
| server1 | Proxmox VE 9.2, 12 cores, 15 GB RAM | 192.168.1.112 | Hosted every server-side container |
| server0 | Not Proxmox; serves 80/443 | 192.168.1.111 | Meant to be lab PC "lab-a-01". **Not used:** the login we were given was rejected |
| laptop (`enigma-b`) | Ubuntu 22.04 | 192.168.1.199 (server VLAN) | Researcher "alice", in Docker |

enigma, server1 and the laptop already run Tailscale on a hosted (tailscale.com) tailnet. That tailnet
was never touched. Each simulated client ran its own `tailscaled` inside a container instead.

## State before we started (the baseline)

`../sim/ledger/baseline/` holds a snapshot of each machine, taken before any change:

- server1: container and VM lists, network interfaces, the weekly backup job, the CT 110 Prometheus config hash
- enigma and the laptop: Tailscale status, installed packages, CA store, DNS drop-ins

Existing server1 containers: 101 `headscale-lxc` (an earlier Headscale attempt, stopped), 102 `hermes`,
110 `infra-monitoring` (Prometheus + Grafana), 120 `portfolio`, 200 `hub`.

## Permanent change (not part of the simulation)

At your request, the stopped OPNsense VM (VM 100) on server1 was **deleted for good**, because you now
have a dedicated router. Its disks were removed and it was taken out of the weekly backup job.
Three old backups of it are still on `storage1tb` (about 1.7 GB); delete them if you don't need them:

    storage1tb:backup/vzdump-qemu-100-2026_09_26-01_00_02.vma.zst
    storage1tb:backup/vzdump-qemu-100-2026_10_03-03_35_00.vma.zst
    storage1tb:backup/vzdump-qemu-100-2026_10_10-03_35_01.vma.zst

## Side effect on server0

Early login attempts from enigma tripped server0's SSH ban (fail2ban or similar). If enigma
(192.168.2.101) still can't SSH to server0, unban it there.
