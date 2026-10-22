---
version: 1
slug: "labslots-labslots-templates-grid-html"
primary_target: "labslots/labslots/templates/grid.html"
related_targets: ["labslots/labslots/templates/base.html","labslots/labslots/templates/dashboard.html","labslots/labslots/templates/calendar.html","labslots/labslots/templates/requests.html","labslots/labslots/templates/groups.html","labslots/labslots/templates/group_edit.html","labslots/labslots/templates/pcs.html","labslots/labslots/templates/terms.html","labslots/labslots/templates/settings.html","labslots/labslots/templates/audit.html","labslots/labslots/templates/login.html","labslots/labslots/templates/_cell.html","labslots/labslots/templates/_cell_form.html","labslots/labslots/static/style.css"]
---

# Surface: labslots admin desk (all pages)

Scope: every page of the admin desk at /slots (Now, Schedule, Calendar, Requests, Groups, PCs, Terms, Settings, Log, sign-in). Mode: Operate.
Audience: lab admins and supervisors, laptop first, phone for checks. Task: see who has which PC now and next, approve requests, build and adjust a term's weekly grid.
Constraints: server-rendered Jinja + htmx, no build step; keep every route, form field and htmx target; must stay usable on a phone.

## Direction contract

THESIS: The schedule is the department's class routine: days across, PCs down, group codes typed into ruled cells. It refuses the admin-template look of cards, pills and a grey sidebar.

OWN-WORLD: White sheet ground; ink rules, heavier at each day boundary; routine blue (#1D4E89) owns the shell bar and today's column; a pale blue-grey second layer for panels; each group a highlighter tint behind its bold capital code; pending cells dashed and hollow, a failed switch red; system sans, one size inside the grid, tabular numerals.

STORY: An admin or supervisor opens the desk, reads who is on each PC this slot and when it changes, clears pending requests, and edits the week in place without leaving the sheet.

FIRST VIEWPORT: Blue bar with "BRACU CSE Research Lab", "Slots" and the navigation; a status line beneath (live slot, next change, enforcement switches, pending count); the routine grid fills the rest, PC column fixed left, seven day columns each split 08-20 / 20-08, today tinted blue, the live cell reversed; the cell editor docked right.

FORM: Class Routine, position 1 on my ordered list (the pick card), seed:5b3aec548af6a403. Signature move: highlighter marking, choosing a group highlights its cells across the routine and dims the rest, the way a student marks their own classes. Phone: one PC's week per screen, swipe snaps to the next.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
