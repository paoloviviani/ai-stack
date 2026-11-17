# Batch 5: delegation skill + coordination docs (the public gate)

Branch feat/coord-docs off main (/home/ubuntu/workspace/Cerea, on main).
Docs + one skill file ONLY — no product code. You implement; ambiguity →
stop and report.

## The delegation skill (~0.15d)

Find where agent-facing skills live (skills/service.ts + skills/prompt.ts
exist — read them first; follow the established skill format exactly, do
NOT invent a new mechanism). Write ONE delegation skill teaching the model:
- fan out READ-ONLY work with several `task` calls in one message, on
  non-overlapping scopes;
- keep every edit in the parent; summarize children's results before acting;
- use `session_spawn` / `session_send` ONLY knowing each call raises an
  approval the person answers (never assumed, never bypassed);
- never promise background runs, inter-agent messages without approval, or
  top-level spawning outside the tools above.
The skill must describe ONLY what exists on main TODAY (blocking task
children, session_spawn/session_send with per-call approval, steering
mid-turn sends, hop-4 fallback, auto-approve badges). Verify each claim
against the shipped code/docs as you write it.

## Docs (~0.35d)

1. `docs/agent-machines.md` — new "Sessions that talk to sessions" section:
   the three tools, what each approval card shows (spawn: title+mode+full
   prompt; send: target+message+hop), the limits (chain≤2, ≤3 live/root,
   hop>3 asks, rate refuses), steering + hop fallback, the auto-approve
   rule (caller auto-accept in effect AND target same-workspace +
   equal-or-stricter; unknown asks; badges mark what went through), the
   --no-agent-tools opt-out. Read the shipped code (agenttools.go,
   PROTOCOL.md Auto-approval section) — document behavior, not wishes.
2. `docs/code-panel.md` — one table row for coordination (as the wave did
   for other features; keep it to a row + pointer to agent-machines).
3. **The residual, stated plainly on BOTH pages:** "an approved shell
   command can do anything you can on that machine (opencode's server
   password sits in its process environment, readable by same-user
   processes); the coordination gates constrain the model's tools, not an
   approved shell."
4. Rebuild the affected site strictly (`uv run --with-requirements
   docs/requirements.txt mkdocs build --strict`) — green required.

## Rules (binding)
- NO sub-agents; foreground; every heavy command `timeout -s KILL <secs>
  flock /tmp/heavy.lock`; free -m ≥1500 (read the AVAILABLE column if free
  misleads — page cache inflates used; `available` is the real figure) /
  df ≥20% before heavy steps, WAIT rather than compete (a second worker
  shares the box). Never kill processes you did not start. NO npm install.
  Never ports near 5199, never /opt/cerea.
- GIT: Paolo Viviani (configured); NO AI trailers; coherent commits; push
  feat/coord-docs; NO merge to main.
- Report: files, commits, exact test/build commands + results, deviations.
  Then STOP for review.
