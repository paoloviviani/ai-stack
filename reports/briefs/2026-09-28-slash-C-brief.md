# Batch C brief: backend commands end to end in Cerea

Worktree: /home/ubuntu/workspace/slash-cerea (branch feat/slash-commands at
931935b6: A0+B+A done). Cerea-side: the forwarder, the client API, the
transcript rendering, and the menu's backend half — plus running the
batch-B e2e from the MAIN checkout. You implement, you don't redesign;
ambiguity → stop and report.

Plan of record: /home/ubuntu/workspace/ai-stack/reports/2026-09-27-slash-commands-plan-rev1.md §4 batch C row; superseded 2026-09-26 plan §2.2 (forwarder table), §2.3's remaining halves (backend groups + shell icon + confirmation sheet), §2.6 (hermetic specs). galopin's side is DONE — read agent/PROTOCOL.md §6 (backend.commands + session.command rows, the Command type, the gate/refusal codes: not_found, conflict, forbidden, invalid) and §7 (Message.command marker) at 931935b6; that is your contract.

## 1. Forwarder rows (src/routes/api/v2/code/[...path]/+server.ts)

| Method | Browser path | galopin op | Notes |
| --- | --- | --- | --- |
| GET | v1/agents/:id/commands | backend.commands {sessionId} | getPairedDevice gate. Map to CodeCommand[] (the PROTOCOL Command shape). capability unsupported → 404, and the menu then shows panel commands only |
| POST | v1/agents/:id/command | session.command | zod: name /^[A-Za-z0-9][\w.:-]{0,63}$/, arguments ≤ the messages cap, messageId?, templateHash?. Attachments exactly as messages (promptAttachments under messageId). forbidden → 403 naming the enroll flag (--allow-command-shell); conflict → 409 "This command changed on the machine; review it again"; not_found → 404; invalid → 400. Audit row code.command {name, origin, shell} — NEVER arguments |

Follow the file's existing allowlist-table idiom exactly (read its header
first). $lib/codeApi.ts gains listAgentCommands + runAgentCommand. The
header's "Deliberately NOT offered" list stays true: no raw template read.

## 2. The transcript (src/lib/server/code/machineTimeline.ts)

- Map the user Message's `command` marker (PROTOCOL §7) onto the timeline:
  the bubble renders "/name args" as the person's message; the expanded
  template folds into a collapsed "Expanded command" disclosure beneath it
  (the existing fold/collapse idiom — find how long user texts or tool
  calls collapse today).
- Snapshots carry the marker via galopin's overlay — reload shows the same
  bubble shape. Sessions run before a galopin restart lose the marker and
  show the expanded text (acceptable, PROTOCOL says so).

## 3. The menu's backend half (AgentComposer + SlashCommand*)

- Fetch commands for the open agent when the `/` menu first opens (cache
  per open agent ~60s — the plan's rule); merge with the panel table:
  groups Panel / Project (badge "from this repo") / Machine / Skills / MCP
  (the autocomplete component already renders group headings).
- A shell icon on `shell: true` rows with a tooltip (the machine's snippets
  are NOT in the list payload — snippets only appear in the confirmation).
- Backend names colliding with reserved panel names render greyed
  "shadowed by a panel command" (the plan's collision rule).
- While a turn runs: the whole menu still opens but backend commands
  refuse with the existing mid-turn toast (galopin would answer invalid).
- Capability unsupported (old galopin) or 404: panel commands only — batch
  B already handles an empty backend list; wire the fetch failure the same
  way (silent fallback, panel-only).

## 4. The confirmation sheet

Even when commandShell is allowed, the first run of a `project`-origin or
`shell: true` command per (device, workspace, name, templateHash) opens a
confirmation sheet: the shell snippets (the list payload does NOT carry
them — fetch them… NO: PROTOCOL carries snippets in Command.shellSnippets
from backend.commands; render those), the file refs, "This command runs
on your machine. Running a project command is running repository code."
Accept → run with templateHash; remembered in localStorage per device;
"review again" on hash change (the 409 copy already says it). This is a
UI speed bump; the machine policy is the real veto.

## 5. Hermetic specs + the batch-B e2e

- Vitest: codeApi mapping; the forwarder route (zod, 403/409/404/400
  mapping, audit row) — follow the existing forwarder route tests;
  machineTimeline command bubble + collapsed expansion (the existing
  timeline test pattern).
- The B e2e (tests/code-commands.spec.ts) still needs a working build:
  **run it from the MAIN checkout /home/ubuntu/workspace/Cerea** (its
  node_modules has @xterm etc.; the worktree's symlinked node_modules
  breaks the build). Fetch feat/slash-commands into the main checkout on
  a DETACHED worktree add (do NOT move main): `git -C ~/workspace/Cerea
  worktree add /tmp/e2e-slash origin/feat/slash-commands` — but reuse
  node_modules by symlinking JUST the missing modules or by running from
  the main checkout after `git stash`-safe checkout. Simplest sanctioned
  path: in the MAIN checkout, `git checkout feat/slash-commands` is
  FORBIDDEN (main must stay on main) — so: worktree add to /tmp, symlink
  the main checkout's node_modules wholesale (same trick as slash-cerea),
  build there (the missing @xterm was a slash-cerea symlink artifact —
  verify: if the main node_modules builds, the /tmp worktree with the
  same symlink builds), run `E2E_APP_PORT=<free, NOT 5199>
  E2E_MONGO_PORT=8790-or-free MOCK_* ports per the spec's harness npx
  playwright test tests/code-commands.spec.ts` with a build first
  (E2E_SKIP_BUILD after). If the build still fails on a pre-existing
  module gap, report honestly and leave the e2e marked unverified — but
  TRY the main-checkout route; it has never actually been attempted.
- Add the new e2e cases to the same spec: backend command listed + run
  against the fake machine (the fake machine framework exists — extend
  it to answer backend.commands and accept session.command); the
  confirmation sheet on first project-command run; the 409-on-hash-change
  copy; panel-only fallback when the fake machine 404s.

## Box + git rules (binding)

- NO sub-agents. Foreground only; heavy commands under
  `timeout -s KILL <secs> flock /tmp/heavy.lock <cmd>`; free -m ≥1500 MB
  first (the Playwright build+run is the heaviest thing on this box —
  wait if low; disk check too: df before the build, ≥20% free).
- Client vitest needs TEST_MONGODB_URL=mongodb://127.0.0.1:8801.
- Git: configured identity, NO AI trailers, commit per coherent piece.
  Push feat/slash-commands; no merge, no main, no /opt/cerea, never 5199.
- The /tmp e2e worktree is throwaway: remove it (git worktree remove)
  when done, and never leave a build running there.

## Report

Design as built (rows, timeline shape, menu merge, the sheet), files,
commits, exact test commands + pass counts — the e2e's status stated
honestly (ran-from-main-checkout or unverified+why), deviations. Then
stop for review.
