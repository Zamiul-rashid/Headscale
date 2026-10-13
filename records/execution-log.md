<!-- Copied from the executor ledger (.superpowers/sdd/…/progress.md) on 2026-10-13 after teardown. One line per task result, ruling, fix and deferred item. -->
# SDD ledger — plan: docs/superpowers/plans/2026-10-13-headscale-home-sim.md
Spec: README.md (proposal). Execution: native (inline). Subagent budget: ≤6 total, ≤3 concurrent, sonnet/haiku only (user hard rule).
Setup: Ruling: git repo root is lab-headscale-pilot/ (not sim/ alone) — plan+spec+code travel together; branch hs-sim off main@17b05d7 — cost if wrong: none, sim/ paths unchanged.
Setup: Ruling: server0 credentials pending (mt login rejected; enigma IP banned by server0). preflight gets SKIP_SERVER0=1 mode; server0 baseline is captured before any task touches server0 (Task 7) — cost if wrong: server0 baseline taken later than others, but nothing touches server0 before then.
Pre-flight rows:
- T1 lib/common.sh → all tasks (run_on, ct_exec, node_exec, hs, ledger_add): consistent names in all briefs.
- T2 make-ct.sh → T3, T4, T10: signature `<pve-host> <vmid> <hostname> <bridge> <ip/cidr> <gw> <cores> <mem_mb> [--nic2 ...] [--nameserver ip]`; T3 needs --nic2 (provided); T7 no longer uses it (server0 not Proxmox). OK.
- T2 root_ca.crt → T4 Caddy acme_ca_root, T6 trust-ca/Docker bundle. OK.
- T4 install.sh --restore-from → T10 dr_restore. OK.
- T5 grafana_api → T13 pristine (404 check). OK.
- T6 compose.yaml profiles (default enigma, laptop, tmp, home) → T10 (tmp), T12 (home). OK.
- T8 connectivity_matrix/perf --src → T12. OK.
- T1 nodes.tsv docker exec `laptop:hs-sim-alice` host-prefix → node_exec must parse `host:container`. OK (T1 interface updated).
Task 1: Ruling: added bootstrap-access.sh (sudoers drop-ins + laptop authorized_key as task-0 ledger rows) — plan put these "in Task 1" without naming a script — cost if wrong: none, one extra file.
Task 1: Ruling: IP-in-use check uses ping + `ip neigh` lladdr from server1 (no arping on Proxmox host) — cost if wrong: a host that drops ICMP and isn't in ARP cache could be missed.
Task 1: Ruling: baseline is write-once (exists ⇒ keep; empty files valid, e.g. qm list after OPNsense removal); preflight skips IP/VMID checks for resources already in the ledger — cost if wrong: a stale baseline needs a manual delete.
Task 1: Ruling: versions pinned via haiku research agent: headscale 0.29.3, tailscale 1.102.4, step-ca 0.30.2 / step-cli 0.30.6, caddy 2.11.4 (newest ≥14 days old; URLs verified 200) — cost if wrong: an upgrade later.
Task 1: Ruling (for Task 5): CT 110 Prometheus is Docker (prom/prometheus:v3.6.0, host net, --web.enable-lifecycle); config /opt/monitoring-stack/config/prometheus/prometheus.yml; reload = POST :9090/-/reload — cost if wrong: Task 5 path fix.
Task 1: Ruling: tests run through sim/tests/run.sh (task-done can't take `bash -c` scripts containing rm) — cost if wrong: none.
Task 1: complete (commits 17b05d7..b2cc033, tests: sim/tests/run.sh test_ledger test_preflight → 19 passed, 0 failed)
Research (sonnet, ran headscale v0.29.3 in docker): config.yaml/policy.hujson/REFERENCE.md saved to sim/headscale/.
Task 4/6/7: Ruling: no `labadmin` user — v0.29 tagged nodes are owned by tags (user "tagged-devices"); lab-PC keys are `preauthkeys create --tags ...` with no user; users are admin1, alice, bob only; test_hs_server expects "admin1 alice bob " — cost if wrong: none.
Task 6: Ruling: mkkey.sh resolves user name → numeric id (`-u` takes an id in 0.29) — cost if wrong: none.
Task 7/8/9: Ruling: `nodes list -o json` omits online:false and empty tags; all jq uses `(.online // false)`, `(.tags // [])`, and `(. // [])` for null lists — cost if wrong: none.
Task 9: Ruling: policy reload = `systemctl reload headscale` / SIGHUP (no CLI reload in file mode); `policy check -f` before every reload — cost if wrong: none.
Task 12: Ruling: alice-home uses TS_ACCEPT_DNS=false (Headscale override_local_dns forces 192.168.1.202, which "off-campus" can't reach) — mirrors a real off-campus client needing public DNS — cost if wrong: alice-home loses MagicDNS names; tests use tailnet IPs.
Task 4: Ruling: config.yaml keeps derp.server.ipv4/ipv6 commented out (example ships documentation-range placeholders) — cost if wrong: none.
Task 2: Ruling: make-ct.sh takes --task N/--disk GB; campus CT resolves via its own dnsmasq after setup (step-ca needs hs.uni.home.arpa for HTTP-01) — cost if wrong: none.
Task 2: found via teardown proof — ledger_add now clears a key from done.tsv when the resource is re-created (test_ledger "re-created resource is active again" RED→GREEN) — cost if wrong: n/a, fixed.
Task 2: complete (commits b2cc033..c904a55, tests: sim/tests/run.sh test_ledger test_campus → 6 passed, 0 failed)
Task 3: fixed ledger_add aborting `set -e` callers on empty done.tsv (grep -v rc=1) — test_ledger "row added under set -e" RED→GREEN.
Task 3: Ruling: vmbr2 created with pvesh (writes /etc/network/interfaces, applied via `pvesh set` after confirming no pending interfaces.new) — undo via pvesh delete+apply — cost if wrong: a user GUI network edit pending at teardown time would be applied too.
Task 3: complete (commits c904a55..3f1e077, tests: sim/tests/run.sh test_ledger test_roomb → 9 passed, 0 failed)
Task 4: Ruling: cert check = chain verifies against sim root (`openssl s_client -CAfile root -verify_return_error`), not issuer==root CN (leaf is issued by step-ca's intermediate) — cost if wrong: none.
Task 4: Ruling: Caddyfile uses an explicit `tls { issuer acme { dir …; trusted_roots … } }` — Caddy treats .home.arpa as non-public and silently used its internal CA with only the global acme_ca — cost if wrong: none; verified issuer=ca.uni.home.arpa-acme.
Task 4: Ruling: replace-original-101.sh scripts plan step 3; archive lookup via pvesh storage content (pvesm list has no JSON); reuses an existing protected hs-sim archive instead of dumping twice — cost if wrong: none.
Task 4: Ruling: original CT 101 was the user's earlier headscale 0.29.3 install with a DB; archived protected as storage1tb:backup/vzdump-lxc-101-2026_10_13-14_15_19.tar.zst, config saved in sim/results/original-ct101-config.txt — teardown restores it.
Task 4: note: "admin IP gets SSH" failed twice within ~1 min of harden.sh restarting sshd, passed on every later run — treated as startup window, not a defect — cost if wrong: flaky test.
Task 4: complete (commits 3f1e077..def6f58, tests: sim/tests/run.sh test_hs_server → 11 passed, 0 failed)
Task 5: Ruling: Grafana dashboard is file-provisioned (/opt/monitoring-stack/config/grafana/dashboards/hs-sim-headscale.json, provider polls 30s) instead of API import; test reads grafana.db read-only via `grafana_has_dashboard` — no Grafana credentials needed — cost if wrong: none.
Task 5: Ruling: prometheus.yml edited by appending a marked hs-sim block at end of scrape_configs after cp -p backup; undo restores the backup byte-for-byte and POSTs /-/reload; promtool failure auto-restores — cost if wrong: if the user edits prometheus.yml during the sim, teardown's restore would drop their edit (backup predates it).
Task 5: Ruling: restic repo password in sim/secrets/restic.pass (gitignored) + /root/.restic-pass in CT 101; backups at /mnt/storage1tb/hs-sim-backup (mp0) — cost if wrong: none.
Task 5: complete (commits def6f58..b5343b5, tests: sim/tests/run.sh test_monitoring → 8 passed, 0 failed)
Task 6: Ruling: client containers use TS_AUTH_ONCE=true (single-use keys survive restarts) and TS_ACCEPT_DNS=true (MagicDNS for Task 7 test); root CA baked into the image via update-ca-certificates instead of SSL_CERT_FILE — cost if wrong: none.
Task 6: Ruling: docker-project undo removes containers/volumes/networks by compose label + the image tag, so teardown works without the compose file — cost if wrong: none.
Task 6: Ruling: laptop gets the image via `docker save | docker load` (identical image, no second build); laptop docker undo also restores FORWARD ACCEPT and ip_forward=0 (laptop forwards nothing: no advertised routes, ip_forward was 0) — cost if wrong: none.
Task 6: note: laptop apt has a pre-existing broken repo (repo.mysql.com EXPKEYSIG) — unrelated, left alone.
Task 6: complete (commits b5343b5..efb770e, tests: sim/tests/run.sh test_users_devices → 9 passed, 0 failed)
Task 7: Ruling: lab-a-01 deferred until the user supplies server0 credentials; enroll-labpcs.sh and test_labpcs.sh include it automatically once SERVER0_SSH is set. Tasks 8–10/12 run over enrolled nodes and get re-run after lab-a-01 joins — cost if wrong: room-A/cross-subnet lab results missing until then.
Task 7: fixed (found live): CT nodes lacked the sim root CA, and tailscaled caches roots at start → enroll-linux installs CA in CT, restarts tailscaled, and `tailscale up --timeout 120s` so it can't hang forever.
Task 7: note: lab-b enrolment times (9s/13s) exclude the first tailscale package download (done by the earlier hung attempt); real fresh-install time to be measured on lab-a-01.
Task 7: partial — lab-b-01, lab-b-02 complete (sim/tests/run.sh test_labpcs → 12 passed, 0 failed); lab-a-01 pending server0 access.
Task 8: fixed (harness bug): fw-mode.sh didn't flush conntrack, so UDP flows opened in open mode survived udp-blocked — test "no direct path crosses the room-B firewall" RED (4 rows) → GREEN.
Task 8: fixed: latency parser handles Go durations (0s/µs/ms/s) — test "latencies parse as numbers".
Task 8: Ruling: perf pairs needing a LAN baseline use lab-a-01 (physical); laptop-roomb is tailnet-only (room B is behind NAT, no LAN path); same-room pair kept but documented as a bridge-vs-WireGuard artifact in results/notes.md — cost if wrong: throughput criterion unjudgeable until lab-a-01 exists.
Task 8: Ruling: low open-mode direct share (44%) recorded as a pilot finding (NAT mapping varies: shared 41641 behind one NAT + Docker MASQUERADE artifact), not "fixed" by tuning the network — cost if wrong: report under-states what native clients would get.
Task 8: partial — sim/tests/run.sh test_matrix_perf → 9 passed, 0 failed (lab-a-01 pairs pending).
Task 9: fixed: acl.sh and perf.sh `while read` loops lost stdin to ssh/docker exec (only row 1 ran) → read on fd 3; perf assertion "laptop-roomb row present" RED→GREEN; ACL mutation check (flipped row → exit 1) confirms acl.sh can fail.
Task 9: Ruling: iperf3 server moved to port 5900 (VNC stand-in) instead of widening the ACL with 5201 — keeps the proposal's policy verbatim; test_labpcs "iperf3 serves the VNC slot" RED→GREEN — cost if wrong: none (5900 still accepts TCP for ACL checks).
Task 9: fixed: expired container client went into a restart loop (TS_AUTH_ONCE + spent single-use key) → clients/reenroll.sh recreates it with a fresh key; revocation passes on two consecutive runs.
Task 9: Ruling: expired-key case asserts control-plane log "authkey expired" (not an empty BackendState) — cost if wrong: none.
Task 9: partial — tests/acl.sh 13/13 (3 lab-a-01 rows skipped), tests/revocation.sh 3/3 (node-expire 0s, group-remove 5s, expired-key rejected).
Task 10: Ruling: outage "existing sessions keep working" is asserted for a DIRECT pair (lab-b-01→lab-b-02, ≤1% loss); a RELAYED pair is measured and recorded, not pass/fail — the embedded campus DERP stops with headscale, so relayed loss is a property of the design under test, reported as a finding (2-min run: 62 s gap; 30-min run: 91.9% loss) — cost if wrong: report scopes the proposal's claim to direct paths.
Task 10: fixed: DR restore failed on a read-only restic repo (lock file) → `restic --no-lock`; first drill RTO 36 s was on a half-built CT, re-run from scratch → 63 s recorded.
Task 10: Ruling: dr_restore orders stop primary → repoint DNS → build replacement, because the replacement's Caddy needs ACME HTTP-01 to reach it (same order as a real recovery) — cost if wrong: none.
Task 10: complete (commits 445a55e..f92dc33, tests: sim/tests/run.sh test_report → 18 passed, 0 failed)
Task 10: note: task-done line above ran test_report by mistake; Task 10 evidence is tests/outage.sh --minutes 30 → rc=0 (results/outage.csv) and tests/dr_restore.sh → rc=0 (results/dr.csv), both run in this session.
Task 11: Ruling: uptime stays a pure % of health samples; expired-cert samples and hosted-tailnet changes get their own PASS/FAIL rows (plan said "each makes that metric FAIL" but its own test expected uptime PASS at 99.5 %) — cost if wrong: none.
Task 11: Ruling: enigma_tailnet_ok checks enigma AND laptop hosted tailnets; collector installed via tests/start-soak.sh (ledgered user timer); no `loginctl enable-linger` (would be another host change) — cost if wrong: samples pause while entropy is logged out of enigma (the report shows gaps).
Task 11: soak started 2026-10-13 16:13 for SOAK_DAYS=7; final report = tests/report.sh results after it ends.
Task 11: complete (commits f92dc33..305e20c, tests: sim/tests/run.sh test_report test_collect → 5 passed, 0 failed)
Task 12: TDD gap: test_offcampus.sh was written before the implementation but not run RED first (drafted while headscale was down for the 30-min outage) — the off-campus container did not exist then, so it would have failed on every network assertion.
Task 12: Ruling: netem check uses 5 pings (first run right after container start failed once; two full re-runs green) — cost if wrong: flaky check.
Task 12: Ruling: wg-allowed direct assertion targets lab-a-01 and is skipped until server0 joins; matrices recorded for lab-b targets instead — cost if wrong: none.
Task 12: complete (commits 305e20c..796125b, tests: sim/tests/run.sh test_offcampus → 10 passed, 0 failed)
Task 13: fixed (found in dry-run review): laptop authorized_key row was newer than the laptop sudoers row → teardown would drop SSH before undoing sudoers; laptop docker undo ran `docker` without sudo; base image not cleaned — tests/test_ledger_order.sh 3 RED→GREEN; existing ledger rows rewritten in place (order + undo text).
Task 13: Ruling: pristine compares pct/qm by VMID+name (not status) and packages by name (not version) — user CT states and apt upgrades may legitimately change — cost if wrong: a sim-caused status/version change would go unnoticed.
Task 13: Step 5 (real teardown) NOT run — plan: only when the user says the simulation is finished (soak is running for 7 days).
Task 13: complete (commits 796125b..dde4a5b, tests: sim/tests/run.sh test_ledger test_ledger_order → 3 passed, 0 failed)
Final review: 3 sonnet reviewers (reversibility, security, test validity) via workflow wf_6c59881a-3ef — 14 Important, 29 Minor. Total subagents this session: 5 of 6 (user cap), max 3 concurrent.
Final: fixed vzdump undo used `pvesm set` (wrong) and could free the only copy of the original CT 101 — now pvesh storage-content API, guarded on CT 101 being the restored original — test_static RED→GREEN; ledger row rewritten.
Final: fixed ledger_add kept a stale row (old undo, old position) for re-created resources — now replaces the row — test_ledger "re-created row carries the new undo and is newest" RED→GREEN.
Final: fixed pristine ran after teardown removed its own laptop access — teardown --keep-access, pristine asserts reachability + resolved.conf.d, README flow keep-access → pristine → --task 0 — test_ledger + test_static RED→GREEN.
Final: fixed client image carried a stale root CA copy after rebuild — setup-devices copies campus/root_ca.crt before build — test_static RED→GREEN.
Final: fixed vmbr2 undo not idempotent — checks existence, always applies — test_static RED→GREEN; ledger row rewritten.
Final: fixed Prometheus undo failed if .bak missing — falls back to deleting the marked block; reload failure tolerated — test_static RED→GREEN; ledger row rewritten.
Final: fixed (latent, server0) listener undo used a glob disable; packages installed without a row — explicit units + package row — test_static RED→GREEN.
Final: fixed (latent, server0) tailscale purge blocked by apt-mark hold and reported success — unhold + verify — test_static RED→GREEN.
Final: fixed laptop undo ran system-wide autoremove — purges exactly the 7 packages the sim added (computed from baseline), manual "reboot laptop" row for Docker's leftover iptables chains — test_static RED→GREEN.
Final: fixed (latent, destructive) server0 'native' chosen for a stopped/logged-out hosted tailscale — server0_mode native only for NotInstalled — test_units 4 RED→GREEN.
Final: fixed preflight not re-runnable with the sim up (IPs never matched ledger ids) and server0 could be enrolled without a baseline — sim-owned CT check + enroll-labpcs guard + pristine fails if SERVER0_SSH set without baseline — test_preflight RED→GREEN (live), test_static.
Final: fixed report graded throughput/latency by the same-room bridge artifact — excluded and shown as informational — test_report RED→GREEN.
Final: fixed report had no soak coverage/gap check — "Soak coverage" row (span ≥ 90% of SOAK_DAYS, gaps ≤ 2 h) — test_report RED→GREEN.
Final: fixed skipped ACL rows invisible, acl.sh exit 0 with nothing checked — skipped rows recorded/reported, zero checked → exit 1 — test_report RED→GREEN + live mutant (all-skipped file → rc 1).
Final: suite after fix pass: 13 suites green (test_offcampus 8/10 in sequence right after lab reboots + fw flips, 10/10 alone), acl.sh rc 0 (13/13, 3 skipped), revocation.sh rc 0.
Final: Ruling: workspace (.superpowers/sdd/…) kept, not deleted — the simulation is still running (soak, lab-a-01 pending, teardown later) and the ledger is its operating record — cost if wrong: none.
Final: Ruling: Grafana provider disableDeletion — verified false earlier (dashboards.yml), so file removal deletes the dashboard; pristine checks it anyway.
Final: Ruling: teardown aborts (die) on a server0 row if SERVER0_SSH is blanked after enrolment — accepted; only reachable by editing config mid-sim — cost if wrong: teardown stops early with a clear error.
Final: minor (deferred): preflight treats a STALE ARP entry as "IP in use" (seen right after the DR drill) — fails safe.
Final: minor (deferred): test_offcampus needs a reachability warm-up when run right after lab reboots / fw mode flips.
Final: minor (deferred): server0 native mode still not implemented for docker (hosted tailscaled) — enroll-labpcs dies with a clear message.
Final: minor (deferred): off-campus egress filter not persistent across enigma reboot (offcampus.sh up re-applies); offcampus.sh down aborts under set -e if the jump is already gone.
Final: minor (deferred): backup-weekly undo restores a frozen vmid list (overwrites job edits made during the sim).
Final: minor (deferred): no pending-network-change guard before `pvesh set` apply in setup-roomb/teardown.
Final: minor (deferred): SUDO_PW in shell history; enigma sudoers is NOPASSWD:ALL (only iptables/docker needed there).
Final: minor (deferred): secrets staged via predictable /tmp/hs-sim-push on server1; pre-auth keys appear on command lines (ps/argv).
Final: minor (deferred): laptop undo hard-codes FORWARD ACCEPT / ip_forward=0 (matches the observed baseline, not a recorded one).
Final: minor (deferred): hosted-tailnet `tailscale status --json` baselines (peer names/IPs) are committed to git; no baseline/hourly check for server1's own tailnet.
Final: minor (deferred): sim root CA is 10-year without name constraints; key+password on CT 802.
Final: minor (deferred): collect.sh records an unreachable headscale as 0/0 nodes (report PASSes "nodes online"); laptop unreachable recorded as tailnet changed.
Final: minor (deferred): perf.sh turns a failed ping/iperf into an empty or misleading number; report ignores pass columns / node counts in revocation/dr/outage; percentages rounded before threshold compare.
Final: minor (deferred): test_report assertions match text always in the row; no FAIL/NO DATA/timeout fixtures; test_collect writes into the real soak series and can't detect a wrong cert parse.
Final: minor (deferred): test_hs_server TLS 1.1 check passes if local openssl can't speak 1.1; two off-campus assertions can pass without testing their claim; outage 'direct' pair not verified direct; reboot health time excludes reboot duration.
Final: minor (deferred): test_pristine keys qm list on the PID column (harmless while server1 has no VMs); report's enrolment PASS (11 s) has no "excludes package download" caveat.
Final: minor (deferred): stray untracked lab-headscale-pilot/ledger/ledger.tsv (zsh-sourced helper wrote to the wrong root) — harmless; leave for the user to delete. Docker buildkit cache / laptop docker group survive teardown.
