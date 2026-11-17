# Agent coordination wave — worker C (Cerea): steering UI + coordination rendering

Branch feat/agent-coord-ui off main. You own src/** and nothing else
(worker G owns agent/** + PROTOCOL.md — read its §6/§7 DRAFT as your
contract, but never edit those files). You implement; ambiguity → stop
and report.

Plan of record: the advisor's go-decision answer, logged in
/home/ubuntu/workspace/oc-orchestrator/STATE.md (2026-09-30 ~19:30 entry —
read it FIRST; it amends the parked designs with the rendering homes:
transcript not CodeTasks, top-level nav rows with the rails idiom, and
the slash-refused-while-running rule).

## Steering UI + fold (~1.5d, starts day 1 — needs nothing from G)

- **Send beside Stop while a turn runs**: the composer gains a send action
  active during a busy turn (the person steers mid-turn); a "Stop and send"
  menu for the stop-then-prompt path. Keep the existing mid-turn toast for
  SLASH commands (slash stays refused while running in this wave — steering
  applies to PROMPTS only).
- **The mid-turn fold**: a user message arriving while the session is busy
  (opencode folds it into the next step; a new assistant message follows
  with NO fresh idle/busy pair) must render as one continuous turn, not a
  broken pair. Hermetic spec replaying opencode 1.18.32's real event order
  (capture the order from a live run if the docs don't pin it).
- Follow the composer/menu/pill idioms the recent waves established
  (TogglePill compact, the AgentComposer patterns, mobile parity — desktop
  AND mobile equally per the standing rule).

## Coordination rendering (~1–1.5d, against G's §6/§7 draft)

- **Galopin's approvals**: reuse the approval card (never-auto-accepted
  spawn/send calls surface through it) — read G's draft for the exact
  fields before building.
- **Markers**: Message.sentBy {sessionId,title,hop} → the target's bubble
  reads "From agent ‹title›", visually distinct from the person's own
  messages, with a link to the sender; the sender's transcript shows
  "Sent to ‹title›" and "Spawned ‹title›" tool cards with links.
- **Nav tree**: spawned sessions are TOP-LEVEL rows; reuse the rails +
  "↳ from" idiom that just landed (the collapse+rail wave) for the
  spawnedBy link.
- **NOT CodeTasks**: session_send renders in the transcript; CodeTasks
  stays the todo list only.

## Rules (binding)

- NO sub-agents; foreground; every heavy command `timeout -s KILL <secs>
  flock /tmp/heavy.lock`; free -m ≥1500 / df ≥20% before heavy steps, WAIT
  rather than compete (worker G shares the box). Never kill processes you
  did not start. Client vitest needs
  TEST_MONGODB_URL=mongodb://127.0.0.1:8801 (component specs run locally
  in Chromium as the recent waves did). npm run check baseline: 0 — 0
  new. Prettier/eslint clean on touched files. NO npm install. Never ports
  near 5199, never /opt/cerea.
- GIT: Paolo Viviani (configured); NO AI trailers; coherent commits
  (steering UI, fold spec, approvals rendering, markers, nav link); push
  feat/agent-coord-ui; NO merge to main.
- If G's draft isn't pushed yet when you need it, build steering first
  (it needs nothing from G) and say so in the report — do NOT invent the
  contract.
- Report: design as built, files, commits, exact test commands + pass
  counts, deviations. Then STOP for review.
