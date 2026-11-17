# Agent coordination wave — worker G (galopin): tools, spawn, list, send

Branch feat/agent-tools off main. You own agent/** and PROTOCOL.md and
nothing else (worker C owns src/**; worker BG owns its own branch later —
see the wave brief for the file split). You implement; ambiguity → stop
and report.

Plan of record: the advisor's go-decision answer, logged in
/home/ubuntu/workspace/oc-orchestrator/STATE.md (2026-09-30 ~19:30 entry —
read it FIRST; it amends the parked designs with the tool-injection
prerequisite, galopin-owned approval, and the five review bar items).
opencode is 1.18.32, installed; the M-round slash gates are the bar for
every new injected tool (each gate proven in a live IT).

## Batch 1 — the spike, DAY 0.5 deliverable: PROTOCOL.md §6/§7 DRAFT

Before building anything: prove the injection route against real 1.18.32.
(a) Write a throwaway opencode custom tool installed by galopin; confirm
`execute(args, ctx)` receives ctx.sessionID and can call galopin's
loopback API. (b) Confirm a local MCP server does NOT carry the opencode
session (the reason it's the wrong route). (c) Confirm how galopin's
approval surfaces: a synthetic permission.asked event galopin holds and
resolves through the EXISTING permission.reply op — custom tools may run
without any ask, so "never auto-accepted" is enforced IN GALOPIN's code
path, never via opencode's permissions and never via isHandoffApproval's
substring match. Write the §6 (ops: backend.spawned?, session.spawn,
backend.sessions?, session.send + the steer capability) / §7 (Message.sentBy
{sessionId,title,hop}, the spawnedBy marker) DRAFT — worker C's contract
— and push it. Report the spike result (injection route proven? approval
path proven?) before continuing; if the route is wrong, STOP with evidence.

## Batch 2 — the framework + the three ops (~2d after the spike)

- **Tool framework + galopin-owned approval**: the injection mechanism from
  the spike, hardened; every injected tool call blocks on galopin's own
  approval (never auto-accepted, whatever the flags).
- **session_spawn {title, prompt, mode?}**: caller's workspace ALWAYS (no
  escape — refuse any other); mode inherits, equal-or-more-restrictive
  ONLY (no escalation); model inherits + the free-model gate; child
  auto-accept OFF whatever the caller has; NEVER auto-approved (handoff
  rule) with the title+mode+prompt on the card; fork-bomb limits (chain
  ≤2, ≤3 live per root, a rate limit); spawnedBy marker + audit rows on
  BOTH sessions.
- **session_list**: the machine's sessions (id, title, workspace, mode,
  status) for the caller's addressing.
- **session_send {target, text} delivery**: hop carries +1 per forward,
  refuse above 3; per-pair rate limit; same machine only; the target
  tracked and not archived; NO self or subtree sends (use task for that);
  deliver via prompt_async (busy targets fold server-side — Cerea's fold
  is worker C's half, not yours).
- **steer: true capability** advertised when the backend supports mid-turn
  prompts.
- **Live ITs pinned to 1.18.32** for EVERY gate (the M-round bar): a spawn
  from plan mode can't come out more permissive; a child's auto-accept
  stays off; hop and rate limits refuse; a spawn can't target another
  workspace; busy-target delivery folds.
- PROTOCOL.md finalized for what you built. The skill (batch 5) and docs
  residual ("an approved shell escapes every gate") are OC's, not yours.

## Rules (binding)

- NO sub-agents; foreground; every heavy command `timeout -s KILL <secs>
  flock /tmp/heavy.lock`; check free -m ≥1500 / df ≥20% before each heavy
  step, WAIT rather than compete (worker C shares the box; worker BG may
  join). Never kill processes you did not start (exact PID only after ps
  confirms an orphaned probe/IT instance). Go live ITs: GALOPIN_OPENCODE_IT=1
  (and ACP where the path is shared); client vitest needs
  TEST_MONGODB_URL=mongodb://127.0.0.1:8801. npm run check baseline: 0 —
  0 new. NO npm install. Never ports near 5199, never /opt/cerea.
- GIT: Paolo Viviani (configured); NO AI trailers; coherent commits (spike,
  framework, each op, ITs); push feat/agent-tools; NO merge to main.
- Report: design as built (the spike proof first), files, commits, exact
  test commands + pass counts, deviations. Then STOP for review.
