# Lab PC access: Headscale and labslots

Remote access to the BRACU CSE Research Lab's PCs over a self-hosted Headscale tailnet, limited to each
thesis group's booked slots.

Every PC has 14 slots a week (06:00–17:55 and 18:00–05:55, Asia/Dhaka). Each slot ends five minutes before
the next starts; in that switch-over no group has access. The weekly routine lives in a Google Sheet.
**labslots** reads it every 30 seconds. One slot agent per Headscale server then:

- writes the policy for the current slot, closing it at its end before the next group is let in;
- makes the incoming group's account the only active one on each PC, over Tailscale SSH (in the switch-over,
  no account: the outgoing group's sessions and processes end);
- optionally removes devices that are out of their slot.

A student reaches their group's PC only while the group's slot is running. They log in with Tailscale SSH as
the group's account, with no key or password.

## Layout

```
labslots/                    the slot system (Python 3.11+, FastAPI, SQLite)
  labslots/
    web.py                   hub: admin pages, enrollment, settings, agent API, Sheet sync loop
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
    mailer.py                outgoing email for enrollment decisions
    backup.py                nightly copies of the SQLite databases
    config.py                settings from the environment; secrets are read from files
    pc/setup-lab-pc.sh       prepares a lab PC: Tailscale SSH, the labsched account, slot-switch
    templates/, static/      Jinja pages, stylesheet, htmx
  tests/                     pytest suite
  stress/                    load tests: run.py (one host), scale.py (several hosts), results/
  Dockerfile                 the labslots image, published as ghcr.io/zamiul-rashid/labslots
  docker-compose.yml         hub, slot agent, scheduler sidecar and backup, next to Headscale
  agent-compose.yml          slot agent for an additional Headscale server
  deploy.sh                  pull a release (or build), switch, health-check, roll back
  devserver.py               local demo with illustrative data (devserver_scale.py: 70 PCs)
headscale/                   production Headscale and Headplane configuration (secrets referenced by path)
.github/workflows/           ci.yml: tests and image build; release.yml: image and GitHub release per tag
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

## What runs where

| Part | How it runs |
|---|---|
| Headscale | **On the host, not in Docker**: the official `.deb` from Headscale's GitHub releases, version pinned, as the `headscale` systemd service. Config in `/etc/headscale/` (see `headscale/headscale-config.yaml`), data in `/var/lib/headscale/`. Upgrade it by hand with the next `.deb`, after reading Headscale's upgrade notes. |
| labslots hub, slot agent, backup | Docker, from the published image `ghcr.io/zamiul-rashid/labslots:<version>` (`labslots/docker-compose.yml`) |
| Scheduler node (`ts-scheduler`) | Docker, the upstream `tailscale/tailscale` image, pinned in the compose files |
| Headplane | Docker, the upstream `ghcr.io/tale/headplane` image (`headscale/headplane-config-and-compose.yaml`); reads Headscale's config read-only and never restarts it |

All containers use host networking and reach Headscale at `127.0.0.1:8080`. Headscale is never in a
container in production, and no release contains it; the backup service only reads its database. (The
load tests in `labslots/stress/` start a throwaway Headscale in Docker on a test host, for tests only.)

## Releases

Each release of labslots is a Docker image and a GitHub release with the same version number:

- `ghcr.io/zamiul-rashid/labslots:<X.Y.Z>`, plus `:<X.Y>` and `:latest`, for `linux/amd64` and `linux/arm64`;
- a release on the [Releases page](https://github.com/Zamiul-rashid/Headscale/releases) saying which image
  to deploy, with the changes since the last one.

To make one: set `version` in `labslots/pyproject.toml`, commit, then tag and push the tag:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

`.github/workflows/release.yml` checks the tag matches `pyproject.toml`, runs the tests, builds and pushes
the image and writes the release. `ci.yml` runs the tests and an image build on every push and pull request
but publishes nothing. The running version shows at `/slots/healthz`.

## Deployment

**Hub and first agent:** on the Headscale host, in `/opt/labslots`, with `docker-compose.yml` and
`deploy.sh` from this repo. Secrets go in `secrets/<service>/`; the comments at the end of
`docker-compose.yml` list each file.

```sh
./deploy.sh 0.2.0      # pull that release, switch to it, roll back if the health checks fail
./deploy.sh rollback   # back to the image that ran before
./deploy.sh status     # running image, kept images, container health, last backup
./deploy.sh build      # build from the source in this folder instead (unreleased code)
```

The image in use is `LABSLOTS_IMAGE` in `.env`; `deploy.sh` keeps it and the previous one there.

**More Headscale servers:** Headscale is installed there the same way (`.deb`, systemd). Register the
server under Settings → Headscale servers, then follow the steps at the top of `agent-compose.yml`. It
needs only that file and a release version in `.env`, not the source.

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
| `LABSLOTS_STUDENT_DOMAINS` | domains students may enroll with (default `g.bracu.ac.bd`) |
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
