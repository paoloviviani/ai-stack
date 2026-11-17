# Coordination follow-ups — worker P (auto-approve with no-escalation guard)

Branch feat/coord-autoapprove off main. You own the approvals change across galopin (agent/**) + the Cerea sender-card badge. A sibling worker owns the tree provenance change on a separate branch — coordinate implicitly via the file boundary (you do NOT touch CodeNavTree/codeSubagents; it does NOT touch agent/**, dispatch, relay, or ToolUpdate approval internals).

Plan of record: the advisor's verdict, logged in /home/ubuntu/workspace/oc-orchestrator/STATE.md (2026-09-30 ~23:15 entry — read it FIRST; the approvals section is your spec). You implement; ambiguity → stop and report.

## Spec (user's proposal + no-escalation guard)

- **Galopin (`agenttools.go`, decision BEFORE `Ask`):** a spawn or send is auto-approved (no gp_ ask raised) ONLY when (a) the caller's auto-accept is in effect (the session toggle AND the machine policy — the machine veto still vetoes), AND (b) for SENDS, the target's mode is equal-or-stricter than the sender's via modeRank, with an unrankable mode counting as MORE permissive. SPAWNS need no target check (the child is equal-or-stricter by construction, own auto-accept off, asks for its own tools). Handoffs and questions: never auto-accepted, UNCHANGED. The gp_ path stays exactly as is when an ask IS raised (never auto-accepted, Always→Once). No change to neverAutoAccept.
- **Hop fallback (not refusal):** at hop 4+, a send FALLS BACK to the approval card instead of refusing (this is what makes continuous back-and-forth possible). The per-pair rate limit stays a HARD refusal (the loop brake).
- **Audit:** decision:"auto" with the reason (e.g. "auto-accept; target no more permissive") next to approved/declined.
- **Cerea sender cards:** "Spawned …" / "Sent to …" cards gain an "auto-approved" badge when no ask was raised (so nothing goes through invisibly). The approval card itself is unchanged when shown.
- **Docs (PROTOCOL.md + the two site pages that will present it — check what exists):** state the rule + the residual, honestly: an auto-accept session can message equal-or-stricter peers unseen — power it already holds unattended, so no new capability; exposure = noise + peer context-steering, bounded by hop/rate, visible in audit + badges. `--no-agent-tools` still turns the whole thing off.

## ITs (live, pinned to 1.18.32, the M-round bar)
- a plan sender to a build target ASKS (card raised);
- two build sessions with auto-accept on go through automatically (no card, badge path);
- hop 4 asks instead of refusing;
- the rate limit refuses;
- with the machine's auto-accept denied, it always asks;
- a spawn under auto-accept creates a child with auto-accept off.

## Rules (binding)
- NO sub-agents; foreground; every heavy command `timeout -s KILL <secs> flock /tmp/heavy.lock`; free -m ≥1500 / df ≥20% before heavy steps, WAIT rather than compete (the tree worker shares the box). Never kill processes you did not start (exact PID only after ps confirms an orphaned probe/IT instance). Go live ITs: GALOPIN_OPENCODE_IT=1; client vitest needs TEST_MONGODB_URL=mongodb://127.0.0.1:8801. npm run check baseline: 0 — 0 new. NO npm install. Never ports near 5199, never /opt/cerea.
- GIT: Paolo Viviani (configured); NO AI trailers; coherent commits; push feat/coord-autoapprove; NO merge to main.
- Report: design as built, files, commits, exact test commands + pass counts, deviations. Then STOP for review.
