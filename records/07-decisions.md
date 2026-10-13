# 07 — Decisions taken along the way

These are the calls made without stopping to ask. Each one notes what it would cost if it was wrong.

| Decision | Why | Cost if wrong |
|---|---|---|
| Simulate the university's DNS and CA with dnsmasq + step-ca instead of a real domain | No domain was available; you wanted it as close to real as possible | None: Caddy still used a real ACME flow |
| Run every client in Docker | enigma and the laptop already use a hosted tailnet that must not change | An extra NAT layer lowered the direct-connection share |
| Rebuild CT 101 instead of using a new ID, archiving the original first | You chose "rebuild 101" | None: restored at teardown |
| Take CT 101 out of the weekly backup job during the simulation | The job keeps only 2 backups and would have pruned the original's | None: re-added at teardown |
| Add the dashboard to Grafana as a file | No Grafana credentials were needed | None |
| Defer server0 (lab-a-01) | Its login was rejected | No room-A or LAN performance results |
| Keep the proposal's ACL exactly; run iperf3 on an allowed port | Test the policy as written | None |
| Record the low direct share as a finding instead of tuning the network | Report what really happens | May understate what native clients achieve |
| Judge the outage claim on direct sessions only; record relayed loss as a finding | The embedded relay stops with Headscale by design | Narrows the proposal's claim |
| Grade lab-PC throughput only on pairs with a real LAN comparison | Two CTs on one bridge are not a LAN | Throughput can't be judged without lab-a-01 |
| Compare containers by ID and name, and packages by name, in the final check | Your own CTs and apt upgrades may change status and versions | A status or version change made by the simulation would go unnoticed |
| Pin versions to releases at least 14 days old | Avoid brand-new releases | An upgrade later |

The full list of 40 decisions, each with its reasoning, is in [execution-log.md](execution-log.md)
(every line containing "Ruling:") and in the commit messages.
