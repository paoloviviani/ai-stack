# 0099 — Delegates: spawned sessions report back

- Date: 2026-10-15
- Status: **Accepted** 2026-10-16 (implemented in Cerea main 7af488c4, wired through ADR 0097's decision function in 7a9fb333)
- Related: 0097 (answer-not-write permissions: its decision function consumes the delegate predicate below), 0089 (the machine agent), 0075 (what a coding agent may do), PROTOCOL.md §6 "Agent tools" and §7.

## Context

galopin gives a model two ways to hand work to another agent, and they do not
behave alike:

- `task` (opencode subagents) runs inside the session and **returns its result
  to the caller** when it ends.
- `session_spawn` creates a new top-level session the person can open and talk
  to. It does **not** report back: the call returns an id and nothing else.

Four problems follow, all analysed on 2026-10-14.

1. **The model must choose between tools that differ in the one thing it
   cares about.** The skill papers over the gap by telling the model to ask the
   child to `session_send` it back
   (`agent/internal/backend/opencode/skill.go:47`, "you get its id back, not its
   result … tell it to reply with one short message"). Whether that works
   depends on the child obeying, and on problem 2.
2. **The way back is gated.** A child's `session_send` to its spawner raises a
   card: `auto` needs an Allow grant, the same workspace, and a hop within the
   limit (`agent/agenttools.go:741`), and nothing looks at `spawnedBy`. The
   spawner's `session_read` of the session it spawned asks too: the read's
   `auto` is `grant == Allow && same workspace`
   (`agent/agenttools_read.go:127`), so a spawned session is treated like any
   unrelated one. The marker is written (`agenttools.go:528`) and then ignored.
   The rule exists for a good reason (PROTOCOL.md §6: a transcript can hold
   secrets) but it makes the person approve the reading of work the model
   itself started a minute ago.
3. **A child waiting on a permission card is silent.** The spawner is not told.
   It cannot distinguish "still working" from "blocked on the person", and a
   child that raised a card in a background tab can sit there indefinitely.
4. **The skill teaches caution and not the situation.** Its trigger describes
   mechanics ("when you might start or message another coding session
   (task, session_spawn, …)") and not the moments a model should delegate
   (hand-off, second opinion, parallel work, being stuck); it is ~100 lines,
   most of them limits; and it ends with "If the person asked for none of this,
   do the work yourself" (`skill.go:87`), which a model reads as a reason never
   to delegate.

**Precedent: Paseo.** `create_agent` returns immediately and, with
`notifyOnFinish` (on by default), the daemon injects the child's final message
into the caller when the child finishes; callers are told to trust that report
and not poll. The model needs one idea ("start it, it will tell me") rather
than a protocol it must instruct the child to follow. Paseo has no policy
layer; ours does, so the report path must also be a permitted path.

## Decision

### A. Delegates

A session created by `session_spawn` is a **delegate of its spawner**. The link
is direct and not transitive: grandchildren are delegates of their own spawner
only. Between a spawner and its own delegate, with **no card**:

- the spawner `session_read`s the delegate's full transcript (the read tool's
  existing shape: text messages, caps and rate limit unchanged);
- the spawner `session_send`s to the delegate;
- the delegate `session_send`s to its spawner.

Everything else is exactly as today: other workspaces, the hop limit, the
per-pair rate limits, unrelated sessions, a task subagent's refusal to send up
its tree. The spawner's machine **ceiling still wins**: a deny or ask on the
coordination tool (`session_read`, `session_send`) from the machine's rules
beats the delegate relationship. A delegate may read nothing of its spawner
(only send); a spawner may not read a session that merely sent to it.

The ceiling here is the machine's: an explicit deny or ask from the machine's rules (the policy and the enroll-time ceiling) beats the delegate relationship. The session's own word does not. Reports are still delivered to a spawner in Plan (or Deny, which ADR 0097 folds into Plan): the turn they start cannot change anything.

The relationship is a predicate, `IsDelegatePair(caller, target) (delegate
bool, direction)`, computed from the persisted `spawnedBy` markers
(`SpawnMarks`), so it survives restarts and needs no new state. ADR 0097's
decision function calls it for its rule "delegate rule → once" and does not
re-derive it. Until 0097 lands, the same predicate feeds the existing `auto`
computation in `agenttools_read.go` and `agenttools.go`, so the behaviour ships
independently of the permission redesign.

### B. Report-back, on by default

galopin, not the model, delivers the delegate's outcome to the spawner:

1. **Report.** When a delegate's turn ends, galopin sends its **final assistant
   message** to the spawner as a user-role message carrying the usual
   `SentBy` sender and a preface naming it: `Report from <title> (session
   <id>)`, plus the line that this is an agent's report and not the person.
   It uses the existing send path minus the gating (it is the same relationship
   as A) and does **not** count as a hop (the report is the delegate's
   conclusion, not a request; hop counts requests). The text is capped at 8 KiB
   like a send; a longer final message is cut with a pointer to
   `session_read`.
2. **Error notice.** Once per turn that ends in an error: `Delegate <title>
   (session <id>) failed: <message>`.
3. **Approval notice.** Once per permission card the delegate raises while it
   is a delegate: `<title> is waiting for approval: <tool>`. It carries no
   card content beyond the tool name (the person answers in the panel; patterns
   and arguments may hold secrets). The notice is not repeated when the card is
   answered; the later report says how the turn ended.
4. **Opt out.** `session_spawn` takes an optional `report: false` (fire and
   forget). It is recorded with the spawn marker and disables 1 to 3 for that
   delegate.

**Origin of a turn.** Only turns the **spawner started** are reported: the
spawn's initial prompt, and a turn started by the spawner's `session_send`.
A turn the person starts by typing in the delegate produces no report, no error
notice and no approval notice: the person's later conversation does not leak
to the spawner and the spawner gets no surprise turn. galopin tags the origin
when it sends the prompt (it sends both the initial prompt and every
`session_send`), recording "reportable turn pending" on the delegate, and does
not infer it from the transcript. A message from the person arriving while a
reportable turn is running folds into it, as any send does; the turn is then
reported (the tag is per turn, set at the first send, cleared on idle).

A turn that galopin itself starts by delivering a report or notice to a session that is itself a delegate with reporting on counts as part of its spawner's work and is reported too (A spawns B, B spawns C: B's first turn ends after spawning C and A gets that interim report; C's report then starts a turn in B whose final message is the real result, and A gets it). Accepted edge case: if the spawner's `session_send` arrives while the delegate is busy on a turn the person started, that turn's end is reported, because the send tags the delegate before the turn boundary.

**When "finished" is detected.** On the normalized event stream galopin already
consumes, not an opencode-specific signal: a delegate's `status: idle`
(§7), taken as the end of a turn only if it was `busy` since its last report.
That covers opencode's `session.status idle` and `session.idle`, and any ACP
backend that emits the same normalized event. The final assistant message is the
last assistant message of the transcript (text parts, not tool output or
reasoning). A turn aborted by the person's Stop produces **no** report: Stop is
not a result (§7); the spawner gets nothing and may `session_read`. An idle
that follows an error event produces the error notice, not a report. The error
and permission notices come from the same stream (`error`, `permission.asked`).
A delegate idle with no assistant text (an empty turn) reports "finished with
no message".

**Delivery to a busy spawner.** A report is not injected into a turn in
progress: an agent halfway through editing should not have a foreign message
folded into its context. galopin queues it and delivers when the spawner goes
idle, in order, and as **one** message if several are waiting (each report
labelled). Notices queue the same way. An idle spawner receives it at once and
starts a turn: that turn is the spawner's answer to the report.

**Restart.** A queued item is persisted before it is acknowledged, in a small
galopin-owned file beside the other agent state, written atomically, keyed by
the spawner; delivery removes it. A report whose delegate finished while
galopin was down is recovered at start: for each delegate whose last turn
ended after its recorded last report (galopin records the id of the last
message it reported per delegate), galopin delivers the missing report. Both
mean a restart never drops a report; notices are best effort across a restart
(an error or card that appeared during downtime is visible in the panel and
in the delegate's transcript, and the report on its eventual finish carries the
outcome).

**Spawner gone.** If the spawner is archived or deleted when delivery is due,
the item is dropped with one log line (`report dropped: spawner <id> archived`).
It is not forwarded to anyone else: the delegate remains a normal session and
the person can read it.

**Loop guard.** The existing limits are the guard and are unchanged: spawn depth
2, three live spawned sessions per root, six spawns per ten minutes, the
per-pair send rate and hop limit on `session_send`. A report is a turn
trigger, so a ping-pong (spawner reacts to a report by messaging the delegate,
the delegate reports again) is possible; it is bounded by the send rate limit
on the spawner's side and by each delegate reporting at most once per turn.
The delegate's own reply to the spawner after a report is a `session_send`
(hop counted, rate limited) as before. A test pins that a scripted ping-pong
stops at those limits.

### C. The skill

Rewritten situation-first and about half the length: a decision table (a
quick helper inside this session → `task`; a handoff you want to see and talk to
as its own session → `session_spawn`, which reports back automatically), a
briefing template (Task / Context / Files / Tried / Decisions / Acceptance /
Constraints), "trust the report, do not poll", the safety rules in one short
block at the end, and the closing "do the work yourself" line removed. The
trigger describes situations: hand off, second opinion, parallelise, when
stuck, long-running work. It keeps the one-time resume line for a `task`
subagent whose tools were refused (legacy sessions still need it) and the
background-task and schedule sections in tightened form. The tool descriptions
become short: they say what the tool does and that `session_spawn` reports
back; the procedure lives in the skill.

### D. Evaluation

A small harness under `agent/eval/delegation/`: about ten prompts (some that
should delegate, some that should not), run on two or three models, scoring
whether the model's choice was right and whether the round trip completed
(spawned session ran, report arrived, the model used it). It runs against an
isolated opencode and galopin like the integration tests, on a key that is not
the owner's live machine key. A baseline on `origin/main` precedes the
after-run on the branch, capped at about 200 model calls.

### Protocol changes

PROTOCOL.md §6 "Agent tools": the delegate relationship; the no-card rows for
spawner-read, spawner-send and delegate-send; the `report` argument; the report
and the two notices as attributed user messages and when they are delivered; the
queueing and restart behaviour. §6 "Permissions" gains a pointer only (the
other ADR owns it). §7 gains no event kind: reports are ordinary user-role
`message` events with the existing `sentBy`. docs/code-panel.md's coordination
section describes what the person sees.

### What the person sees

In the spawner's transcript, a user-role message marked as sent by an agent
session (the existing `sentBy` rendering): "Report from <title> (session <id>)"
followed by the delegate's final message, and a one-line notice for a failure
or a card waiting. In the Needs-you inbox the delegate's card is unchanged; the
person sees it both there and as the notice in the spawner. The person is the
only one who answers a card: a notice gives the spawner no way to approve.
The Cerea panel is believed to render these as it renders any `sentBy`
message; to be verified, and changed only if it does not.

### Interaction with 0097

0097 moves approval into one galopin decision function and writes no rules into
the agent. The delegate predicate is an input to that function (rule "delegate
rule → once" for the coordination tools): 0097 owns when a card is raised,
this ADR owns who is a delegate and what reaches whom. The ceiling and the
cross-workspace rule are 0097's and keep winning. If 0097 lands first, the
decision function calls `IsDelegatePair`; if this lands first, the inline
`auto` computation does, and 0097 replaces that call site. Report delivery
does not go through approval at all: it is galopin's own message, like the
background task's result injection.

## Consequences

- One mental model: `session_spawn` starts it and it tells you. The model stops
  having to instruct the child to call back, and the person stops approving the
  reading of work the model started.
- A spawner can read a delegate's whole transcript without asking, including
  anything the delegate's own tools saw. What a spawned session actually starts
  with (`agenttools.go` spawn): the spawner's agent mode (or a stricter one it
  asks for; a looser one raises a card), the spawner's model, the spawner's
  permission word only when it is Allow (a Deny or Ask spawner gets a child on
  the default, Ask), and a copy of the spawner's coordination grant and
  exceptions, all under the machine ceiling. So a delegate is not always bounded
  by the spawner's word; the spawner could have read what a delegate's tools
  saw only if it could have run those tools itself. We accept this: the
  delegate is the spawner's own work product in the same workspace, and the
  read is limited to text messages. Reads stay confined to turns the spawner
  started (see "Origin of a turn" below only for reports; reads are not
  filtered, which is the stated trade-off).
- A report is one more turn for the spawner and so one more model call.
  `report: false` is the escape; the spawn limits bound the total.
- A queue file is new state to maintain. It is small, owned by galopin, and
  recoverable (it can be deleted: the next idle of a delegate whose message
  was not reported re-derives the report).

## Rejected

- **Making `task` and `session_spawn` one tool.** A subagent is part of the
  session's tree and conversation and gives no separate panel entry; a spawned
  session is one the person can open and steer. Both stay, with the skill
  choosing.
- **Reports through a model-visible tool the child must call.** It is the
  protocol the skill taught, and it is exactly what fails (obedience plus the
  gate).
- **Polling the delegate.** Wastes turns and the rate budget; the report
  replaces it.
- **Injecting a report into a busy spawner's running turn.** Disturbs a turn
  in the middle of tool work; waiting for idle costs seconds.
- **Letting the delegate read the spawner.** Not needed for reporting, and the
  spawner's transcript holds the person's whole conversation.
- **Delegate profiles (model, mode, notes), invokable recipes (handoff,
  advisor, committee) and per-session MCP endpoints** are out of scope; the
  last is layer 3 of the coordination architecture.
