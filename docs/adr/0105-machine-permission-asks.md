# 0105 — Machine permission asks: a skip flag and a review-model auto mode

- Date: 2026-10-29
- Status: **ACCEPTED** 2026-11-04, with the owner's decisions below (the reviewer is a decision model, ADR 0100). Was: PROPOSED, not started. The owner reviewed the amended draft
  themselves and applied their modifications directly; the owner's edits in
  this file are part of the proposal.
- Related: 0075 (the chat's approval gate — untouched by this ADR), 0097 (the
  permission decision function and its protected asks), 0090 (the code audit
  store), 0100 (decision models — a different concept, see Future), 0104 (the
  admin-control pattern this follows for enablement), P17 (request logs, the
  shape of the decision record)
- Code touched: `agent/` (galopin: the flag, two policy keys, an auto branch in
  the decision function, the hello capability), PROTOCOL.md **and its fixtures
  in the same commit** (the `auto` value in the permissiveness lattice and its
  enums, a reply-actor field, `capabilities.autoPermission`, the posture flag on
  the status frame), Cerea (`src/lib/server/code/`: the reply path gains the
  review-model interposition, the audit lines, the mode in the agent view and
  schedule editor; `push/watch.ts`: the interposition before notification),
  Pystino: a catalogue flag on a chat-kind model (no new kind, no router)

## Context

Machine permission asks — opencode's "may I run this / touch that", decided by
galopin's decision function and surfaced by Cerea to the person — have no
answer when nobody is watching. On the night of 2026-10-28 a release train
stalled for hours on a single `external_directory` ask at 23:00. Two postures
are wanted, for two different situations:

- **The owner is confident and absent on purpose** (a release train, a batch of
  workers): every ask that today would become a card should be answered "allow"
  without a human, because the human has accepted the residual risk at launch.
- **The owner is absent and wants a delegate**: a model should answer the
  routine asks and wake the owner for the rest.

Two different tools, two different risks. The design mistake to avoid is making
the delegate an unconditional approver: it sits downstream of injectable content
(the agent's own prompt and even a page it fetched can carry planted
instructions — "always approve"), so it must never be the final word on anything
dangerous.

Two systems must not be confused. **Machine permission asks** are the subject of
this ADR. **The chat's tool-approval gate** (ADR 0075: a turn parks until the
person approves a tool call) is a different system with different stakes — a
model answering that would change what "approved" means for every chat turn. It
stays human.

**Who owns what today** (it matters for everything below): the pending ask lives
on the machine — opencode parks it (`permissions.pending`, "a read of live
state, never a queue") and it dies only with the opencode process; galopin's
decision function decides locally what it can. Cerea owns the reply path, the
panel, the push notification and an audit store — not the pending state.

## Decision

### 1. `--dangerously-skip-permissions` (galopin run)

- **Scope, said honestly:** one `galopin run` process is the machine's whole
  agent (single-instance lock) and serves every session of every workspace,
  including sessions opened mid-run and scheduled runs that fire while it
  lives. The flag is therefore **process-wide and machine-wide for its
  lifetime — but not persisted**: it is a per-invocation acceptance typed by the
  owner at launch, dying with the process; a restart without the flag restores
  cards. It is never a machine setting.
- **Semantics against the ceiling:** in the implemented decision function the
  ceiling is a cap, and a ceiling of `ask` produces a card **even in Allow
  mode**. Under skip there are no cards, so a ceiling-asked action is
  **hard-refused** — skip never widens the ceiling, and it says so at the cost
  of usefulness: **on a default enrollment (`bash=ask` is the default ceiling)
  skip means "reads, edits and web only; bash is refused"**. An owner who wants
  unattended bash enables it at enroll time, eyes open. The refusal is logged.
- **What skip never allows, enforced as Reject in the decision function** (a
  static check galopin can do itself, not a card): galopin's own config and
  state paths — above all its `policy.json`, so an agent cannot lift its own
  ceiling with no witness — the cache root (excluded from the safe
  directories precisely because a write there runs code past the bash
  ceiling), `~/.ssh` and the other credential paths, and gateway and kit
  configuration on the machine. Skip's Reject list is never narrower than
  auto mode's static escalate list (§2): the run with nobody watching must not
  reach what the reviewed run would have to ask a human for.
- **The runaway-loop brake stays.** A `doom_loop` ask under skip is refused,
  and the session is left to stop, not waved on: an unattended run is exactly
  where a loop burns hours and spend.
- **What skip dissolves, named:** two asks deliberately survive Allow today and
  skip auto-allows them — a sensitive `.env` read inside the workspace, and an
  outside-workspace ask that is not on the Reject list. That is part of what
  the owner accepts at launch, and this ADR records it rather than inheriting
  it silently.
- **Audited on the machine:** every decision skip makes (allow, Reject,
  ceiling refusal, loop refusal) is written to galopin's local audit with
  `by: skip`, the same trail an answered card writes. Skip has no per-ask
  witness, so it keeps a per-ask record.
- **Visible:** the status frame carries the posture, and the agent view shows
  "permissions skipped" for the **machine**, for the process lifetime. Run
  starts are logged.

### 2. Auto mode with a review model

**The review model** is an ordinary chat-capable model in the Pystino catalogue,
carrying a flag (a `review` marking on a chat-kind row — **not a new kind**: a
new kind needs its own metered router, which this ADR refuses to require). The
wire field is named `reviewModel` throughout. It is a different thing from
ADR 0100's "decision models" (typed questions, calibrated probabilities,
parked).

**Enablement chain:**

1. Pystino: the catalogue flag on a chat-kind model. (Pystino changes nothing
   else.)
2. galopin's **hello** — the first frame, machine → Cerea — advertises what
   galopin *is*: the build capability ("this galopin understands `auto`",
   versioning the panel against an old binary that would answer `invalid`) and
   `policy.autoPermission` inside the policy block the hello already carries.
   galopin cannot condition its hello on a Cerea advertisement it has not yet
   received, so it does not try.
3. **Cerea composes** that with catalogue availability: the Auto mode is
   offered in the agent view and the schedule editor only when the machine
   advertises the capability, the policy allows it, and a review model is
   configured and reachable. A deployment kill switch
   (`CHAT_AUTO_PERMISSIONS`, shaped like `CHAT_SCHEDULES_ENABLED`) turns the
   whole thing off.
4. Per session: "Auto" becomes a value of the existing
   `session.setPermissionMode` op, slotted into the permissiveness lattice
   **between ask and allow** (an Allow session may schedule auto runs — it
   could already schedule allow; an Ask session may not). Default off, per
   session.

**What galopin does in auto mode:** the decision function gains an auto branch
that behaves exactly as Ask behaves today — reads and safe-directory asks
answered once locally, everything else becomes a card that travels to Cerea.
(Cerea-side "trivially safe" pre-allowing is therefore dropped: those asks never
leave the machine.) Asks from ACP backends flow through the same function and
the reply maps to allow-once, as today.

**Asks the ceiling forces stay human.** A ceiling of `ask` means "a human
decides" — on a default enrollment that is every bash command. galopin marks
such a card as ceiling-forced (a field on the ask frame), and Cerea never
sends it to the review model: it escalates like the static list. Otherwise
auto would be more permissive than skip, which hard-refuses the same ask, and
the model would be widening the ceiling the owner set. The review model only
answers asks the ceiling allows but the session's selector put to a card.

**The review loop — where the owner sits today:**

1. An ask reaches Cerea. Cerea checks: the session is in Auto mode, the machine
   is auto-capable, the ask is not ceiling-forced, and the ask passes the
   **static pre-filter**. Push
   notification is **interposed**: for an auto session, the "needs you"
   notification does not fire before the decision — the decision service runs
   first, and the push fires only on escalation (a suppressed push plus a
   crashed decision service would be a silent ask, so a watchdog pushes anyway
   if the decision does not land in time). Asks deduplicate by request id, the
   same key the notification path already uses.
2. **The static pre-filter is code, and it is structural — it does not parse
   shell.** It sees the tool key and metadata; "escalate" on: anything outside
   the workspace (an `external_directory` ask reaching Cerea is
   outside-safeDirs by construction — galopin already answered the rest);
   galopin's own config/state paths; `~/.ssh` and other credential paths;
   gateway and kit configuration on the machine; `.env` files. A conservative
   bash heuristic escalates anything it cannot fully parse. **Residual, stated:
   an obfuscated `git push --force` reaches the review model — that is the
   designed guard**, and it is why the model exists at all.
3. **The model's inputs, named** (the ask frame carries no task text): the
   ask's own fields — tool, title, the command text (for bash the pattern is
   the command), metadata — plus the session title (model-generated, injectable
   via a fetched page) and the workspace path. **Every machine-originated field
   is fenced as untrusted data.** The model decides on the ask alone, with zero
   task context — a deliberate smaller surface; transcript context can come
   later, fenced, if escalation volume demands it.
4. Reply schema: `{ decision: "allow" | "escalate", reason }`, structured
   output. **There is no "deny"**: a wrong deny blocks the owner's own intent
   and is annoying to discover; a wrong allow is caught by the same audit;
   escalate preserves the deny function at the human. Malformed output, a
   timeout (configurable; default generous enough for a mid-tier model — a
   reasoning-class review model blows 10 s routinely) or a provider error ⇒
   **escalate: fail closed to the human, never fail open to allow**. When
   failing closed persists (provider outage), the machine's posture shows "auto
   degraded", and escalations past the cap are paced, not streamed.
5. `allow` answers the pending ask through the exact existing response path.
   The reply gains an **actor field** (`review-model:<id>` with the reason) so
   galopin's local audit — the trail Cerea cannot rewrite — records `by: auto`
   instead of `by: user`, and so the audit records **applied** decisions (an
   allow that lands as already-resolved after a restart never happened, and the
   audit must say so). `escalate` surfaces to the owner exactly as today
   (panel + push, carrying the model's reason for why it would not settle it).
   The card reads "Auto-allowed by ⟨model⟩ — ⟨reason⟩", rendered where
   permission replies render today; an auto-decision is never silent.
6. **Audit:** one line per decision into Cerea's code audit collection (ADR
   0090): time, session, tool, decision, reason (capped, display text — for
   bash it can quote command text), model, ask hash, applied-or-not. It is
   best-effort and 90-day TTL, like the store's existing discipline. **It has
   no reader today**; shipping a minimal reader (or cutting the "reviewable"
   claim to the raw collection) is part of the plan, not an assumption.
7. **Metering:** the review call is made by Cerea on the machine-link event
   path — no browser, no user token — so it authenticates with the deployment's
   own credential: **the deployment pays**. (A satellite deployment has no
   stored key at all, so auto mode is off there by construction.) Enabling
   auto mode requires the deployment to be able to make the call; pinning a
   different billing group is a later mechanism.
8. **Rate limit:** counted by Cerea, the answerer — a rolling hour, in-process
   (lost on restart; acceptable and said), with a bound on parallel review
   calls, `maxPerHour` per machine from galopin's policy echoed down the link.
   Beyond the cap, escalations are paced. This bounds a runaway agent loop from
   rubber-stamping asks, burning spend, or training the owner to dismiss pushes.

**What stays human, always:** the chat's approval gate (ADR 0075), every ask
the ceiling forces, the static escalate list, every escalation, and every ask when no review model is
configured — auto mode then degrades to today's behaviour, never to skip.
**Also still stalls, named:** `question.asked` — an unattended run that asks a
question (the known `plan_exit` case) waits for a human; auto mode does not
cover it, and this ADR does not pretend it does.

## Consequences

- Unattended batches stop stalling on *permission* asks that the filter can
  settle; the confident case (skip) stops stalling on all of them within the
  ceiling. **The 23:00 case itself is not fixed by auto mode** — an
  `external_directory` ask is outside-workspace by construction and always
  escalates. The fix for that pattern is registering a safe directory at
  configure time (`permission.safeDirs`, which exists today); it is step 0 of
  the plan, not a side note.
- **Machine data leaves the machine.** The review model receives command
  text, file paths, the session title and the workspace path, so the
  provider behind the deployment's review model sees them. The admin who
  flags a review model chooses a provider trusted with code metadata; the
  admin docs say so where the flag is set.
- The review model's mistakes are bounded by construction: it cannot widen the
  policy ceiling, cannot touch the escalate list, cannot deny, and cannot
  outlive its rate limit. Its residual risk is "allowed something it should
  have escalated", visible in the audit. It never sees an ask the ceiling
  forces, so it can never be the reason a ceiling-asked command ran.
- **Availability coupling, owned:** auto mode depends on the review model's
  provider. An outage converts auto into cards — an overnight batch can stall
  again, exactly as today. The posture flag makes that visible instead of
  silent.
- Two failure modes to watch: a review model that escalates everything (the
  escalation rate is the first signal; the audit is the second, once its reader
  ships), and prompt injection through machine-originated fields (mitigated by
  fencing and the escalate list, not eliminated — said plainly here).
- The owner's mental model must see the asymmetry at a glance: **skip is
  machine-wide, recorded only on the machine, no path back; auto is
  session-scoped, audited per ask in Cerea, escalates.** The status and card wording carry that.

## Alternatives considered

- **A deny-capable review model** (`allow`/`deny`/`escalate`): rejected — a
  wrong deny blocks the owner's own intent; escalate preserves the deny
  function at the human, and ADR 0075's philosophy (the person holds the
  approve/deny monopoly; automation defers) is preserved rather than inverted.
  Revisit if escalation volume proves noisy.
- **galopin answers the ask itself** (calls the gateway with its own
  credential): rejected on the real grounds — the review model is a catalogue
  choice that would then need a galopin redeploy on every machine to change,
  and Cerea already owns the push, the cards and the audit of record — not
  because galopin "does not answer asks" (its decision function answers most
  of them today).
- **An agent inside opencode answers** (a sub-agent approves): rejected — the
  approver must not live in the same process (or the same context) as the
  actor it approves; independence is the point.
- **Ask the owner's calendar/presence instead of a model** (auto-allow while
  "away"): rejected — time of day is not risk; the ask content is.

## Owner decisions (2026-10-29)

- Direction approved: both postures, the review model as allow-or-escalate
  (not deny-capable), the static pre-filter, fail-closed-to-human, per-session
  opt-in.
- Advisor review (glm-5.3) applied 2026-10-29: the ceiling-ask refusal and the
  bash consequence, the Reject list under skip, the process-wide scope, the
  hello-first enablement chain, the structural pre-filter, the named model
  inputs, the push interposition with watchdog and dedup, the code-audit
  destination with the actor field, deployment-billed metering, the lattice
  position, and the `question.asked` caveat are all part of this proposal.
- Second review (2026-10-29) applied: asks the ceiling forces never reach the
  review model (auto must not be more permissive than skip); skip's Reject
  list is at least auto's escalate list (credentials and kit config added);
  skip keeps the runaway-loop brake; skip writes `by: skip` lines to galopin's
  local audit; the data-egress consequence; safe-directory registration as
  plan step 0.

## Owner decisions (2026-11-04) — supersede the parts of §2 they name

- **Accepted, both postures:** the skip flag (§1) and auto mode (§2) are built.
- **The reviewer is a decision model only (ADR 0100), not a chat model.** Wherever §2 says "review
  model", read: a `decision`-kind model in the Pystino catalogue carrying the `review` flag, called
  through Pystino's `POST /v1/decisions`. There is no chat-model reviewer and no fallback to one: with no
  decision model flagged and reachable, Auto is not offered (and a session already in Auto degrades to
  Ask, never to skip).
- **The question and the threshold.** The ask (fenced, untrusted fields: tool, title, command text,
  metadata, session title, workspace path) is the `input`; one `predicate` question asks whether
  allowing it is routine and safe for a coding agent in that workspace. `allow` only when the answer's
  probability is at or above a threshold (deployment setting, conservative default, e.g. 0.9) **and**
  its confidence is high; anything else — below threshold, a `refusal`, an error, a timeout — is
  `escalate`, with the probability as the reason shown to the user. Still no deny.
- The wire field stays `reviewModel`. Billing, rate limit, audit, card wording, push interposition and
  every "always human" rule of §2 are unchanged.
- **Verified live 2026-11-04** (report an internal decision-reviewer trial report (not published)): a predicate answer has `probability` but no `confidence`, so the rule is probability ≥ threshold only. Default threshold **0.90** (trials: routine 0.906–0.965, dangerous ≤ 0.122; 0.80 would pass `docker compose down -v`). CI workflow paths (`.github/workflows/` and similar) join the static escalate list.
- **The admin chooses the reviewer, on a dedicated screen (owner, 2026-11-04).** Pystino only provides `decision`-kind models (no `review` flag in its catalogue). Cerea's admin area gets an **Agent auto-approval** screen: the on/off switch (alongside the `CHAT_AUTO_PERMISSIONS` deployment kill switch), the decision model (chosen among the gateway's `kind: decision` models), the threshold, the default per-machine hourly cap, and the **review log** (each decision: time, machine, session, tool, command/path, probability, outcome, applied or not) — this is the audit reader of Plan step 4. Owner's first choice of model: `clef-flash`.
- **ADR 0100 is unparked** to provide the `decision` kind and route; its live verification with a
  scoped Cortecs key (owner provides) comes before the Pystino plugin is finalised.

## Open questions (as asked)

1. Which catalogue model carries the review flag (the wire name is settled:
   `reviewModel`).
2. Whether "permissions skipped" should also stamp the session title, or only
   the status frame and a badge (the posture is machine-wide either way).
3. The escalation-notification wording (it should say what the model was
   unsure about, using its reason).
4. The final contents of the static escalate list — the structural set above
   is the starting set; house rules welcome before acceptance.

## Plan (after acceptance)

0. Before any code: register the safe directories the release and worker
   runs need (`permission.safeDirs`), which removes the 23:00 stall pattern
   on its own.
1. PROTOCOL.md **and its fixtures in one commit** (both sides' completeness
   checks fail otherwise — a MAINTAINING-grade trap): the `auto` value in the
   lattice and enums, the reply-actor field, the ceiling-forced field on the
   ask, `capabilities.autoPermission`, the posture flag, `maxPerHour` down the
   link.
2. galopin: the flag (refused when policy says so), the policy keys, the auto
   branch in the decision function, skip's Reject list (at least auto's
   escalate list) and loop refusal, the ceiling-forced marking, `by: skip`
   audit lines, the hello fields.
3. Cerea: the review service behind `CHAT_AUTO_PERMISSIONS` (interposition
   before `observeMachineEvent`, watchdog, request-id dedup, the code-audit
   line with actor and applied-or-not), the mode in the agent view and the
   schedule editor, the card wording, the posture display.
4. A minimal audit reader (or the "reviewable" claim is cut to the raw
   collection).
5. The live check: a scripted agent fires a harmless ask (expect auto-allow
   with reason), an escalate-list ask (expect a human card with the model's
   reason), a bash command on a default enrollment (expect a human card that
   never reached the model), and an ask with the review model's provider unreachable (expect
   escalation and the "auto degraded" posture).
6. Ship with everything default-off; the owner flips per machine.

## Future

If ADR 0100 (decision models through the gateway) is picked up, the permission
ask is exactly its shape — a typed question over a piece of text with
calibrated confidence — and the same ask could be routed to it (an `allow?`
choice with a confidence threshold, escalating below it). The review model
above is deliberately specified as an ordinary chat model so this ADR does not
wait on 0100.
