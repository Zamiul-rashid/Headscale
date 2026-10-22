# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Lab admins** (the project team: Zamiul Rashid, Akid Anis, Tanzim Ahmed) run the system day to day. Mostly on a laptop, on campus or at home; sometimes a quick check on a phone between classes.
- **Supervisors** (Md. Golam Rabiul Alam, Mollah Md. Saif) open the same desk to see which group has which PC and to approve requests.
- Thesis group students use only the enrolment and status page (`/slots/enroll`), never the admin desk. Day to day they sign in to Headscale from their own devices and SSH to their group's PC during its slot with Tailscale SSH (no key or password: the tailnet identity is checked against the policy).

## Product Purpose

The admin desk of the BRACU CSE Research Lab's PC slot system. Every thesis group has booked 12-hour slots on lab PCs, but before this system nothing enforced them (anyone with a PC's AnyDesk details could connect at any time). The desk is where admins set the weekly schedule, approve booking requests, and see what the enforcer is doing right now. Success: at any moment an admin or supervisor can tell at a glance who is on which PC, what changes next, and whether enforcement is healthy, and can build or adjust a term's schedule quickly.

## Positioning

The schedule is the access control. Approving a cell in the weekly grid is what lets a group's devices reach that PC over the tailnet at that time; within 30 seconds the scheduler rewrites the Headscale policy, removes out-of-slot devices and switches the slot-active account on the PC. A calendar tool or spreadsheet only records bookings; this one enforces them.

## Operating Context

- Use is split evenly between two rhythms: heavy grid editing when a term is set up or reshuffled, and daily status checks and approvals through the semester.
- Slot model (proposal.tex): 14 slots per PC per week, 08:00-20:00 and 20:00-08:00 (Asia/Dhaka). A night slot belongs to the date it starts. Each group normally gets two slots on different days. Bookings repeat weekly within a term (a date range).
- Thesis groups do not request PCs or slots. They **enrol**: one member signs in with their BRACU Google account at `/slots/enroll` and sends the group's details (group name, thesis title, the supervisor and any co-supervisors with their emails, up to five members with name, student ID and BRACU G Suite email (@g.bracu.ac.bd, never a personal address), hardware needs). This replaces the Google Form the lab used before.
- An admin reviews each enrolment and **assigns** the group a PC and its weekly slots; timing is entirely the admin's decision. Approving creates the group and its bookings in one step. Rejections carry a reason.
- Groups learn the outcome on their status page at `/slots/enroll` (PC, slots, how to connect) and by email to every member once outgoing email is configured.
- Groups are lists of BRACU emails plus one Linux account (`grp-<slug>`); nobody holds an SSH key. PCs are tagged Headscale nodes (`tag:pc-41`).
- Enforcement has three switches: policy writing (on), device clean-up (dry-run by default), and on-PC account switching over Tailscale SSH (off until a PC is prepared with setup-lab-pc.sh). Failure falls back to an admins-only policy.

## Capabilities and Constraints

- Admin pages: Now (status), Schedule (weekly grid per term), Calendar (dated week view), Enrolments (queue and one-step assignment), Groups, PCs, Terms, Settings (admins, enforcement switches, extra policy grants, policy preview), Log (audit). Student page: Enrol / status.
- Stack: FastAPI, server-rendered Jinja templates, htmx 2 for in-place cell edits; no build step, no JS framework. Runs in Docker in a 2-core, 1 GB LXC.
- Served publicly at `https://hs.zamiulrashid.online/slots`; sign-in is Google, restricted by Google to the BRACU organisation, then to the admin list.
- Scale in the pilot: 15 PCs planned (3 enrolled now: pc-41, pc-43, pc25), up to about 6 groups per PC.

## Brand Commitments

- On-screen name: **BRACU CSE Research Lab** (the slot desk of that lab). No logo or other BRACU identity assets are in the repository; do not invent or imitate one.

## Evidence on Hand

- Real: the slot model and weekly example schedule in `proposal.tex`; three enrolled PCs (pc-41, pc-43, pc25); the enforcement behaviour in `labslots/labslots/enforcer.py`.
- Not yet real: thesis groups, members and bookings are still being set up with three experimental users. Any example groups shown in design work are illustrative and must be labelled as such.

## Product Principles

1. The whole week at a glance: every PC by every slot must stay scannable in one view, like a spreadsheet.
2. State before decoration: what is live now, what is pending, and what failed outrank everything else on screen.
3. Every action is accountable: approvals, removals and enforcement runs are visible and logged.
4. Fast in both rhythms: bulk grid editing at term start and one-tap checks and approvals during the term.
5. Works on a phone, built for a laptop.
