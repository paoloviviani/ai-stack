# 0097 — galopin answers permission requests and writes no rules

- Date: 2026-10-15
- Status: **Accepted** 2026-10-16 (implemented in Cerea main 7a9fb333; proposed 2026-10-15, design approved by the owner in conversation the same day).
- Related: 0089 (the machine agent and its enrollment), 0075 (the coding-agent permission framework this replaces in part), 0096 (capabilities). Layer 2 of the three-layer plan of 2026-10-13: containment (OS sandbox) and coordination over MCP are separate, later decisions.

## Context

galopin keeps a per-session permission selector (Deny · Ask · Allow), per-session "always allow" exceptions, and a machine ceiling. Today it enforces them by **writing rules into opencode's own session store**: a composed block of about 100 rules (machine rules, the mode block, restated agent rules, exceptions, safe directories, the ceiling's tail) is PATCHed into the session on every mode change, agent switch and "always allow". That design has three costs, all measured.

1. **The store is append-only and only grows.** opencode 1.18.34's `PATCH /session/:id` sets `Permission.merge(current.permission ?? [], payload)` and `merge` is `rulesets.flat()` (`packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts:197`, `src/permission/index.ts:200-202`). No endpoint replaces it. The brief for the opencode 2 migration records one real session on the owner's machine at **2,141 rules / 175 KB** (26 blocks, of which only the last decides anything); that machine is not this box. The same query on this box's `opencode.db` (read-only, `SELECT … json_array_length(permission) FROM session`) finds 4 sessions with rules, 1,145 rules in all: a root at **399 rules / 34.6 KB** (6 blocks), a second root at 196, and two `@general` children at **275 rules / 30 KB each** (29 denies each).
2. **Deny seeding poisons task children.** `deriveSubagentSessionPermission` copies every `deny` rule and every `external_directory` rule of the parent's stored list into a new child (`src/agent/subagent-permissions.ts:14-27`, called at `src/tool/task.ts:139`). An old Deny block's `* * deny` therefore refuses or hides every tool of every future child, even after later blocks overrode it for the parent. That is the "An earlier Deny is stuck" banner, and `permrules/stale.go`, the tool-visibility sentinel and the skill's "resume once" line exist only to live with it.
3. **It is opencode-shaped.** The composer, the restatement logic (last-match-wins makes an appended ceiling soften a `deny` unless every key is restated and lowered) and the per-child application race (`applyChildLocked`, the child's first call beating the PATCH) are all opencode's rule algebra. A second backend (ACP, later Claude's `canUseTool`, Codex approvals) cannot reuse any of it. opencode 2.x replaces rules on update and copies none from the parent (`BRIEF-opencode-2-migration.md`: `core/src/session/session.ts:82`, `projector.ts:593`, `tool/plugin/subagent.ts:184-198`), so the composer would need a second rewrite there.

**Precedents.** Paseo answers every ask itself with `once` and keeps the owner's choices in its own store; Codex's approval policy and sandbox are the agent's, and its approvals are answers; opencode itself treats a `once` reply as stateless (`src/permission/index.ts:143`). Answering is the model all three share: a card, or an automatic answer, per request, with the policy outside the agent.

## Decision

1. **The control surface stays small.**
   - The **machine ceiling** is exactly today's: enroll-time `policy.json` / `galopin policy set`, which needs a local login. It is the only security ceiling. There is **no per-workspace policy**. The embedded terminal stays a machine-side setting; the docs say that enabling it lets a Cerea session change the ceiling (a shell on the machine can edit `policy.json` and the config galopin starts opencode with).
   - **One selector per root session: Plan · Ask · Allow.** Deny is folded into Plan. Plan = opencode's `plan` agent (its prompt, and its own config denying edits) **and** galopin rejecting every effectful request. Ask = the `build` agent + cards. Allow = the `build` agent + automatic `once` answers up to the ceiling. Existing sessions stored as Deny read as Plan.
   - **"Allow always" exceptions** per root session keep today's `{permission, patterns}` shape, never exceed the ceiling, and live **only in galopin** (the overlay).
2. **Every tool call reaches galopin.** A constant "everything asks" floor sits in the config galopin owns (`OPENCODE_CONFIG_CONTENT`, built at each start of the process, as today), written once per start and never per session. Verified below.
3. **One decision function**, agent-agnostic, returns `reject | once | card`. galopin **never replies `always`** to an agent. Rules and order below.
4. **Nothing per session is written to opencode**: no `PATCH` of session rules, no restated agent rules, no tool-visibility sentinel (not needed for new sessions, shown below).
5. **Existing sessions** get one final neutralising rule on first contact after the upgrade, recorded in the overlay, and never again.
6. **Fail safe.** If galopin is down when opencode asks, the ask stays pending (opencode holds a `Deferred` until a reply, `src/permission/index.ts:98-106`; there is no timeout). On start galopin answers what is still pending from `GET /permission` (`permission.list`, `index.ts:169-172`; route `server/routes/instance/httpapi/groups/permission.ts`). A pending ask dies only with the opencode process (`index.ts:54-61`), as it does today.
7. **Cost is acceptable: reads ask too** (measured below).
8. **Honesty about what the ceiling is.** Until the OS sandbox exists, the ceiling is galopin rejecting or carding asks, which is as advisory against `bash` as today's rules: a shell can do anything the ask for it does not name. A ceiling that denies or asks for `bash` is meaningful against a hijacked Cerea session; `webfetch=deny` with `bash=allow` is not (a command can fetch). `galopin enroll` and `galopin policy set` warn on that combination; `docs/code-panel.md` and `docs/agent-machines.md` say so.
9. **Adapters** share the function: opencode `permission.asked`, the ACP backend's `session/request_permission`, later Claude `canUseTool` and Codex approvals. Each adapter must guarantee "every effectful call asks" for its agent (ACP: by construction, every `request_permission` arrives; an agent that auto-approves natively is outside what galopin can promise, and the adapter says so in `Capabilities`).
10. **Protocol and Cerea: no wire change.** `session.setPermissionMode` keeps `"deny" | "ask" | "allow"`; `"deny"` is the wire spelling of Plan, and `"plan"` is accepted as an alias on input. Cerea's selector is relabelled **Plan · Ask · Allow** and the agent picker hides `build` and `plan` when the selector drives them while still listing custom agents (same branch, Cerea panel). Scheduled runs that use Deny keep their wire value; see open question 2 for the plan-agent switch.

## What opencode 1.18.34 does (verification)

Source: `sst/opencode` at tag `v1.18.34` (`aec0b9a`), `packages/opencode/src`. Where a claim could be checked on the running binary it was: an isolated `opencode serve` with `OPENCODE_CONFIG_CONTENT={"permission":{"*":"ask"},"agent":{"zed":{"permission":{"bash":"allow"}}}}` and `GET /agent`, then last-match evaluation per key.

**How the layers merge.** A tool ask is judged against `Permission.merge(agent.permission, session.permission)` (`session/tools.ts:87`; `session/prompt.ts:346`), `evaluate` takes the **last** match and no match means ask (`permission/index.ts:28-38`). An agent's own list is `defaults`, the agent's specifics, then **`user` = the global `permission` config, last** for every built-in (`agent/agent.ts:119-138`; build 145-152, plan 160-178, general 185-191, explore 198-212, compaction/title/summary 225/241/256) and `merge(defaults, user)` for a custom agent (`:277`). A per-agent config block is appended after that (`:293`). Config sources merge in this order: global dir, `OPENCODE_CONFIG`, project (skipped under `OPENCODE_DISABLE_PROJECT_CONFIG`, which galopin sets unless the machine opts in), `OPENCODE_CONFIG_DIR` agents, then **`OPENCODE_CONFIG_CONTENT` last** (`config/config.ts:272-274, 415, 420, 473-475, 482-490`). A string `permission` is the `{"*": action}` rule (`core/src/v1/config/permission.ts`, `normalizeInput`). `mergeDeep` keeps an existing key's position (`config.ts:42-44`); this matters below.

**Consequences, observed on the live binary** (probe above):

| Agent | `read/edit/bash/webfetch/task/skill/MCP key/external_directory` with a global `*: ask` |
| --- | --- |
| build, general | all `ask` (the floor holds from the first call: it lives in the agent, not the session) |
| **plan** | `edit` becomes **ask** (plan's `edit: deny` is before `user`) |
| **explore** | everything **ask** (its `"*": deny` is before `user`) |
| **compaction, title, summary** | everything **ask** (their `"*": deny` is before `user`) |
| a custom agent with its own `bash: allow` | `bash` stays **allow**; the rest ask |

So a blanket floor alone is not enough: it **un-denies** the read-only and hidden agents (and un-hides their tools, `permission/index.ts:204-214`). The floor therefore has two parts, both static and written once per start: the global `*: ask` and, per built-in agent that has denies, the agent's own denies **restated in `agent.<name>.permission`** (which merges after `user`, `agent.ts:293`): plan's `edit` (`{"*":"deny", ".opencode/plans/*.md":"allow"}`), explore's `"*": deny` with its allowed read keys back at `ask`, and `"*": deny` for compaction, title and summary. That table is `permrules/floor.go` today (it exists for the same trap) and `floor_it_test.go`'s comparison against the live `GET /agent` stays, extended to the new shape, so a release that changes a built-in agent fails a test instead of loosening a machine. The floor never writes a literal `task` or `todowrite` key: `task.ts:143-150` and `subagent-permissions.ts:18-19` add the child's own `task`/`todowrite` denies **unless the agent has a rule literally named so**, and a literal `task: ask` would let `general` start nested subagents.

**Children from the first call.** `task` creates the child session with only the parent's denies and `external_directory` rules plus `todowrite`/`task` denies (`task.ts:139-170`, `subagent-permissions.ts:14-27`), and the child's agent rules, floor included, apply to its first tool call. With no session rules on a new root, the child inherits **nothing** and the sentinel is unnecessary: the only denies in a new child are the two `task.ts` adds on purpose.

**What can still bypass an ask, and how it is closed or why it is acceptable.**

| Path | Source | Verdict |
| --- | --- | --- |
| A custom or global agent that allows a key in its own block (`bash: allow`, shown above) | `agent.ts:293` | **Open for non-built-in agents.** galopin reads every agent's ruleset (`GET /agent`) at start and on the existing one-minute refresh and evaluates it for the full key set; any native `allow` is reported (status warning, audit `floor.breach`, device card). Closing it needs the agent's own keys restated at `ask`, which galopin can generate from that same read: proposed, open question 1. Project config is off by default, so the sources are the owner's own global files and `OPENCODE_CONFIG_DIR`. |
| Position trap: a lower source defining `"*"` earlier and a later key `allow` | `config.ts:42`, remeda `mergeDeep` | Closed for every key galopin names (it overwrites the value in place); open only for a tool key galopin does not know. MCP tool keys are `<server>_<tool>`: covered by `*` unless the owner's own config names that key. Same remedy as above. |
| Tools with no permission key | `tool/registry.ts:116-170` (`fromPlugin` asks nothing unless the plugin calls `ctx.ask`); `{tool,tools}/*.{js,ts}` in config dirs, `registry.ts:185` | galopin's own four tools self-gate (PROTOCOL.md §6 "Agent tools") and go through the same function as category `coordination`. External plugins are off (`opencode serve --pure`, as today). Other custom tools are the owner's code in the owner's config dir; acceptable, and listed by the same scan as a warning. |
| MCP tools and MCP resource reads | `session/tools.ts:408` (`permission: key`), `:180` (`read` with `mcp:<server>:*`) | Reach galopin as category `mcp`, treated as effectful (card on Ask, reject on Plan). Closed. |
| `external_directory` | `tool/external-directory.ts:13-41` asks before the tool's own key | Reaches galopin (category `outside-workspace`). Its `bypass` option and opencode's own `Truncate.GLOB` allow (`agent.ts:306-309`: reading its truncated-output files) are internal and acceptable. |
| `doom_loop` | `session/processor.ts:372-378` judges against `agent.permission` only (no session rules) | Still asks under the floor; category `brake`, a card on Ask and Allow. |
| `task` started by an `@agent` mention in the person's message | `task.ts:119` skips its ask when `bypassAgentCheck` | Person-initiated; Cerea does not send agent parts. Acceptable. |
| `POST /session/:id/shell` and `!`cmd`` inside a command template | `session/prompt.ts:451`, `:1397` | Not tool calls: the first is galopin's own gated `commandShell`, the second is owner-authored command text in a config dir. Acceptable. |
| `question`, `plan_enter`/`plan_exit` | `tool/question.ts`, `plan.ts` use the Question service, not `Permission.ask` | Not permission asks; they are questions to a person and keep working. |
| `bash` can do anything | by nature | The ceiling's honesty clause (Decision 8). Not closable without the OS sandbox. |
| `PATCH /session/:id` by a hijacked session that holds the server password | `session.ts:197` | Today's residual, unchanged: galopin's own answering is not affected by session rules, **because the function ignores them**, but a session that rewrote its own rules to `allow` would stop asking. The floor lives in agents, not sessions, and session rules sit after agents (`tools.ts:87`), so this stays open while `bash` runs; the sandbox closes it. |

**Reply semantics galopin relies on.** `reject` with a message becomes a `CorrectedError` (`index.ts:121-127`), the model sees the text; `reject` also rejects **every other pending ask of that session** (`:129-138`), so a Plan refusal of one of several parallel calls refuses them all, which is acceptable for Plan and for a ceiling `deny`; `once` completes only that ask (`:142-143`); `always` would append to a process-wide approved list (`:145-151`) and is never sent.

## The decision function

One pure function in a new package (`agent/internal/decide`), fed a normalised request `{session, root, isChild, category, key, patterns, workspace}` and the root's state `{mode, exceptions, coordination grant}` plus the machine's ceiling, own rules and safe directories. First match wins:

1. The ceiling **denies** the key → **reject** (audited `by:"galopin"`).
2. The ceiling **asks** for the key → **card**, in every mode; exceptions cannot lift it.
3. Session on **Plan** → a read inside the workspace: `once`; an edit of a plan file the plan agent may write (`.opencode/plans/*.md`): `once`; everything else effectful: **reject**.
4. **Delegate rule**: the spawner and the session it spawned (`spawnedBy`) reading or messaging each other, and the delegate's report back → `once`. Exposed as a predicate hook owned by the delegation work; until it exists it returns false.
5. **Coordination grant** (scheduled runs) → `once`, within today's hard limits (PROTOCOL.md §6 "Coordination grant": another workspace, hop 4+, a task subagent's send, rate limits still apply as non-permission limits).
6. A root-session **exception** matches (every pattern of the request is covered) → `once`.
7. The machine's own `allow` rule for the key → `once` (its `ask` and `deny` fold into steps 2 and 1).
8. Session on **Allow** → `once`.
9. Session on **Ask** → a read inside the workspace: `once`; everything else: **card**.

Safe directories (policy `safeDirs`) are decided at the category level: an `outside-workspace` ask for a path under one is treated as inside the workspace (so it follows the read or edit rule beneath), and the ceiling is evaluated first. A sensitive read (`*.env`, `*.env.*` except `*.env.example`, opencode's own list) is a card on Ask and Allow and a reject on Plan. `brake` (doom_loop) is a card on Ask and Allow and a reject on Plan.

**Children (task subagents) decide by their ROOT's state**: the function receives the root's mode, exceptions and grant, so `ChildAskAction`, `ApplyChildRules`/`applyChildLocked` and the "child's first call beats the PATCH" race disappear. A Plan root refuses a child at its first effectful call; a root switched Plan → Ask/Allow lets a child spawned afterwards edit on its first turn (the first call asks, galopin answers by the root's word, nothing waits on a write). Read-only child agents keep their semantics through the agent-level restatement above.

**Categories**, and the opencode keys that map to them (an unknown key is `mcp`, the cautious default):

| Category | opencode permission keys | Note |
| --- | --- | --- |
| read | `read`, `glob`, `grep`, `list`, `lsp`, `skill` | inside the workspace; patterns that are not paths (`mcp:<server>:*`) are `mcp` |
| edit | `edit` (covers `write`, `apply_patch`) | |
| bash | `bash` | |
| web | `webfetch`, `websearch`, `codesearch` | |
| outside-workspace | `external_directory` | paths outside the workspace root and the safe directories |
| spawn | `task` | not effectful in itself: behaves like `internal` (`once` in every mode, the ceiling's deny or ask on `task` still applying at steps 1-2). The child is judged by its root's state from its first call, so a Plan root's child cannot edit, and Plan can use explore-style subagents |
| internal | `todowrite` | no effect outside the session: `once` in every mode the ceiling allows (`spawn` behaves the same) |
| brake | `doom_loop` | |
| mcp | any other key, MCP resource reads | effectful by default |
| coordination | `session_list`, `session_read`, `session_send`, `session_spawn` (galopin's tools, asked through the same function) | machine rules and the ceiling keys apply as today |

## Measurement

`opencode 1.18.34`, isolated instance and mock LLM (the `permRig`), 80 sequential single-`read` turns per arm after 5 warm-ups, native allow versus "everything asks" with an immediate `once` answered through the real machine path (including the audit write). Two runs:

| | native p50 / p95 | ask + once p50 / p95 | ask seen → tool completed p50 / p95 |
| --- | --- | --- | --- |
| run 1 | 427 / 537 ms | 438 / 647 ms | 201 / 302 ms |
| run 2 | 340 / 647 ms | 441 / 651 ms | 201 / 303 ms |

The turn-time difference is noisy (p50 +10 ms and +100 ms, p95 +110 ms and +4 ms) because a turn includes two mock-LLM round trips. The stable figure is the ask-to-completion one: **p50 about 200 ms, p95 about 300 ms** per ask, an upper bound (the harness reads events through a polling log and answers through the full op path; the opencode-to-galopin SSE delivery before the ask is seen is not in it). A 30-read exploration adds roughly 6 s to a turn that spends tens of seconds on model calls. **Decision: reads ask.** The fallback (workspace reads allowed natively by the floor with `read: {"*":"allow","*.env":"ask",…}`, `external_directory` still asking) is a one-line change in the floor and is kept written down but not taken. Phase B re-measures with the real decision function and puts the number in a test.

## What is deleted

| File | Goes | Replaced by |
| --- | --- | --- |
| `permrules/permrules.go` | `Compose`, `ComposeParts`, `blanketBlock`, `Tail` and the cap/restatement logic, `ChildRules`, `ChildCeiling` (as rule composer), `Grant`/`GrantAllowBlanket`, `ToolVisibilitySentinel`, `Fingerprint`, `Blanket`/`Untouched` lists | `internal/decide` (the function and the categories); `Ceiling`, `Selector`, `Exception`, `Match`, `Evaluate` stay (the ceiling, the exceptions and the legacy banner use them) |
| `permrules/floor.go` | `subagentAsk`, `Layers.Floor` per-ceiling restatement, safe-dir allows on agents | a constant floor: `*: ask` plus the built-in agents' restated denies; no ceiling in it, so no policy change restarts the process for it (a tightened ceiling no longer needs a restart for correctness) |
| `permrules/stale.go` | everything except `FindStaleBlanketDeny` / `FindStalePolicyDenies` reading a **legacy** session's stored rules (banner only) | the same two functions, called once per legacy root, no composition input (they compare against "no blanket deny at all") |
| `backend/opencode/permissions.go` | `composeFor`, `patchRules`, `ensureRules*`, `applyChildLocked`, `ApplyChildRules`, `ChildAskAction`, `EffectiveRules`/`RuleLayers` composition, `denyOnly`, `denyNote` replaced by a reject message, `fileRules` | the opencode adapter: normalise `permission.asked`, call the function, `ReplyPermission`; startup pass over `GET /permission`; `RuleLayers` becomes a read-only view of the floor + the function's state |
| `backend/opencode/overlay.go` | `RulesFP` | `Neutralised` (one boolean per legacy session); selector, exceptions and grant stay |
| `backend/backend.go` | `RuleHost` methods that write rules (`EnsureRules`, `ApplyChildRules`, `ChildAskAction`) | a narrower `Decider` hook; `StaleDeny`/`StalePolicy` stay for legacy sessions |
| `main` (`permissions.go`) | `giveChildTheCeiling`, `answerChildAsk`, `rejectDenyAsk` and the sessions pre-filter's Deny special case | one `answerAsk` that runs the function for every ask, root or child, and replies |
| `tools.go`, `skill.go` | nothing now (the skill's "resume once" line stays: legacy sessions still need it) | |

## Migration

- **Machines update galopin; nothing re-enrolls.** `policy.json` is unchanged (ceiling, rules, safe directories, `commandShell`, `agentTools`). The first start of the new binary writes the new constant floor into `OPENCODE_CONFIG_CONTENT` as every start does; the static `opencode.json` that `enroll` wrote (`edit/bash/webfetch: ask`) is harmless under it.
- **Selector, exceptions and grants** are in the overlay already and keep their shape; a stored `deny` reads as Plan; scheduled runs and their coordination grants keep working because the grant is evaluated at step 5.
- **Existing sessions: one neutralising rule.** On first contact (prompt, ask or poll) galopin sends `PATCH {permission: [{"*","*","ask"}]}` once and records it in the overlay. It is last, so it beats every older allow, exception and mode block (the rules that would otherwise let a call through unasked) and it un-hides tools an old `* * deny` hid for that root. **It cannot fix:** the stale denies already stored still seed 1.18 children (`subagent-permissions.ts:21-23` copies every stored `deny` and every `external_directory` rule, allow or not), so a legacy root's new children can still be refused, or can still inherit an old `external_directory` allow, until the person starts a new session. The stuck-deny banner stays for legacy sessions only; new sessions never write rules, so they never grow a stale one.
- **Downgrade is safe.** The overlay's old fields are untouched, so an older galopin recomposes and appends its blocks after the neutralising rule exactly as it does today, and the floor is rebuilt by whichever binary starts opencode.
- **Cerea** needs no new operation; the relabel and picker change ship in the same release train as the agent, and an older Cerea still shows "Deny" for a session now acting as Plan.

## Consequences

Pending asks and their answers become the single enforcement point, so the audit log (`permission {…, by:"galopin"}`) now records every automatic answer, not only rejections; `permission.rules` shows the floor and the function's state instead of a composed list. A Plan session refuses MCP tools it cannot classify, as Deny refused them. A reject of one of a session's parallel asks rejects all of them. A person on Ask sees fewer cards than today for reads and the same for effects. The cost is one local round trip per call (about 0.2 s). The ceiling is as strong as the answers galopin gives, and no stronger against `bash` until the sandbox exists.

## Rejected

- **Writing a smaller composed block per session.** Still append-only, still seeded into children; the problem is writing at all.
- **Per-workspace policy.** One opencode process serves all workspaces; a second policy object without a sandbox to enforce it is a second advisory layer. Revisit with the sandbox.
- **A selector that adds Deny beside Plan.** Plan already refuses every effect, and the plan agent's prompt makes the model say so; a fourth word would only be a Plan without the agent switch.
- **Allow natively through the floor for workspace reads** (kept as the documented fallback, not taken: measured cost is small and a uniform "everything asks" keeps one code path and one audit trail).
- **Replying `always` and letting opencode remember.** Its approved list is process-wide and shared by every session in the workspace (`index.ts:145-151`).

## Out of scope

Coordination tools over MCP with a session-scoped endpoint (layer 3), and the OS sandbox (layer 1, owned by the owner).

## Review answers (2026-10-15, folded in)

1. **Custom-agent floor is generated.** At start galopin reads `GET /agent` and writes, for every agent that is not a built-in, per-agent `ask` entries for every key the agent names plus `*`, and restates the agent's own denies, exactly as the table does for the built-ins. A custom agent's own `allow`s are therefore **no longer honoured natively**: the place for a standing allow is the machine's policy rules (decision step 7). The docs say so. The one extra start happens only when a custom agent exists.
2. **Plan and the agent switch.** An interactive `session.setPermissionMode` to Plan switches the session to the `plan` agent (and back to `build` on Ask or Allow when the agent is `plan`). Scheduled and granted runs keep their agent and get galopin's rejections plus a short system note, which is today's behaviour: the plan agent's `plan_exit` asks a person a question an unattended run cannot answer.
3. **Wire.** `deny` stays the wire spelling of Plan; `plan` is accepted as an input alias; the Cerea change is labels and the agent picker only.
4. **Machine rules.** `ask` and `deny` fold into steps 2 and 1; `allow` is step 7 and never lifts Plan or the ceiling.
5. **Carve-outs.** An edit of `.opencode/plans/*.md` is `once` on Plan; a sensitive `*.env` read is a card on Ask and Allow and a reject on Plan.
6. **Package and hook.** `agent/internal/decide`. The delegate rule (step 4) is a hook `func(caller, target string) bool` that the delegation work implements from the persisted spawn marks. The delegate's report back is galopin's own message delivery and does not go through the function.
7. **Docs** must say that a legacy session's new children can still inherit old `external_directory` allows and stale denies, and the way out is to start a new session. If the re-measured p50 per read with the real function exceeds about 300 ms, Phase B reports it before deciding anything.

## Implementation notes (Phase B, 2026-10-15)

What the build settled where the text above left room, recorded so the code and the ADR agree (`Cerea@feat/answer-not-write`).

1. **The ceiling is a cap, not a step.** The function's answer is the stricter of the cap (the ceiling, plus the machine's own `ask`/`deny` rules) and the mode's answer. So on Plan a ceiling `ask` is moot for an effectful request (Plan already rejects, which is stricter than a card), and exceptions, Allow, a grant and the delegate rule can never lift a cap. Plan's reads under a ceiling `ask` for `read` are a card.
2. **The delegate rule precedes Plan** (it applies to the coordination tools only), so a Plan spawner can still collect its delegate's report; the cap still applies to it.
3. **Three asks that protect a person survive Allow**, as they did before: work outside the project folder, the stuck-agent brake and a `*.env` read are a card on Ask and Allow (an exception lifts them; Plan rejects them). The machine's safe directories answer `once` on Ask and Allow and, as a convenience, on Plan.
4. **The agent switch is Cerea's, not galopin's.** The panel sets the `plan` agent when a person chooses Plan (Ask and Allow switch back to `build` unless the person picked a custom agent). `session.setPermissionMode` never changes the agent, so scheduled and granted runs keep theirs for free; the Plan system note rides their prompts.
5. **A tightened ceiling restarts nothing.** It is audited as `permission.tightened {restarted:false}`; cards the ceiling now refuses are rejected at once and a reply to one that was already showing is sent as a reject.
6. **The custom-agent check runs at each start of opencode**, not on a timer: a changed agent file is picked up at the next start.
7. **ACP.** The selector, exceptions and grant of an ACP session are galopin's own state in memory (a restart of galopin starts them on Ask); ACP asks reach the same function with the tool call's kind mapped to a key (`read`, `edit`, `execute` → `bash`, `fetch` → `webfetch`, an unknown kind is an effectful tool).
8. **Measured with the real function** (isolated opencode 1.18.34 and the mock LLM, 60 reads per arm, in-process answers): per-ask cost **p50 94 ms, p95 97 ms** against the same read with no floor. Reads ask; no fallback is needed.
9. **Plan beats the delegate rule for everything but reading.** A Plan caller's `session_send`, `session_spawn` and `schedule` are refused even to its own delegate (a delegate spawned on Allow would otherwise carry the change); reading its own delegate still works, and a delegate's own sends to its spawner are decided by the delegate's state. Report delivery is galopin's own message and does not go through the function.
