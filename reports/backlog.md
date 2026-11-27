# Backlog

**State on 2026-11-20: Cerea 0.60.4 released and live, Pystino 0.33.5.** Cleaned and aligned with GitHub issues on 2026-11-19: every row checked against `origin/main`, release tags, PR and issue states. Closed rows and their PR or version are in `backlog-archive-2026-11-19.md`; older detail is in `backlog-archive-2026-11-06.md` and `backlog-notes-2026-11-06.md`. IDs are stable. Update this file, don't keep lists in chat. Rows marked "(verify)" were not conclusively checked.

Prefixes: P = Pystino, C = Cerea (including the galopin agent under `agent/`), G = galopin. Every open issue in both repos has a row below.

## 0. Current priorities

| ID | Item | Status | Next step |
|---|---|---|---|
| P31 | Classifier provider allowlist: classifiers may use only models of providers an admin ticks (empty by default), replacing PR #61's "Allow remote classifiers" switch; fail closed for a stored classifier on a provider no longer allowed | Parked on owner go; Pystino PR [#61](https://github.com/paoloviviani/Pystino/pull/61) open | Rework #61 when the owner says go |
| C99 | Privacy-withheld files follow-ups: (a) vision-refused images withheld and (c) owner one-time download shipped in v0.60.0 (#304). Left: (b) no backfill for files stored before #193 | Backlog | Decide whether (b) is worth a migration |
| C149 | Standing engine pin bumps: opencode now 2.4.1 (v0.64.1, #354; #352 and #289 closed). goose: 1.60.1 ([#288](https://github.com/paoloviviani/Cerea/issues/288)) and 1.60.2 ([#322](https://github.com/paoloviviani/Cerea/issues/322)) pass the suite | Pins on main: opencode 2.4.1, goose 1.57.0 | Bump goose to 1.60.2, close #288 |
| C148 | Secret manager plus credential injection at egress (write-only per-workspace/user secrets; the cloud-workspace egress proxy injects the real credential). Report `2026-11-18-mistral-secrets-knowledge.md` | Deferred to the owner; not started | Owner decision |
| C166 | Flaky e2e `tests/chat-code-run-pause.spec.ts:16` ("a run paused in the background past the original deadline resumes…", expect toBeGreaterThan) failed once in #364 CI, passed on re-run (2026-11-25) | Confirmed flake | Fix at the cause after the next release |
| C170 | Flaky e2e `tests/code-machine-parity.spec.ts:929` ("opencode's own question tool becomes the SAME card as chat's ask_user_question"): 180 s click timeout, failed once each on #369 and #371 on 2026-11-26 (unrelated diffs), passed on re-run. Test-only flake, fix at the cause after the release | Open | — |
| C171 | Flaky e2e `tests/mcp-apps.spec.ts:380` ("the app view shows with its run folded into a summary, and folding never reloads it"): the app iframe never appeared within 45 s; failed once on #378 (2026-11-26, branch does not touch MCP Apps), passed on re-run | Confirmed flake | Fix at the cause after the v0.67.0 release |
| C172 | Desktop window browser follow-ups from the #378 delta review (all Low): write `cdp-endpoint-window` into the window browser's private dir instead of galopin's; the keep-alive refreshes only the caller's own lease; limit the window secret to `/cdp` | Backlog | Small PR after v0.67.0 |
| C173 | Flaky client test `McpAppFrame.svelte.test.ts` ("expected 1 to be less than 0", a timing assertion): failed once on #388 CI (2026-11-27, PR did not touch it), passed on re-run | Confirmed flake | Fix at the cause after v0.67.0 |
| C174 | galopin: stop sending "X is waiting for approval" notices to the parent session (the card reaches the owner anyway; the parent reads the child with session_read). Owner go 2026-11-27 | Agreed | After v0.67.0 |
| C175 | Auto redesign: the **outside access** row of Workspace → Agents → "On Auto, per kind of action" gets a fourth option, **Secret rules** (alternative to Reviewer): reading is free; a card only when a secret would leave the computer. Full design, open points and code pointers: `reports/2026-11-27-parked-auto-secret-rules-and-session-archive.md`. Local branch `wip/env-blind-narrowing` holds the computed-word narrowing | **Parked** (owner 2026-11-27: no tokens now) | Owner answers the 3 open points, then build |
| C176 | galopin agent tool `session_archive {target}`: an orchestrator archives the sessions it spawned (own delegates and task subagents only; Allow runs, Ask card, Plan refuses; busy sessions refused; audit row). Note: `session.archive` and `session.delete` both delete today (dispatch.go → DeleteSession). Design and tests: `reports/2026-11-27-parked-auto-secret-rules-and-session-archive.md` | **Parked** (owner 2026-11-27) | Owner decides archive vs delete, then build |
| C177 | Desktop: a slim custom title bar on macOS (`titleBarStyle: hiddenInset`): the server name, the profile switcher and the tabs sit beside the traffic lights, and the browser panel's toolbar (including the new Home button) moves next to them. Windows and Linux keep the OS title bar. Full frameless on all OSes was considered and not chosen (close/minimise/maximise, drag, resize edges) | Agreed (owner 2026-11-27, option 1) | After v0.67.2 |
| C178 | Desktop nav-guard follow-ups from the #395 review (all Low, pre-existing): a window-open to the server's own origin is loaded in the Cerea view instead of opening outside (navGuard.ts:87 early-return precedes the window-open check), and that path never clears a live IdP excursion (main.ts setWindowOpenHandler doesn't call apply). Neither escalates: no third origin becomes reachable | Agreed | Small PR after v0.67.2. Also document that a user-chosen server is fully trusted: the app reaches its own origin and the IdP its enroll.json declares (docs/dev/desktop-app.md) |
| C179 | Desktop nav-guard tests: pin at the chain level that a stale chain whose from is the IdP cannot hop to the IdP after the excursion expires, and that hops within a live excursion don't extend it (both are only pinned at the guard level today, navGuard.test.ts) | Agreed | Same PR as C178 |
| C180 | Browse: a runtime `approval_required` with no grant (an element the runtime classifies commit and the loop classified safe) now hard-stops the task; it used to surface as one failed step the model could recover from. Consider mapping it to a fresh ask (fail-closed today, from the #396 review) | Proposal | Owner to weigh recovery vs strictness |
| C181 | Desktop smoke covers what Macs hit: a userData path with a space, a fake server under `/chat`, and (where possible) the real renderer sandbox. v0.67.3's browser bug (bridge socket under "Application Support", `%20` in the ws+unix URL) shipped because CI tests none of these. The smoke with a space in TMPDIR currently does not reach READY: find that cause first | Agreed (fix shipped in v0.67.3, #400) | Then add AGENTS.md "Debugging a failure only the user can see" (owner to OK the text) |
| C150 [#270](https://github.com/paoloviviani/Cerea/issues/270) | Clone a Git repository when creating a new workspace | Open, no code on main | Schedule |

## 1. Owner decisions and ideas

| ID | Item | Status |
|---|---|---|
| C116 [#278](https://github.com/paoloviviani/Cerea/issues/278) | Cloud workspaces: hosted galopin sandboxes (ADR 0115 class P): own switch `SANDBOX_MACHINES_ENABLED` (refused today), egress proxy, persistent volume, idle stop, OpenShell evaluation first | Open design, owner's decision; not started |
| P36 | Vision chat model as an OCR reader on `/v1/ocr`: admin marks an image-capable chat model usable for OCR; the extractor draws page images, the gateway transcribes each page with a fixed prompt (temperature 0) into `pages[]`; text-layer pages and Office files stay on markitdown (recommended) or every page goes to the model; per-model page concurrency so chat keeps the GPU; token billing; privacy rules treat it as a reader. Drawbacks: invented or "corrected" text, slower than RapidOCR, output-token limits per page. About 2–3 days | Parked by owner 2026-11-22; open questions: go, and scanned-only vs all pages |
| C160 | App links in replies (e.g. Joplin): a deployment setting `CHAT_LINK_SCHEMES=joplin,obsidian,zotero` lets those schemes render as links (v0.62.1 renders unknown schemes as plain text). For Joplin the in-app link is `joplin://x-callback-url/openNote?id=<note id>` (desktop app; mobile support uncertain). The owner's connector (github.com/Alexander-Zhukov/joplin-server-mcp, MIT) returns ids and markdown bodies but no URLs: either a fork/upstream PR adding the deep link per note, or a connector instruction telling the model the link shape. That connector also disables TLS verification (`verify=False`) and rewrites internal note links to `(resource:<id>)` unless `raw=True` | Parked by owner 2026-11-22 |
| C161 | Evaluate unkernel (github.com/pithings/unkernel) as a browser-side "full Linux" code runner next to Pyodide: Linux 7.x compiled to wasm with an arm64 user-mode emulator, unmodified Alpine/Debian binaries (Python, Node, apk), runs on the user's device; about 10 MB download to a shell on a phone (per its docs), prompt in ~0.3 s, CPU-heavy work well behind native. Cautions: young (one main author, Nov 2026), no security claims or seccomp, JSPI browsers only (Chrome/Edge 137+, Firefox 153+, Safari 27+; Pyodide stays as fallback), networking via a Wisp proxy we would host (egress under privacy rules), kernel GPL-2.0 (ship as a separate module with source; SDK MIT). Spike: run the `scripts/pyodide_*_check` document checks under it, compare speed, size, breakage | Parked by owner 2026-11-22 |
| C162 | Visibility plan: README + demo merged (#353), topics done, awesome-mcp-clients PR #433 open, social preview upload by the owner; **late January 2027**: Reddit posts and awesome-selfhosted (owner, from 2027-02-02). Details and drafts: `reports/2026-11-24-visibility.md` | In progress |
| C163 | Pairing without the Confirm step when the sign-in happens in a browser on the computer itself (local redirect proves presence); keep Confirm only for the link-and-code sign-in from another device (device-code phishing). Amends ADR 0089. About half a day | Parked by owner 2026-11-24 |
| C167 | WebMCP: the W3C proposal (github.com/webmachinelearning/webmcp; `navigator.modelContext.registerTool`) lets websites expose tools to browser agents. Uses: (1) browser use calls a site's registered tools instead of clicking (fewer steps/tokens, commits still get approval cards); (2) Cerea registers its own tools so a browser's built-in assistant can drive it. webmcp.dev is a non-compliant early prototype, not the standard. Check browser support/adoption before building | Parked by owner 2026-11-25 |
| C151 [#290](https://github.com/paoloviviani/Cerea/issues/290) | WYSIWYG slides editor: fork Small Reveal into the slides artifact | Open, owner's decision |
| C80 | Per-workspace switch for a project's own opencode setup / AGENTS.md (today an enroll flag) | Owner decision |
| C79 | Session sharing: `galopin attach`, goose shared history (report `2026-11-06-session-sharing-goose-opencode.md`) | Owner thinking |
| C83 | Workflows: multi-step recipes with typed outputs, approval gates, shared definitions | Discussed; first process and run-as open |
| C84 | Meeting notes: import/record, transcript, template summary, actions via connectors | Discussed; online vs in-person open |
| C85 | Memory as a knowledge graph, per user/project | Proposed |
| C86 | VS Code extension as a thin bridge to galopin (MVP 4–6 days; try an off-the-shelf extension first) | Idea |
| C113 | Cerea desktop app (Electron, macOS first; ADR 0117 accepted 2026-11-13; phase 1 spike) | Not started |
| C121 | Browser extension as an entry point for chat-only users (ADR 0116 option C) | Idea, not decided |
| C105 | /code dev-server previews through galopin, owner-only | Design after browser use ships |
| C106 | web_fetch site allow/deny lists | Owner request 2026-11-12, not to be implemented yet |
| C127 | Project context for coding agents (ADR 0118) | Parked, kept warm |
| C123 | Conversation-scoped memory (PR [#236](https://github.com/paoloviviani/Cerea/pull/236)) | Closed by owner 2026-11-24; branch `feat/scoped-memory` kept |
| C117 | Server sandboxes: PyPI installs in `execute_code` (wheels only, minimal egress proxy) | On hold by owner |
| C133 | galopin: opt-in opencode Code Mode | Held by owner; blocked on opencode (no `execute` ask) |
| C1 [#9](https://github.com/paoloviviani/Cerea/issues/9), C13 [#10](https://github.com/paoloviviani/Cerea/issues/10) | Kit: Dex in front of Authelia / Dex alone with break-glass | Parked (single-IdP decision; blocked on Pystino groups-from-claim) |
| C41 [#40](https://github.com/paoloviviani/Cerea/issues/40), C42 [#44](https://github.com/paoloviviani/Cerea/issues/44), C59, C63 | Skills-first before connector tools, MCP Apps (ADR first), chat/code bridge, M365/Google connector reference | Parked |

## 2. Pystino

| ID | Title | Status | Next step |
|---|---|---|---|
| P37 | A Pystino provider type: serve a model from Pystino through Pystino (a gateway upstream of the gateway), instead of only OpenAI-compatible and Anthropic protocol types. Owner 2026-11-27 | Proposal | Owner to confirm the shape (chained gateways, cost/billing, privacy rules on both hops) |
| P2 [#3](https://github.com/paoloviviani/Pystino/issues/3) | Decision models as a routing selection (only the metered kind shipped) | Open | Build on P1 or park |
| P3 [#4](https://github.com/paoloviviani/Pystino/issues/4) | vLLM semantic-router spike | Open, no code | Long-term |
| P8 [#8](https://github.com/paoloviviani/Pystino/issues/8) | Multi-tenancy (notes `2026-10-17-multi-tenancy-notes.md`) | Idea, no code | Owner to schedule |
| P13 [#14](https://github.com/paoloviviani/Pystino/issues/14) | Console language picker | No second console language yet | After the first translation |
| P30 [#60](https://github.com/paoloviviani/Pystino/issues/60) | Live checks fail on a fresh stack (redaction, providers, reporting scripts); partly repaired by #54 and #59 (verify) | Open | Re-run on main, fix or close |
| C19 [Pystino #20](https://github.com/paoloviviani/Pystino/issues/20) | Users API returns chat capability flags when chat is off | Parked | |
| C22 [Pystino #21](https://github.com/paoloviviani/Pystino/issues/21) | Split `routers/admin.py` | Parked | |
| G16 [Pystino #19](https://github.com/paoloviviani/Pystino/issues/19) | Spurious ERROR on standalone Pystino (machine-client poll) | Parked | |

## 3. Cerea chat

| ID | Title | Status | Next step |
|---|---|---|---|
| C36 [#41](https://github.com/paoloviviani/Cerea/issues/41) | Composer draft edge cases | Partly done (#227); open: saved-then-502 duplicate | Needs a reconciliation design |
| C39 [#43](https://github.com/paoloviviani/Cerea/issues/43) | Pill leftovers | Partly done (#227); open: long-label ellipsis on PILL, 390 px / 130% font test | Small |
| C50 | mrl-truncate wording ("cut to fit", source cite) | Still unchanged | Batch with the next knowledge change |
| C61 [#56](https://github.com/paoloviviani/Cerea/issues/56) | Assistant creates and fills knowledge bases (`kb_create` absent) | Open | Owner to schedule |
| C75 [#115](https://github.com/paoloviviani/Cerea/issues/115) | Provenance note on repeated text | Open, "later" | |
| C96 [#190](https://github.com/paoloviviani/Cerea/issues/190) | Admin Knowledge screen does not poll after the async reindex (specs fixed in #229) | Issue #190 closed; polling gap still open | Server needs a pending count |
| C126 | Project knowledge passages ride the system prompt and break prompt caching | Open (verify after v0.57.0) | Move to the uncached tail |
| C140 | History budget should count several mid-size turns that together pass the window | Open (verify after v0.57.0) | Check, then close or build |
| C81 | ADR 0108 follow-ups: pi connector extension; per-turn cost after reload (`x-pystino-turn` not on main); real-opencode e2e for `connector_*`; connector picker at session creation | Open | Schedule |
| C30 | Office docs step 4 (`doc_convert`; step 5 depends on C12) | Not built | Decide if still wanted |
| C40 [#39](https://github.com/paoloviviani/Cerea/issues/39) | PDF forms step 3 (`look_doc` shipped) | Open | Schedule |
| C12 [#18](https://github.com/paoloviviani/Cerea/issues/18) | Euro-Office backend | Long-term | |
| C17 [#28](https://github.com/paoloviviani/Cerea/issues/28) | Open Design / CoDesign integration | Spike not done | |
| C71 [#50](https://github.com/paoloviviani/Cerea/issues/50) | OpenTelemetry tracing across Cerea, Pystino and galopin | Agreed by owner 2026-11-21 (after the Pystino /metrics endpoint P34) | Design, then build |
| C46 | OSM maps skill caveat | Optional | |

## 4. Agents and galopin

| ID | Title | Status | Next step |
|---|---|---|---|
| G19 | Mistral Vibe parity with opencode (owner go 2026-11-24; cheapest agent per task in the Artificial Analysis chart). Phase 1 (in progress, branch `feat/vibe-parity`): ACP investigation, AGENTS.md, compact, thinking effort, ask-the-user tool → question cards, queued mid-turn messages. Phase 2: per-session cost, workspace snapshots + file revert (all engines), subagent cards from delegation calls. Not closable without Vibe/ACP: conversation rewind, true mid-turn steering | Phase 1 (#356) and Phase 2 (#357) merged to main, unreleased by owner choice; Phase 2 reviewed twice (revert via Vibe rewind with a preview gate, fork, subagent cards). Residual: a preview→rewind file-swap window, acceptable without an OS sandbox; revisit with restoreFiles:false + galopin-side restore if agent commands are ever sandboxed | Merge #357 after full runs; release when the owner says |
| G18 | `galopin launch <tool>`: today only `launch opencode` exists; goose, Mistral Vibe and Claude Code shipped in Cerea v0.64.0 (#350, live 2026-11-23; per-launch proxy secret, whoami check, key-header stripping); Codex, pi, trust list (also answers C80) still open | Partly built | Codex/pi when wanted |
| C82 | ADR 0109 follow-ups: re-send Auto map to machines offline at save; optional admin caps | Open (verify) | |
| C128 | galopin upgrade follow-ups (#238 re-review): pid re-scan, `/proc` scan with a space, saved `upgrade-*` cleanup, XDG vars, `was-running` marker | Low | Backlog |
| C130 | opencode 2 follow-ups (#239 re-review): project-config + provider pair via re-enroll; `checkFloor` only at start; npm integrity for the CLI | Open | |
| C119 | Sandbox follow-ups (#231): warm pool, staging document-tool files, usage into quotas, shared lease map, rich outputs, start-up ordering | Backlog | |
| C120 | Browser use phase 2a: live view and takeover (PR [#214](https://github.com/paoloviviani/Cerea/pull/214), conflicting with main since ~11-24) | On hold by owner; proposal 2026-11-24 awaiting decision: live thumbnail in the browse card (streams only while visible) → full viewer with Take control/Hand back at any time; "Open here" on verification/sign-in cards and push (the core: solve it from a phone); "Open browser" → open on the computer or here (sign in to sites remotely); page snapshot on commit approval cards; video (2b) deferred. ~3–4 days incl. rebase | Owner decision |
| G3 [#21](https://github.com/paoloviviani/Cerea/issues/21) | OS-level sandbox for agent commands | Not built; hosted sandboxes are C116 | Merge into C116 |
| G12 [#24](https://github.com/paoloviviani/Cerea/issues/24) | Machines show offline after a server restart | Not investigated | Low |
| G14 | `TMPDIR` inside the galopin tree | Still the case | Low |

## 5. Deploy and kit

| ID | Title | Status | Next step |
|---|---|---|---|
| C23 [#35](https://github.com/paoloviviani/Cerea/issues/35) | Shrink the chat image (Pyodide package allowlist, runtime-only node_modules) | Not done | Needs the owner's package list |
| C1, C13 | Dex identity modes for the kit | Parked (section 1) | |

## 6. Flakes and tests

| ID | Title | Status | Next step |
|---|---|---|---|
| C93 [#189](https://github.com/paoloviviani/Cerea/issues/189) | Standing reliability issue: flakes and e2e build OOM (heap raised to 6 GB; route.fulfill fixed) | Standing | Keep open as the tracker |
| C125 | `sandbox/exec-image` test_execd timeout test: IndexError on empty daemon output | Open flake (recurred 2026-11-17 in release CI) | Fix the wait-for-daemon-ready in the test |
| C147 | `code-machine-parity.spec.ts:803` subagent approvals (child.txt) | Open flake (once, on #291) | Fix after release |
| C112 | `code-machine-terminal.spec.ts:241` workspace "repo" not visible | Not reproduced in 3 runs | Keep artifacts if it recurs |
| C114 | `chat-agent-sessions` "Allow once" card flake (the `chat-slides:100` half was fixed with C143 in v0.60.3) | Not reproduced | Keep artifacts if it recurs |
| C115 | `chat-turn-info.spec.ts:54` grey dot panel not found | Seen once (verify) | Reproduce ≤3 times |
| C66 | `code-machine-parity` timeouts (also C78: a second test machine's opencode exits 1). The retry/reload case was a real galopin resync bug, fixed in v0.60.3/v0.60.4 (#317, #320) | Watch | Capture opencode stderr if it recurs |
| C129 | Client tests leak the viewport (`SettingsShell`, `AgentHeaderRow`, `InstructionsSection`); `PairDeviceDialog` fails locally when the vitest UI writes localStorage | Open | Restore in `afterAll` or shared setup |
| C37 [#42](https://github.com/paoloviviani/Cerea/issues/42), C43, C45 / C57 | CodeNavTree, ChatInput cascade submenu, ToolUpdate thumbnail flakes | No recurrence seen | Fix at the cause if they recur |
| C32 [#32](https://github.com/paoloviviani/Cerea/issues/32) | Client harness noise (`wrapDynamicImport`) | Parked | |
| C25 | Audit of sliding-panel and leaky tests | Fold into per-flake fixes | |
| C56 | Pin `listKnowledgeFiles` URLs: the fifth case in `attachmentMountBase.svelte.spec.ts` | Not verified | Check, add the case |
| C68 | V8 start-up crash in CI | Mitigated (retry on exit 133) | Watch |
| C69 | `chat-artifact-table.spec.ts:26` partial artifact on CSV download | Cause unknown (verify) | Wait for another run |
| C19 [#36](https://github.com/paoloviviani/Cerea/issues/36) | Test coverage: WebKit and real phones | Parked | |
| C22 [#34](https://github.com/paoloviviani/Cerea/issues/34) | Split the largest modules (forwarder, `AgentView.svelte`, `dispatch.go`) | Parked | |

## 7. Dropped

| ID | Item | Reason |
|---|---|---|
| Pystino as the model provider for Hermes Agent / OpenClaw (docs + compatibility check) | Declined by owner 2026-11-21 | Not pursued |
| C26 | Move-to-project on the open chat page | Dropped 2026-10-25 |
| C74 | Workspace config that runs code on open | Owner, 2026-11-06 |
| P19 | Redaction allow-list combine | The first policy's list is the design (ADR 0038) |
| P21 | Volume check | Not verifiable from git |
| C34 | Reused login code gives 500 | Owner plan 2026-11-09 |
| P6 | Refuse Anthropic server tools on `/v1/messages` | Rejected |
| G5 | Billing group per session | Rejected |
| G9 | Report to opencode upstream | Rejected |
| G10 | Free-model sessions | Not a leak |
| C6, C14 | MongoDB EOL plan; DocumentDB/FerretDB | Rejected or merged into C5 |
| P1 follow-ups, C71/C72 and C51 duplicate rows | Old "Design" and "Owner decisions" tables | Duplicates of rows above |

## 8. Done since 2026-11-06

**2026-11-21 (evening):** C156 client-proposed message ids (#338, v0.61.2; also fixes reply panels closing by themselves and the C115 turn-info flake); send-after-turn 500 fixed (#335, v0.61.1).

**2026-11-25:** merged, release held by owner: `doc_extract` (C164, #364: OCR a fetched/received file on demand, cached, page budget, privacy refusal withholds the file); landing page redesign in the app style (#366, Hugging Face named only in NOTICE); docs themes for Cerea and Pystino (#365, Pystino #77). MCP Apps in progress (C165).

**2026-11-24 (night):** Cerea v0.65.0 released and live: Mistral Vibe parity phases 1–2 (G19, #356 #357), connectors in `galopin launch` + `galopin setup` as launch-by-default + run mode (G20, #361), phone terminal long-press (C158, #362). Live update briefly bound the side ports (~1 min outage, fixed).

**2026-11-23/24:** Cerea v0.64.0 (galopin launch goose/vibe/claude, #350) and v0.64.1 (opencode 2.4.1, #354) released and live; README first screen + demo PR #353 awaiting owner review.

**2026-11-22 (late):** Cerea v0.62.1 released and on the live stack: new-chat composer back at the bottom, phone logo fix (#344), links that point nowhere render as plain text (#346). C156 test flake found (test-only: settle() returned before the turn's final save), fix in #348. C159 Upgrade button (#345, galopin changed) released in Cerea v0.63.0 and on the live stack (2026-11-23 00:30 UTC); computers need one manual galopin update to start reporting the capability.

**2026-11-22:** P35 quotas per provider or model (Pystino #74, with a MissingGreenlet fix for routed aliases #76) and P34 `/metrics` (#75) merged; the Cerea kit refuses `/metrics` at the proxy (#342). Released in Pystino 0.34.0 (live checks green) and Cerea v0.62.0 (pins Pystino 0.34.0, ships C157); live stack still down for the weekend. C157 terminal Select text / Copy moved out of the output: bottom bar on desktop, keys panel on a phone (#341, on main, ships in the next release); Cerea v0.61.2 released.

**2026-11-21:** C152 relayed coordination across a user's computers (ADR 0121, Cerea #331, ships in v0.61.0); C155 parallel tool-call join (#323, v0.60.5); P32/P33 (Pystino #73, 0.33.6); audio Opus/M4A (#324/#325); placeholders second pass (#327); mobile terminal copy (#330).

**v0.60.1 to v0.60.4 (2026-11-19/20):** connector file references made unambiguous with sent-file notes (#308); phone composer keeps the box on screen with many attachments (#310); vision: EXIF-upright photos, 2048 px images, `view_image` tool, request-wide image budget (#311); skeleton placeholders and all-at-once loading (#312); message image thumbnails with group reveal (#316); galopin resync no longer drops a running turn's text, per-part merge, browser text correction, tombstones, serialized resyncs (#317, #320); flakes fixed at the cause: C143 slides fullscreen (#314), parity retry-reload (#314/#317), C124 transcript paging (#317), galopin link harness and permission-floor test (#315, with `checkFloor` hardening), knowledge retry spec (#318). C153: test renamed, no recurrence found; closed.

**v0.60.0 / Pystino 0.33.5 (2026-11-19):** C73 secret-value guard (#303), C99 (a)+(c) withheld-file follow-ups (#304), C139 large attachments + 32 MiB reader (#302, Pystino #72), failed-turn re-attach loop and orphan reaper (#301), connector `$file` references + truncation message + sliced read-back (#305), composer model pill without effort (#306). C154 shipped in v0.59.1 (#299).

About 70 rows plus the releases v0.55.0 to v0.59.0 are listed with their PR or version in `backlog-archive-2026-11-19.md`. Highlights: share links (v0.55.0), prune artifact versions C122 (v0.56.0), artifact-aware history (v0.57.0), Italian, Mistral Vibe, failed-turn fix and any text file (v0.58.0), UI polish step 2 (v0.59.0), self-hosted servers C141 (Pystino 0.33.4, v0.54.1), large content C138, sandboxes C72/C118.
