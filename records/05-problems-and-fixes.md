# 05 — Problems found and how they were fixed

Each fix was made test-first: a test that failed, then the fix, then the test passing.

## While building

| Problem | Fix |
|---|---|
| A resource rebuilt after teardown stayed marked "done", so a later teardown would have skipped it | The ledger re-activates a row when its resource is created again |
| The ledger helper aborted scripts that use `set -e` when the done-list was empty | Fixed the exit status |
| The room-B firewall kept old UDP flows open after switching to "UDP blocked" | Mode changes now flush connection tracking |
| Latencies under 1 ms (`0s`, `µs`) were not parsed | Parser handles every Go duration unit |
| Lab PCs didn't trust the simulated CA, and `tailscale up` hung forever | CA installed first, `tailscaled` restarted, `tailscale up --timeout 120s` |
| ACL and performance loops ran only their first row (`ssh` / `docker exec` swallowed the input) | Loops read from a separate file descriptor |
| Researchers couldn't run iperf3 because port 5201 is outside the ACL | iperf3 runs on 5900, an allowed port, so the proposal's policy stays unchanged |
| An expired container client got stuck in a restart loop | `clients/reenroll.sh` recreates it with a fresh key |
| Restore from a read-only backup failed on restic's lock file | `restic --no-lock` |
| On the laptop, teardown would have removed its own SSH key before finishing there | The key is now the last thing removed |

## From the final review

Three independent reviewers read the finished code. All 14 "Important" findings were fixed:

- **Your original CT 101 could have been lost.** The archive cleanup used the wrong command, and nothing
  checked the restore had worked before freeing the only copy. It now frees the archive only once your
  CT 101 is back.
- **server0's own Tailscale could have been taken over** if it was merely stopped. Native enrolment now
  happens only if Tailscale is not installed at all.
- **The final check couldn't reach the laptop**, because teardown had already removed access. Teardown
  now has a `--keep-access` mode so the check runs first.
- The laptop cleanup ran a system-wide `apt autoremove`; it now removes exactly the 7 packages the
  simulation added.
- Bridge and Prometheus undos weren't safe to run twice; now they are.
- The client image carried a stale copy of the CA after a rebuild.
- Preflight couldn't be re-run while the simulation existed.
- The report graded throughput using a pair that isn't a real LAN comparison, hid skipped ACL rows, and
  didn't check how long the soak had run.

Lower-priority items (29) were logged but not fixed; they are listed as "minor (deferred)" at the end of
[execution-log.md](execution-log.md).

## During teardown

The final check reported that the original-CT-101 archive still existed. It didn't: the check used
`pvesm path`, which builds a path from the name without looking. The check now asks the storage what it
actually holds.
