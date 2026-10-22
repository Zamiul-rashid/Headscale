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

## Second check (same day, after teardown)

Everything was re-checked by hand from scratch:

- server1: containers and VMs as before; CT 101 config identical to the pre-simulation copy, stopped,
  `onboot: 0`; no `vmbr2` (neither live nor in the interfaces files); backup job `101,102,110,120`;
  no backup folder or simulation archive; no `hs-sim` anywhere in `/etc/pve` or `/tmp`;
  `prometheus.yml` hash identical to the baseline; no dashboard file or Grafana database entry.
- **Headscale is not running anywhere:** not on the server1 host and not in any running CT. The only
  Headscale install is your original CT 101, which is stopped and does not start at boot (`onboot: 0`).
- enigma: no `hs-sim` containers, volumes, networks, images or firewall chains; no timer; sudo asks
  for a password again; hosted tailnet identical to the baseline (same IP).
- laptop: no Docker packages, data, `docker0` or Docker iptables chains (so no reboot is needed);
  enigma's key and the sudoers file removed; `FORWARD ACCEPT` and `ip_forward=0` as before; hosted
  tailnet identical to the baseline.

- server0 (checked once its login was known): no Headscale process, unit or container; fail2ban shows
  0 banned IPs; its hosted tailnet and its own DERP relay containers untouched.

Three leftovers found and removed in this pass: the empty `docker` group on the laptop, Docker's build
cache on enigma (192.5 MB, all from the client image build), and the stray `lab-headscale-pilot/ledger/`
file.

## Left for you

- Optional: delete the three old OPNsense backups (see 01-environment.md).
- The passwords shared in chat are used on several machines; consider changing them.
- Harmless: enigma's `~/.ssh/known_hosts` gained entries for the laptop and the simulation CTs' IPs.
