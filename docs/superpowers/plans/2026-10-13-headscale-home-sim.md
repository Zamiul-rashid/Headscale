# Headscale Pilot — Home-Lab Simulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rehearse the whole 15-PC Headscale pilot (server, enrolment, ACLs, connectivity/performance/resilience tests, soak, report) on the home network, as close to the real deployment as possible, with every change recorded so the whole simulation can be deleted and the network returned to exactly its starting state.

**Architecture:** server1 (Proxmox) hosts the Headscale server, a "university IT" container (DNS + ACME CA), and a firewalled "lab room B" subnet (an nftables router CT plus two lab-PC CTs on a new isolated bridge). The server0 host is lab room A's PC. enigma runs the researcher, admin and simulated off-campus clients in Docker containers, so its existing hosted Tailscale is untouched. The laptop (`enigma-b`) runs the second researcher in Docker for the same reason. Every created resource is appended to a ledger with its undo command, and `teardown.sh` replays the ledger in reverse.

**Tech Stack:** Bash, Proxmox `pct`/`pvesh`, Ubuntu 24.04 LXC, Headscale (`.deb`), Tailscale client, Caddy 2, step-ca (ACME), dnsmasq, nftables, restic, existing Prometheus + Grafana (CT 110), Docker Compose, iperf3, nmap, socat.

**Spec:** [../../../README.md](../../../README.md) (the pilot proposal), plus the simulation decisions below.

## Simulation Decisions (agreed 2026-10-13)

| Proposal element | Simulated as |
|---|---|
| `hs.[uni-domain]`, university DNS (U3) | dnsmasq in CT 802 authoritative for `uni.home.arpa` (RFC 8375 home-network domain) |
| Let's Encrypt (U4) | step-ca ACME server in CT 802; Caddy uses the real ACME HTTP-01 flow; clients trust the sim root CA |
| University VM for Headscale (U1) | CT 101 on server1, rebuilt (original backed up with vzdump, restored at teardown) |
| Two rooms/subnets | Room A = server LAN 192.168.1.0/24 (server0 host + laptop at 192.168.1.199); room B = 10.20.0.0/24 behind campus-fw CT 803 on new bridge `vmbr2`; enigma wired 192.168.2.0/24 |
| Campus firewall blocking UDP (U5) | `fw-mode.sh udp-blocked` on CT 803 |
| 15 lab PCs (10 Linux, 5 Windows, ≥2 GPU) | 3 Linux lab PCs: lab-a-01 (server0), lab-b-01, lab-b-02 (`tag:gpu`). **Windows is not covered** |
| Pilot users | admin1 (enigma container), bob (enigma container), alice (laptop `enigma-b`, in a Docker container because its host Tailscale is on the hosted tailnet) |
| Prometheus + Grafana | existing CT 110 gets one scrape job + one dashboard, both removed at teardown |
| Department backup storage (U10) | `storage1tb` directory bind-mounted into CT 101 |
| 4-week pilot, survey | 7-day soak (`SOAK_DAYS`) with hourly metrics; survey not simulated |
| Off-campus (U6) | Task 12: container `alice-home` on enigma in its own Docker network. Egress filter: it can reach the internet and only the server's "public" ports (443/tcp, 3478/udp), never the campus LANs. `tc netem` adds home-ISP latency. No phone or router change needed |
| OIDC, subnet router, client/server upgrade rehearsal, approvals (Phase 0) | Not simulated |

## Global Constraints

- All simulation code lives in `lab-headscale-pilot/sim/`, its own git repo. Paths below are relative to it.
- **Every resource created outside a sim-owned CT** (CT, bridge, file, cert, container, volume, timer, config edit, router rule) gets a `ledger_add` call *before or in the same step* that creates it, with a working undo command. Anything created *inside* a sim CT needs no entry, because destroying the CT removes it.
- Everything is named or tagged `hs-sim`: Proxmox CTs `--tags hs-sim`, Docker project `hs-sim`, files `hs-sim*`, Grafana dashboard uid `hs-sim`.
- **Never modify**: the host `tailscaled` on enigma, server1 or the laptop (all are on hosted tailnets); CTs 102, 120, 200; bridge `vmbr1`; CT 110, except the one scrape job (backed up first).
- **VM 100 (OPNsense) is deleted permanently**, at the user's request (2026-10-13: "I have a dedicated router now"). This is a one-off cleanup, **not** a simulation resource. It is never ledgered and teardown never restores it. **Done 2026-10-13**: VM and both disks destroyed, and it was purged from the `backup-weekly` job. Three old archives `storage1tb:backup/vzdump-qemu-100-*` were kept pending the user's decision.
- **Weekly backup job.** `backup-weekly` (Sat 03:35, `prune-backups keep-last=2`, vmids `101,102,110,120`) would back up the *sim* CT 101 and prune the *original* CT 101's backups. Task 4 therefore removes 101 from the job (ledgered; undo re-adds it) and creates the original-101 archive with `--protected 1`.
- **Access.** SSH keys only. Passwords the user gave in chat are never written to files, the ledger, git or memory. On enigma and the laptop, Task 1 adds `/etc/sudoers.d/hs-sim` (`entropy ALL=(ALL) NOPASSWD:ALL`) so scripts can run without a password. It is ledgered and is the last thing teardown removes. enigma's public key in the laptop's `~/.ssh/authorized_keys` (added 2026-10-13) is ledgered the same way.
- Domains: `server_url: https://hs.uni.home.arpa`, CA `ca.uni.home.arpa`, MagicDNS `base_domain: lab.internal`.
- Versions: Headscale, Tailscale client and step-ca are pinned in `config/versions.env`. The Tailscale client version is the same on every node, installed with `apt-mark hold`, and the Docker image tag matches it.
- All scripts are idempotent: a re-run converges and never duplicates ledger entries.
- Secrets (pre-auth keys, CA password, restic password, Grafana token) go only in `secrets/`, which is gitignored. Pre-auth keys are single-use with a 24-hour expiry unless a step says otherwise.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Pass/fail targets are copied verbatim from proposal §11: enrolment ≤ 10 min; uptime ≥ 99 %; direct pairs ≥ 80 %; added latency ≤ 5 ms; throughput ≥ 70 % of LAN; ACL tests 100 %; revocation ≤ 1 min; RTO ≤ 2 h.

`config/sim.env` (Task 1) fixes these values:

```bash
PVE1=server1  PVE1_NODE=proxmox  SERVER0_SSH=<user>@192.168.1.111   LAPTOP_SSH=entropy@192.168.1.199   # server0 user TBD; jump via server1 if enigma is banned
LAN_GW=192.168.1.1  ENIGMA_LAN_IP=192.168.2.101
TEMPLATE=local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst  BACKUP_STORAGE=storage1tb
CT_HS=101      IP_HS=192.168.1.201
CT_CAMPUS=802  IP_CAMPUS=192.168.1.202
CT_FW=803      IP_FW=192.168.1.203   ROOMB_GW=10.20.0.1  ROOMB_CIDR=10.20.0.0/24
CT_LABB1=804   IP_LABB1=10.20.0.11
CT_LABB2=805   IP_LABB2=10.20.0.12
IP_LABA1=192.168.1.111                                  # lab-a-01 = server0 host (not Proxmox)
CT_RESTORE=899 IP_RESTORE=192.168.1.205
CT_MON=110     SOAK_DAYS=7
UNI_DOMAIN=uni.home.arpa  HS_FQDN=hs.uni.home.arpa  CA_FQDN=ca.uni.home.arpa  MAGIC_DOMAIN=lab.internal
```

## Review Focus

1. **Teardown after a half-finished run.** A task fails midway, or the user stops after Task 5. `teardown.sh` must still undo everything recorded, skip resources that are already gone, and be a no-op on a second run. *(Tests: Task 1 `test_ledger.sh`; Task 2 real `--task 2` teardown and rebuild.)*
2. **Existing hosted tailnets must never change.** enigma's `tailscale status` (BackendState, tailnet name, IP 100.68.226.55) must stay identical before, during and after the simulation. The laptop and server1 hosts likewise. *(Tests: Task 6 baseline comparison, Task 11 `collect.sh` hourly, Task 13 pristine check.)*
3. **Short-lived certificates during a multi-day soak.** step-ca issues 24-hour certs, so Caddy must renew them unattended. One missed renewal looks like a Headscale outage to every client. *(Test: Task 11 `collect.sh` records hours left on the cert; the report fails if any sample is ≤ 0 or the health check failed.)*
4. **Reboots.** Lab PCs must reconnect with no one logged in, campus-fw must keep its mode and NAT, and Headscale must come back after its CT restarts. *(Tests: Task 3 fw reboot, Task 7 lab-PC reboot, Task 10 CT 101 reboot.)*
5. **Static IP collisions.** 192.168.1.201–203 and .205 may already be in use or inside the router's DHCP pool. *(Test: Task 1 `preflight.sh` pings and ARPs each one and refuses to continue if any answers. The user confirms the range is outside the DHCP pool.)*

---

## File Structure

```
sim/
  README.md                       what exists, how to run, how to tear down
  .gitignore                      secrets/  results/raw/
  config/sim.env  config/versions.env
  config/nodes.tsv                name  role  exec  target  tags  user
  lib/common.sh                   log/die, run_on, node_exec, node_ip, hs, ledger_add
  preflight.sh  teardown.sh
  ledger/ledger.tsv  ledger/done.tsv  ledger/baseline/
  hosts/make-ct.sh                create a tagged sim CT on a Proxmox host
  campus/                         dnsmasq.conf, setup-campus.sh, set-hs-ip.sh, root_ca.crt,
                                  setup-roomb.sh, nftables.conf, fw-mode.sh
  headscale/                      install.sh, config.yaml, policy.hujson, Caddyfile,
                                  harden.sh, backup.sh, hs-sim-backup.{service,timer}, users.sh
  monitoring/                     setup-monitoring.sh, prometheus-job.yml, dashboard.json
  clients/                        trust-ca.sh, resolved-dropin.sh, mkkey.sh, enroll-linux.sh,
                                  labpc-listeners.sh, enigma/{Dockerfile,compose.yaml}
  tests/lib/assert.sh  tests/test_*.sh  tests/fixtures/
  tests/connectivity_matrix.sh perf.sh acl.sh acl_expectations.tsv revocation.sh
  tests/outage.sh dr_restore.sh collect.sh report.sh
  results/                        CSVs + report.md
```

`config/nodes.tsv` (Task 1 creates it; later tasks fill in the `exec` targets):

```
lab-a-01      labpc       ssh     server0              tag:labpc          labadmin
lab-b-01      labpc       pct     server1:804          tag:labpc          labadmin
lab-b-02      labpc       pct     server1:805          tag:labpc,tag:gpu  labadmin
alice-laptop  researcher  docker  laptop:hs-sim-alice  -                  alice
bob-enigma    researcher  docker  hs-sim-bob           -                  bob
admin-enigma  admin       docker  hs-sim-admin         -                  admin1
alice-home    researcher  docker  hs-sim-alice-home    -                  alice      # Task 12 only
```

---

### Task 1: Scaffold, ledger, teardown engine, preflight baseline

**Files:**
- Create: `README.md`, `.gitignore`, `config/{sim.env,versions.env,nodes.tsv}`, `lib/common.sh`, `teardown.sh`, `preflight.sh`, `tests/lib/assert.sh`
- Test: `tests/test_ledger.sh`, `tests/test_preflight.sh`

**Interfaces:**
- Produces (`lib/common.sh`, sourced by every script):
  - `run_on <host> <cmd>`: `host` ∈ `enigma` (local `bash -c`) | `server1` | `server0` | `laptop` (ssh using `PVE1`/`SERVER0_SSH`/`LAPTOP_SSH`)
  - `ct_exec <host> <vmid> <cmd>` → `run_on <host> "pct exec <vmid> -- bash -lc '<cmd>'"`
  - `node_exec <node> <cmd>`: dispatches on `nodes.tsv` `exec` (pct → `ct_exec`; docker → `docker exec <c> sh -c`, with `host:` prefix → `run_on <host> "docker exec …"`; ssh → `run_on <target>`); `node_ip <node>` → the node's tailnet IPv4 via `tailscale ip -4`
  - `hs <args…>` → `ct_exec server1 $CT_HS "headscale <args>"`
  - `ledger_add <task> <host> <kind> <id> <undo_cmd>` appends a TSV row `ts task host kind id undo` to `$LEDGER_DIR/ledger.tsv` (default `ledger/`). If a row with the same (task, host, kind, id) exists it does nothing.
- Produces `teardown.sh [--dry-run] [--task N]`: replays undo rows in reverse file order through `run_on <host>`, skips rows already in `done.tsv`, appends each success to `done.tsv`, and continues past failures. It exits 1 and lists any failed rows. `kind=manual` rows are printed for the user, not executed.
- Produces `tests/lib/assert.sh`: `assert_eq a b msg`, `assert_contains hay needle msg`, `assert_ok cmd…`, `assert_fails cmd…`, `t_done` (prints pass/fail counts, exits 1 if any failed).

- [x] **Step 0: Delete the OPNsense VM (permanent, not ledgered). Done 2026-10-13.** On server1:
  1. Look first: `qm config 100` should show `name: opnsense`, and `qm status 100` should be `stopped`.
  2. Check nothing else uses vmbr1: `grep -l vmbr1 /etc/pve/lxc/*.conf /etc/pve/qemu-server/*.conf` should list only `100.conf`.
  3. Show both outputs to the user and get a final yes.
  4. Run `qm destroy 100 --purge 1 --destroy-unreferenced-disks 1`.

  Expected: `qm list` no longer shows 100, and `pvesm list local-lvm | grep vm-100` is empty. Leave `vmbr1` and `enp2s0` alone; removing them is a separate decision. This step must run before Step 7, so the baseline is taken without VM 100.

- [ ] **Step 1: Write `tests/test_ledger.sh`** (local only, temp `LEDGER_DIR`, host `enigma`):

```bash
ledger_add 1 enigma file a "echo 1 >> $T/order"; ledger_add 1 enigma file a "echo 1 >> $T/order"
assert_eq "$(wc -l < $LEDGER_DIR/ledger.tsv)" 1 "duplicate add is a no-op"
ledger_add 2 enigma file b "echo 2 >> $T/order"; ledger_add 2 enigma file c "false"
ledger_add 3 enigma file d "echo 3 >> $T/order"
assert_eq "$(./teardown.sh --dry-run | grep -c UNDO)" 4 "dry-run lists 4"; assert_fails test -e $T/order
./teardown.sh --task 3; assert_eq "$(cat $T/order)" "3" "--task 3 only"
assert_fails ./teardown.sh                    # row c fails…
assert_eq "$(tr '\n' ' ' < $T/order)" "3 2 1 " "…but the rest ran, reverse order"
assert_fails ./teardown.sh; assert_eq "$(tr '\n' ' ' < $T/order)" "3 2 1 " "re-run only retries failed row"
```

- [ ] **Step 2:** Run `bash tests/test_ledger.sh`. Expected: FAIL (`lib/common.sh` missing).
- [ ] **Step 3:** Implement `lib/common.sh`, `teardown.sh`, `tests/lib/assert.sh`, `config/sim.env`, `config/nodes.tsv`, `.gitignore`, and `git init` in `sim/`.
- [ ] **Step 4:** Run `bash tests/test_ledger.sh`. Expected: all pass.
- [ ] **Step 5: Pin versions.** Query the GitHub releases API for the latest stable `juanfont/headscale` and `smallstep/certificates`, and pkgs.tailscale.com `stable` for Tailscale. Skip any release newer than 14 days. Read the Headscale release notes for its minimum supported Tailscale client version. Write `config/versions.env`: `HEADSCALE_VERSION=…  TS_VERSION=…  STEPCA_VERSION=…  CADDY_VERSION=…`.
- [ ] **Step 6: Write `tests/test_preflight.sh`.** It asserts that `preflight.sh` exits 0 and creates: `ledger/baseline/enigma-tailscale.json`, `server1-pct.txt`, `server1-qm.txt`, `server1-network.json` (`pvesh get /nodes/proxmox/network --output-format json`), `ct110-prometheus.sha256`, `server0-tailscale.json`, `server0-ca-certs.txt`, `server0-resolved.d.txt`, `server0-packages.txt` (`dpkg-query -W`), `laptop-tailscale.json`, `laptop-packages.txt`, `laptop-ca-certs.txt`, `laptop-resolved.d.txt`. With `SERVER0_SSH=` empty, `preflight.sh` must exit non-zero with a message naming `SERVER0_SSH`.
- [ ] **Step 7:** Implement `preflight.sh`. It checks:
  - SSH works to server1, server0 and the laptop.
  - Each `IP_*` on 192.168.1.0/24 gets no ping or `arping` reply; otherwise it dies with the IP.
  - VMIDs 802–805 and 899 are free.
  - `vmbr2` is absent.
  - The `TEMPLATE` exists.
  - On server0, whether `tailscaled` is already on a tailnet. It writes `native` or `docker` to `config/server0-mode`; Task 7 reads it. The laptop is known to be `docker`.
  - Before writing the baseline, ledger the access changes: the laptop `authorized_keys` line (undo: `sed -i '\#<enigma pubkey>#d' ~/.ssh/authorized_keys`), server0's line once it's added, and the sudoers drop-ins (undo: `sudo rm -f /etc/sudoers.d/hs-sim`). These are task 0 rows, so teardown undoes them last.

  Then it writes the baseline files. The user must supply the server0 login and confirm 192.168.1.201–203 and .205 are outside the router's DHCP pool.
- [ ] **Step 8:** Run `bash tests/test_preflight.sh`. Expected: pass.
- [ ] **Step 9:** Commit: `feat(sim): ledger, teardown engine, preflight baseline`.

### Task 2: Campus services CT (simulated university DNS + ACME CA)

**Files:**
- Create: `hosts/make-ct.sh`, `campus/dnsmasq.conf`, `campus/setup-campus.sh`, `campus/set-hs-ip.sh`, `campus/root_ca.crt` (generated, public)
- Test: `tests/test_campus.sh`

**Interfaces:**
- Consumes: `ledger_add`, `run_on`, `ct_exec` (Task 1).
- Produces:
  - `hosts/make-ct.sh <pve-host> <vmid> <hostname> <bridge> <ip/cidr> <gw> <cores> <mem_mb> [--nic2 <bridge>,<ip/cidr>] [--nameserver <ip>]`. It creates an unprivileged Ubuntu 24.04 CT with `nesting=1,keyctl=1`, `--tags hs-sim`, `onboot 1`, and the TUN passthrough lines CT 101 already uses (`lxc.cgroup2.devices.allow: c 10:200 rwm`, `lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file`). It starts the CT and records `ledger_add <task> <pve-host> ct <vmid> "pct stop <vmid>; pct destroy <vmid> --purge"`. If the VMID exists with tag `hs-sim` it does nothing; if it exists without the tag it dies. The default nameserver is `IP_CAMPUS`.
  - `campus/set-hs-ip.sh <ip>` rewrites the `hs.uni.home.arpa` record in CT 802 and reloads dnsmasq.
  - `campus/root_ca.crt`, the sim root that all later tasks trust.

- [ ] **Step 1: Write `tests/test_campus.sh`:**

```bash
assert_eq "$(dig +short @$IP_CAMPUS $HS_FQDN)" "$IP_HS" "hs record"
assert_eq "$(dig +short @$IP_CAMPUS $CA_FQDN)" "$IP_CAMPUS" "ca record"
assert_ok  dig +short @$IP_CAMPUS pkgs.tailscale.com            # forwards upstream to $LAN_GW
assert_contains "$(curl -s --cacert campus/root_ca.crt --resolve $CA_FQDN:443:$IP_CAMPUS \
  https://$CA_FQDN/acme/acme/directory)" newOrder "ACME directory up"
assert_contains "$(run_on server1 "pct config $CT_CAMPUS")" "tags: hs-sim" "tagged"
assert_contains "$(cat ledger/ledger.tsv)" "ct	$CT_CAMPUS" "ledgered"
```

- [ ] **Step 2:** Run the test. Expected: FAIL (dig times out).
- [ ] **Step 3:** Implement `make-ct.sh`. Implement `setup-campus.sh`:
  - Create CT 802 (1 core, 512 MB, vmbr0, `--nameserver $LAN_GW`).
  - dnsmasq: listen on eth0, upstream `$LAN_GW`, `address=/hs.uni.home.arpa/192.168.1.201`, `address=/ca.uni.home.arpa/192.168.1.202`.
  - Install step-ca `$STEPCA_VERSION`. Run `step ca init` with DNS `ca.uni.home.arpa`, address `:443`, `--acme`, the password from `secrets/stepca.pass`, and the default 24-hour leaf duration.
  - Run it as a systemd unit, then copy the root cert to `campus/root_ca.crt`.
- [ ] **Step 4:** Run the test. Expected: pass.
- [ ] **Step 5: Prove teardown on a real resource.** Run `./teardown.sh --task 2`, then confirm `pct status 802` fails on server1. Re-run `setup-campus.sh`, then re-run the test. Expected: pass. The new root cert replaces the old one.
- [ ] **Step 6:** Commit: `feat(sim): campus DNS + ACME CA container`.

### Task 3: Lab room B behind a campus firewall

**Files:**
- Create: `campus/setup-roomb.sh`, `campus/nftables.conf`, `campus/fw-mode.sh`
- Test: `tests/test_roomb.sh`

**Interfaces:**
- Consumes: `make-ct.sh`, `ledger_add` (Tasks 1–2).
- Produces:
  - Bridge `vmbr2`, ledgered with undo `pvesh delete /nodes/proxmox/network/vmbr2 && pvesh set /nodes/proxmox/network`.
  - CT 803 campus-fw: eth0 = 192.168.1.203 on vmbr0, eth1 = 10.20.0.1/24 on vmbr2, `net.ipv4.ip_forward=1`, nftables masquerade out eth0.
  - CTs 804 and 805 (base Ubuntu, gateway 10.20.0.1).
  - `campus/fw-mode.sh open|udp-blocked|status` (runs on enigma and drives CT 803). `udp-blocked` drops all UDP forwarded from room B except UDP 53 to `IP_CAMPUS`. The mode lives in `/etc/nftables.d/mode.nft`, which the persistent `/etc/nftables.conf` includes.

- [ ] **Step 1: Write `tests/test_roomb.sh`:**

```bash
B="ct_exec server1 $CT_LABB1"
campus/fw-mode.sh open
assert_contains "$($B 'ip route')" "default via $ROOMB_GW" "room B gateway"
assert_ok $B "dig +short @1.1.1.1 example.com | grep -q ."
assert_ok $B "curl -sfI https://pkgs.tailscale.com"
campus/fw-mode.sh udp-blocked
assert_fails $B "dig +time=2 +tries=1 @1.1.1.1 example.com"
assert_ok   $B "dig +tcp +short @1.1.1.1 example.com | grep -q ."
assert_eq "$($B "dig +short @$IP_CAMPUS $HS_FQDN")" "$IP_HS" "campus DNS allowed"
run_on server1 "pct reboot $CT_FW"; sleep 20
assert_eq "$(campus/fw-mode.sh status)" udp-blocked "mode survives reboot"
assert_fails $B "dig +time=2 +tries=1 @1.1.1.1 example.com"
campus/fw-mode.sh open
```

- [ ] **Step 2:** Run the test. Expected: FAIL (CT 804 missing).
- [ ] **Step 3:** Implement `setup-roomb.sh` (bridge first, then CT 803 with 1 core / 256 MB, then CTs 804 and 805 with 1 core / 512 MB each, with `dnsutils curl nmap netcat-openbsd iperf3` installed), `nftables.conf` and `fw-mode.sh`.
- [ ] **Step 4:** Run the test. Expected: pass.
- [ ] **Step 5:** Commit: `feat(sim): firewalled lab room B subnet`.

### Task 4: Headscale server (rebuild CT 101)

**Files:**
- Create: `headscale/{install.sh,config.yaml,policy.hujson,Caddyfile,harden.sh,users.sh}`
- Test: `tests/test_hs_server.sh`

**Interfaces:**
- Consumes: `make-ct.sh`, `root_ca.crt`, `versions.env`.
- Produces:
  - `headscale/install.sh <vmid> <ip> [--restore-from <restic-repo-path>]`: builds a complete server into the given CT. Task 10 reuses it for the disaster-recovery drill.
  - `headscale/users.sh`: idempotently creates users `admin1`, `alice`, `bob`, `labadmin`.
  - Headscale API on `https://hs.uni.home.arpa`; metrics at `192.168.1.201:9090` and node_exporter at `:9100`, reachable from CT 110's IP only.

- [ ] **Step 1: Write `tests/test_hs_server.sh`:**

```bash
C="--cacert campus/root_ca.crt --resolve $HS_FQDN:443:$IP_HS"
assert_contains "$(curl -s $C https://$HS_FQDN/health)" pass "health"
assert_contains "$(echo | openssl s_client -connect $IP_HS:443 -servername $HS_FQDN 2>/dev/null \
  | openssl x509 -noout -issuer)" "$(openssl x509 -in campus/root_ca.crt -noout -subject | sed 's/.*CN *= *//')" "issued via sim ACME"
assert_fails sh -c "echo | openssl s_client -tls1_1 -connect $IP_HS:443 2>/dev/null | grep -q 'BEGIN CERT'"
assert_ok hs configtest
assert_ok ct_exec server1 $CT_HS "headscale policy check --file /etc/headscale/policy.hujson"
assert_eq "$(ct_exec server1 $CT_LABB1 "nmap -Pn -p1-10000 --open -oG - $IP_HS" | grep -o '[0-9]*/open' | sort | tr '\n' ' ')" \
  "443/open 80/open " "non-admin sees only 80,443"
assert_contains "$(nmap -Pn -p22 --open $IP_HS)" "22/open" "admin IP gets SSH"
assert_contains "$(cat ledger/ledger.tsv)" "vzdump" "original CT 101 backed up"
assert_eq "$(hs users list -o json | jq -r '.[].name' | sort | tr '\n' ' ')" "admin1 alice bob labadmin " "users"
```

- [ ] **Step 2:** Run the test. Expected: FAIL.
- [ ] **Step 3: Back up and remove the original CT 101.** Record `pct config 101` in the commit message. Remove 101 from the weekly job: `pvesh set /cluster/backup/backup-weekly --vmid 102,110,120`, ledgered with undo `--vmid 101,102,110,120`. Run `vzdump 101 --storage $BACKUP_STORAGE --mode stop --compress zstd --protected 1` and note the archive path. Then add these ledger rows, in this order:
  1. kind `vzdump`: undo `pvesm set <archive-volid> --protected 0 && pvesm free <archive-volid>`
  2. kind `ct-original`: undo `pct status 101 >/dev/null 2>&1 && { pct stop 101; pct destroy 101 --purge; }; pct restore 101 <archive> --storage local-lvm && pct set 101 --onboot 0`

  Then destroy CT 101. Reverse replay restores the original CT before it deletes the archive.
- [ ] **Step 4:** Implement `install.sh`. It:
  - Creates the CT via `make-ct.sh` (2 cores, 2048 MB).
  - Installs the root cert into the system store.
  - Installs Headscale `$HEADSCALE_VERSION` `.deb` and Caddy `$CADDY_VERSION`.
  - Deploys `config.yaml` and `policy.hujson`.
  - Runs `harden.sh`: ufw default deny; allow 80/tcp, 443/tcp, 3478/udp; 22/tcp from `ENIGMA_LAN_IP` only; 9090 and 9100 from CT 110's current IP only. It also sets key-only sshd and installs fail2ban, unattended-upgrades and prometheus-node-exporter. If ufw can't load in the unprivileged CT, it applies the same rules as `/etc/pve/firewall/101.fw` instead, ledgered.
  - Enables all services.
  - With `--restore-from`, it runs `restic restore latest` into place before starting Headscale.

  `config.yaml` is proposal §5.4 with these changes:
  - `server_url: https://hs.uni.home.arpa`
  - `metrics_listen_addr: 0.0.0.0:9090` (a deviation from the proposal; ufw restricts it to CT 110)
  - `dns.nameservers.global: [192.168.1.202]`
  - `base_domain: lab.internal`
  - embedded DERP enabled, `region_code: campus`, public DERP map kept as fallback

  Reconcile the keys against the pinned version's `config-example.yaml`.

  `policy.hujson` is proposal §5.5 verbatim, with `group:admins: ["admin1@"]` and `group:researchers: ["alice@", "bob@"]`.

  `Caddyfile`: a global block with `acme_ca https://ca.uni.home.arpa/acme/acme/directory` and `acme_ca_root /etc/caddy/sim-root.crt`, plus a site block `hs.uni.home.arpa { reverse_proxy 127.0.0.1:8080 }`. Then run `users.sh`.
- [ ] **Step 5:** Run the test. Expected: pass.
- [ ] **Step 6:** Commit: `feat(sim): headscale server with ACME TLS, embedded DERP, hardening`.

### Task 5: Monitoring and backups

**Files:**
- Create: `monitoring/{setup-monitoring.sh,prometheus-job.yml,dashboard.json}`, `headscale/{backup.sh,hs-sim-backup.service,hs-sim-backup.timer}`
- Test: `tests/test_monitoring.sh`

**Interfaces:**
- Consumes: `ct_exec`, `ledger_add`, Grafana credentials in `secrets/grafana.env` (the user supplies them).
- Produces:
  - `grafana_api <METHOD> <path> [json-body]` in `lib/common.sh`: curl to `http://<CT 110 IP>:3000<path>` with the token from `secrets/grafana.env`. It returns non-zero on HTTP ≥ 400.
  - Prometheus jobs `hs-sim-headscale` and `hs-sim-node` on CT 110.
  - Grafana dashboard uid `hs-sim`.
  - Restic repo at `/backup/restic` in CT 101.
  - `headscale/backup.sh`. It snapshots the database with `sqlite3 .backup`, backs up the database, `/var/lib/headscale/*.key`, `/etc/headscale` and `/etc/caddy/Caddyfile`, then runs `forget --keep-daily 30 --prune`.

- [ ] **Step 1: Write `tests/test_monitoring.sh`:**

```bash
P="http://$(ct_exec server1 $CT_MON 'hostname -I | cut -d" " -f1'):9090"
assert_eq "$(curl -s "$P/api/v1/query?query=up{job=\"hs-sim-headscale\"}" | jq -r '.data.result[0].value[1]')" 1 "hs scraped"
assert_eq "$(curl -s "$P/api/v1/query?query=up{job=\"hs-sim-node\"}" | jq -r '.data.result[0].value[1]')" 1 "node scraped"
assert_ok grafana_api GET /api/dashboards/uid/hs-sim
ct_exec server1 $CT_HS "systemctl start hs-sim-backup.service"
assert_contains "$(ct_exec server1 $CT_HS 'restic -r /backup/restic --password-file /root/.restic-pass ls latest')" db.sqlite "backup has db"
assert_ok ct_exec server1 $CT_HS "systemctl is-enabled hs-sim-backup.timer"
```

- [ ] **Step 2:** Run the test. Expected: FAIL.
- [ ] **Step 3:** Implement `setup-monitoring.sh`:
  - Find Prometheus's `--config.file` (`systemctl cat prometheus` in CT 110). Copy it to `<file>.hs-sim.bak`, add a ledger row (undo: restore from `.bak`, `systemctl reload prometheus`, remove `.bak`), then append the two jobs from `prometheus-job.yml`. Run `promtool check config`, then reload.
  - Import `dashboard.json` through the Grafana API. Panels: `up`, process CPU and RAM, node_exporter CPU/RAM/network for CT 101, and every `headscale_*` gauge that `/metrics` exposes at deploy time. Ledger undo: `DELETE /api/dashboards/uid/hs-sim`.
  - Create `<storage1tb path>/hs-sim-backup` (chown 100000:100000), ledgered with undo `rm -rf`. Add it with `pct set 101 -mp0 <dir>,mp=/backup`. Initialise restic and install the daily 02:00 timer.
- [ ] **Step 4:** Run the test. Expected: pass.
- [ ] **Step 5:** Commit: `feat(sim): prometheus scrape, grafana dashboard, nightly restic`.

### Task 6: Client tooling and user devices (proposal Phase 1 "Done when")

**Files:**
- Create: `clients/{trust-ca.sh,resolved-dropin.sh,mkkey.sh,enroll-linux.sh}`, `clients/enigma/{Dockerfile,compose.yaml}`
- Test: `tests/test_users_devices.sh`

**Interfaces:**
- Consumes: `hs`, `node_exec`, `ledger_add`.
- Produces:
  - `clients/mkkey.sh <user> [--tags tag:a,tag:b] [--reusable]` prints a 24-hour pre-auth key.
  - `clients/trust-ca.sh <host>`: installs `/usr/local/share/ca-certificates/hs-sim-root.crt` and runs `update-ca-certificates`. Ledger undo: `rm …; update-ca-certificates --fresh`.
  - `clients/resolved-dropin.sh <host>`: writes `/etc/systemd/resolved.conf.d/hs-sim.conf` (`DNS=192.168.1.202`, `Domains=~uni.home.arpa`). Ledger undo: remove the file and restart resolved.
  - `clients/enroll-linux.sh <node> <key>`: installs `tailscale=$TS_VERSION` from pkgs.tailscale.com with `apt-mark hold`, runs `tailscale up --login-server https://hs.uni.home.arpa --authkey <key> --hostname <node>`, and appends `<node>,<seconds>` to `results/enrolment.csv`. Seconds are counted from the start of install to `tailscale status` showing Running. Only on non-CT hosts, it adds a ledger row with undo `tailscale logout; apt-get purge -y tailscale; rm /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg`.
  - enigma Docker project `hs-sim` with services `hs-sim-bob` and `hs-sim-admin`. The image is `FROM tailscale/tailscale:v$TS_VERSION` plus socat, iperf3, nmap-ncat, and a CA bundle including the sim root (`SSL_CERT_FILE`). Each service gets `cap_add NET_ADMIN`, `/dev/net/tun`, `TS_USERSPACE=false`, `TS_STATE_DIR` on a named volume, `dns: [192.168.1.202]`, and `TS_EXTRA_ARGS=--login-server=https://hs.uni.home.arpa`. Ledger undo: `docker compose -p hs-sim down -v --rmi local`.
  - Laptop: its host Tailscale is on the hosted tailnet, so alice runs as `hs-sim-alice` under the compose `laptop` profile on the laptop. The laptop has no Docker yet. Install `docker.io` + `docker-compose-v2` from Ubuntu's archive, ledgered with undo `apt-get purge -y docker.io docker-compose-v2 containerd runc && rm -rf /var/lib/docker /var/lib/containerd && apt-get autoremove -y`. Before installing, check `iptables -S FORWARD`; Docker sets the FORWARD policy to DROP, and the user should know if the laptop was forwarding anything.

- [ ] **Step 1: Write `tests/test_users_devices.sh`:**

```bash
ON=$(hs nodes list -o json | jq -r '.[] | select(.online) | .given_name' | sort | tr '\n' ' ')
for n in admin-enigma alice-laptop bob-enigma; do assert_contains "$ON" "$n" "$n online"; done
assert_contains "$(node_exec alice-laptop 'tailscale ping --c 3 admin-enigma')" pong "alice<->admin ping"
assert_contains "$(node_exec alice-laptop 'tailscale netcheck')" campus "campus DERP listed"
assert_eq "$(tailscale status --json | jq -r '.BackendState, .CurrentTailnet.Name')" \
          "$(jq -r '.BackendState, .CurrentTailnet.Name' ledger/baseline/enigma-tailscale.json)" "enigma hosted tailnet untouched"
```

- [ ] **Step 2:** Run the test. Expected: FAIL.
- [ ] **Step 3:** Implement the scripts and the compose files, then enrol `admin-enigma` (admin1), `bob-enigma` (bob) and `alice-laptop` (alice).
- [ ] **Step 4:** Run the test. Expected: pass.
- [ ] **Step 5:** Commit: `feat(sim): enrolment tooling + researcher/admin devices`.

### Task 7: Enrol the lab PCs (proposal Phase 2)

**Files:**
- Create: `clients/labpc-listeners.sh`, `clients/enroll-labpcs.sh`
- Test: `tests/test_labpcs.sh`

**Interfaces:**
- Consumes: `make-ct.sh`, `mkkey.sh`, `enroll-linux.sh`.
- Produces:
  - Lab PCs `lab-a-01` (the server0 host itself, bare metal like a real lab PC), `lab-b-01` (`tag:labpc`) and `lab-b-02` (`tag:labpc,tag:gpu`). All are enrolled under user `labadmin` with single-use tagged keys.
  - `clients/labpc-listeners.sh <node>`: installs openssh-server (22), systemd units `hs-sim-listen@{3389,5900,8888,9999}` (`socat TCP-LISTEN:%i,fork,reuseaddr EXEC:/bin/echo`), and an `iperf3 -s` unit.

  server0 is not Proxmox, so lab-a-01 runs on the server0 host. If `config/server0-mode` is `native`, run `trust-ca.sh`, `resolved-dropin.sh`, `enroll-linux.sh` and `labpc-listeners.sh` there, with every file, unit and package ledgered. If it is `docker`, run a `hs-sim-lab-a-01` container with `network_mode: host` **not** allowed (it would clash with the host tailscaled); use a bridge network and publish nothing. Before choosing ports, check `ss -ltn` on server0: server0 already serves 80/443, and listeners 3389/5900/8888/9999 must not collide with anything.

- [ ] **Step 1: Write `tests/test_labpcs.sh`:**

```bash
for id in $CT_LABB1 $CT_LABB2; do run_on server1 "pct reboot $id"; done; run_on server0 'sudo systemctl restart tailscaled'; sleep 90   # don't reboot server0 itself; it hosts other services
J=$(hs nodes list -o json)
for n in lab-a-01 lab-b-01 lab-b-02; do
  assert_eq "$(jq -r ".[] | select(.given_name==\"$n\") | .online" <<<"$J")" true "$n online after reboot"; done
assert_contains "$(jq -r '.[] | select(.given_name=="lab-b-02") | .tags // .forced_tags | tostring' <<<"$J")" "tag:gpu" "gpu tag"
assert_eq "$(awk -F, '/^lab-/{s+=$2;n++} END{print (s/n<=600)?"ok":"slow"}' results/enrolment.csv)" ok "mean enrol <= 10 min"
assert_eq "$(node_exec alice-laptop "getent hosts lab-b-01.lab.internal | cut -d' ' -f1")" "$(node_ip lab-b-01)" "MagicDNS"
```

  The `.tags` / `.forced_tags` field name depends on the pinned version; adjust it to match `nodes list -o json`.
- [ ] **Step 2:** Run the test. Expected: FAIL.
- [ ] **Step 3:** Implement the scripts, set up lab-a-01 on the server0 host, and enrol the three lab PCs.
- [ ] **Step 4:** Run the test. Expected: pass.
- [ ] **Step 5:** Commit: `feat(sim): enrol 3 lab PCs across two rooms`.

### Task 8: Connectivity matrix and performance

**Files:**
- Create: `tests/connectivity_matrix.sh`, `tests/perf.sh`
- Test: `tests/test_matrix_perf.sh`

**Interfaces:**
- Consumes: `node_exec`, `node_ip`, `fw-mode.sh`.
- Produces:
  - `tests/connectivity_matrix.sh <label> [--src <node>]` (`--src` limits rows to that source) writes `results/connectivity-<label>.csv` with header `src,dst,path,latency_ms`. `path` is `direct`, `derp:<region>`, `no-peer` (the ACL hides the peer), or `fail`. The script parses the last line of `tailscale ping --c 5 --until-direct=false <dst>`.
  - `tests/perf.sh <label> [--src <node>]` writes `results/perf-<label>.csv` with header `pair,lan_mbps,ts_mbps,ratio,lan_ms,ts_ms,added_ms`. Pairs: `same-room` (lab-b-01→lab-b-02), `cross-subnet` (bob-enigma→lab-a-01), `laptop` (alice-laptop→lab-b-01, from a physical machine through the campus firewall). Each pair runs `iperf3 -t 10 -J` and `ping -c 20` against the destination's LAN IP and then its tailnet IP.

- [ ] **Step 1: Write `tests/test_matrix_perf.sh`:**

```bash
campus/fw-mode.sh open;        tests/connectivity_matrix.sh open;  tests/perf.sh open
campus/fw-mode.sh udp-blocked; tests/connectivity_matrix.sh udp-blocked
campus/fw-mode.sh open
assert_eq "$(head -1 results/connectivity-open.csv)" "src,dst,path,latency_ms" "header"
assert_eq "$(tail -n +2 results/connectivity-open.csv | wc -l)" 30 "6x5 ordered pairs"
assert_eq "$(grep '^alice-laptop,lab-a-01,' results/connectivity-open.csv | cut -d, -f3)" direct "open: direct"
assert_eq "$(grep '^lab-b-01,lab-b-02,' results/connectivity-udp-blocked.csv | cut -d, -f3)" direct "same room stays direct"
assert_contains "$(grep '^lab-b-01,lab-a-01,' results/connectivity-udp-blocked.csv | cut -d, -f3)" derp "blocked: relayed"
assert_eq "$(grep '^alice-laptop,bob-enigma,' results/connectivity-open.csv | cut -d, -f3)" no-peer "ACL hides peers"
assert_eq "$(tail -n +2 results/perf-open.csv | wc -l)" 3 "3 perf pairs"
```

- [ ] **Step 2:** Run the test. Expected: FAIL.
- [ ] **Step 3:** Implement both scripts.
- [ ] **Step 4:** Run the test. Expected: pass. If a direct/derp expectation fails, record the observation in `results/notes.md` instead of changing the network. That observation is a pilot finding.
- [ ] **Step 5:** Commit: `test(sim): connectivity matrix + perf, open vs udp-blocked`.

### Task 9: ACL and revocation tests

**Files:**
- Create: `tests/acl_expectations.tsv`, `tests/acl.sh`, `tests/revocation.sh`
- Test: both scripts are the tests (exit 0 means pass)

**Interfaces:**
- Consumes: `node_exec`, `node_ip`, `hs`, `mkkey.sh`, `enroll-linux.sh` / compose.
- Produces:
  - `results/acl.csv` with header `src,dst,port,expect,got,pass`.
  - `results/revocation.csv` with header `case,seconds,pass`.

`acl_expectations.tsv` (src dst port expect):

```
bob-enigma    lab-b-01      22    allow     bob-enigma    lab-b-01      3389  allow
bob-enigma    lab-b-01      5900  allow     bob-enigma    lab-b-01      8888  allow
bob-enigma    lab-b-01      9999  deny      alice-laptop  lab-a-01      22    allow
alice-laptop  lab-a-01      9999  deny      alice-laptop  bob-enigma    9999  deny
bob-enigma    alice-laptop  9999  deny      lab-b-01      alice-laptop  9999  deny
lab-b-01      lab-b-02      9999  allow     lab-a-01      lab-b-02      22    allow
admin-enigma  lab-b-01      9999  allow     admin-enigma  alice-laptop  9999  allow
```

(Two rows per line for brevity; the file has one row per line.)

- [ ] **Step 1:** Write `acl_expectations.tsv` and `tests/acl.sh`. For each row, `node_exec src "nc -z -w 3 $(node_ip dst) port"` gives `allow` or `deny`. A laptop or container destination gets a temporary `socat` listener on 9999 for the duration of the run only.
- [ ] **Step 2:** Run `tests/acl.sh`. Expected: 14/14 pass, exit 0. A mismatch is a real policy finding: fix `policy.hujson`, not the expectation, unless the proposal says otherwise.
- [ ] **Step 3:** Write `tests/revocation.sh` with three cases:
  - **`node-expire`**: confirm alice→lab-b-01:22 is allowed, run `hs nodes expire --identifier <alice id>`, then poll every 5 s for up to 120 s until the connection fails. Pass if ≤ 60 s. Re-enrol alice with a fresh key.
  - **`group-remove`**: remove `bob@` from `group:researchers` in the deployed policy, send SIGHUP to Headscale (or `systemctl reload` if the pinned unit supports it), and poll bob→lab-b-01:22 until it is denied. Pass if ≤ 60 s. Restore the policy and confirm it is allowed again.
  - **`expired-key`**: create a key with `--expiration 1s` and confirm enrolment with it fails.
- [ ] **Step 4:** Run `tests/revocation.sh`. Expected: all pass, exit 0, and alice and bob have access again at the end.
- [ ] **Step 5:** Commit: `test(sim): ACL matrix + revocation timing`.

### Task 10: Resilience (outage, server reboot, disaster-recovery restore)

**Files:**
- Create: `tests/outage.sh`, `tests/dr_restore.sh`
- Test: both scripts are the tests

**Interfaces:**
- Consumes: `install.sh --restore-from`, `set-hs-ip.sh`, `make-ct.sh`, `clients/enigma/compose.yaml`.
- Produces:
  - `results/outage.csv` with header `case,metric,value,pass`.
  - `results/dr.csv` with header `rto_seconds,nodes_back,nodes_total,pass`.

- [ ] **Step 1:** Write `tests/outage.sh [--minutes 30]`. Default 30, as in the proposal; `--minutes 2` for a dry run.
  - Start `ping -i 2` from bob-enigma to lab-b-01's tailnet IP in the background.
  - Stop Headscale. A fresh temporary container `hs-sim-tmp` with a new key must fail to enrol within 60 s, with a non-zero exit.
  - Wait the given minutes, then start Headscale. `hs-sim-tmp` must now enrol. It is the `tmp` profile of the Task 6 compose project, so the existing ledger row also covers it if the test crashes. Delete its node and remove the container.
  - Ping loss during the outage must be ≤ 1 %.
  - Then run `pct reboot 101`. Health must return within 120 s, and all 6 nodes must be online within 180 s.
- [ ] **Step 2:** Run `tests/outage.sh --minutes 2`, then `tests/outage.sh`. Expected: both exit 0.
- [ ] **Step 3:** Write `tests/dr_restore.sh`:
  1. Run `backup.sh`.
  2. Run `install.sh 899 192.168.1.205 --restore-from /backup/restic`. CT 899 gets the same `mp0`, read-only.
  3. Start a timer. Stop CT 101, run `set-hs-ip.sh 192.168.1.205`, and poll `nodes list` on 899 until all 6 nodes are online.
  4. Record the RTO; pass if ≤ 7200 s.
  5. Restore: run `set-hs-ip.sh 192.168.1.201`, start 101, wait until all nodes are online on 101, then run `./teardown.sh --task 10` to destroy 899.
- [ ] **Step 4:** Run `tests/dr_restore.sh`. Expected: exit 0, 6/6 nodes back, and afterwards `pct status 899` fails.
- [ ] **Step 5:** Commit: `test(sim): outage, reboot, DR restore drill`.

### Task 11: Soak run and report (proposal Phases 4–5)

**Files:**
- Create: `tests/collect.sh`, `tests/report.sh`, `tests/fixtures/*.csv`, `tests/hs-sim-collect.{service,timer}` (systemd user units on enigma)
- Test: `tests/test_report.sh`

**Interfaces:**
- Consumes: every `results/*.csv` from Tasks 6–10.
- Produces:
  - `tests/collect.sh` appends one row to `results/soak.csv`, header `ts,nodes_total,nodes_online,hs_health,cert_hours_left,direct_share,enigma_tailnet_ok`. `direct_share` comes from a fresh open-mode matrix. `enigma_tailnet_ok` compares against the baseline exactly as in Task 6.
  - `tests/report.sh <results-dir>` writes `<results-dir>/report.md`: a table with one row per §11 metric (Metric | Target | Measured | PASS/FAIL), using the targets in Global Constraints. Uptime = `hs_health` ok-rate over soak samples. Throughput and latency come from `perf-open.csv`, using the worst pair. User satisfaction is `N/A (not simulated)`. Security incidents come from `results/incidents.txt` (default 0).
  - The report also lists:
    - any soak sample with `cert_hours_left ≤ 0`, `hs_health` not ok, or `enigma_tailnet_ok=0`. Each makes that metric FAIL.
    - a "Not covered by the simulation" section copied from the Simulation Decisions table.

- [ ] **Step 1: Write `tests/test_report.sh`** against `tests/fixtures/`. The fixture `soak.csv` has 200 samples, 1 with health failing, 1 with `cert_hours_left=-1`. The `perf-open.csv` worst ratio is 0.65. Assertions:

```bash
tests/report.sh tests/fixtures; R=tests/fixtures/report.md
assert_contains "$(grep -i 'uptime' $R)" "99.5" "uptime computed"; assert_contains "$(grep -i 'uptime' $R)" PASS ""
assert_contains "$(grep -i 'throughput' $R)" FAIL "0.65 < 0.70"
assert_contains "$(cat $R)" "cert_hours_left" "expired-cert sample flagged"
assert_contains "$(grep -i 'satisfaction' $R)" "N/A" "survey not simulated"
assert_contains "$(cat $R)" "Windows" "gaps listed"
```

- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement `report.sh`, `collect.sh` and the user units. The timer runs hourly. Ledger undo: `systemctl --user disable --now hs-sim-collect.timer; rm ~/.config/systemd/user/hs-sim-collect.*; systemctl --user daemon-reload`.
- [ ] **Step 4:** Run `tests/test_report.sh`. Expected: pass. Run `tests/collect.sh` once. Expected: a new row in `soak.csv`.
- [ ] **Step 5:** Enable the timer. Use the tailnet for real work for `SOAK_DAYS` days (SSH into lab PCs, Jupyter on 8888, file copies). Re-run Task 8's matrix and perf scripts at the end, then run `tests/report.sh results`.
- [ ] **Step 6:** Commit: `feat(sim): soak collector + success-criteria report`. Commit the results after the soak with `docs(sim): soak results + report`.

### Task 12: Simulated off-campus (no phone, no router change)

**Files:**
- Create: `clients/offcampus.sh` (`up | down | mode strict|wg-allowed | status`), plus the `home` profile service `hs-sim-alice-home` in `clients/enigma/compose.yaml`
- Test: `tests/test_offcampus.sh`

**Interfaces:**
- Consumes: `ledger_add`, `node_exec`, `mkkey.sh`, `connectivity_matrix.sh --src`, `perf.sh --src`.
- Produces:
  - Docker network `hs-sim-home` (172.30.99.0/24) on enigma.
  - Container `hs-sim-alice-home` (Headscale user alice, a second device). It has `extra_hosts: hs.uni.home.arpa:192.168.1.201` (playing the server's public DNS record), `dns: [1.1.1.1]`, and at start `tc qdisc add dev eth0 root netem delay 30ms 5ms` (home ISP).
  - iptables chain `HS-SIM-HOME`, jumped from `DOCKER-USER` for packets from `-s 172.30.99.0/24`:
    - `strict` mode: ACCEPT 192.168.1.201 tcp/443 and udp/3478; DROP 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16; RETURN everything else (the internet).
    - `wg-allowed` mode: also ACCEPT udp to 192.168.1.0/24. This plays a campus that allows inbound WireGuard UDP.

    Ledger undo: `iptables -D DOCKER-USER -s 172.30.99.0/24 -j HS-SIM-HOME; iptables -F HS-SIM-HOME; iptables -X HS-SIM-HOME`. The rules don't survive an enigma reboot; `offcampus.sh up` re-applies them.

- [ ] **Step 1: Write `tests/test_offcampus.sh`:**

```bash
clients/offcampus.sh up; clients/offcampus.sh mode strict
H="docker exec hs-sim-alice-home"
assert_fails $H nc -z -w 3 192.168.1.111 22                 # no LAN path, like being at home
assert_fails $H nc -z -w 3 $IP_CAMPUS 53
assert_ok    $H nc -z -w 3 $IP_HS 443                        # the server's "public" port
assert_ok    $H sh -c 'wget -qO- https://pkgs.tailscale.com >/dev/null'   # internet works
assert_ok    $H sh -c 'ping -c 3 1.1.1.1 | grep -qE "time=[3-9][0-9]"'    # netem delay applied
assert_contains "$($H tailscale ping --c 5 --until-direct=false lab-a-01)" "DERP(campus)" "strict: relayed via campus DERP"
assert_ok $H nc -z -w 3 $(node_ip lab-a-01) 22                # ACL still lets alice SSH
assert_fails $H nc -z -w 3 $(node_ip lab-a-01) 9999
clients/offcampus.sh mode wg-allowed
assert_contains "$($H tailscale ping --c 10 lab-a-01)" "via 192.168.1.111" "wg-allowed: direct"
```

- [ ] **Step 2:** Run it. Expected: FAIL (no container).
- [ ] **Step 3:** Implement `offcampus.sh` and the compose `home` profile. Enrol alice-home with a fresh alice key.
- [ ] **Step 4:** Run the test. Expected: pass. Then, in each mode, run `tests/connectivity_matrix.sh offcampus-<mode> --src alice-home` and `tests/perf.sh offcampus-<mode> --src alice-home`. perf compares against the same pair from `perf-open.csv`, so the report shows what "from home" costs.
- [ ] **Step 5:** Commit: `test(sim): simulated off-campus with egress filter + netem`.

### Task 13: Pristine check and runbook README

**Files:**
- Create: `tests/test_pristine.sh`; complete `README.md`
- Test: `tests/test_pristine.sh`

**Interfaces:**
- Consumes: `ledger/baseline/*` (Task 1) and `teardown.sh`.

- [ ] **Step 1:** Write `tests/test_pristine.sh`. It asserts each of these equals its baseline:
  - server1: `pct list` (CT 101 back, stopped), `qm list`, network JSON (no vmbr2), CT 110 Prometheus config sha256
  - server0: tailscale JSON, CA certs list, `resolved.conf.d` list, package list
  - enigma: tailscale `BackendState` / tailnet / IPs
  - laptop: tailscale JSON (`BackendState`, tailnet), CA certs list, `resolved.conf.d` list

  And that each of these is empty or gone:
  - enigma: `docker ps -a`, `docker volume ls`, `docker images` filtered on `hs-sim`; `systemctl --user list-timers | grep hs-sim`
  - Grafana: dashboard uid `hs-sim` → 404
  - storage: `<storage1tb>/hs-sim-backup` and the vzdump archive

  Finally, every row in `ledger.tsv` must appear in `done.tsv`, except `manual` rows. Each manual row is printed as a reminder and must be confirmed by the user.
- [ ] **Step 2:** Run it now. Expected: FAIL, listing every sim resource. This confirms the check sees everything Tasks 2–12 created. If any created resource is *not* listed, add the missing ledger row in the owning task's script.
- [ ] **Step 3:** Write `README.md`: the topology table (who is where, IPs, VMIDs), the run order (Tasks 1–12 scripts), how to switch firewall modes, where the results are, and **teardown**: `./teardown.sh --dry-run`, then `./teardown.sh`, then `tests/test_pristine.sh`.
- [ ] **Step 4:** Commit: `docs(sim): pristine check + runbook`.
- [ ] **Step 5 (only when the user says the simulation is finished):** Run `./teardown.sh --dry-run`, show the output to the user, and get confirmation. Then run `./teardown.sh`, then `tests/test_pristine.sh`. Expected: PASS, with any `manual` rows confirmed by the user.
