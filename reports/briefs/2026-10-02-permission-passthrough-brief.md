# Brief: permission pass-through — opencode's rules become the only ones (plus auto-accept done right)

## Decision (user, settled — not up for re-debate)
Cerea passes through opencode's permission system instead of running its own.
opencode owns every tool permission; Cerea shows opencode's asks as cards and
relays answers unchanged. Galopin keeps ONLY what opencode cannot own
(spawn/send approvals, which have no native equivalent, plus hard
non-permission rules: hop limit, rate limit, same-workspace check on sends).
Precedence, by user vote: Cerea-composed rules beat static file config —
the expected machine is headless, enrolled once and never touched, so policy
must move forward without SSH edits.

## Amendment (user requirement — implement as specified)
**Auto-accept inherits to subagents.** A child with no explicit setting
follows its nearest ancestor with one (on or off); a child explicitly off
overrides a parent that is on. The responder answers child asks under the
same caps as parent asks (tool asks only, `once`, ceiling-limited, never
questions). Rationale: the user lives in auto-accept; children that each
re-prompt would make it unusable. Note this is about galopin's RESPONDER,
not opencode rule inheritance (the binary inherits only denies to children
— handled separately by the agent-level floor below). Do not conflate them.

## Facts from the opencode 1.18.32 binary (advisor-read, not memory)
- Rules live in config `permission` (global file, project file if allowed),
  then per-agent `agent.<name>.permission`; `OPENCODE_PERMISSION` env is
  merged last *among config files* but still below session rules.
- Built-in default: `"*": "allow"`; only `doom_loop`, `external_directory`
  and reading `*.env` ask.
- `prompt_async` accepts NO `permission` field (Paseo's per-prompt approach
  targets an older SDK and is silently ignored here). The deprecated `tools`
  map REPLACES session rules wholesale (allow/deny only) — never send it,
  strip it from any input.
- Session rules: set at create or via `PATCH /session/:id {permission}`
  (appends: `merge(existing, payload)`). Ask resolution order, lowest to
  highest: built-in defaults → config permission → agent rules →
  **session rules** → in-memory "always" approvals (shared across every
  session in the workspace, checked after everything).
- Last matching rule wins, default `ask`.
- Subagents inherit ONLY parent denies and outside-workspace rules; parent
  allow/ask never reach children (children fall back to agent rules;
  `general` is `"*": allow`).
- "Always" beats even a later deny until opencode restarts.
- One reject ends all pending asks in that session.

## The five guards (all mandatory — the precedence claim in docs depends on them)
1. Apply rules atomically and in order: pass composed rules at session
   create, re-send only on change; machine ceiling appended AFTER Cerea's
   rules every time, so the ceiling always wins ties.
2. Never forward `tools` to opencode; strip it from any input (unit test).
3. Cap "always" by the ceiling: where the ceiling's max is below `allow`,
   turn an "always" answer into "once" (one click must not exceed the
   ceiling for every session in the workspace).
4. Restart opencode when the ceiling tightens (only way to clear in-memory
   "always"; galopin supervises the process anyway).
5. Agent-level floor: galopin sets `OPENCODE_CONFIG_CONTENT` at `run`,
   derived from `policy.json` (top-level `permission` + built-in agents'
   permission). Separately, apply the parent's composed rules to each child
   as soon as its session event appears (best effort — a first tool call
   can win the race; the floor holds that window).

## What happens to each piece
- `Policy.autoAccept`: deleted (Load ignores, Save drops, `policy show`
  stops printing). `enroll --allow-auto-accept`: becomes the ceiling's
  "responders allowed" setting (NOT a deprecated no-op).
- Panel Auto-accept toggle: stays, but DEFINED as opencode's own auto mode
  (per-session client-side responder: `once`, tool asks only, never
  questions, can't touch denies, nearest-explicit-ancestor inheritance
  INCLUDING subagents per the Amendment). It must never write permission
  rules (that would make machine permissions writable over the link).
- Panel gains a read-only Permissions line: effective rules for the
  session's agent + saved approvals; removing a saved approval is the
  only write (tighten-only). User-written global-file rules shown as
  "overridden by Cerea".
- `session.setAutoAccept`: stays, with the new meaning. `modeRank`,
  handoff name-substring rule, any-ancestor inheritance: deleted.
- Spawn/send decisions read galopin's composed rules (rule names
  `session_spawn`/`session_send` looked up from the asking agent's
  opencode rules): allow → no card (badge reads "allowed by this
  machine's rules"); deny → refused; ask-or-absent → galopin `gp_` card.
  `"*": "allow"` NEVER grants these two (else the permissive default
  silently enables session traffic); `"*": "deny"` refuses them.
  "Always" on a `gp_` card behaves as "once" (card hides Always).
- `enroll` writes `edit`/`bash`/`webfetch: ask` into the galopin-owned
  `opencode.json` for NEW machines. Existing machines: NO migration of
  `opencode.json` (dropped from the plan). Static file keeps only today's
  provider content; `OPENCODE_CONFIG_CONTENT` (rebuilt every `run`) carries
  the ceiling denies + the ask floor. No translation of old policy into
  allow-rules (would silently loosen).
- Protocol: `permission.reply` stays the single answer path (gp_ ids
  resolve galopin's held call, others go to opencode). Removed:
  `Policy.autoAccept` (§5), `by: "auto"` on `permission.replied`,
  §6 Auto-approval + subagent-inheritance text. Added: read-only
  `permission.rules` (effective rules + saved approvals) and
  `permission.saved.remove` (tighten-only, audited). Audit every reply
  and refusal as `permission {session, requestId, tool, decision,
  by: user}` — no patterns (for bash the pattern IS the command text).
- Threat model (must hold): ceiling appended last on every apply;
  responder + "always" capped by the ceiling; nothing else writes session
  rules. A hijacked session may loosen up to the ceiling (the voted
  trade) but never past it. Honest gap, document it: if the ceiling lets
  bash run, the agent can read opencode's server password from its
  environment and widen its own session — so `enroll` defaults bash to
  `ask`.

## Specs (all against the real 1.18.32 binary + the existing mock LLM)
- P1 file `edit: deny` + Cerea `edit: allow` → runs, no ask (Cerea beats file).
- P2 file `edit: allow` + Cerea `edit: ask` → exactly one `permission.asked`,
  still pending seconds later regardless of panel state; `once` lands it,
  `reject` errors the tool.
- P3 Cerea `edit: allow` + ceiling max ask → asks (ceiling wins); "always"
  becomes "once" (next identical write asks again).
- P4 parent `edit: allow`, subagent writes → asks (no inheritance; floor applies).
- P5 parent `edit: deny`, subagent writes → denied, no card (deny inherits).
- P6 "always" given, ceiling tightened to deny → denied after galopin
  restarts opencode.
- P7 a prompt carrying `tools` → never reaches opencode (unit test).
- Auto-accept: deny + auto on → no ask, no reply, no card; auto reply is
  always `once`, never creates saved approvals; questions never
  auto-answered; child explicitly off overrides parent on; **child with no
  setting follows parent on (Amendment) — responder answers the child's
  tool asks under full caps**.
- Spawn/send: allow/deny/ask/absent/`"*"`-allow (must card)/`"*"`-deny
  (must refuse)/cross-workspace/hop>3.
- Upgrade canaries (fail loudly on opencode bumps): last-match-wins;
  session-after-agent order; children inherit deny-only; "always" shared
  and checked after rules.
- Rules applied at create time, before the first prompt (no window).

## Rules of engagement (standard)
Work ONLY on `feat/permission-passthrough`, never main; no deploys; never
/opt/cerea. Gate heavy commands with `timeout -s KILL` + `flock
/tmp/heavy.lock`, only when `free -m` available ≥1500MB. Go tests for
touched agent packages; live ITs against the real 1.18.32 binary where the
specs above demand it. svelte-check/eslint/prettier on touched panel code.
Report per-case test counts, pushed commits, open items. Stop for approval
before any merge. Estimated 5–7 days; land it in reviewable commits.
