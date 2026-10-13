# Headscale pilot — home-lab rehearsal record

On 2026-10-13 we rehearsed the 15-PC lab Headscale pilot (see `../README.md`) on the home network,
ran its tests, and then removed everything. This folder is the written record of that run.

**Status:** torn down on 2026-10-13. Every machine was checked against its pre-simulation state
(21/21 checks passed). One manual step remains: **reboot the laptop** to clear Docker's leftover
iptables chains.

## Contents

| File | What it covers |
|---|---|
| [01-environment.md](01-environment.md) | The home lab before we started, and the one permanent change (OPNsense removed) |
| [02-what-was-built.md](02-what-was-built.md) | Topology, components, versions, and how each piece stands in for the real pilot |
| [03-tests-and-results.md](03-tests-and-results.md) | Every test, what it measured, and the numbers against the proposal's targets |
| [04-findings.md](04-findings.md) | What the rehearsal taught us for the real pilot |
| [05-problems-and-fixes.md](05-problems-and-fixes.md) | Bugs found while building and in the final review, and how each was fixed |
| [06-teardown.md](06-teardown.md) | What was undone, how it was verified, and what is left to do |
| [07-decisions.md](07-decisions.md) | Decisions taken along the way, and what each would cost if it was wrong |
| [execution-log.md](execution-log.md) | The raw executor log: every task result, decision, fix and deferred item, in order |

## Where the detail lives

- Plan: `../docs/superpowers/plans/2026-10-13-headscale-home-sim.md`
- Code, tests and runbook: `../sim/` (`../sim/README.md`)
- Raw results: `../sim/results/` (CSV files, `report.md`, `notes.md`)
- Every change made, with its undo command: `../sim/ledger/ledger.tsv`
- Git history on branch `hs-sim`: one commit per task, plus the review fixes and the final snapshot

The simulation can be rebuilt from `../sim/README.md` ("Build order").
