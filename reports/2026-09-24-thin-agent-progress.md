# Thin machine agent: progress log

Started 2026-09-24 (session began 2026-09-23 22:10 UTC). Design and wire spec: `reports/2026-09-24-thin-agent-protocol.md` (canonical copy in Pystino `deploy/agent/PROTOCOL.md`).

## Decisions

- **Machine agent:** one Go binary, `pystino-agent`, grown out of `pystino-enroll` and moved to Pystino `deploy/agent/`. Its subcommands: `enroll`, `serve` (the shim alone, kept), and `run` (the shim, an opencode supervisor, the session materializer and the WSS link). No Node, npm, Python or paseo is needed on the machine.
- **Backend interface:** we own it, shaped like ACP, with opencode first over `opencode serve` HTTP+SSE. ACP becomes the second adapter rather than the interface, because it lacks listing, usage, diffs, subagent trees and multi-client attach, and because `opencode serve` is the richer surface and survives restarts. See the protocol doc, §2.
- **Transport:** the machine dials out over WSS to `/api/v2/code/machine` on the chat origin. The bearer is its enrollment access token, validated locally (`iss`, `aud ∋ pystino-api`, `azp == opencode-enrollment`). The token is renewed in-band, and the connection is dropped at `exp + 60 s` without a renewal.
- **Pairing:** a machine's first connection creates a *pending* row, and the owner confirms it in the browser. Revoking tombstones the machine id and closes the socket. There is no paste flow and no pairing code.
- **C4, what we achieve:** Cerea stores no capability at rest. Authority is per device and per user, and it ends on revoke, or on IdP revocation within one token lifetime. The machine can veto auto-accept and confine workspaces. What remains: while a machine is connected, a compromised Cerea process can still prompt it, within the machine's policy.
- **Wire and cursor:** each session has its own `(epoch, seq)`; `session.sync` returns either the events since a cursor or a snapshot. The text-part contract makes the snapshot plus the deltas exact. Dedup is identity-based only (R3/R4).
- **Browser API:** the `/api/v2/code/*` surface stays, so the UI and its specs survive. Only the server behind it changes, and `@getpaseo/*` is removed.

## Research notes (opencode 1.18.31, verified live on this box)

- A single `GET /global/event` SSE stream covers every directory (`{directory, payload}`). A full loop was verified against the hermetic mock-openai: create → `prompt_async` → `message.part.delta` tokens → `session.idle`; a bash tool call → `permission.asked` → `POST /permission/:id/reply {reply:"once"}` → the tool ran.
- `OPENCODE_SERVER_PASSWORD` enables basic auth on the server. Modes come from `GET /agent` (build and plan are primary). Mode and model are per-prompt parameters.

## Workstreams

| Workstream | Repo / branch | Worktree | Agent |
| --- | --- | --- | --- |
| Go machine agent | Pystino `thin-agent/machine-agent` | `thin-machine-agent-pystino` | 8a9f7846 |
| Cerea machine link (WS, auth, registry, forwarder, bridge, pairing UI, paseo removal) | Cerea `thin-agent/machine-link` | `thin-machine-link-cerea` | 14483d64 |
| Salvage from batch4 (+ scroll-anchoring watch) | Cerea `thin-agent/salvage` | `thin-salvage-cerea` | 91f8494a |
| Quick wins C5, C7, C8, O6, O8, CI | both repos `thin-agent/quickwins` | `thin-quickwins-{cerea,pystino}` | 0f62b354 |
| P0 e2e harness (mock OIDC, real opencode + agent) | Cerea `thin-agent/p0-e2e` | `thin-p0-cerea` | orchestrator |

Quick-win ownership: C1, C6, R1, R3/R4, R6, X4 and O8's duplicate handlers belong to machine-link; C3, R7 and R8 belong to machine-agent.

## Log

- 22:10 Research, design and spec written. Four agents dispatched.
- 22:24 A host restart stopped every agent. Only machine-agent had work, an uncommitted step 1; the orchestrator committed it as `ad56312` and pushed it. All four sessions were resumed with `send_agent_prompt` and are running.
- ~23:05 The box ran out of memory (load 42, about 500 MB free) and every agent died. The orchestrator committed the WIP it found: machine-link `93a7f302` (the WS upgrade hook, machine auth, registry and device rows, unchecked) and quickwins-cerea `99a33753` (C5, partial). Go agent was already clean at `66c08bd` (C3, R7). Quickwins-pystino had `0c9b0a9` (O6). Salvage had 5 commits.
- 02:05 New resource rules: at most 2 Sonnet sub-agents at a time; every heavy command runs under `flock /tmp/heavy.lock`; no nested sub-agents; servers are killed after use. machine-link and the Go agent were resumed. Salvage and quick wins are parked until P0 passes, and salvage resumes first.

## Inputs for later milestones

- **Images and files (milestone 6):** the attachment store is done on Cerea `feat/attachment-store` (`cc107cb3`, `e9175dfe`, `136fc886`, `a3cf7df6`; not merged). The API is described under "Attachments" in that branch's `docs/code-panel.md`. The owner key is `code:<deviceId>:<sessionId>`.
  - **Routes:** `POST` and `GET` on `/api/v2/code/attachments/<key>`, and `/<sha>` for the bytes.
  - **Server helpers:** `storeAttachment`, `findAttachments(key, messageId)`, `readAttachment`, `deleteAttachments` and `deleteAttachmentsByPrefix`.
  - **UI pieces:** a `fileBaseUrl` seam on `ChatMessageColumn`, plus `pastedAttachments`, `uploadComposerFiles`, `FileDrag` and `ComposerFileChips` for the composer.
  - **What we wire:**
    - upload before sending, with the same `messageId`, which travels as the `session.prompt` `clientMessageId` and must be echoed on the user message;
    - on user-frame replay, attach `findAttachments`;
    - pass `fileBaseUrl`;
    - give `AgentComposer` a `mimeTypes` allowlist;
    - call `deleteAttachments(key)` on session delete, and delete by prefix on device revoke;
    - Cerea hands the bytes to the machine from `readAttachment` as `Attachment` data URLs, treating `application/vnd.chatui.clipboard` as `text/plain`.
  - At that milestone, merge `feat/attachment-store` into `thin-agent/main`.
- ~01:15 The account usage limit stopped everything; it reset at 04:40. The user checkpointed WIP: machine-agent `b262bbb`, machine-link `88557c8c`. On re-validation, the Go side was green except its own step-5 test, and Cerea had 5 type errors, all in tests. A stale `opencode serve` probe from the Go agent had held `/tmp/heavy.lock` since 03:07; it was killed by PID.
- **Go machine agent done** (`2210609`). Verified by the orchestrator: gofmt, vet and `go test ./...` are green, and the agent reports the real-opencode IT green (prompt, permission, cancel). It is merged into Pystino `thin-agent/main` (`c5dbd70`). What its live-only IT exposed about opencode 1.18.31:
  - the health check hung with no bound;
  - `ReplyPermission` needs `?directory=`;
  - tool status lives at `part.state.status`.

  Deviations: the machine id is minted by `run` (`<state-dir>/machine-id`), and the live `session.diff` event is not forwarded, so the diff is polled.
- The salvage agent was resumed in the freed slot, for its checks and the scroll-anchoring counts.

## P0 — PASSED (2026-09-24 ~06:45)

Branches: Cerea `thin-agent/main` @ current head (machine-link + p0-e2e merged, plus fixes); Pystino `thin-agent/main` @ `11dd7b9` (machine-agent merged, plus fixes). Everything is pushed.

- `tests/code-machine-p0.spec.ts` passes (chromium, 39 s) and then passed again in the full run. Only the LLM (mock-openai) and the IdP (mock-oidc) are fakes; everything else in the chain is real: browser → Cerea → WSS → pystino-agent → real `opencode serve` 1.18.31. The spec covers:
  - confirming a pending machine;
  - adding a workspace;
  - creating a session;
  - prompting and streaming the reply;
  - approving a bash permission, after which the tool writes a file on disk;
  - stopping a 400-token turn part-way.
- `/code` suite: the first full run was 21 of 23. The 2 failures (the pair dialog not closing on confirm; an offline-device spec counting AgentView's own lookup) were fixed. The 3 affected spec files, P0 included, then passed 10 of 10.
- Check 0/0, lint clean, `go vet` and `go test ./...` green.

Integration bugs the first real run found (unit tests on both sides had passed):
1. Go marshals nil slices as `null`, so the hello's `workspaceRoots: null` was dropped silently by Cerea's strict schema and the link never paired. The same happened with transcript lists and empty op results, and the stream answered 500. Fixed on both sides: the Go agent always sends arrays, and Cerea tolerates a missing list and logs a malformed hello loudly.
2. opencode parts carry no role, so the person's prompt rendered as agent text. The materializer now stamps each message's role onto its parts and deltas.
3. Stop surfaced as a failed turn (`MessageAbortedError`). The adapter now treats an abort as a normal end.
4. Creating a session didn't navigate to it: `{@const}`s were read after the block tore down.
5. The link now logs the close reason when it disconnects.

Test infrastructure: `E2E_SKIP_BUILD=1` in `playwright.config.ts` serves an existing `build/`. The production build (~2 GB) alongside the stack under test was OOM-killed, so the procedure is: build alone under the lock, then run the specs.

Open (not P0):
- The installer still references the deleted relay overlay (`installer/install.sh`, `compose-flags.sh`); the link agent left that to `deploy/rearch`.
- Salvage (scroll-anchoring counts) and quick wins (C5, C7, C8, O8, CI) are still parked.
- The link-review nits: the discovery fetch has no timeout, and discovery's `issuer` is not cross-checked.

## Parity batch A: milestones 1, 2, 4, 5 and the machine-token review points (2026-09-24 ~08:30)

Cerea `thin-agent/main` @ `256f97c8`; Pystino `thin-agent/main` @ `6830bac`.

- **M1, models/modes and the free-model filter.**
  - The server-side policy lives in `src/lib/server/code/modelPolicy.ts`. The models list drops non-`pystino/*` ids unless the machine's hello policy has `allowFreeModels`. Setting or creating a session with a disallowed model returns 403 before the machine is asked.
  - The agent also filters, and now reports `hidden` in `backend.models`. The pill note shows the total ("N non-gateway models hidden: this machine was enrolled without --allow-free-models").
  - Session create accepts a live `modeId`/`modelId`; plan/write is kept as the fallback.
  - Commits: Cerea `a2b4436b`; Pystino `118bc63`.
- **M2, auto-accept.** It was already built on both sides. It is now verified live: it is absent under the default machine policy, and with `autoAccept: allowed` a bash call runs with no prompt.
- **M5, diff pane.** The real-machine run found that opencode's session diff misses files written by shell commands. `session.diff` now computes the checkout's uncommitted diff with git: untracked files included, capped at 200 files and 256 KiB each, binaries marked. It falls back to the backend's own diff outside git. This makes the diff backend-agnostic. Commit: Pystino `6830bac`.
- **M4, subagents.** Verified live: an opencode `task` call renders its card with the task's description in the parent transcript, and the turn completes. Not yet verified: expanding the card to show the child session's own transcript (`session.children` plus a child sync).
- **Review points.** Machine-token discovery and JWKS fetches now time out after 5 s, and the discovery document must name the configured issuer. Commit: Cerea `62d4687c`.
- **Tests.**
  - `tests/code-machine-parity.spec.ts` (real machine, chromium): 4/4 pass, covering the models, auto-accept absent, auto-accept plus diff, and subagent cases.
  - Forwarder vitest 8/8, including model-policy enforcement; machineAuth 11/11, including the issuer mismatch.
  - `go test ./...` green, including the new `internal/checkout` tests. Check 0/0 and lint clean.
- **Harness.** The machine policy can be set per test; a non-gateway `freebie` provider is listed; mock-openai gains `toolCallsOnce`.
- **In flight:** M3 (usage meter and compaction) is with a Sonnet agent on `thin-agent/m3-usage` in both repos. The salvage agent is running the scroll-anchoring counts.

## Backlog after parity (added by the user, 2026-09-24 09:40)

- (a) A **non-blocking** nightly real-opencode IT against opencode `latest`, kept light for CI because the free GitHub plan has limited Action minutes: a scheduled run only (nightly or weekly), no matrix, short.
- (b) Update the `/code` docs to describe the thin agent instead of paseo.
- (c) X2, native transcript rendering: optional. Propose it; don't build it.

Status 09:45: the M3 and salvage final reports are in hand, and both branches are merged. The quick wins (0f62b354) and M9 (81c7f2fb) were resumed after the usage-limit cut; the orchestrator checkpointed quickwins-pystino WIP `b8bf139`. M6 is committed on `thin-agent/m6-files` @ `81d70936` (check 0/0) and has not yet been e2e-verified. The M4 Go fix (`4e68efe`: subagents anchored at their task call, children dropped from `session.list`) still needs its Cerea half.

## Parity batch B: M3, M6, M9, the M4 fixes, quick wins, salvage (2026-09-24 ~11:30)

Cerea `thin-agent/main` @ `3dfd0ce1`; Pystino `thin-agent/main` @ the quick-wins merge on top of `959abc1`.

- **M3, usage/context meter and compaction** (Sonnet 003c984c, merged).
  - Agent: a `session.compact` op, usage on `session.get`/`list` and in snapshots, and a `compaction` part.
  - Cerea: usage/compaction side-channel frames, a fold that never touches turns, `ContextMeter.svelte` (a ring in the composer pill row that shows % when the max is known and a token count otherwise, with a "Compact now" action), and the route `POST v1/agents/:id/compact`.
  - Tests: 43 vitest and 4 hermetic Playwright.
- **M6, images and files** (orchestrator).
  - `feat/attachment-store` is merged. Its conflicts were resolved for user-owned, tombstoned devices, and its specs moved to signed-in owners (C6).
  - The composer uploads under the prompt's `messageId`. The server sends the stored files to the machine as data URLs: documents go as their extracted markdown, and a long paste as `text/plain`. The bridge attaches `findAttachments` to user frames, the fold puts them on the user message, and `fileBaseUrl` serves them. Deleting a session deletes its files.
  - Agent: the link's read limit was raised from 32 KiB to 160 MiB.
  - ChatInput gains `chatTools` (default on) so the agent composer shows the attach control without chat's MCP, knowledge, web-search and tools pills.
- **M4 fixes.** The earlier "pass" was a false positive: the child session was listed in the sidebar and no card rendered.
  - Agent: task tool parts carry the child session id, `session.children` sets `parentToolCallId`, and `session.list` drops children.
  - Cerea: the card anchors on `parentToolCallId`. A tool call's first frame had no `parameters`, which crashed AgentView's task scan and blanked the turn; fixed in both the mapping and the view.
  - The parity spec now also writes the agent log and the browser console to disk on failure.
- **M9, generic ACP adapter** (Sonnet 81c7f2fb, merged).
  - `run --backend acp --acp-command "<cmd>"` (default `opencode acp`). It supervises an ACP agent over stdio JSON-RPC and maps `session/update` and `session/request_permission` onto the normalized events.
  - Its IT passes against real `opencode acp`: prompt→idle, and permission→once→tool runs.
  - Diffs, children, usage, compact and worktrees are reported as unsupported, because ACP has no messages for them. The diff pane still works through git.
- **Quick wins** (Sonnet 0f62b354, merged in both repos).
  - C5: SameSite=lax by default, and JSON or multipart required on non-GET `/api` (415 otherwise).
  - C7/C8: the whoami-v2 bearer path and `TRUSTED_EMAIL_HEADER` are deleted, after a grep audit.
  - O8: the dead vector-store forward is removed.
  - O6: Keycloak `directAccessGrantsEnabled:false` and `bruteForceProtected`.
  - CI workflows for both repos are parked at `deploy/ci/github-workflows/`, because the push token lacks `workflow` scope; moving them is a two-line step documented in its README.
- **Salvage** (Sonnet 91f8494a, merged). Scroll-anchoring passed 3/3 on salvage and 2/3 on main, so it is a pre-existing flake, not a batch4 regression.
- **Tests on the M6 branch**, which carries all of the above except the quick wins:
  - The full `/code` suite plus smoke and attachments: 39/40, then the attachments spec fixed, 3/3.
  - Real-machine P0 and parity 5/5: models, auto-accept ×2, files, subagents with card expansion.
  - `go test ./...` green. Check 0/0 on merged main.
- **Notes for deploy.**
  - `codeDevices` now has a non-partial `userId_1_updatedAt_-1` index. An existing database keeps the old partial index of the same name, `createIndex` logs "already exists with different options", so drop the old index at rollout.
  - One agent killed another's mock by pgrep'ing PIDs, so the rule is now recorded PIDs only.
  - Disk: Docker build cache is 11 GB (9 GB reclaimable), from image builds outside this workstream; not pruned here.
- **In flight:** M8 (worktrees, Sonnet 12e960cd) and M7 (handoffs, Sonnet 228482b4).

## Backlog (a) done: weekly real-opencode IT (Pystino `816d05d`)

The Go ITs no longer spawn the chat repo's Node mock from a path on this box. An in-process Go mock, `deploy/agent/internal/mockllm`, uses the same `/__control` plane and named scenarios. Both suites pass on it: opencode serve (prompt, permission, cancel) and opencode acp (prompt, permission).

`deploy/ci/github-workflows/opencode-latest.yml` runs them against `opencode-ai@latest`. It is weekly (Mon 04:17 UTC) plus manual dispatch, never on push or PR, one job, no matrix, 15-minute cap. It is parked with `ci.yml` until someone moves it into `.github/workflows/` with a token that has `workflow` scope.

## Backlog (c): X2, a native transcript. A proposal, not built

**Today.** Normalized machine events are translated server-side into chat `MessageUpdate` frames (`machineTimeline.ts`). They are folded client-side into chat `Message[]` (`consumeAgentUpdates.ts`), with one assistant message per turn, `adoptRunning` heuristics and side-channel cases, and rendered by `ChatMessage`. Every bug of this kind that parity found sits at that emulation seam:
- the missing `parameters` on a first tool frame blanked a turn;
- a role had to be stamped onto parts so a prompt would not render as agent text;
- subagents are anchored by scanning tool-call frames;
- usage and compaction needed fold side channels.

**Proposal.** Render the normalized model directly.
- **Client store.** A `SessionTranscript` keyed by message and part id, applying the protocol's own semantics: upsert message/part, append delta, permission asked/replied, status. That is the same logic as the Go materializer, and about 150 lines. The SSE carries the normalized envelopes unchanged, with SSE id = `epoch:seq`. The client then deduplicates by seq, and a reset is simply "clear the store".
- **Rendering.** Each part renders through chat's leaf components:
  - text and reasoning through chat's markdown renderer;
  - tool through the existing tool card;
  - permission through the approval card;
  - subtask through `SubagentCard` (anchored by `parentToolCallId`, no scanning);
  - file through `UploadedFile`;
  - compaction as a divider.

  Keep `ChatMessageColumn` as the scroll container, so the sticky-bottom and anchoring behaviour and its specs stay.
- **What goes away:** `machineTimeline.ts`'s chat mapping, `consumeAgentUpdates.ts`, the one-assistant-per-turn emulation and the per-bridge role and messageId tracking.
- **What becomes natural:**
  - several assistant messages per turn, as opencode actually produces;
  - steer, since a mid-turn user message is just another message;
  - history paging, by prepending messages;
  - rewind, by removing messages.

**Cost and risk.** About 4–6 days including specs. The risk is losing chat behaviours `ChatMessage` gives for free: copy and retry affordances, the markdown and code-block tooling, a11y. Mitigate by composing those leaf components, never forking them.

**Recommendation.** Do it after parity and behind a flag. The trigger is the first of steer or history paging, because both break the one-turn emulation. Until then the current fold is adequate and tested.

## 2026-09-24 ~12:00: integration and deploy in progress (deployment agent 35b5abb4)

`thin-agent/main` is frozen at Cerea `3dfd0ce1` and Pystino `816d05d`, and is being merged with `deploy/rearch` into `main` in both repos and deployed live. Until that is reported done: no pushes to `thin-agent/main`, and M7/M8 are not merged. Both keep committing on their own branches with minimal heavy runs.

Afterwards, M7 (`thin-agent/m7-handoffs`), M8 (`thin-agent/m8-worktrees`, both repos) and the `/code` docs rewrite target `main` directly: merge `origin/main`, verify, then merge into `main` for a later deploy. Neither milestone will be fully verified within the deploy window, so both stay out of it.

## Parity complete: M7 and M8 merged into `main`, docs rewritten (2026-09-24 ~15:30)

**Heads.** `main`: Cerea `70067318`, Pystino `9f5456d`. Not deployed; the redeploy is to be scheduled by the orchestrator.

**M7, handoffs** (Sonnet 228482b4; plus one orchestrator fix `a227cb46`).
- A "Hand off…" action on a finished assistant message opens a dialog. The target can be the same machine or another paired one, with any allowed mode and model.
- The route `POST v1/agents/:id/handoff` builds a curated `chat-history.md`, capped at 200k with a note when truncated, creates `Handoff: <title>`, and prompts it.
- The new session's header shows where it came from.
- The fold gains a `messageBoundary` side-channel frame that stamps `machineMessageId`.
- Orchestrator fix: "up to here" now carries the rest of the clicked turn, because opencode writes one assistant message per step.

**M8, workspaces and worktrees** (Sonnet 12e960cd).
- `workspace.suggest` gives path autocomplete inside `workspaceRoots`, or `$HOME` when there are none.
- `workspace.create {worktree}` runs `git worktree add`; archive can remove the worktree.
- In the UI: "New worktree…" and a branch badge.

**Integration.** The two merged with one import conflict in the forwarder and one semantic conflict (M8 made `isGitRepo` required, and M7's fallback lacked it); both were fixed.

**Verified on the combined tree:**
- Check 0/0, lint clean.
- `/code` vitest 88/88.
- Playwright `code-*` plus attachments and smoke: **44/44, including the real-machine P0 and parity specs**.
- Pystino `go test ./...` green.

**Docs (backlog b).**
- Cerea `docs/code-panel.md` gains "What the panel does", a feature map tying each feature to its op, capability and policy.
- `CLAUDE.md`'s `codeDevices` entry now describes the thin agent's rows.
- Pystino `docs/coding-agents.md` documents `run --backend acp`, and the `PROTOCOL.md` status reads "implemented".

**Remaining, not started:**
- the X2 native transcript (proposal only, above);
- agent-initiated handoff through an MCP tool injected into agents (paseo's `injectIntoAgents` equivalent), not in scope of M7;
- the parked CI workflows, which need a token with `workflow` scope;
- dropping the old `codeDevices` partial index at rollout;
- prune of the 9 GB of reclaimable Docker build cache (not ours).

## ADR renumbered (2026-09-24)

The agent-host decision was drafted as 0086. The deployment re-architecture has since taken 0086–0088, so the decision is now **ADR 0089, accepted**, and it supersedes 0085. It includes an "as built" section. The index gains its missing 0085 row plus 0089. Commits: ai-stack `main` `838398e`, Cerea `91291deb`, Pystino `2c34537` (references by number only).

## Design: agent-initiated handoff (backend-generic)

**Goal.** An agent can hand work to a new session through a tool it is given, and nothing happens until the owner approves in the panel.

1. **An MCP server hosted by the machine agent.**
   - `pystino-agent run` serves a small MCP endpoint (streamable HTTP) on loopback, with the same hardening as the shim (review C3): a random per-run bearer, a `Host` allowlist, 127.0.0.1 only.
   - It exposes one tool, `handoff {title, prompt, modeId?, modelId?}`. The description tells the model to write a self-contained briefing, because the new session starts with no context.
   - The tool is injected **generically through the backend**. `CreateSessionOptions` / backend config carries `McpServers []McpServer{name, url, headers}`.
     - opencode: the agent writes a `mcp.pystino` remote entry into the opencode config it launches with, and allows that tool in opencode's own permission rules. Our approval is the gate, not a second opencode prompt.
     - ACP: the adapter passes the server in `session/new` and `session/load` `mcpServers`, as HTTP when the agent's `mcpCapabilities.http` allows it.
2. **The approval.** A tool call does not act. The agent emits a new normalized event, `handoff.requested {requestId, title, prompt, modeId?, modelId?, callId?}`, on the calling session and holds the MCP call open, for up to 10 minutes by default.
   - The panel renders it as an approval card in the parent transcript: "The agent wants to hand off: ‹title›", showing the brief, with Approve / Reject and an optional model/mode override.
   - The answer is a new op, `handoff.reply {sessionId, requestId, decision, modeId?, modelId?}`.
   - On approve, the agent creates the child session in the same workspace. The session records `handoffFrom = parent`, is titled `Handoff: ‹title›`, and is prompted with the brief. The tool returns `{sessionId, title}`.
   - On reject or timeout, the tool returns a refusal the model can read.
   - `handoff.resolved` closes the card.
   - Auto-accept never applies to handoffs; they are always the owner's call. The model policy applies to the chosen model.
3. **The link back.**
   - The parent transcript's resolved card links to the child.
   - The child's header says "Handed off from ‹parent›", from `Session.handoffFrom`, the same header that fork handoffs use.
   - Children are ordinary top-level sessions, not subagents. The person drives them.
4. **Capabilities.** The backend advertises `handoffTool: true` when it can take injected MCP servers: opencode yes, and ACP yes when `mcpCapabilities.http` is set. The panel shows the feature only then.
5. **Tests.**
   - Go unit tests with a fake backend: the tool call → `handoff.requested` → approve → child created → tool result; reject; timeout.
   - An opencode IT with the mock LLM scripted to call the `pystino_handoff` tool.
   - Cerea: mapping, forwarder and fold tests.
   - The real-machine parity spec gains a handoff case: the agent calls the tool, the owner approves in the card, and the child session appears with the brief.

## Follow-up workstreams (started 2026-09-24 evening, during the live redeploy)

| Workstream | Branch | Worktree | Agent |
| --- | --- | --- | --- |
| X2 native transcript (flag `CODE_NATIVE_TRANSCRIPT`, default off) | Cerea `thin-agent/x2-native` | `thin-x2-cerea` | b95a5aa8 |
| Agent-initiated handoff (MCP tool plus owner approval) | Cerea and Pystino `thin-agent/agent-handoff` | `thin-ah-cerea`, `thin-ah-pystino` | 6916427b |

Both do design and implementation only (no build or Playwright) until the deployment agent reports the redeploy done.

## Live feedback (2026-09-24 afternoon): "basic functions are fine", plus three issues

X2 is parked at `thin-agent/x2-native` @ `5d4660a2`.
- Verified: check 0/0, lint, store vitest 7/7, the hermetic native spec 2/2, the flag-off `/code` suite 33/33, and real-machine P0 plus 4 of 5 parity cases with the flag both on and off.
- Left: with the flag on, a subagent card's expanded child transcript is empty.

1. **Deleting a device does nothing live.** No DELETE reached the server. `revokeDevice` does use `base` (`${base}/api/v2/code/devices?id=`), and the button calls `handleRevoke`, so the cause is elsewhere: the button being unreachable, the hook rejecting the request before it logs anything behind the `/chat` proxy, or a client exception. It needs a repro on a build served under `APP_BASE=/chat`. The e2e suite runs at root. Related: an offline machine's 502s, and the `OpError unavailable` in the stream log, must render as a clean "offline" state.
2. **"No auto mode / approve tools."** The pill is hidden whenever the machine's policy denies auto-accept; the user enrolled without `--allow-auto-accept`. Changes:
   - the toggle is always shown, disabled with the exact re-enroll flag when the machine vetoes it;
   - the approval card offers Allow once / Always allow / Deny, where "always" maps to `permission.reply always`;
   - the default is to be proposed, not changed silently.

## Design: the user-question tool (chat and agents, one card)

- **Chat.** Cerea already has `ask_user_question` (`src/lib/server/askUserQuestion.ts`, builtin `builtinTools/askUserQuestion.ts`, `AskQuestion.svelte`). It uses durable elicitation, so it survives reload, and supports 1–4 questions of 2–4 options, a header, multi-select and "other". Today it is offered only in ML Assistant conversations (`builtinTools/index.ts`). The change: offer it in every conversation, behind a setting that defaults on, with a deployment kill switch. Check the reload/resume path, and add vitest plus an e2e for an ordinary chat.
- **Agents.** opencode 1.18.31 has a native question API: the `question` tool, question events, `GET /question`, and `POST /question/:id/reply|reject`.
  - The machine protocol gains `question.asked {request: {id, questions: [{question, header?, options: [{label, description?}], multiple?}], callId?}}` and `question.resolved {requestId, answers|rejected}`, plus a `question.reply {sessionId, requestId, answers}` op (and a reject).
  - The ACP adapter reports `questions: false`; ACP has no question method. The fallback for backends without a native tool is the injected MCP mechanism the agent-handoff work is building, which could serve an `ask_user_question` tool.
- **UI.** One shared component: the chat's `AskQuestion` card, whose answer is dispatched through a prop so it serves both chat's elicitation endpoint and the `/code` forwarder route `POST v1/agents/:id/questions/:requestId`.
- **Tests.** vitest for the mapping and route; the chat e2e; and a real-machine parity case where the mock LLM calls opencode's `question` tool, the card appears, it is answered, and the turn resumes.

## 2026-09-24 ~13:50: restored after an accidental archive

The user's cleanup archived every agent at 13:47–13:48. The orchestrator committed the WIP it found:
- `fix/code-live-feedback`: `4f7c8868` and `0c31fb21`, the base-path e2e plumbing and 14 spec updates;
- Pystino `thin-agent/agent-handoff`: `0c36bda`, the buildHello capability fix.

Priority order, and who has each item:
1. Device delete under `/chat` and the offline state, then 2. auto-accept and the approvals UX: a fresh Sonnet agent, 3c09c951, on `fix/code-live-feedback`. The first agent, 2d4a71a2, was cancelled and archived at 170K of its 200K context.
3. The question tool.
   - Chat half: `feat/ask-question`, with the orchestrator rerunning its check, build and e2e.
   - Agent half: handed to 6916427b once handoff verification is done, on new `feat/agent-question` branches.
4. Agent-initiated handoff: 6916427b resumed to finish verification.
5. X2: parked at `5d4660a2`.

## Question tool, chat half: merged (Cerea `main` @ `473c3fb9`)

`ask_user_question` (1–4 questions of 2–4 options, a header, multi-select, "other") now joins every conversation, not only ML Assistant, behind the `CHAT_ASK_USER_QUESTION_ENABLED` switch, which is on unless set to `"false"`. The card was already durable. Verified:
- check 0/0, lint clean;
- builtin-list and `runMcpFlow` vitest 242/242, with the stale "withheld outside the mode" test updated to cover both sides of the switch;
- the new e2e `tests/chat-ask-question.spec.ts` plus the smoke, conversation-streaming, generation-* and attachments specs: 38/38;
- the known `replayRoundTrip` flake passes alone.

The agent half (opencode's native question API, reusing the same card) is next with 6916427b.

## Machine agent: revocation and re-enroll fixes, merged (Pystino `main` @ `d49672b`)

The live report: after removing the device and re-enrolling with `--allow-auto-accept`, `run` reconnected forever against `4403 "this machine was revoked"`. The fixes:
- `enroll` rotates `machine-id` (and clears the revoked marker), as the docs already said it did.
- A 4403 during the welcome handshake is now terminal too (`link.ErrRevoked`). `run` prints the fix (re-enroll, or delete `machine-id`) and exits 78.
- The systemd unit has `RestartPreventExitStatus=78`. launchd cannot filter exit codes, so `run` writes a `revoked` marker keyed to the machine id, and a restart with the same id exits 0.
- The `enroll` epilogue now names `run` plus confirming in `/code`, with `serve` as the panel-less shim. The spend line points at the gateway ledger.

Tests: link `TestClose4403DuringWelcomeIsTerminal` (exactly one dial), rotation and marker tests, and the full `go test ./...` passes.

The user's workaround until the next deploy: `rm ~/.config/opencode/machine-id` and restart `run`.

## Queued

- **Context meter shows 0% mid-turn** (live bug). Cause: opencode's new assistant message carries all-zero tokens until its step ends, and the agent mapped that to a usage event, and cached it too. The Go fix, which treats all-zero usage as not yet reported, is committed on Pystino `fix/usage-zero` @ `463c17a`, **not merged**. The Cerea-side guard (`keepReportedUsage`, its vitest and a meter spec) was not written: the user stopped that step. Awaiting direction.
- **Pystino quotas in the `/code` panel** (Cerea only), after the live fixes. Revised placement: **inside the context ring's popup**, below the context and compaction content. There is no separate indicator in the composer.
  - The popup lists every quota section with `UsageBar`, plus a link to Settings → Usage.
  - Fetched from `GET /api/v2/usage` when the popup opens, and after each completed turn while it is open. No polling. The section is hidden when the gateway reports no quotas.
  - Every section is shown, with no claim about which group the machine bills (`x-bill-to` is chosen at enroll). Possible follow-up, not to be built now: the agent reports its billing group in `hello`.
  - Tests: a vitest for the popup's quota derivation (hidden when empty, sections in order), and a `/code` Playwright spec that opens the ring's popup and asserts the quota sections and the Settings link, at root and under `/chat`.
- **Model picker in the style of Claude's** (chat and `/code`), queued after the live fixes and the quota work. The design goes here before implementation:
  - one shared picker with search, models plus one-line descriptions, a check on the current one, an Effort submenu, and "More models";
  - chat: it moves into the composer pill, with effort persisted per conversation and a user default;
  - `/code`: the pill shows the real model name, and effort is its own pill, wired through the machine protocol to opencode (variant or reasoning effort; ACP noted);
  - tests: vitest for search and effort capability; Playwright for both pickers at root and under `/chat`; the real-machine parity spec checks that effort reaches opencode.
- House rule: no "WIP:" subjects on `main`. Pystino `463c17a` went in with one; history is left as is.

## Final `main` for the live deploy (2026-09-24 evening): Cerea `43462b69`, Pystino `1824935`

Merged: `fix/code-live-feedback`, `fix/usage-zero` and `feat/agent-question` (both repos), each with a `--no-ff` merge and a proper message.
- Cerea `/code` Playwright: **49/49 at root and 49/49 under `/chat`**, including the real-machine P0 and parity specs.
- Go `go test ./...` passes, including the real-opencode and ACP ITs.
- Check 0/0, lint clean.

The SHAs were sent to the deployment agent 35b5abb4. **Not included:** agent-initiated handoff (`thin-agent/agent-handoff`, unverified; its agent moved on to the question tool before verifying it).

Next: the quotas in the ring popup (`feat/code-quotas` @ `7fac7b0e`, implementation done, heavy runs held until the deploy is done), verifying the handoff branch, then the model-picker design.

## Plan: move the machine agent into Cerea as `galopin` (decided 2026-09-24; runs after the live deploy's checks report)

"galopin, the Cerea machine agent": Torinese for a clerk or handyman. This is one move plus one rename.

1. **Move with history.** No extra tool is needed: git's built-in subtree does it.
   - In Pystino: `git subtree split --prefix=deploy/agent -b agent-history origin/main`, which gives the directory's own history.
   - In Cerea: `git subtree add --prefix=agent <pystino> agent-history`, so `git log -- agent/` keeps the history.
   - Licensing: an `agent/README.md` (and a header note) says the directory is first-party code under Cerea's own licence file (then separate from upstream's), not the Apache-2.0 upstream chat-ui code. `PROTOCOL.md` moves with it.
2. **Rename.**
   - Go module `galopin`, with imports `galopin/internal/...`.
   - Binary `galopin`, and the `--help`/usage and version strings.
   - Log prefixes: `pystino-agent:` becomes `galopin:`, and `pystino shim:` becomes `galopin shim:`.
   - `packaging/build-dist.sh` emits `galopin-<os>-<arch>` plus `REVISION`/`SHA256SUMS`.
   - `galopin.service`, and the LaunchAgent label `org.cerea.galopin` (`org.cerea.galopin.plist`).
   - The docs in both repos, ADR 0089 and its references (by number), the CLAUDE.md files, the Cerea README, the pairing dialog's printed command, and Pystino `adopt.py`'s re-enrol hint.
3. **Keep live machines working.**
   - Unchanged: the wire protocol, `/api/v2/code/machine`, the subprotocol, the `opencode-enrollment` client id, and the opencode config default `~/.config/opencode/opencode.json`.
   - State moves to `<config-dir>/galopin/`: `credentials.json` (it carries the shim secret), `machine-id`, `policy.json`, `revoked`, `opencode-overlay.json`, and the health/status file.
   - One-time migration on first `run`/`enroll`/`serve`: if `<config-dir>/opencode/pystino-credentials.json` (plus its siblings) exists and `galopin/` does not, move them and log it once. Tests cover a fresh machine, a migrated machine, and both present, where the new directory wins and nothing is overwritten.
4. **Pystino.**
   - Remove `deploy/agent/`.
   - `docs/coding-agents.md` shrinks to the gateway contract: `/v1`, `x-bill-to`, the Authelia `opencode-enrollment` client and its lifetimes, with the machine documentation pointing at Cerea's `agent/` and `docs/agent-machines.md`. Cerea's `docs/agent-machines.md` already exists and becomes the galopin doc.
   - `scripts/README.md`, `AGENTS.md`, `CLAUDE.md` and `docs/deployment.md` are pointed at the new location.
   - The parked CI moves the Go job and `opencode-latest.yml` to Cerea's parked workflows.
   - The release manifest notes that the agent version follows the Cerea pin, since the dist is built from the pinned Cerea revision's `agent/`.
5. **Cerea.**
   - The parked `ci.yml` gains the Go job.
   - The real-machine specs' harness builds `agent/` in-repo, and `GALOPIN_BIN` overrides it; this drops the cross-repo `PYSTINO_AGENT_BIN` path.
6. **Verify.**
   - Go: gofmt, vet, and `go test ./...` including the real-opencode and ACP ITs.
   - Cerea: check, lint, vitest, and `/code` at root and under `/chat`, with the real-machine specs building galopin locally.
   - Pystino: pytest and `ruff check` for anything touched.
7. **Merge.** `--no-ff` merges with proper messages into both `main`s, then a report. The user rebuilds the dist and deploys.

Execution: the orchestrator does step 1, the history move, itself, because it must be exact. One Sonnet agent then does steps 2, 3, 5 and 6 on a Cerea branch, and a second does step 4 on a Pystino branch. The Pystino side only needs the new names and paths, so the two can run in parallel.

## After the live deploy (2026-09-24 ~19:00)

- **Live deploy verified** by 35b5abb4: Cerea `43462b69`, Pystino `1824935`, upgraded in place with data preserved and `doctor` clean. Sign-in, a chat completion and the machine flow all passed. The one failure: after a revoke, `run` hung instead of exiting 78.
- **Fixed**, Pystino `main` @ `383638a`. The event forwarder waited on the process-wide context, which only a signal cancels, so it now gets its own. Checked end to end against a fake Cerea that pairs then closes 4403: exit 78, and a restart with the same id exits 0 through the marker. The dist in `~/pystino-agent-dist` predates this and needs a rebuild.
- **galopin move, in progress:**
  - Cerea `feat/galopin`: history added with `git subtree add` (`23ea9f5e`; 35 commits of `deploy/agent` history, while the pre-`deploy/agent` history stays in Pystino). The rename, migration, CI and tests are with Sonnet 7595e73a.
  - Pystino `feat/galopin-move` @ `6b2d187`, done by the orchestrator:
    - `deploy/agent` and `docs/agent-machines.md` removed;
    - `docs/coding-agents.md` reduced to the gateway contract;
    - references updated in AGENTS.md, CLAUDE.md, `scripts/README.md`, `docs/deployment.md`, mkdocs and the `adopt.py` hint;
    - the parked CI's Go job and the opencode-latest workflow removed;
    - a release-manifest note that the agent follows the Cerea pin;
    - ruff clean and 85 deploy pytest tests passing.

    It merges only after Cerea's branch does, so neither `main` is ever left without the agent.
- **Quotas in the ring popup:** Sonnet 2b300665 resumed for full verification.

## Design: the model picker in the style of Claude's (chat and `/code`); queued after galopin and the quotas

**What exists.**
- Chat: `ModelPicker.svelte` is a searchable overlay; picking PATCHes the conversation, or sets `settings.activeModel` on a new chat. `ThinkingEffortChip.svelte` is a separate chip whose value is `settings.reasoningEffortOverrides[modelId]`, forwarded as OpenAI `reasoning_effort` (`endpointOai.ts`). It shows only for models the gateway marks `supportsReasoning` (`models.ts`, from the model's features).
- opencode 1.18.31: the per-prompt knob is **`variant`** (a string on `prompt_async`, also stored on the session's model). Each model lists **`variants`** (`/config/providers`: an object keyed by variant id, e.g. `{"low":{...},"high":{...}}`). A custom provider's variants come from `opencode.json` (`provider.<id>.models.<id>.variants`).
- ACP has no standard effort control (`session/set_model` is itself unstable), so the ACP backend reports none.

**The shared component: `ModelEffortPicker.svelte`.** Anchored to a composer pill that reads `<model name> <effort>` (for example "GLM 5.3 Flash  Medium"), it opens a popover with:
1. a search field, filtering by name and description;
2. a short list: the current model plus recent or favourite models, up to about 6, each with its name, a one-line description (the gateway's model description, trimmed) and a check on the current one;
3. a divider;
4. an **Effort ▸ `<value>`** row with a submenu: the effort levels the model supports, plus "Default". Shown only when the model supports effort;
5. **More models ▸**, which opens the existing full `ModelPicker` overlay.

The component takes callbacks (`onpickModel`, `onpickEffort`) and a capability (`efforts: string[] | null`), so chat and `/code` wire it differently. Links use `${base}`.

**Chat.**
- The pill replaces the separate `ThinkingEffortChip` in the composer. Its model half reuses `ModelPicker`'s pick semantics: the PATCH, or `activeModel` on a new chat.
- Effort is persisted **per conversation** (a new optional `Conversation.reasoningEffort`) with the **user default** being today's `settings.reasoningEffortOverrides[modelId]`. The effective value is the conversation's, else the user default, else the model's default. It is sent as `reasoning_effort` only when the model supports it.

**`/code`.**
- The model pill shows the real model name. When the session has no explicit model, it uses the backend default from `backend.models` (`isDefault`), instead of "Model".
- Effort is its own pill (it matters more for agents), hidden when the model or the backend has no efforts.
- Machine protocol: `Model` gains `efforts?: string[]`, the opencode variant ids. `Session` gains `effort?`. A new op, `session.setEffort {sessionId, effort|null}`, is stored in galopin's session overlay and sent as `variant` on every prompt, the same way mode and model are. The capability is advertised as `efforts` per backend; ACP reports none.
- `galopin enroll` writes `variants` (`low`, `medium`, `high`, each mapping to opencode's `reasoningEffort` option) for gateway models the gateway marks as reasoning-capable.

**Tests.**
- vitest: search filtering, the short-list composition, and the effort capability (hidden with none, levels otherwise).
- Playwright: the chat pill (pick a model, pick an effort, and the request carries `reasoning_effort`) and the `/code` pills (the real model name, the effort pill hidden or shown), at root and under `/chat`.
- The real-machine parity spec: picking "high" leads the mock LLM's request from opencode to carry the variant's `reasoning_effort`.

## Live bug: subagent permissions never surface (high priority, ahead of the model picker)

**Root cause** (read from the code):
1. The machine does forward a child's events. The materializer creates state for any session it sees and publishes the child's `permission.asked` under the **child's** `sessionId`. But Cerea's SSE bridge subscribes only to the parent's session id (`subscribeSessionEvents(deviceId, sessionId, …)` in `agents/[id]/stream`). A child's events have no listener, so they are dropped. The approval card never appears, the child blocks, and so does the parent's `task` tool.
2. When the person pressed Stop, the parent's turn ended. The subagent roster re-polls at turn boundaries, so the expanded child transcript (`session.sync` of the child) now showed everything, including its pending prompts. That is why it all appeared at once.
3. Auto-accept is a **per-session** flag (`st.autoAccept`, checked at `sessions.go` ~391 on `permission.asked`). A child session never has it set, so a parent with auto-accept on still had its subagents blocked.

**Fix plan** (on Cerea `agent/` after the galopin branch merges, plus Cerea):
- **Machine.** The materializer learns each session's parent from the backend: opencode's session info carries `parentID`, and `session.created`/`updated` already map to `Session.ParentID`. On `permission.asked` for a session without its own auto-accept, it walks up to the root and auto-replies when an ancestor has auto-accept on and the policy allows it. This is never applied to handoff approvals. Envelopes gain `rootSessionId`, the top-level ancestor (itself for a top-level session).
- **Cerea.** Listeners are keyed by root. The bridge for a top-level session also receives its descendants' envelopes.
  - A child's `permission.asked`/`replied` and `question.asked` become the same approval and question frames, labelled with the subagent's title and carrying the child's session id, so the reply goes to the child's request.
  - A child's parts and deltas emit a side-channel `childActivity {childId}` frame, and an expanded subagent card re-syncs on it (throttled), so its output streams live.
  - The permission route accepts the child's session id.
- **Tests:**
  - Go, with a fake backend: a child's `permission.asked` is forwarded with `rootSessionId`, and auto-accepted when the parent has the flag on.
  - A real-opencode IT: the parent spawns a task whose child needs bash permission.
  - Real-machine parity at root and under `/chat`: the card appears mid-turn, approving it lets the child's output stream, and with auto-accept on there is no card and the child completes.

## Queued after the subagent-permission fix (Muse Spark handoffs allowed)

- **Retry and rollback on agent messages.** Today the button is probably chat's own retry, which does nothing for a machine session.
  - Implement "retry" (re-send the last prompt) and "rollback to here" (opencode `POST /session/:id/revert {messageID, partID?}` plus `unrevert`; check 1.18.31's exact API and whether it restores files) through the machine protocol.
  - Gate it per backend capability (ACP: hide it if unsupported), and say in the UI whether files are reverted.
  - If it proves large, hide the dead button now and file the full version.
  - Tests: vitest for the gating, and a real-machine parity case (the transcript truncates and the next prompt continues from there) at root and under `/chat`.
- **Rename the M7 "Handoff" to "Fork"** (the button, the dialog and its copy, "Fork from here") and update the docs. "Handoff" stays for the agent-initiated feature.
- **Subagents in the `/code` sidebar** (queued right after the subagent-permission fix, whose parent links it reuses). The approved design: no tree, because parent and child can sit in different workspaces or worktrees.
  - **Placement:** each session stays under its own workspace. This reverses M4's hiding of children from `session.list`; they are listed now, but marked.
  - **Subagent rows:** a "sub" badge, plus a line "↳ from ‹parent title›" (adding "· ‹workspace/worktree›" when the parent lives elsewhere). Clicking the line opens the parent.
  - **Parent rows:** a "N subagents" count whose popover links to each child, wherever it lives.
  - **Status on subagent rows:** running, waiting for approval (prominent), done or failed. A parent row flags it when any descendant is waiting.
  - **In a subagent's view:** a "Subagent of ‹parent›" header with a link back.
  - **Filter:** a sidebar toggle to show or hide subagents, on by default.
  - **Protocol:** `session.list`/`get` carry `parentId`, optionally `rootId`, and a child-status summary. It is backend-generic; ACP reports none.
  - **Tests:** vitest for the badge, link and status derivation. A real-machine Playwright case at root and under `/chat`: the badge and from-link, the parent's count and popover, the waiting marker while an approval is pending, and the filter toggle.

## `ask_user_question` spec clarity (branch `fix/question-summary`, 2026-09-24 ~21:15)

**What opencode tells the model**, read from the 1.18.32 binary's `question` tool description:
- "When `custom` is enabled (default), a "Type your own answer" option is added automatically; don't include "Other" or catch-all options."
- "Answers are returned as arrays of labels; set `multiple: true` to allow selecting more than one."
- "If you recommend a specific option, make that the first option… add "(Recommended)"."

Its tool result is `User has answered your questions: "<question>"="<answers joined ', '>"…`. It does not distinguish a typed answer from an option.

**The mismatch.** Cerea's agent question card had no `allowOther`, so the model was promised a free-text choice the user never saw.
- **Fix:** `machineTimeline` sets `allowOther: q.custom !== false`. The protocol `Question` gains an optional `custom`.
- **Gap:** galopin's `QuestionItem` doesn't carry `custom` yet, so the default (on) always applies. That's a one-field follow-up on Cerea `agent/`.

**Chat's own tool:**
- The description is rewritten in the style of Claude Code's AskUserQuestion:
  - use it only when blocked on a real choice;
  - 1–4 questions of 2–4 options, with `multiSelect`;
  - the header is a chip label of at most 12 characters;
  - the "Other" choice is always added by the UI, so the model must never add its own;
  - option descriptions give a purpose line.
- `setBudgetUsd` appears only in the ML Assistant preset's variant (`askUserQuestionToolPlain` elsewhere).
- The result is `Q: <question>` / `A: chose "X", "Y"` or `A: typed their own answer (custom, not one of your options) "…"`.
- A model-authored catch-all option ("Other…", "Something else", "Type my own…") is dropped when at least 2 real options remain; otherwise it is kept and the form's own "Other" is suppressed.

## Queued after the model picker: `/code` files and terminal (plan accepted 2026-09-24)

The plan is `reports/2026-09-24-code-files-and-terminal-plan.md`, with D1–D14 accepted as recommended. The full queue now runs: subagent-permission fix → sidebar subagents → retry/rollback and Fork rename → model picker → the following.
1. **F0 (S), design work, done by me or an Opus agent:**
   - add plan §3 to `agent/PROTOCOL.md`;
   - a new ADR in ai-stack under the next free number, amending 0089's C4 consequence (D5). Cite ADRs by number only.
2. **F1 (M), a Muse Spark handoff (`opencode/muse-spark-1.3-contributor-free`):** the read-only explorer.
   - Machine side: `os.Root` confinement, the D3 deny list, git decorations.
   - UI: the Files tab, our own Svelte tree (D10), and a read-only CodeMirror 6 viewer.
   - Switches: on by default with `--no-files` (D2), and `CODE_FILES_ENABLED` (D7).
   - The `codeAudit` collection with a 90-day TTL (D14).
   - Tests at root and under `/chat`.
3. **T1 (L), security-critical, review carefully:** the terminal behind `--allow-terminal` and `CODE_TERMINAL_ENABLED` (both off).
   - WebSocket with a ticket (D9), step-up auth (D6), the D8 lifetime.
   - It starts only after F0's ADR merges. It's split into Muse Spark handoffs (Go half and Cerea half).
4. **F2–F4, T2, H1–H2:** they stay in the plan and aren't started.

Rules: at most 2 sub-agents, `flock`, the box rules in every Muse Spark brief, merge into `main` after verification, no deploy.

## Chat fixes from live conv `6ab5325c…` (glm-5.3-flash), queued 2026-09-24 after question-summary

**What happened.** All 4 `<artifact` occurrences were inside `<think>`. The model drafted the artifact in its reasoning, announced it, then ended each of its 5 steps with an `ask_user_question` call instead of emitting the artifact.
1. **Question tool: never to confirm; deliver first.** Done on `fix/question-summary` (`6f7676df`), in both the tool description and the preprompt. The preprompt was trimmed to stay under the 32k ML-preset system-message ceiling.
2. **The artifact prompt vs the tool loop.** Check how the "don't call tools while creating an artifact" instruction and the tool list interact, and move the instruction next to the tool list. Report whether a cheap guard is feasible: an answer that announces an artifact, contains no tags, and ends in a tool call.
3. **Multi-step text is concatenated without a separator** in the UI and the markdown export. Insert a paragraph break between steps' text segments.
4. **The export says "Called 1 tool"** when there were 5 calls. Fix the count, or list the calls.

Tests for 1, 3 and 4: vitest for the prompt text, the export and the separator. Merge into `main`; no deploy.

## Tool-based artifacts (user decision 2026-09-24: BUILD, inline tags kept as fallback), queued after the chat fixes

Modelled on Claude.ai's artifacts tool and ChatGPT Canvas. The design goes here first, then a Muse Spark handoff, reviewed carefully.
- **One tool, `artifact`:**
  - `create {identifier, type: html|react|svg|mermaid|markdown|code(+language), title, content}`;
  - `update {identifier, old_str, new_str}`, which must match exactly once, else a recoverable error result;
  - `rewrite {identifier, content}`.

  Every call is a new version in the existing panel and history. The result is short ("created particle-playground v1") and never echoes the content.
- **Streaming preview** while the tool arguments stream, where the provider streams them; otherwise a "writing…" placeholder. Check what the gateway and OpenAI-compatible providers do with streamed tool-call arguments.
- **Prompting.** When the tool is offered, drop the inline-tag instructions. The description says to use it for substantial standalone content, to deliver first, and never to follow with a question call in the same step.
- **Fallback.** The inline parser stays for old conversations and for models or presets without tool calling (gated per capability). Tags emitted despite the tool still render. Never parse tags inside `<think>` or reasoning.
- **MCP UI resources.** `ui://` / `text/html` embedded resources render in the same panel, sandboxed. This can be a follow-up slice, but design for it now.
- **Security.** The same sandboxed iframe and CSP, with no new capabilities.
- **Scope (user clarification 2026-09-24): chat side only.** That means Cerea's normal chat, its artifact panel and its tool loop. It is NOT the `/code` agent panel, NOT galopin, and NOT the machine protocol, so the branch and tests stay on chat code paths. The same applies to chat fixes 2–4 above. The only agent-side item was the one check of opencode's question-tool wording, and that's done.
- **Tests:**
  - vitest for the schema, `update` exact-match and its errors, versioning, the gating, and the parser fallback (tags outside `<think>` only);
  - e2e with mock-openai for create, update and rewrite with versions, the inline fallback, and tags inside thinking being ignored, at root and under `/chat`.

Merge into `main`; no deploy.

### Tool-based artifacts: design (2026-09-24, chat side only)

**What exists today:**
- Artifacts are inline tags in `message.content`, parsed client-side by `$lib/utils/artifacts` (a shared util, so it's usable server-side too).
- `buildArtifactRegistry` strips `<think>` before parsing (`artifacts.ts` ~368), so tags in reasoning already never render. That's what happened in the live conversation: the drafts sat inside `<think>`.
- Updates are `type="update"` blocks with `old_str`/`new_str` pairs, applied first-occurrence on the latest version. Versions come from successive blocks with the same identifier across messages.
- The prompt, `ARTIFACTS_SYSTEM_PROMPT`, is added via `preprompt.ts` when the model has `supportsArtifacts`.
- Tool-call arguments do stream from OpenAI-compatible providers. `runMcpFlow.ts` (~885) accumulates `delta.tool_calls[].function.arguments` per index, but nothing is forwarded to the client until the call completes.

**Decision: the tool writes a canonical inline block into the content (the content stays the single source of truth).**
- The `artifact` builtin tool executes server-side. It validates, resolves the latest version by running the shared parser over the conversation's earlier assistant messages (think-stripped), and appends a canonical block to the current assistant message's content:
  - `create` and `rewrite` append `<artifact identifier type title [language]>content</artifact>`;
  - `update` appends `<artifact identifier type="update"><old_str>…</old_str><new_str>…</new_str></artifact>`.
- The panel, version history, cards, markdown export and old conversations then work unchanged, and back-compat is automatic.
- **The alternative, rejected:** a structured `message.artifacts[]` field. It's more robust to content collisions, but it touches the parser, registry, pane items, export and migration. Not worth it for v1.

**Tool contract.** One tool, `artifact`, with `command`:
- `create {identifier, type: html|react|svg|mermaid|markdown|code, language?, title, content}`: an error if the identifier exists (the result points the model at `rewrite`/`update`).
- `update {identifier, old_str, new_str, title?}`: `old_str` must occur **exactly once** in the latest version. For 0 or more than 1 matches, return an error result naming the count and saying to copy `old_str` verbatim or use `rewrite`. Nothing is appended on error.
- `rewrite {identifier, content, title?}`: an error if the identifier is unknown (point at `create`).
- The result is short and never echoes content: `created particle-playground v1 (html)` / `updated particle-playground → v3` / `rewrote … → v4`.
- `exemptFromToolRestraint`, never parks.
- Content containing a literal `</artifact>` would break the inline parse. Reject it with a recoverable error; this is rare, and v1 accepts the limitation.

**Streaming preview.**
- In the accumulation loop, when an index's name is `artifact` and the command is `create`/`rewrite`, extract the partial `content` string with a small incremental JSON-string decoder. It has to handle escapes and a cut mid-escape.
- Emit a throttled (~250 ms) `MessageUpdate` `ArtifactDraft {toolCallId, identifier?, type?, title?, content}`. The client shows it as a `closed:false` streaming block in the panel; the parser already supports growing unterminated blocks.
- When the call executes, the canonical block replaces the draft.
- `update` drafts show a "Editing ‹title›…" placeholder. A provider that doesn't stream arguments shows "Writing…" until the call completes.

**Gating and prompting.**
- A new per-model `artifactsMode: "tool" | "tags"`, defaulting to `"tool"` when `supportsArtifacts && supportsTools`, else `"tags"`. Presets may override.
- In tool mode, `ARTIFACTS_SYSTEM_PROMPT`'s tag grammar is dropped. What's kept goes into the tool description: when to make an artifact, the types, the sandbox allow/block list, "deliver first, never follow with `ask_user_question` in the same step", and "earlier artifacts appear in the conversation as `<artifact>` blocks; change them with `update`/`rewrite`, never by writing tags".
- In tags mode, nothing changes.
- The ML-preset 32k system-message ceiling benefits, since the tag grammar leaves the system message.

**Fallback.** The inline parser stays for:
- old conversations;
- tags mode;
- a tool-mode model that emits tags anyway (still rendered);
- never inside `<think>` (existing behaviour, now tested).

**History replay.** The model sees earlier artifacts as the canonical blocks in assistant text, which gives it the verbatim latest version for `old_str`. The risk is that it imitates the tags; the tool description counters that. Watch it in the e2e.

**Token cost.** Roughly the same as inline: content goes out once as arguments, is replayed once in history, and the result is short. The tool description (~1k tokens) replaces the system-prompt grammar (~1.5k).

**MCP UI resources (follow-up slice, same sink).** An MCP tool result carrying an embedded resource with a `ui://` URI or `mimeType: text/html` goes through the same "append canonical block" function: type `html`, identifier from the URI, title from the resource or tool name. It renders in the same sandboxed iframe and CSP.

**Security.** The same render path, the same iframe sandbox and the same CSP. The tool adds no capability, since it only produces content the inline path could already produce.

**Tests:**
- vitest:
  - the schema per command;
  - `update` with 0, 1 and 2 matches (only exactly one appends);
  - `create` on an existing identifier, `rewrite` on an unknown one;
  - version numbering across messages;
  - the gating (`artifactsMode` default and override; the prompt drops the grammar in tool mode);
  - the partial-JSON content decoder;
  - parser fallback (tags outside `<think>` only).
- e2e (mock-openai) at root and under `/chat`:
  - create, then update, then rewrite render v1→v3 in the panel with history;
  - a streamed-arguments draft is visible before completion;
  - the inline-tag fallback on a tags-mode model;
  - tags inside `<think>` are ignored.

## Follow-ups noted 2026-09-24
- **galopin: carry opencode's `question` tool `metadata.answers` and the question's `custom` on parts/requests.** Cerea currently rebuilds an answered agent question on reload from opencode's result text (`answersFromQuestionOutput` in `machineTimeline.ts`). That works, but it's a parse of upstream wording that returns null if the wording changes.

## Overnight queue (set 2026-09-24 ~21:40; work through without waiting)
1. question fix + quotas merge
2. galopin merge (after the deploy agent's workflow move)
2b. **galopin-dist** (user decision 2026-09-24): Cerea's image builds the 4 binaries, and it serves `{base}/galopin/<os>-<arch>`, `SHA256SUMS`, `version` and `install.sh` publicly (exempt by route id, 4-name allowlist). The one-liner goes in the pairing dialog, and the docs make it the primary path. Brief: `reports/briefs/2026-09-24-galopin-dist-brief.md`. It runs in parallel with item 3 (different code).
3. subagent approvals. Brief: `reports/briefs/2026-09-24-subagent-approvals-brief.md`.
4. sidebar subagent labels
5. retry/rollback + Handoff→Fork rename
6. model picker
7. chat fixes 2–4. **Started early** in a free slot: Muse Spark `9c252c60`, branch `fix/chat-steps`.
8. artifact tool (chat side; design above)
9. F0 → F1 → T1 (T1 only after F0's ADR merges)

## CI: agent e2e hang fixed (2026-09-24 ~21:55)
`TestE2EFakeCereaAgainstFakeBackend` hung about 1 in 40 runs, and it failed the first real CI run (Pystino PR #1).
- **Cause:** the test's fake Cerea. `handleReq` runs per-req goroutines, so a turn's events can precede its `res`. `readUntilType("res")` discarded those events, including `permission.asked`, and then the script waited forever.
- **Fix:** keep the skipped frames. Pystino `main` `ff837c8`; Cerea `feat/galopin` `28f5d61c`. 300 of 300 runs pass. The deploy agent was told to re-run CI.

## Known CI exclusions (deployment agent 35b5abb4, 2026-09-24 ~20:00)

- **`src/lib/utils/execution/pyodide.worker.integration.spec.ts`** skips in Cerea's PR CI: its suite is `describe.skipIf(!DIST_PRESENT)` and CI does not fetch the dist. It needs the vendored Pyodide dist (`npm run sync-pyodide`, ~325 MB from the pyodide CDN and PyPI), and even with the dist present the run exits 1: its clean/dirty exit test provokes Pyodide's stray `SystemExit` duplicates as unhandled rejections (the test's own comment calls them harmless; vitest fails a run on any unhandled rejection). It failed the same way on `main` locally, and the M7 agent listed it as pre-existing. To bring it back: filter exactly those rejections in the spec (the worker's `guardCleanExitRejection` shape, extended to non-zero exits), then run it in its own non-blocking job with the dist cached.
- **`replayRoundTrip.spec.ts`** ("degrades the oldest turns") is NOT excluded: it passed in both CI runs, which use Mongo 8. On this box it fails every time, in the full suite, because the box has no AVX and runs Mongo 4.4 (5.0+ needs AVX). So the "known flake" is really a Mongo 4.4 difference, not flakiness; expect it red in local runs only. (Not the skills seeds: `ensureDeploymentSeeds()` re-seeds on every call, so `load_skill` is offered in every run, CI included.)

## Merged 2026-09-24 ~22:05: Cerea `main` `791a5b78`
- `29c591bf`: fix/question-summary.
  - Answered-question summary in chat and on `/code`, surviving a reload. On `/code`, the snapshot rebuilds the card from opencode's tool part.
  - The ask_user_question spec rewrite: the "Other" rule, `setBudgetUsd` only in the ML preset, `chose` vs `custom` results, the model's own catch-all deduped, the confirm/deliver-first rule.
  - Agent questions now offer free text.
  - The smoke spec is base-aware.
  - Verified: vitest; e2e chromium at root 12/12 and under `/chat` 12/12.
- `791a5b78`: feat/code-quotas (quotas in the context ring popup). Verified by its agent at 43/43 root and 43/43 `/chat`; reviewed; check and lint on the combined tree.
- **Not a regression:** WebKit isn't installed here, so specs run with `--project=chromium`.

## Overnight progress (2026-09-24 ~22:40)
- **Chat fixes 2–4** (`fix/chat-steps`), from Muse Spark `9c252c60`, reviewed:
  - The artifact/tool rule now sits beside the tool guidance.
  - The export counts calls with multiplicity (`ask_user_question ×5`). The UI count was already correct.
  - The step separator had a real bug: reasoning streamed per token put the break inside `<think>`, and the backward scan was quadratic, which a replay-budget test caught once it ran on a private Mongo. I rewrote it (`6f1c349f`) as a per-message incremental think state, plus tests (split tags, a 30k-token linearity check).
  - The announced-artifact guard was only assessed: feasible, one retry mirroring `leakedToolCallRetries` (`runMcpFlow.ts` ~1315).
  - vitest: generation and textGeneration 569/569. The e2e (chat-ask-question and smoke, root and `/chat`) is queued.
- **Test-infra note:** concurrent vitest runs sharing one Mongo (8791/8792 are used by other agents) cause false failures. Private container `e2e-mongo-8794` created for orchestrator runs.
- **The artifact tool was started early** in the free slot: Muse Spark `88ddd846`, branch `feat/artifact-tool`. Brief: `reports/briefs/2026-09-24-artifact-tool-brief.md`. The `agent/`-touching items wait for the galopin merge.
- **galopin:** `feat/galopin` is up to date with `main`, plus the CI test fix. Check, lint and Go pass; e2e root 56/56; `/chat` running.

## galopin merged (2026-09-24 ~23:05)
- **Cerea `main` `057f65f4`:** merge of `feat/galopin`, resolved against the deploy agent's `.github/workflows/` move. The Go job is in `ci.yml`; `opencode-latest.yml` is weekly. Verified: Go vet and tests with the ITs, check, lint, and e2e 56/56 at root and 56/56 under `/chat`.
- **Pystino `main` `80bc49b`:** merge of `feat/galopin-move`. The `deploy/agent` test fix was dropped with the directory; `ci.yml` has no Go job; `opencode-latest.yml` removed. Verified: ruff, and pytest 1563 passed.
- **Next:** subagent approvals, Muse Spark `afeebad1` on `fix/subagent-approvals`, using Mongo 8795. The artifact tool is in the other slot. galopin-dist follows when a slot frees.
- **Chat fixes 2–4 merged:** Cerea `main` `ca2fc067`. e2e: chat-ask-question and smoke, 4/4 at root and 4/4 under `/chat`.
- **F0** (spec and ADR) started by the orchestrator while both slots are busy.

## F0 done (2026-09-24 ~23:30)
- **ADR 0090 (accepted):** "Files and a terminal on galopin, each behind a double veto", ai-stack `ccb6501`. It amends 0089's C4 consequence. 0089's header now points at Cerea `agent/PROTOCOL.md` and notes the galopin rename; index row added.
- **`agent/PROTOCOL.md` §9**, "Machine powers", plus policy fields in §4 and the hello/Policy/Machine shapes in §5: Cerea `main` `3afd2eda`. Specified, not built.
- T1 is now unblocked by the ADR, but stays queued behind F1 per the plan.
- **Briefs ready**, each with its own private Mongo (8795 subagents, 8796 F1, 8797 galopin-dist, 8798 retry/Fork, 8799 picker): `reports/briefs/`. Launch order as slots free: galopin-dist → sidebar (after subagents) → retry/Fork → picker → F1 → T1.
- **More briefs ready:** `2026-09-24-sidebar-subagents-brief.md` (after subagents merges), `2026-09-24-f1-explorer-brief.md`, and `2026-09-24-t1a-terminal-galopin-brief.md`. T1a is the Go half; per plan §10 it may run in parallel with F1. T1b (Cerea half: tickets, browser WS, xterm UI, codeAudit terminal actions) will be briefed after F1's side pane and T1a's review.
- **Slots at 23:40:** artifact tool (`88ddd846`), subagent approvals (`afeebad1`).
- **`main` regression, fixed:** my question-fix and chat-fixes merges together put the ML-preset system message at 32,079, over the 32,000 ceiling test. Each branch alone was under, and I didn't rerun vitest on the combined tree. Fixed by tightening the wording, not raising the ceiling: `b0db6661`. **Lesson:** rerun the prompt-size vitest after every merge that touches prompts.
- The artifact agent now has a private Mongo, 8800.

## After the 23:24 OOM (paseo daemon restart)
- **Merged state intact:** Cerea `main` `b0db6661` (galopin, chat fixes, F0, ceiling fix); Pystino `main` `80bc49b`.
- **Checkpoints pushed by the user:** `feat/artifact-tool` `2f7eeaf2` and `fix/subagent-approvals` `d03a6b0f`. Both agents (`88ddd846`, `afeebad1`) resumed with the new memory rules and are working.
- **New rule:** one heavy job at a time; kill every server after use; pause the second agent under 1.5 GB available.
- 23:41: available memory 1,442 MB during the artifact agent's vite build (2.2 GB). **Paused** `afeebad1` (subagent approvals) per the rule; its queued build was cancelled. It resumes once the build ends and memory is above 2.5 GB.
- 23:43: memory back to 3.1 GB; `afeebad1` resumed.

## 2026-09-24 ~23:57: the Muse Spark free quota ran out
- Both Muse Spark agents stalled on `Provider retry (attempt 1): Free usage exceeded, subscribe to Go` (`opencode/muse-spark-1.3-contributor-free`). The stall-watch checkpointed their work, unverified: `feat/artifact-tool` `10779482` (`88ddd846`) and `fix/subagent-approvals` `7ac4147c` (`afeebad1`).
- Both agents cancelled. **No fallback** to the paid Muse Spark or to Sonnet: the user chose the free model, and that choice is theirs to change (morning decision).
- **The orchestrator (Opus) takes over the queue itself**, one item at a time and one heavy job at a time: first `fix/subagent-approvals`, then `feat/artifact-tool`, then the rest in order.
- **Finding from `afeebad1` before it stalled (for the user):** the real-machine e2e failed because the child's bash tool returned "OpenCode session is not bound to a Paseo agent". Cause: a paseo-run agent's shell carries `OPENCODE_CONFIG_CONTENT` (paseo's opencode plugin, `~/.paseo/runtime/opencode/paseo-*.mjs`), which leaks through the harness into galopin's supervised `opencode serve`. There, paseo's plugin refuses tools for sessions it doesn't own.
  - It's not a paseo bug and not a Cerea bug. It's environment leakage, and it only affects tests run from inside a paseo opencode agent.
  - **Hardening worth doing:** galopin (and `tests/machineHarness.ts`) should drop an inherited `OPENCODE_CONFIG_CONTENT` / `OPENCODE_CONFIG` from the environment of the `opencode serve` it supervises, since galopin writes its own config overlay. Paseo's runtime files were not touched.

### Takeover notes (orchestrator, 2026-09-25 ~00:10)
**`fix/subagent-approvals`, taken over:**
- Reviewed. Two bugs fixed in `f47d31bc`:
  - a subagent's own view got no live events: tree watchers fired only on the root;
  - live child frames carried the child's seq as SSE id, corrupting the parent's Last-Event-ID resume cursor.
- Regression tests added, plus a stale comment fixed.
- Full verification running: check, lint, Go with the subagent ITs, vitest, e2e at root and under `/chat`.

**`feat/artifact-tool`: review findings to fix on takeover:**
1. The debugging leftovers must go: `tests/artifact-probe.spec.ts`, `tests/artifact-shot.spec.ts`, `mcp/draftProbe.spec.ts`.
2. `execute` history reads the stored conversation, which may already hold this turn's in-progress message, **and** appends `turnBlocks` under the same message id. Versions may be double-counted. Exclude the current message id from the stored history.
3. The draft parse runs on every chunk (quadratic over long content): throttle the parse, not just the emit.
4. The final draft (full content) stays in `message.updates` after the call completes, storing the content twice. Drop it once the call's canonical block or result lands.
5. Open bug the agent was chasing when it stalled: the draft doesn't render in the browser mid-stream (it suspected the smooth-streaming pacer holds back non-text updates).
- The subagent verification's vitest run, over a directory, picked up `previewSrcdoc.svelte.test.ts` (a client-project browser test; 5 fail on this box). It's unrelated to the branch; CI runs the client project in the Playwright image.

## Merged 2026-09-25 ~01:05: subagent approvals, Cerea `main` `5d77d171`
- Built by Muse Spark `afeebad1` until the quota ran out; taken over, fixed (`f47d31bc`) and verified by the orchestrator.
- **Root cause** (as diagnosed): the bridge listened to the parent's session id only, and auto-accept was per session.
- **Built:**
  - galopin parent tracking, `rootSessionId` on envelopes, and auto-accept inherited from ancestors (never for handoff approvals);
  - Cerea tree subscription, labelled child cards whose replies route to the child, and a `childActivity` live re-sync of subagent cards.
- **Verified:** Go with the real-opencode subagent ITs, vitest, check, lint, and e2e 56/56 at root and 56/56 under `/chat`.
- **Next:** `feat/artifact-tool` (takeover; findings above), then galopin-dist, sidebar labels, retry/Fork, picker, F1, T1a.
- **`feat/artifact-tool` takeover (01:40):**
  - review fixes in `c…` "versions counted once, drafts cheap and never stored twice";
  - the **draft-not-rendering bug found**, by tracing server yield → route → client consume → derived state → panel. `ArtifactPanel` mounted only for an artifact already in the registry, and a new artifact's draft has none. Fixed.
  - Full verification running: check, lint, e2e for artifacts, ask-question, smoke and all `/code` specs (the branch changed `tests/mock-openai.ts`), at root and under `/chat`.

## Merged 2026-09-25 ~02:05: tool-based artifacts, Cerea `main` `55fc37d1`
- Muse Spark `88ddd846`'s work plus the orchestrator's takeover fixes.
- Verified: vitest 602/602, check, lint, and Playwright 62/62 at root and 62/62 under `/chat` (artifact, ask-question, smoke, all `/code`).
- **MCP UI resources:** the seam exists (`resolveArtifactOp` is the sink), but the feature isn't built. It's the follow-up slice.
- **Next:** galopin-dist (orchestrator).
- **galopin-dist (orchestrator, ~02:40): implemented on `feat/galopin-dist`.**
  - Dockerfile `galopin` stage and public `{base}/galopin/*` routes (allowlist, ETag/304, `no-cache` revalidation so an old binary never meets a new SHA256SUMS; a deviation from "long cache", for correctness).
  - The route is exempted from the login wall by route id. The `install.sh` passes shellcheck (checked with the koalaman/shellcheck container locally; not a dependency).
  - The pairing dialog leads with the one-liner; docs updated.
  - **Caddy (Pystino `deploy/stack/proxy/Caddyfile`, read-only):** `/chat/*` → `reverse_proxy chat:3000` with `flush_interval -1`, no `request_body`/size limit, no `encode`. A ~10 MB download passes through unbuffered.
  - **Note:** the e2e stack has browser login unconfigured, so the login-wall exemption is covered by code, not by the e2e (which proves no-cookie access).
  - Verification running.

## Merged 2026-09-25 ~03:00: galopin-dist, Cerea `main` `cf1f63fc`
- Verified: check, lint, vitest 8/8, the Docker galopin stage (4 binaries, **+28 MB**), shellcheck clean, and Playwright 13/13 at root and 13/13 under `/chat` (a real `sh` install, a refused tampered checksum).
- `REVISION` reads "built from Cerea unknown" unless the image build passes `PUBLIC_COMMIT_SHA` (Pystino's image workflow should pass it; for the deploy agent).
- **Next:** sidebar subagent labels (orchestrator).

## Disk cleanup (2026-09-25 ~03:20): 83% → 69% (19 GB free)
- **Removed worktrees**, each checked clean, merged into `main` and pushed:
  - Cerea: artifact, chatfix, f0, galopin, gdist, qsum, quota, subperm, cerea-store, thin-cerea;
  - Pystino: galopin-move, e2efix, thin-pystino.

  The `node_modules` symlink was removed first, so the shared `code-enrollment-live/node_modules` stayed intact.
- **Kept:**
  - `thin-ah-*` and `thin-x2-cerea` (unmerged: agent-handoff and X2);
  - `deploy-*` and `integrate-*` (the deploy agent may use them);
  - `code-enrollment-live` (the node_modules source), `merge-cerea` (the merge workspace), `sidebar-cerea` (current work).
- Deleted `build/`, `.svelte-kit/output` and `test-results/` everywhere, plus my `/tmp` logs, pid files and old harness binaries. Docker volumes untouched.

## Merged 2026-09-25 ~04:05: sidebar subagents, Cerea `main` (see the log)
- Orchestrator-built. Verified: Go, vitest 106/106, check, lint, and `/code` e2e 55/55 at root and 55/55 under `/chat`.
- **Next:** retry/rollback + Fork rename (orchestrator). The `/code` retry button is currently dead: `ChatMessageColumn` always passes an `onretry` wrapper. opencode API: `POST /session/{id}/revert {messageID, partID?}` returns the session with `revert {messageID, partID?, snapshot?, diff?}` (files restored via snapshot); `POST /session/{id}/unrevert`.
- **Retry/rollback + Fork (orchestrator, ~04:50), `feat/agent-retry-fork`:**
  - `session.revert`/`unrevert` in galopin with capabilities `revert` and `revertFiles`.
  - **Real-opencode IT (`TestRevertIntegration`):** the turn leaves the transcript, the file it wrote is restored **only in a git repository** (opencode snapshots are git-based; in a non-git directory the file stayed), and unrevert restores the turn.
  - UI: retry on an answer, or editing a prompt, confirms (the wording follows `workspace.isGitRepo`), then reverts, re-syncs and re-sends. The dead icon only renders when the capability is present.
  - No undo button: the re-send ends opencode's undo window. The op is kept for a future "rollback without resend".
  - Handoff → "Fork from here", with the old "Handoff: " titles still recognised.
  - Verification running.
- 2026-09-25 ~05:20: the stall-watch stopped idle e2e Mongo containers 8794–8797, 8799 and 8800 (memory). The rule now: stop an agent's container once its work merges.

## Merged 2026-09-25 ~05:45: retry/rollback + Fork, Cerea `main` `d0705f35`
- Verified: Go with the real-opencode revert and subagent ITs, vitest 100/100, check, lint, and Playwright 60/60 at root and 60/60 under `/chat`.
- **Test lesson:** opencode asks the mock for a session title, so assert answers inside the transcript and let a turn settle before changing the mock scenario.
- **Next:** model picker (orchestrator).
- **Model picker, chat slice (orchestrator, ~06:30), `feat/model-picker`:**
  - `ModelEffortPicker` pill (search, short list with recents, Effort submenu, More models) replaces `ThinkingEffortChip`.
  - `Conversation.reasoningEffort` via PATCH (null clears it), with one `effectiveReasoningEffort` resolver for the route and both sweepers.
  - A new-chat pick sets the user's per-model default.
  - vitest 8/8; check, lint; e2e running.
  - **The `/code` slice follows:** real model name, effort pill, `session.setEffort`, opencode `variant`, enroll variants.
- **Picker `/code` slice: facts gathered (from the opencode 1.18.32 binary):**
  - model config `variants: {<id>: <providerOptions>}`, e.g. `{"high": {"reasoningEffort": "high"}}`; `@ai-sdk/openai-compatible` maps `reasoningEffort` → `reasoning_effort`;
  - `prompt_async` accepts `variant`;
  - the gateway lists `supported_features: ["reasoning", …]`, so enroll writes low/medium/high variants only for those models.
- **Picker chat slice, verification:** the full Playwright suite passes **107/107 at root**.
  - **Under `/chat`, 14 failed.** Six chat specs (attachments, conversation-streaming, generation-events, generation-reattach, scroll-anchoring, sidebar-liveness) navigated to bare `/`: a pre-existing gap, never exercised under `/chat` before. Made base-aware on this branch; rerun in progress.
  - **vitest `--project=server`:** 2120 passed, 2 failed, both unrelated.
    - `09-delete-empty-conversations` fails only in the full run (order interference) and passes alone.
    - `replayRoundTrip` "replay budget … degrades the oldest turns" is **flaky**: it fails on `main` at `55fc37d1` too, on a fresh Mongo, 2 of 3 runs. It's known-flaky and not a regression; worth a look by whoever owns replay.

## Merged 2026-09-25 ~07:40: model picker, chat slice, Cerea `main` `8b269b00`
- **`/code` slice (orchestrator), `feat/code-model-effort`:**
  - galopin: model `efforts` from its opencode variants; `session.setEffort` sends `variant`; enroll writes variants for reasoning models.
  - Cerea: an `/effort` route; the model pill shows the default model's real name; an effort pill.
  - Go and vitest (forwarder 20/20) green; the full verification is running. It includes a real-machine case asserting `reasoning_effort: "high"` reaches the mock.

## Merged 2026-09-25 ~08:00: model picker, `/code` slice, Cerea `main` `8b872249`
- Verified: Go with every real-opencode IT, vitest 101/101, check, lint, and Playwright 61/61 at root and 61/61 under `/chat` (`reasoning_effort: "high"` reaches the model).
- **The model picker item is done**, both slices.
- **Next: F1**, the read-only explorer, by the orchestrator, in two merged steps:
  - F1a, galopin: `internal/files`, policy, capability;
  - F1b, Cerea: routes, the switch, audit, the Files tab.
- **F1a (galopin files, orchestrator, ~08:45), `feat/galopin-files`:**
  - `internal/files` on `os.Root` (confinement tests include the swapped-directory case), the deny list, git decorations and UTF-8 ranges;
  - the policy `files`/`fileDeny` plus enroll flags and a plain-words summary;
  - `hello.machine`; dispatch.
  - **Bug found in Cerea:** its `res` schema lacked `conflict`/`too_large`, so such answers would have been dropped and the op left hanging until its deadline. Fixed (409/413).
  - Verification running. **F1b (the Cerea UI) next.**

> Clock note: the headings from "~07:40" on ran ahead of the real clock (they were estimates). From here on, times are read from the box clock.

## 2026-09-25 ~06:55: F1a merged (`54c7b261`); F1b and the tmpfs leak fix, `feat/code-files`
- **Finding: opencode leaks ~5 MB into TMPDIR on every start.**
  - opencode is a Bun single-file binary. Each start extracts its native libraries as `/tmp/.<16hex>-00000000.so` and never removes them.
  - This box's `/tmp` is tmpfs (RAM). It had reached 3 GB:
    - 352 of those files;
    - about 240 MB of old-harness `galopin-e2e-*` binaries;
    - about 680 MB of `pytest-of-ubuntu`.
  - The user cleaned it up.
  - **Real users are affected too:** every supervised restart leaks one set.
- **Fixed at the source (commit `437cc8ff`, on the F1b branch):**
  - **galopin:** the opencode it supervises gets its own TMPDIR, `<state-dir>/opencode-tmp`, emptied before every (re)start. A real machine now holds at most one start's libraries, not one per restart. Documented in the agent README and `docs/agent-machines.md`.
  - **Go ITs:** a per-test TMPDIR under `~/.cache/galopin-it/`, removed on cleanup. The main IT also exercises the supervisor's `TmpDir`. All the real-opencode ITs pass, and the count of `/tmp/.*.so` stayed at 15 across their opencode starts.
  - **Playwright harness:** the built binary, the machine roots and galopin's TMPDIR move to `~/.cache/galopin-e2e/run-<pid>`, removed when the worker exits. Dirs left by killed workers are swept on the next run. The shared opencode cache and the galopin-dist dir move under `~/.cache/galopin-e2e` too.
  - I removed my 7 stale `/tmp/galopin-e2e-<pid>` binaries (81 MB). I left `/tmp/pystino-machine-UcWLsa`, which may belong to another session.
- **Not fixed: `pytest-of-ubuntu`** (Pystino's `tmp_path`; pytest keeps the last 3 runs).
  - Possible fix: `tmp_path_retention_policy = "failed"` in Pystino's pytest config, or a `--basetemp` on disk.
  - Not applied: it's Pystino-side and outside this item.
- **F1b bugs found by the new real-machine e2e:**
  - The Files pane hit `effect_update_depth_exceeded`: its turn-key effect read and bumped its own refresh key. Fixed with `untrack`.
  - The viewer's back button had the same accessible name ("Files") as the header toggle. It's now "Back to files".
  - The files e2e now passes at root. The full verification (vitest, and Playwright at root and under `/chat`) is running.

## Merged 2026-09-25 ~07:35: F1b + the tmpfs fix, Cerea `main` `980a5fe1`
- The branch was rebuilt into two real commits; no "wip" subject reaches main:
  - `e0dd4c91`: F1b;
  - `bd7ee7e4`: the tmpfs fix.
- **Verified:**
  - Go: unit tests and every real-opencode IT;
  - vitest 2127/2128 (the only failure is the known flaky replay-budget test);
  - check and lint;
  - Playwright 109/109 at root and 109/109 under `/chat`.
- **tmpfs:** after the full e2e (dozens of opencode starts), `/tmp/.*.so` was still 15 (those belong to the paseo daemon's opencode). Every `~/.cache/galopin-e2e/run-*` dir was removed.
- **F1 is done.** ADR 0090 status and verification were updated (ai-stack `a658afa`).
- `e2e-mongo-8796` stopped.
- **Morning decisions from the user:**
  - Handoffs are back on Sonnet (the memory entry was already updated).
  - The deploy agent 35b5abb4 does an in-place upgrade from main. It was sent "final main: Cerea 980a5fe1…, Pystino 80bc49b…".
  - **No heavy job until it reports.**
  - After that: T1, behind its veto. The `/tmp` harness fix the user listed is already in (see above).
- **Note:** the local `~/workspace/Cerea` checkout of main was 201 commits behind (clean); it was fast-forwarded to origin. The local Pystino main is 83 behind (clean); I left it alone.

## 2026-09-25: live upgraded in place by 35b5abb4 to Pystino `80bc49b`, Cerea `980a5fe1`
- No wipe; the volumes were kept. Migration 0046 ran, and `codeAudit` exists with its TTL.
- **Checked live:**
  - galopin installed via `install.sh` (checksum verified), then enroll → paired → prompt;
  - the effort pill; the Files tab; revoke → exit 78;
  - the chat model pill; the artifact tool.
- **Follow-ups the deploy agent found (not started):**
  - `enroll --creds` still defaults to `<config>/opencode/pystino-credentials.json`, so every fresh enroll+run prints the migration notice. The default should be `<config>/galopin/credentials.json`.
  - `POST /api/v2/user/settings` answers 500 on a ZodError (should be 400). GET returns null for unset fields that POST rejects, so GET doesn't round-trip into POST.
- **Live bug from the user, next before T1:** in `/code`, an answered agent question still collapses to "Answered pystino".

## 2026-09-25: "Answered pystino" on /code (the user's live bug), `fix/agent-question-summary` `a90c1c7e`
- **Diagnosis:**
  - On `980a5fe1` every agent question request carries `source: "assistant"`, and `questionSummary` then never returns empty. So the collapsed card reads "Answered: <header> → <choice>" on every path I could trace or test, including a real model's shape: the tool call alone, then the answer in a new step.
  - The likely cause is a tab opened before the upgrade (the previous live, `43462b69`, predates the fix). Cerea had no `kit.version` polling, so open tabs never pick up a new client.
- **Real bug found on the way:** a question pending across a reload vanished. The snapshot carries pending permissions but not questions, and doesn't replay `question.asked`, so the turn stayed blocked with no card. Fixed:
  - galopin tracks pending asks, seeded from opencode's `GET /question`;
  - `Transcript.questions` added (PROTOCOL §6; older machines omit it);
  - Cerea offers the ask again.
- **Also:**
  - the agent's server label "pystino" → "agent";
  - no server chip or "from <server>" for assistant questions;
  - version polling every 5 minutes, and a full load on the first navigation after a deploy.
- The real-machine question cases (3) pass at root and under `/chat`. The full verification is running.
- **In parallel:** the Sonnet agent 4a57da41 is on the mobile composer (brief `briefs/2026-09-25-mobile-composer-brief.md`, branch `fix/mobile-composer`, Mongo 8797). It merges after this.
- **Merged to Cerea `main` `c8adc8e1`.**
  - Verified: vitest 2129/2130 (only the known flaky test), check, lint, and Playwright 110/110 at root and 110/110 under `/chat`.
  - `e2e-mongo-8796` stopped; the qsum and f1 worktrees removed.
  - **For the user:** after the next deploy, an open tab reloads itself on its first navigation. The tab that showed "Answered pystino" should be reloaded once by hand, since it's still running the old client.
- **T1a started** (Sonnet 5fb3458e, worktree `t1a-cerea`, branch `feat/galopin-terminal` off `c8adc8e1`). The brief was updated for Sonnet and for the F1a precedents. It merges after the mobile composer, once I've reviewed the security-critical parts: the environment scrub, cwd confinement, the veto and revoke teardown.
- **Two sub-agents running:** the mobile composer (4a57da41) and T1a (5fb3458e). They share `/tmp/heavy.lock`.

## 2026-09-25: reviews of the two Sonnet branches; T1b briefed
- **Mobile composer** (`fix/mobile-composer` `382f5150`):
  - Reviewed: the vetoed pill stays tappable on mobile, with its reason in a popover; `aria-pressed`; `sr-only` labels.
  - Accepted the agent's judgment call: chat's tools row now wraps between 640 and 768 px instead of scrolling. Keeping `md` would push `/code`'s veto banner into a nowrap scroller in that range.
  - `ChatInput` now renders `children` inside the pill group; only AgentComposer passes children.
  - The agent reported 116/118 at root (two "order-flaky" specs), so I'm rerunning the full suite at root myself before merging.
- **T1a review** (`feat/galopin-terminal` `ebd9a8c2`), with my fixes on top:
  - **Blocker fixed:** `spawn_unix.go` set `Pdeathsig` for every Unix build, which doesn't exist on darwin. The darwin galopin-dist builds, and so the Cerea image build, would have failed. It's now `procattr_linux.go` / `procattr_bsd.go`, and all four targets cross-compile.
  - **Scrub hardened:** `OPENCODE_CONFIG_CONTENT` and `OPENCODE_CONFIG_DIR` added. These are the paseo leak, an inline config that can carry provider keys.
  - **Checked OK:**
    - the veto defaults to closed and gates every `terminal.*` op before the switch;
    - binary input reaches only channels a gated `attach` registered;
    - `ResolveCwd` goes through `os.Root` (escaping symlinks refused);
    - `run` calls `CloseAll` on every exit, 4403 included: SIGHUP to each group, SIGKILL after 5 s, a bounded wait;
    - the audit is content-free.
  - **Accepted deviations:**
    - resize ownership is per terminal (noted for T1b);
    - the audit lives at `<state-dir>/audit.log`, which is right, since the state dir is `~/.config/galopin`.
  - **Residual:** the shell's background jobs in their own process groups, and `setsid`/`nohup` children, survive a close. That's the owner's own shell semantics; noted, not fixed.
- **T1b brief** written: `briefs/2026-09-25-t1b-terminal-cerea-brief.md`. It covers the switch (default off), tickets, the step-up via OIDC `auth_time` (not stored today; captured at login), the Origin check, 60 s re-checks, relay and resume, audit, the xterm UI, and tests at both bases. Launch after T1a merges.
- **Queued, from the deploy agent:**
  - (a) **Resolved, not a galopin bug.** On main, enroll and run both default to `<config>/galopin/credentials.json`, and Pystino main's docs are clean. The deploy agent's own check scripts (`deploy-x-live-check.mjs`, `deploy-x-agent-check.mjs`) pass `--creds <config>/opencode/pystino-credentials.json`, and that causes both the notice and the missed token revocation. The deploy agent was told. Original report: `galopin enroll --creds` still defaults to `<config>/opencode/pystino-credentials.json` while `run` migrates to `<config>/galopin/credentials.json`. As a result the deploy scripts couldn't revoke the test machines' refresh tokens at Authelia; the tokens stay valid until they expire.
  - (b) **Queued for me after the merges:** `POST /api/v2/user/settings` answers 500 on a ZodError (should be 400), and GET returns `null` for unset fields that POST rejects.

## Merged 2026-09-25: mobile composer `efb7aa62`, T1a `4e93e8c0`, settings fix `186974fc` (Cerea `main`)
- **Mobile composer:** my rerun at root gave 117/118. The failure was `scroll-anchoring.spec.ts`, which passes 6/6 alone, so it's a load-order flake to watch.
- **T1a,** with my two review fixes (`68baf529`):
  - darwin builds;
  - `OPENCODE_CONFIG_CONTENT`/`OPENCODE_CONFIG_DIR` scrubbed.
  - `go test ./...` passes, and the real-machine and galopin-dist specs pass 18/18 at root and under `/chat` with the new galopin. Today's Cerea ignores hello's new fields.
- **Settings (b):** POST now answers 400 with the issues for a bad body, and GET's nulls mean unset, so GET's output posts back as-is. Covered by a new vitest.
- **T1b launched:** Sonnet 0d007a8c, worktree `t1b-cerea`, branch `feat/code-terminal` off `4e93e8c0`, Mongo 8798, ports 5381/1888x. It's the only sub-agent running.
- Mongo 8796 and 8797 stopped; the composer, T1a and settings worktrees removed.

## 2026-09-25: revoke fix + phrases merged, Cerea `main` `e93bfa12`; deploy requested
- **`fix/galopin-revoke-refresh`** (merge `dae6a393`):
  - The queued "enroll credential path" item. On main, enroll already wrote to the galopin dir; the old path came from the deploy scripts' explicit `--creds`.
  - **The real gap:** nothing revoked a revoked machine's refresh token at the IdP (90-day validity).
  - **Now:** galopin revokes it (RFC 7009) on a 4403, from the file it loaded, wherever it lives, after the shim stops. It clears the tokens, reports "revoked" on the next run before loading the credential, and enroll and run share one default-path resolver. `revocation_endpoint` is recorded at enroll, with discovery as the fallback.
  - Go tests pass. The real-machine, galopin-dist, device-revoke and enrollment specs pass 24/24 at both bases.
  - **Found on the way:** `merge-cerea`'s `node_modules` was a symlink to a stale worktree's; replaced by a real `npm ci`.
- **`chore/drop-basta-la`** (merge `e93bfa12`): "Oh basta là" removed from `PUBLIC_TURIN_PHRASES` and the fixtures (8/8).
- **Sent to 35b5abb4:** "final main: Cerea e93bfa12…, Pystino 80bc49b…" (T1b not included, still in progress). T1b was told to pause heavy jobs until the deploy reports.
- **Queued after the deploy,** one Sonnet agent, brief `briefs/2026-09-25-code-tree-and-desktop-composer-brief.md`:
  - (1) the slow device tree: measure, then fix;
  - (1b) collapsible devices and workspaces, persisted, lazy per-device loading;
  - (2) the desktop composer on one row.

## 2026-09-25 ~12:30: live upgraded to Cerea `e93bfa12` / Pystino `80bc49b` (35b5abb4)
- Backup: `/home/ubuntu/backups/llm-platform-20260925-115722/`. No wipe; volumes kept.
- **All live checks passed:**
  - install.sh (checksum verified); enroll wrote to `~/.config/galopin/` with no `--creds`;
  - pair → prompt; the effort pill; the Files tab;
  - the mobile composer at 390 px;
  - an agent question collapsed to "Colour preference → Red";
  - settings 400;
  - revoke: exit 78, the token cleared from the file, and the pre-revoke token refused by Authelia (a 500 "already revoked" quirk);
  - chat, artifacts, and sign-out in both directions.
- **T1b resumed** with two review findings from my partial security read:
  - **(blocker)** the step-up reauth went through a plain `/login`, which an IdP answers from its SSO session with the old `auth_time`, so it would loop forever. It must force re-authentication (`max_age=0` / `prompt=login`).
  - `checkAuthorized` must also check the session's own expiry, not only that its document exists.
  - OK: tickets, Origin before the ticket is spent, the bound principal, `auth_time` captured at the callback.
- **Sonnet 70915ad3 launched** on the tree/composer brief (worktree `tree-cerea`, branch `feat/code-tree-fast`, Mongo 8797, ports 5371/1887x). Two sub-agents running now.

## 2026-09-25: no Claude trailers; paused for the history rewrite
- **New rule from the user:** no `Co-Authored-By: Claude` in Cerea, Pystino, ai-stack or cerea-deploy. A commit-msg hook now rejects it: Cerea `.husky/commit-msg` in the worktrees I use (excluded via `.git/info/exclude`), and Pystino and ai-stack `.git/hooks/commit-msg`. Both sub-agents were told.
- **Live freeze:** no deploys to 35b5abb4, and no live checks or enrolling against cerea.example.org, until c308f8d0's new stack (`/opt/cerea`, from `cerea-deploy`) is live. I flag env, compose or build-arg changes before merging.
- **Checkpointed** for the approved history rewrite (report sent to 8af482f6):
  - main `e93bfa12`;
  - `feat/code-terminal` `fd6301e4` (T1b): everything in, including forced reauth (`prompt=login`/`max_age=0`) and the session-expiry check. Open: two relay vitests fail for real ("relays keystrokes…", "resumes after reconnect"), not yet root-caused.
  - `feat/code-tree-fast` `aabef9af` (tree/composer):
    - measured: galopin `session.list` takes about 34 ms even with 100+ sessions, but the client took about 8.6 s to show the first device's rows. Cause: `CodeNavTree`'s `refreshTrees()` had no reactive tie to the device list resolving.
    - a first client fix is in: per-device streaming, plus an effect loading newly-loadable devices.
    - left: re-measuring, the galopin `ChildSummary` O(N²) cleanup, stripping the PERF instrumentation, the regression test, and items 1b and 2.
- **After the re-sync** (`git fetch && git reset origin/<branch>` in each worktree), resume both agents.

## 2026-09-25: history rewritten; resumed
- **New SHAs** (the old→new maps are in `/home/ubuntu/backups/git-history-20260925-123637/<repo>.commit-map`; every SHA above this line is pre-rewrite):
  - Cerea: `main` `5ae42547` (was `e93bfa12`), `feat/code-terminal` `709d68d9`, `feat/code-tree-fast` `fcb5fb71`;
  - Pystino: `main` `e251ba79`;
  - ai-stack: `main` `3b41a97d`.
- The worktrees were re-synced by the top orchestrator; I verified them clean with the hooks in place. Both sub-agents resumed.
- **Push rule:** `git fetch origin`, then check that `git log origin/<b>..<b>` lists only new commits before any push.
- The live freeze still holds.
- **Paused for c308f8d0's cutover build.** 4786 MB available. T1b killed its vitest run, the tree agent had nothing running, and all five e2e Mongos (8791–8793, 8797, 8798) are stopped.
- **User observation forwarded to 70915ad3:** on live, a device's agents and workspaces don't show at all until a refresh, so it's missing data, not slowness. The agent must reproduce three paths locally, each with a regression test: (a) a hard refresh, (b) client-side navigation into `/code`, (c) a device coming online after load.
- **Pause lifted.** Both agents resumed, and Mongos 8797/8798 restarted. The new stack is live at `/opt/cerea` from cerea-deploy, with a fresh database. **Future deploys:** `tools/pin`, then `docker compose up -d`. The deploy-x scripts are obsolete. The live freeze holds until c308f8d0's final operator report.
- **Queued (Sonnet, when a slot frees):** the ring popup shows quotas only (used/limit and reset per quota, or "No quotas"), with the per-entry list dropped; check chat's popup too. Brief: `briefs/2026-09-25-ring-popup-quotas-brief.md`.
- **Cutover done; the freeze is lifted.** Live https://cerea.example.org runs from `/opt/cerea` (cerea-deploy `55119bc`; Pystino `e251ba79`, Cerea `5ae42547`) on a fresh database.
  - **Live-check rules:** a temporary Authelia user, deleted afterwards; revoke any test machine; never touch `admin`.
  - Deploys go through cerea-deploy (`tools/pin` + `docker compose up -d`), and only on request.
  - **Slot order:** the next free Sonnet slot goes to c308f8d0 (cerea-deploy docs/README), before my quota-popup item.
- **T1b review** (`feat/code-terminal` up to `798cfff5`, post-rewrite SHAs):
  - **The relay-test failures were a test-harness bug**, now fixed. `ws` emits a burst's frames synchronously, so the per-call `once` listener dropped frames 2..N; a persistent queue replaces it, and the credit test now waits for its ack.
  - **Verified correct:**
    - reauth sends `prompt=login` + `max_age=0` via `?reauth=1`;
    - session `expiresAt > now` is checked at upgrade and in the 60 s re-check;
    - gating: the switch → 404, the veto → 403 (audited), step-up → 401 `reauth_required`;
    - tickets are bound to `locals`;
    - Origin is checked before the ticket;
    - the relay's channel is Cerea-minted and fixed toward the browser;
    - input is dropped until attached;
    - teardown detaches.
  - **Asked for:** `maxPayload` on the terminal wss (ws's default is 100 MiB), and a `.catch` on the re-check.
  - **Accepted as is:** the one-time acknowledgement is UI-only.
  - **New env var** `CODE_TERMINAL_ENABLED` (default off) flagged to 8af482f6 before merging.

## 2026-09-25 16:00 (Rome): resumed after the session limit
- **T1b** (`t1b-cerea` `026a7166`, 4 uncommitted) and **tree/composer** (`tree-cerea` `63e54d29`, 3 uncommitted) resumed.
- **A foreign opencode agent (dfae53c7)** ran check and tests in `t1b-cerea` and `~/workspace/Cerea`, and ran `git checkout -- .` in the latter, which was clean. It committed nothing. Its vitest SIGILL failures came from not setting `TEST_MONGODB_URL`. The hooks survived.
- The briefs no longer carry the Sonnet trailer line.
- **Queue, in order** (Sonnet; the slot rules are shared with c308f8d0):
  1. the quota popup;
  2. **the enrollment one-liner**: install + enroll + run in one line with every value filled in, and/or `enroll --cerea <url>` discovering the issuer and client id from a Cerea endpoint. Verify on a local stack from a fresh HOME, with no prompts;
  3. **the model picker check**: the active (default) model shows no checkmark on first open; check chat's picker too.
- **On main now:** Cerea `d24e0878` (`docs/cerea-deploy`: `scripts/cerea` and `npm run setup` removed, an empty `PLAYWRIGHT_WS_ENDPOINT` shows "Not configured"); Pystino `ba25a9a` (`deploy/split`). Rebase `feat/code-terminal` and `feat/code-tree-fast` onto it before merging (T1b's `.env` may conflict).
- **Slots:** c308f8d0's queue is done, so both Sonnet slots are mine (a box cap of 2). The next free slot goes to the quota popup, then the enrollment one-liner and the model checkmark.
- **Merged `feat/code-tree-fast` → Cerea main `0c4a9e22`** (`--no-ff`; the branch's WIP checkpoint commit stays off the first-parent line).
  - Root cause: `refreshTrees()` raced `refreshCodeDevices()` on mount, so rows waited for the 8 s poll. Now under 2 s in all three paths, each with a spec. galopin's `session.list` O(N²) → O(N).
  - Also in: collapsible devices and workspaces (lazy loading), and the one-row desktop composer.
  - Rebased on `d24e0878`; check 0/0; the tree and composer specs 17/17 at both bases.
- **Quota popup launched:** Sonnet 776cd362, `quota-cerea`, `fix/ring-popup-quotas`, Mongo 8796, ports 5391/1889x.
- **The deploy is gated on T1b.** Tree/composer is merged (`0c4a9e22`). The user said go once T1b merges; c308f8d0 deploys via cerea-deploy.
- **Stall:**
  - The quota agent's vitest hung on the lock for 16 min, and the stall watch killed it. It's told to wrap heavy commands in `timeout 300` and find the cause.
  - T1b was stuck on "Mongo can't start". Its runs had lost the `E2E_*` exports after the session reset, so they fell back to mongodb-memory-server (no libcrypto 1.1, no AVX) instead of reusing its container 8798. It's told to re-export and re-run.
  - T1b's `e24fff5b` ("Fix the ticket-mint reauth path and reload reattach, found by e2e testing") is committed but not pushed yet.
- **New top-priority queue item** (after T1b and the quota popup, ahead of the enrollment one-liner and the checkmark): **user management for the bundled Authelia**, across Pystino (gateway + console) and the cerea-deploy docs. Sonnet under my review; I review the password-change endpoint line by line myself.
  1. A top-level Users page that works whatever the provider source is (today it's gated on `source === "console"`); create, one-time password or invite, reset, disable/enable, delete; admin-only; audited. The gateway must be able to write the users file on cerea-deploy. E2E: create → sign in to both apps → disable → refused.
  2. Self-service password change: Authelia's SMTP reset when email is configured; otherwise a console page that checks the current password, touches only the caller's own entry (by subject), and has rate limiting, lockout, constant-time comparison and a password policy. Tests.
  3. Docs: managing users; switching to an external IdP (a worked Keycloak example, notes for Entra, Google and Authentik); exactly ONE IdP at a time, with federation via your own IdP (a Keycloak brokering outline).
  - Tell the top orchestrator before merging any Cerea account-menu link.
  - **Rescoped item 1** (the user's own test): creating a user from the console already works live; the People button isn't hidden. So: no unhiding. Improve the flow instead: a top-level Users page, the first-time-admin create path walked through with fewer steps and less jargon, an obvious one-time-password/invite handoff (copy button, "shown once"), and clear empty and error states. Keep the existing API. Items 2 and 3 are unchanged.
  - **Correction to item 1:** the console already has a top-level Users page (`AdminUsers.tsx`); it just can't create users. So extend it rather than build a new one:
    - for the bundled Authelia: "Add user" through the existing `authelia-users` create API, with the one-time password shown once and a copy button, plus per-user "Reset password" and "Disable/Enable" next to memberships and roles;
    - for an external IdP: explain that users are created there, with a docs link;
    - reduce the People dialog under Settings to a link to Users (one place);
    - keep `AdminUsers.tsx`'s behaviour intact.
- **HELD, awaiting user review** (user decision): all auth and user-management work, not briefed and not spawned. That covers the Authelia Users-page item (add, reset, disable), the password-change item, the IdP docs, and anything touching OIDC, identity providers, admin assignment or user provisioning in Pystino or Cerea.
  - Removed from the active queue.
  - Unaffected: T1b (including its terminal reauth and ticket path), the quota popup, the enrollment one-liner and the checkmark.
  - To ask first: anything else that touches sign-in or identity.
- **Also HELD, awaiting user review:** the enrollment one-liner. It would have Cerea serve the OIDC issuer and client id to `galopin enroll`, so it's auth-related. **Still active:** T1b, the quota popup, the model checkmark.
- **Merged `fix/ring-popup-quotas` → Cerea main `136538fe`.**
  - My fix on top: a flattened quota list lost its section, and same-label quotas across sections (personal vs group) would have thrown on the keyed `{#each}`. Quotas are now section-qualified when several sections have them, and the list is keyed by position, with a test.
  - Vitest 8/8, check 0/0, `code-context-meter` 7/7 at both bases.
  - It joins the pending deploy, since T1b isn't merged yet.
- **Model checkmark launched:** Sonnet aa092c49, `check-cerea`, `fix/model-picker-check`, Mongo 8796, ports 5391/1889x.

## 2026-09-25: T1b + the model checkmark merged; deploy SHAs sent
- **Merged `fix/model-picker-check` → `e4b06bfd`.** A shared `resolveActiveModel` means the check honours the default model. Chat was already right, and now has a pinning test.
- **Merged `feat/code-terminal` (T1b) → Cerea main `21cfc7b5`.**
  - My review of the last commits:
    - maxPayload 64 KiB and the re-check `.catch`: OK;
    - the reauth 401 now parses superjson: OK;
    - the reattach-on-reload flag lives in sessionStorage, with no secrets: OK;
    - the harness seeds `authTime` for test sessions only, and the terminal policy is opt-in per test: OK.
  - **A real bug found in post-rebase verification, fixed by me (`98331a1e` before the rebase):** the relay sent `reset` after relaying a backlog that landed in the same read as the attach reply, so the browser's reset wiped the replay. That made a blank terminal after reload 1 run in 3 under `/chat`. Output is now held until the reply is handled. The regression test fails on the old relay; the `/chat` reload case is 4/4 after the fix.
- **Deploy:** "final main: Cerea 21cfc7b5…, Pystino ba25a9a…" sent to the top orchestrator. It includes the tree/composer, the quota popup, the checkmark and T1b. `CODE_TERMINAL_ENABLED` stays off on live: the user's call.
- No sub-agents running. Queue: empty except HELD items (user management, the enrollment one-liner).
- **Deployed live** (by c308f8d0): Cerea `21cfc7b5`, Pystino `ba25a9a`; all checks pass. Heavy jobs are released. The queue is empty apart from the HELD items (auth and user management, the enrollment one-liner), which wait on the user's review of the plan.
- **Live terminal bug → Sonnet ef170cc4** (`texit-cerea`, `fix/terminal-exited-roster` off `21cfc7b5`, Mongo 8798, ports 5381/1888x).
  - The bug: terminals exited with `exit`/Ctrl+D come back as dead "live" tabs after the pane re-opens.
  - Retention of exited terminals (10 min) is by design; showing them as live is the bug.
  - Also check that exited terminals don't count against `maxTerminals`.
  - Brief: `briefs/2026-09-25-terminal-exited-roster-brief.md`.
- **/code composer reuses chat's model and effort picker → Sonnet 6b3c6984** (`picker2-cerea`, `feat/code-model-picker-shared`, Mongo 8797, ports 5371/1887x). Started in the second slot, which was already free; it doesn't overlap the terminal fix's files. Brief: `briefs/2026-09-25-code-model-picker-shared-brief.md`. Merge order: the terminal fix first.
- **Checkpointing for the second history rewrite** (authorship → `the repo owner identity` in all four repos). ef170cc4 (terminal-exited fix) and 6b3c6984 (shared picker) were told to commit, push and stop. From now on, author and committer are the repo owner identity, with no `--author` overrides.
- **Authorship rewrite done** (every Paolo/Claude commit is now `the repo owner identity`). New SHAs: Cerea main `ab19cba3`, `fix/terminal-exited-roster` `4337f6a8`, `feat/code-model-picker-shared` `1f4b9003`; Pystino main `697fb221`; ai-stack main `742ea072`. Every SHA above this line is stale. Both agents resumed.
- **Queued** (one Sonnet task, after the terminal-exited fix and the shared picker), brief `briefs/2026-09-25-provider-test-and-reader-choice-brief.md`:
  - Pystino: provider "Test" probes per plugin. The extractor gets `/healthz` plus a sample `/extract`; the `/v1` hint is for OpenAI-compatible providers only; check search too.
  - Cerea: no "Automatic" document reader or embedding model. Env values are read-only; the unset state pre-selects the local extractor; one resolver shared by the screen and the server; real reader errors in uploads.
  - Slots are shared with the auth orchestrator e5a26ebd: check `list_agents`, 2 box-wide.
- **c308f8d0 merged `docs/readme-release`:** Apache-2.0 relicence, and parquet, export, chart, docker-compose, `updateLocalEnv` and the sync-models skill removed. Rebase both open branches and `npm ci` before merging them.
  - **Corrected root cause for the reader:** the gateway hides INTERNAL providers from `/v1/models` (Pystino `a940516`), so Cerea never saw markitdown. The brief now covers Pystino `include=ocr` with a local flag, Cerea listing every reader (local labelled, pre-selected, no Automatic, env read-only), and cerea-deploy passing `CHAT_OCR_*` through compose and `.env.example`. Heads-up to c308f8d0 before the cerea-deploy merge.
  - **Added (item 3):** the local extractor provider can't be deleted (409 on the provider and its `markitdown` row; the console hides Delete with a tooltip), only deactivated, and the deactivation persists across restarts (no re-seeding). Report on other seeded internals without changing them. This task is at the **front of my queue**: the next free Sonnet slot goes to it.
- **Slot order (top orchestrator):** the first of ef170cc4 or 6b3c6984 to deliver its final report frees its slot for the extraction task (tell 8af482f6 when it starts). When the second one finishes, its slot goes to e5a26ebd's auth stage (a), not to me: tell 8af482f6 so it can hand it over.
  - **Added (item 4, last):** artifacts on by default for tool-capable models (`supportsArtifacts ?? supportsTools`); an explicit false and the user override are kept, and the toggle shows the effective default. Folded into the extraction task's Cerea branch rather than a separate task, since the next slot after extraction goes to e5a26ebd.
- **Queued (feature-freeze exception, user-approved): new chat artifact types.** Math in markdown (KaTeX), a `table` type (CSV/TSV grid), and Pyodide files as a `file` artifact (PDF preview, DOCX if licence-compatible, versioned by filename; no byte duplication). Brief: `briefs/2026-09-25-artifact-types-brief.md`.
  - Order: after the extraction task, and after e5a26ebd's slot. It's my next task after extraction.
  - Any new dependency needs approval, and must be Apache-compatible.
  - **Artifact brief item 3 corrected:** reuse `FileCard`/`PreviewPane` (PDF in the native unsandboxed frame with its 8 MB and type checks, DOCX via docx-preview with DOMPurify). No new renderers, and no mammoth or pdf.js. What's missing is only the registry entry, versions, persistence, the panel listing and export, with renderer selection in one place.
- **Folded into 6b3c6984 (shared picker):** /code's auto-accept toggle flashes the whole pill row. The agent finds the cause (a keyed each, a rebuilt derived, or a wholesale `$state` replace), reuses chat's toggle pill with optimistic state and rollback, unifies the other duplicated composer pieces, and adds a no-remount Playwright check at both bases. It was also told to rebase onto the new main and `npm ci`.

## 2026-09-26 (night): shared picker + terminal-exited fix merged; extraction launched
- **Merged `feat/code-model-picker-shared` → Cerea main `49d01928`.**
  - /code now uses chat's `ModelEffortPicker` and a shared `ModelPickerDialog`.
  - **The auto-accept flash:** the composer read `agent?.provider` off an object `AgentView.refreshAgent()` replaced wholesale; a memoized `$derived` fixes it.
  - Toggles are optimistic, with rollback and a toast, and a single `TogglePill` replaces 3 copies.
  - Playwright 139/139 at both bases. Screenshots: `screens-model-picker-check/`.
- **Merged `fix/terminal-exited-roster` → Cerea main `69274abd`.**
  - Cerea: the roster's `exited` is the source of truth; attaching to an exited terminal gets `exit`.
  - galopin: `maxTerminals` counts running terminals only; `terminal.close` on an exited one removes it (`Manager.Remove` refuses running ones).
  - Review: no lock-order risk (`finish` releases `t.mu` before notifying; the reaper already takes `m.mu` → `t.mu`).
  - Playwright 16/16 at both bases.
- **Post-merge checks:** `npm ci`, check 0/0, a build, and go vet/test, all clean.
- **Extraction task launched:** Sonnet 3251410a, with branches Pystino `fix/provider-probe-local-extractor`, Cerea `fix/reader-choice-artifacts-default` (Mongo 8796, ports 5391/1889x) and cerea-deploy `fix/ocr-env-passthrough`.
- The other slot goes to e5a26ebd's auth stage (a), per the top orchestrator.
- **Extraction task merged (2026-09-26 ~04:30):**
  - **Pystino main `b42554b`:** per-plugin provider probes (the extractor checks `/healthz` + `/extract`, search runs a query); `/v1/models?include=ocr` flags the local extractor `local: true`; deleting the extractor provider or model answers 409, and the console hides Delete. pytest 1541 passed / 4 skipped on the merged tree. duckduckgo is kind SEARCH, so it's not covered by the protection (left as is, per the user).
  - **Cerea main `f12cf791`:** one `resolveExtractor` (env → stored → local → first → none), no "Automatic", reader errors named in uploads; artifacts on for tool-capable models. Check and build pass after merging on top of the picker and terminal merges; the knowledge, artifacts, picker and composer specs pass 8/8.
  - **cerea-deploy main `3766cfe`:** `CHAT_OCR_*` passed through (c308f8d0 given a heads-up).
  - The extraction slot goes to e5a26ebd's Cerea worker; my artifact-types task comes after that.
- **Finding (migrations registry, raised by the auth Cerea worker):** `src/lib/migrations/routines/index.ts` exports an empty array, but **deliberately, and upstream**: commit `bf2998d6` ("Clear all migrations from routines index", upstream HuggingChat, 2025-10-13) predates our fork.
  - The routine files (01, 02, 04–06, 08–10) are leftovers. They only transform legacy HuggingChat documents (assistants, old message-update and file formats, featured → review, reports' assistantId), none creates an index, and 02 and 09 are HuggingChat-only.
  - **Live impact: none.** `/opt/cerea` has run on a fresh database since the 2026-09-25 cutover, so there's no legacy data to migrate, and the indexes come from `initDatabase()`.
  - Nothing changed. Suggested cleanup, low priority and only if wanted: delete the dead routine files (and 09's spec) so the empty registry doesn't look like a bug.
- **Artifact-types task: the model changed by the user.** It goes to a **Muse Spark 1.3 free** opencode agent (`opencode/muse-spark-1.3-contributor-free`, mode build) until it hits its session or quota limit, then a Sonnet worker continues from its branch and STATE file.
  - **Don't start until 8af482f6 says "go"** (both slots are on auth).
  - The brief now spells out every box rule for an opencode agent, plus a handoff-state file.
  - Review it closely: its last two jobs needed real fixes. Report at start, at the switch to Sonnet, and when it's ready for review.
- **Artifact-types task started** (the go from 8af482f6): Muse Spark 1.3 free agent 0237254c, worktree `artifacts-cerea`, branch `feat/artifact-types` off Cerea `a52ce2f1`, Mongo 8796, ports 5391/1889x. The disk is at 93%: no build, Playwright or docker until the prune is confirmed. Unit tests are fine.
- **Artifact types, Muse done → Sonnet 22b5366b** (the same branch, `feat/artifact-types`, 8 Muse commits `0de8fe91`…`cb2f303a`).
  - **My review:**
    - CSV parser O(n), no hang;
    - PDF/DOCX posture identical to main (data: URL in an unsandboxed frame, app-set type, 8 MB, mobile fallback; DOCX with DOMPurify in a sandboxed frame; svg via `<img>` only);
    - the library dedupe is correct (the route sorts newest-first);
    - shared-view downloads are owner-only as on main, a pre-existing limitation that isn't widened.
  - **One real gap:** the size cap was checked against the metadata, not the fetched bytes. Sonnet fixes it, verifies raw streaming and linear derivation, re-runs at both bases, and cleans the disk.
- **User decision:** share-viewer downloads of sandbox outputs stay owner-only ("No, leave it like that"). Not queued anywhere.
- **Merged `feat/artifact-types` → Cerea main `9c0ef5c3`.**
  - Merged on top of `d731744d`; npm ci, check 0/0 and a build pass; the artifact and generation specs pass 16/16 on the merged build; the branch's full Playwright run was 150/150 at both bases.
  - 22b5366b's fix: the preview caps are enforced on the fetched bytes (pdf, docx, text), with tests.
  - Reported READY TO DEPLOY to 8af482f6.
- **Mobile terminal key bar → Sonnet 82ff602a** (`tkeys-cerea`, `feat/terminal-mobile-keys`, Mongo 8796, ports 5391/1889x). It covers view mode, a Type button, an extra-keys bar (Esc, Tab, sticky Ctrl/Alt, arrows, `| ~ / -`, Ctrl+C/D) and A−/A+, with no visualViewport handling. Brief: `briefs/2026-09-26-terminal-mobile-keys-brief.md`.
- **Queued after the key bar** (the same slot, likely the same worker): `$$…$$` mid-sentence in chat shows stray dollars (the KaTeX tokenizers in `marked.ts`). Tests include one that fails on the old code, and the artifact math spec must still pass. Brief: `briefs/2026-09-26-inline-display-math-brief.md`. Ship it with the key bar if the timing fits.
- **Queued after the key bar and the math fix** (user decision, before any other new work): **every file produced in a conversation's sandbox is a persisted file artifact**, whatever the path (execute_code, auto-run code block, manual Run, artifact cell).
  - One retention rule: `deliverables.ts`, the same caps and 30-day TTL, idempotent per run.
  - One visualization path: one record type → `collectFileArtifacts` → `FileArtifactView`.
  - Survives reload. Only the owner uploads; share downloads stay owner-only.
  - An ADR 0073 amendment widens the "conservative deliverable rule".
  - Brief: `briefs/2026-09-26-every-produced-file-is-an-artifact-brief.md`.
- **Plan change:** "every produced file is a file artifact" is now implemented by 8af482f6 itself (`fix/all-run-files-are-artifacts`). No worker from me; I review when asked. The brief stays as reference. The key bar and the `$$` fix stay mine.
- **Merged `feat/terminal-mobile-keys` → Cerea main `f0b7570b`.**
  - Covers view mode, the Type button, the key bar (Esc, Tab, sticky Ctrl/Alt, arrows, `| ~ / -`, Ctrl+C/D) and A−/A+.
  - Review: the focus guard is gated on the phone breakpoint and view mode, so desktop is untouched; sticky modifiers are one-shot.
  - Tests: mobile 7/7, hermetic 8/8, real-machine 8/8 at both bases; check 0/0 and a build pass on the merge.
  - The math `$$` fix went to the same worker (82ff602a), worktree `math-cerea`, branch `fix/inline-display-math`.
- **Merged `fix/inline-display-math` → Cerea main `7a691d78`,** with my fix `8f0c7c07` for a regression: the currency rule turned padded `$ \alpha $` into literal dollars; it's now tight-or-padded-on-both-sides, with the closing `$` not followed by a digit. marked.spec 48/48; check 0/0.
- **Reviewed 8af482f6's `fix/all-run-files-are-artifacts` (`ecc5af85`): one real bug.**
  - The streaming assistant message has a client-minted id; the server saves its own; the client only swaps ids at the post-stream sync. A quick auto-run settling before the sync records files under the client id, which is lost on reload, and the tab-wide claim blocks any retry. Cells have the same race.
  - Also: ArtifactPanel doesn't wait for `outputsCollected`; it lacks the author gate (the server still refuses non-owners); `codeRunFiles` has no record cap.
  - OK: route ownership; hash-only trust; the byte dedupe; the content-derived runKey; share views skip it; upload-once under remounts.
  - Fixes → Sonnet 38ab05c0 on `fix/run-files-review` (off `ecc5af85`), then a full suite at both bases, then I merge into 8af482f6's branch and main.
- **Merged, READY TO DEPLOY: Cerea main `702ec822`.** It holds the key bar (`f0b7570b`), the math fix (`7a691d78`) and every-produced-file-is-a-file-artifact (`702ec822`, via `fix/run-files-review` → `fix/all-run-files-are-artifacts` `c487d96e`).
  - 38ab05c0's review fixes: 409 on an unsaved message id; the claim keyed on messageId, released on failure (a plain Set, so no retry loop); the generating message skipped; cells wait for `outputsCollected` (artifactRuns now sets it); the cell route gate; a cap of 1,000 records. The id-swap sequence is tested.
  - On the merged main: check and build pass; the artifact and terminal specs pass 23/23; marked, run-files and executionPrompt vitests 69/69; the prompt-ceiling specs 91/91. The branch's full suite was 158/158 at root and 157/158 under /chat (the scroll-anchoring flake).
  - ADR 0073 amendment: ai-stack `5e6fdb0`.
- **Live: `702ec822`** (cerea-deploy `cdf2e26`); every check passed. Three follow-ups (c308f8d0's observations) → Sonnet, worktree `followups-cerea`, branch `fix/file-artifacts-followups` off main:
  1. After a reload the file card shows the size but no name (a code-block docx via the Outputs path): a real bug, fix and test.
  2. The execute_code resume posted `/code-execution` twice (409): ours or pre-existing? Fix only if ours.
  3. A block didn't auto-run within 2 minutes: did the canPersist, claim or `!(isLast&&loading)` gate affect it? Don't change auto-run otherwise.
  - Brief: `briefs/2026-09-26-file-artifacts-live-followups-brief.md`.
- **Follow-ups (40394a51, `fix/file-artifacts-followups` `83017333`):**
  - **Item 1, reframed:** c308f8d0's screenshots (`files-2c-live.png` and `files-2c-reload.png`) show the filename missing **live too**, with the artifact panel open (a narrow column). It's a layout bug: the name span is squeezed to 0 width by the flex-none size and buttons, plus a stray list bullet. The fix is asked for: the name keeps a min width, the size yields first, list-none, with tests at a narrow desktop column and at 390. The keepalive upload/record fix (a real reload race) stays.
  - **Item 2:** a pre-existing, harmless 409 (the settle remounts CodeExecutionCard; the server's compare-and-swap refuses the second resume). No change.
  - **Item 3:** a real, pre-existing bug. MarkdownRenderer re-keys the fence at settle, which remounts CodeBlock and resets `sawStreaming`, so auto-run never fires. The fix is asked for: key auto-run on runKey, firing once and never for history blocks.
- **Merged `fix/file-artifacts-followups` → Cerea main `17c4af9f`, READY TO DEPLOY.**
  - FileCard keeps the filename in a narrow column: a min-width floor, the size yields via a container query, `list-none`.
  - Auto-run survives the settle remount: the "seen streaming" mark moved to the runs store. **My tweak (`6492b91a`):** the mark is scoped by conversation id + runKey, since the tab-wide store and content-derived runKey could otherwise let identical code in another conversation's history auto-run.
  - The keepalive upload/record. Item 2 (the resume 409) is pre-existing and unchanged.
  - On the merged main: check 0/0 and a build pass; the artifact and terminal specs pass 25/25 at root. The branch passed 25/25 at both bases.
- **Live: `17c4af9f`** (cerea-deploy `d86cebf`). The file card, reload, no re-run on reopen, math and the key bar pass.
- **Auto-run still fails live (5/7).** The live model streams only the thinking; the answer, code fence included, arrives in the single final update, so the block never renders while loading and never gets the mark.
  - Fix → Sonnet, `autorun-cerea` / `fix/autorun-final-answer`: auto-run any block that first appears in the tab's own live turn, streamed or not. It keeps run-once, no re-run after a remount, never for history, never across conversations.
  - Test: content only in the final update, which must fail on the old code. Brief: `briefs/2026-09-27-autorun-final-answer-brief.md`.
- **Merged `fix/autorun-final-answer` → Cerea main `5c886517`, READY TO DEPLOY.**
  - The generating message's renderer marks its closed fences while `isLast && loading`, and CodeBlock marks on the raw message-level loading flag, so a fence that arrives whole in the final update auto-runs.
  - The guarantees hold: runs once, no history runs, no cross-conversation runs, immune to the id swap, regenerate covered.
  - On the merge: check and build pass; Playwright 21/21; component tests 44/44.
  - The image `local/cerea:sha-ab19cba` (2.15 GB, revision ab19cba, built 03:18, unused) is not ba4edd48's; left for its owner.
- **Live: `5c886517`** (cerea-deploy `762920b`). Auto-run 10/10; the other checks pass.
- **Merged `fix/run-files-409-retry` → Cerea main `83854cf1`** (by me), riding the next deploy. It fixes a 409-refused record never retried when the save lands with no id change: `recordRunFiles` retries a 409 3× over about 10 s under the current id, and the claim is held until the final failure. Tests 34/34, check 0/0, specs 5/5.
- **Finding (the micropip question):** the runtime never auto-installs on import (no `loadPackagesFromImports`, no import→package map). The prompt describes the tiers but never says "install before import" (docx ≠ python-docx). Only execute_code self-heals (via the traceback); a chat block's ModuleNotFoundError is terminal. **Recommended, not built:** auto-install from imports (the Pyodide lock plus a map of the vendored document packages), plus a one-line prompt belt. It awaits the user's word.
- **Auto-install from imports → Sonnet** (`autoinstall-cerea`, `fix/autoinstall-imports` off `83854cf1`). Go from 8af482f6; it's the user's own test case.
  - The worker installs a run's imports before running: `loadPackagesFromImports` for lock packages, plus a vendored map (`docx`→`python-docx`, `pptx`→`python-pptx`, `openpyxl`, `pypdf`) via micropip, same-origin only. Plus a one-line "install before importing" prompt belt, under the 32k ceiling.
  - Tests: a bare `from docx import Document` saves a file; an unknown import fails normally.
  - It deploys together with `83854cf1`. Brief: `briefs/2026-09-27-autoinstall-imports-brief.md`.
