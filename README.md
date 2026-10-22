# Lab PC access: Headscale and labslots

Remote access to the BRACU CSE Research Lab's PCs over a self-hosted Headscale tailnet, limited to each
thesis group's booked slots.

Every PC has 14 twelve-hour slots a week (08:00–20:00 and 20:00–08:00, Asia/Dhaka). The weekly routine lives
in a Google Sheet. **labslots** reads it every 30 seconds. One slot agent per Headscale server then:

- writes the policy for the current slot;
- makes the incoming group's account the only active one on each PC, over Tailscale SSH;
- optionally removes devices that are out of their slot.

A student reaches their group's PC only while the group's slot is running. They log in with Tailscale SSH as
the group's account, with no key or password.

## Layout

```
labslots/                    the slot system (Python 3.11+, FastAPI, SQLite)
  labslots/
    web.py                   hub: admin pages, enrolment, settings, agent API, Sheet sync loop
    sync.py                  Google Sheet -> SQLite; the Sheet is the source of truth, SQLite the last good copy
    sheets.py                Google Sheets API client (service account)
    sheet_style.py           formatting applied to the Sheet
    hub.py                   each server's slice of the schedule; agent tokens and reports
    agent.py                 slot agent: fetch the slice, enforce it, report back (keeps enforcing if the hub is down)
    enforcer.py              one enforcement run: policy, PC accounts, device clean-up
    policy.py                builds the Headscale policy: grants and Tailscale SSH rules
    headscale.py             minimal Headscale REST client
    sshexec.py               runs slot-switch on a PC over Tailscale SSH
    slots.py                 slot arithmetic
    db.py                    SQLite schema and queries
    mailer.py                outgoing email for enrolment decisions
    backup.py                nightly copies of the SQLite databases
    config.py                settings from the environment; secrets are read from files
    pc/setup-lab-pc.sh       prepares a lab PC: Tailscale SSH, the labsched account, slot-switch
    templates/, static/      Jinja pages, stylesheet, htmx
  tests/                     pytest suite
  stress/                    load tests: run.py (one host), scale.py (several hosts), results/
  docker-compose.yml         hub, slot agent, scheduler sidecar and backup, next to Headscale
  agent-compose.yml          slot agent for an additional Headscale server
  deploy.sh                  build, switch, health-check, roll back
  devserver.py               local demo with illustrative data (devserver_scale.py: 70 PCs)
headscale/                   production Headscale and Headplane configuration (secrets referenced by path)
proposal/                    pilot proposal: LaTeX source, PDF, earlier Markdown draft (under revision)
records/                     record of the 2026-10-13 home-lab rehearsal of the pilot
PRODUCT.md, DESIGN.md        product brief and design system for the web UI
```

## Development

```sh
cd labslots
python3 -m venv .venv && .venv/bin/pip install -e '.[test]'
.venv/bin/python -m pytest
env -u PYTHONPATH .venv/bin/python devserver.py
# http://127.0.0.1:8765/slots/dev-login?email=admin@g.bracu.ac.bd
```

## Deployment

**Hub and first agent:** on the Headscale host, in `/opt/labslots`. Secrets go in `secrets/<service>/`;
the comments at the end of `docker-compose.yml` list each file. `./deploy.sh` builds a tagged image,
switches to it and rolls back if the health checks fail. `./deploy.sh rollback` and `./deploy.sh status`
do what they say.

**More Headscale servers:** register the server under Settings → Headscale servers, then follow the steps
at the top of `agent-compose.yml`.

**Lab PCs:**
1. Join the PC to Headscale with its `tag:pc-N` pre-auth key.
2. Download the setup script from the PCs page and run `sudo bash setup-lab-pc.sh <admin-user>`.
3. Set Account switching to Yes for the PC in the Sheet's PCs tab.

Check the policy preview in Settings shows `ssh` rules **before** step 2. With Tailscale SSH on, the PC
accepts tailnet SSH only from those rules.

## Configuration

Hub (`labslots` service):

| Variable | Purpose |
|---|---|
| `LABSLOTS_PUBLIC_URL`, `LABSLOTS_BASE_PATH` | public address, e.g. `https://hs.example.org` and `/slots` |
| `LABSLOTS_BOOTSTRAP_ADMINS` | comma-separated admin emails that always exist (the Sheet's Admins tab adds more) |
| `LABSLOTS_SHEET`, `GOOGLE_SA_KEY_FILE` | the schedule Sheet's ID, and the service-account key that reads it |
| `OIDC_ISSUER`, `GOOGLE_OAUTH_CLIENT_FILE` | Google sign-in; the OAuth client JSON as downloaded |
| `LABSLOTS_STUDENT_DOMAINS` | domains students may enrol with (default `g.bracu.ac.bd`) |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_FROM`, `SMTP_PASSWORD_FILE` | email; off while host or sender is empty |
| `LABSLOTS_DATA`, `LABSLOTS_DB`, `SESSION_SECRET_FILE`, `LABSLOTS_INTERVAL`, `LABSLOTS_DEV_LOGIN` | data directory, database, session key, Sheet read interval (s), demo sign-in |

Slot agent (`labslots-agent` service):

| Variable | Purpose |
|---|---|
| `AGENT_HUB_URL`, `AGENT_TOKEN_FILE` | where the hub is, and this server's token from Settings |
| `HEADSCALE_URL`, `HEADSCALE_API_KEY_FILE` | this server's Headscale |
| `LABSLOTS_SSH_SOCKS` | the scheduler sidecar's SOCKS5 address, used for Tailscale SSH to PCs |
| `LABSLOTS_SSH_USER`, `LABSLOTS_SSH_KNOWN_HOSTS`, `AGENT_INTERVAL`, `AGENT_DB` | PC login account (`labsched`), known hosts file, run interval (s), database |

Backup (`backup` service): `BACKUP_SOURCES`, `BACKUP_DIR`, `BACKUP_KEEP_DAYS`, `BACKUP_AT`.

## Access model

The policy is rewritten at every slot change:

| Who | Network | Tailscale SSH as |
|---|---|---|
| `group:admins` | every lab PC, any port | any non-root account |
| `tag:scheduler` (the slot agent) | every lab PC, `tcp:22` | `labsched` only |
| `group:<code>` while in its slot | its PC, `tcp:22` plus the Ports setting | `grp-<code>` only |

Settings adds **Extra grants** and **Extra SSH rules** (for example the jumphost); each extra SSH rule
comes with its own `tcp:22` grant. If the policy cannot be built or applied, the agent falls back to
admins-only.

Enforcement switches, in Settings:

| Switch | Default |
|---|---|
| Policy writing | on |
| Clean-up of out-of-slot devices | dry-run |
| Removal of devices of students in no group, a day after they leave | on |
| PC account switching | off until PCs are prepared |
