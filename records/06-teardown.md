# 06 — Teardown (2026-10-13)

## What was undone, newest first

1. The off-campus firewall chain on enigma, and the hourly collector timer
2. All client containers, volumes, networks and images on enigma and the laptop
3. Docker on the laptop (exactly the 7 packages it added), and the laptop's forwarding settings
4. The backup folder on `storage1tb`, the Grafana dashboard, and the Prometheus scrape jobs
   (`prometheus.yml` restored byte-for-byte)
5. The simulation's CT 101, then **your original CT 101 restored** from its protected archive, then the
   archive removed, then CT 101 put back into the weekly backup job
6. CTs 802–805 and the `vmbr2` bridge
7. Last: the passwordless-sudo files on enigma and the laptop, and enigma's SSH key on the laptop

Command sequence:

    ./teardown.sh --keep-access     # steps 1–6
    tests/test_pristine.sh          # 21/21 passed
    ./teardown.sh --task 0          # step 7

## How it was verified

`tests/test_pristine.sh` compared every machine with the baseline captured before the simulation:

- server1: the same containers and VMs (CT 101 is your `headscale-lxc` again, stopped, `onboot: 0`); no
  `vmbr2`; the backup job covers 101, 102, 110, 120; `prometheus.yml` byte-identical; no dashboard;
  no backup folder; the archive gone (only your three regular CT 101 weekly backups remain)
- enigma: hosted tailnet unchanged; no `hs-sim` containers, volumes, images, firewall chains or timers
- laptop: hosted tailnet unchanged; package list as before; CA store and DNS drop-ins as before

After the last step, sudo asks for a password again on both machines, and the laptop rejects enigma's key.

## Left for you

- **Reboot the laptop.** Docker leaves its iptables chains and `docker0` interface until the next reboot.
- Optional: delete the three old OPNsense backups (see 01-environment.md).
- Optional: delete the stray file `lab-headscale-pilot/ledger/ledger.tsv`. A helper was accidentally run
  from the wrong directory and created it; nothing uses it.
- Optional: Docker's build cache on enigma still holds the client image layers (`docker builder prune`).
- If enigma is still banned from SSH on server0, unban 192.168.2.101 there.
- The passwords shared in chat (`prova` and others) are used on several machines; consider changing them.
