# ADR 0109: One person, one selector — no machine limits; auto-approval per user

- Status: accepted (owner, 2026-11-06)
- Supersedes: ADR 0107 §1 (machine classes with never/ask/run limits set at enrollment) and §2 (deployment
  admin's auto-approval screen, per-class rows, blocking save-time test). Keeps from 0107: the classes as
  labels for routing/review/audit, Plan · Ask · Auto, the decision-model reviewer, the read-only rule
  (amendment), human "always" (amendment, G11 scoping), the threat model (safety rails, not a boundary).

## Why

The person who uses Cerea is the person who installs galopin. Machine limits did not protect against a
compromised Cerea (an `ask` card is answered through Cerea) and pushed users to re-enroll with everything at
`run` to stop the cards. As in Claude Code, the hard limit is the sandbox (ADR to write, backlog C72); everything
else is chosen by the user in the GUI.

## Decision

1. **No machine limits.** galopin decides from the session word (Plan → refuse, Ask → card, Auto/Allow → run,
   with Cerea routing cards in Auto) plus a fixed floor. `policy.json` limits and `--limit` are ignored (one
   release accepted with a warning; `policy show` says they are ignored). The welcome no longer advertises
   limits; Cerea ignores any it receives. The Pair a machine dialog loses the limits table.
2. **Fixed floor, in code, not configurable:** galopin's own state/config is always refused; in Auto, writes to
   `.git/**`, CI config and credential/secret paths always come to the user (static escalate list); loop alerts
   stay a card; the reviewer's fixed frame and trailer stay.
3. **Optional local deny (advanced, hidden):** `galopin enroll ... --deny CLASS` (repeatable) and
   `galopin policy set --deny`, refuse-only, stored locally, never set over the link. Not in the Pair dialog. For
   an owner who does not fully trust the Cerea server.
4. **Auto-approval per user**, in Workspace → Agents: reviewer on/off, decision model (among the gateway's
   decision models the user may use), threshold (floor 0.50, default 0.85), instructions (inside the fixed frame),
   per-class rows (you | reviewer), "never auto review" per device. Billed to the user's own grant. The standard
   cases are a **Test** button that shows results; they never block a save.
5. **Admin keeps only the switch** that enables Auto with a reviewer for the deployment (and the kill switch
   `CHAT_AUTO_PERMISSIONS`). Room is left for an optional admin policy later (e.g. caps), not built now.
6. **Migration:** the current deployment-level settings seed each user's defaults on first read (users who never
   edit keep the deployment's model/threshold/instructions as their own starting point).

## Plan

Two workstreams, folded into Cerea 0.43.0: (a) galopin: limits removed, floor, local deny, migration, tests incl.
the real-opencode suite; (b) Cerea: user Agents settings + review service per user, admin switch only, Test
button, composer/shield/Pair dialog without limits, docs.

## Amendment 2026-11-06: what each step means without machine limits

- **Plan** refuses. **Ask**: every action is a card to the user. **Allow**: fully hands off — everything runs
  except the fixed floor (galopin's own state refused; credential/secret paths, `.git/**` and CI writes still a card).
- **Auto**: per kind of action, the user's rows in Workspace → Agents now have **three** values:
  **runs** (no card), **reviewer**, **you**. Cerea sends galopin, with the session word, the per-class map for that
  session (`run` | `ask`); galopin runs the `run` classes and raises cards for the `ask` ones, which Cerea routes to
  the reviewer or the user per the row. Read-only commands always run. With the reviewer off (or unreachable, or the
  device opted out), "reviewer" rows fall back to **you** — Auto never silently becomes Allow.
- Defaults for the rows: edit, web, agents, tools → runs; command, outside → reviewer; secrets → you; loop fixed.
- A session's step is chosen in its composer; a project's agent profile (ADR 0106) can set the default step for new
  sessions in that project, so "this project is hands off" is a project setting, not a change to the user's
  reviewer policy.
