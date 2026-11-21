# Backlog

**State on 2026-11-20: Cerea 0.60.4 released and live, Pystino 0.33.5.** Cleaned and aligned with GitHub issues on 2026-11-19: every row checked against `origin/main`, release tags, PR and issue states. Closed rows and their PR or version are in `backlog-archive-2026-11-19.md`; older detail is in `backlog-archive-2026-11-06.md` and `backlog-notes-2026-11-06.md`. IDs are stable. Update this file, don't keep lists in chat. Rows marked "(verify)" were not conclusively checked.

Prefixes: P = Pystino, C = Cerea (including the galopin agent under `agent/`), G = galopin. Every open issue in both repos has a row below.

## 0. Current priorities

| ID | Item | Status | Next step |
|---|---|---|---|
| P31 | Classifier provider allowlist: classifiers may use only models of providers an admin ticks (empty by default), replacing PR #61's "Allow remote classifiers" switch; fail closed for a stored classifier on a provider no longer allowed | Parked on owner go; Pystino PR [#61](https://github.com/paoloviviani/Pystino/pull/61) open | Rework #61 when the owner says go |
| P32 | Console Privacy "What users may add": a multi-select of detector entity types instead of a free-text comma list (a typo silently allows nothing); confirmed 2026-11-19: still a free-text input on main | Backlog | Build with P31 |
| P33 | Privacy rule editor: items (1) match all/any and (2) the "Check" badge shipped (0.33.0, #63). Left: (3) read rules' "Redact with" is unclear and overlaps the chat and embedding pipelines | Owner decision on (3) | Relabel (one-way, before storage) or remove |
| C99 | Privacy-withheld files follow-ups: (a) vision-refused images withheld and (c) owner one-time download shipped in v0.60.0 (#304). Left: (b) no backfill for files stored before #193 | Backlog | Decide whether (b) is worth a migration |
| C149 | Standing engine pin bumps: opencode 2.3.2 ([#289](https://github.com/paoloviviani/Cerea/issues/289)), goose 1.60.1 ([#288](https://github.com/paoloviviani/Cerea/issues/288)). Older bump issues (closed as superseded) [#258](https://github.com/paoloviviani/Cerea/issues/258), [#237](https://github.com/paoloviviani/Cerea/issues/237), [#199](https://github.com/paoloviviani/Cerea/issues/199), [#196](https://github.com/paoloviviani/Cerea/issues/196) are superseded by #288 | Pins on main: opencode 2.3.0, goose 1.57.0 | Bump both pins; close the superseded issues with the bump |
| C148 | Secret manager plus credential injection at egress (write-only per-workspace/user secrets; the cloud-workspace egress proxy injects the real credential). Report `2026-11-18-mistral-secrets-knowledge.md` | Deferred to the owner; not started | Owner decision |
| C150 [#270](https://github.com/paoloviviani/Cerea/issues/270) | Clone a Git repository when creating a new workspace | Open, no code on main | Schedule |
| C155 | Parallel tool calls: a turn resumed when the code result arrived while a slow MCP call of the same turn was still pending (2026-11-19 incident). #301 drops the overtaken run's late writes; the turn should wait for all parallel calls before resuming | Open | Design the join, then build |

## 1. Owner decisions and ideas

| ID | Item | Status |
|---|---|---|
| C116 [#278](https://github.com/paoloviviani/Cerea/issues/278) | Cloud workspaces: hosted galopin sandboxes (ADR 0115 class P): own switch `SANDBOX_MACHINES_ENABLED` (refused today), egress proxy, persistent volume, idle stop, OpenShell evaluation first | Open design, owner's decision; not started |
| C151 [#290](https://github.com/paoloviviani/Cerea/issues/290) | WYSIWYG slides editor: fork Small Reveal into the slides artifact | Open, owner's decision |
| C80 | Per-workspace switch for a project's own opencode setup / AGENTS.md (today an enroll flag) | Owner decision |
| C79 | Session sharing: `galopin attach`, goose shared history (report `2026-11-06-session-sharing-goose-opencode.md`) | Owner thinking |
| C83 | Workflows: multi-step recipes with typed outputs, approval gates, shared definitions | Discussed; first process and run-as open |
| C84 | Meeting notes: import/record, transcript, template summary, actions via connectors | Discussed; online vs in-person open |
| C85 | Memory as a knowledge graph, per user/project | Proposed |
| C86 | VS Code extension as a thin bridge to galopin (MVP 4–6 days; try an off-the-shelf extension first) | Idea |
| G19 | galopin tray app (menu-bar / tray status, control channel first); the C108 menu-bar app shipped, C113 may replace it | Parked |
| C113 | Cerea desktop app (Electron, macOS first; ADR 0117 accepted 2026-11-13; phase 1 spike) | Not started |
| C121 | Browser extension as an entry point for chat-only users (ADR 0116 option C) | Idea, not decided |
| C105 | /code dev-server previews through galopin, owner-only | Design after browser use ships |
| C106 | web_fetch site allow/deny lists | Owner request 2026-11-12, not to be implemented yet |
| C127 | Project context for coding agents (ADR 0118) | Parked, kept warm |
| C123 | Conversation-scoped memory (PR [#236](https://github.com/paoloviviani/Cerea/pull/236) open) | Parked 2026-11-14; owner unsure chat memory is useful |
| C117 | Server sandboxes: PyPI installs in `execute_code` (wheels only, minimal egress proxy) | On hold by owner |
| C133 | galopin: opt-in opencode Code Mode | Held by owner; blocked on opencode (no `execute` ask) |
| C1 [#9](https://github.com/paoloviviani/Cerea/issues/9), C13 [#10](https://github.com/paoloviviani/Cerea/issues/10) | Kit: Dex in front of Authelia / Dex alone with break-glass | Parked (single-IdP decision; blocked on Pystino groups-from-claim) |
| C41 [#40](https://github.com/paoloviviani/Cerea/issues/40), C42 [#44](https://github.com/paoloviviani/Cerea/issues/44), C59, C63 | Skills-first before connector tools, MCP Apps (ADR first), chat/code bridge, M365/Google connector reference | Parked |

## 2. Pystino

| ID | Title | Status | Next step |
|---|---|---|---|
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
| C71 [#50](https://github.com/paoloviviani/Cerea/issues/50) | OpenTelemetry / observability across the stack | No OTel yet | Needs a pipeline in the kit first |
| C46 | OSM maps skill caveat | Optional | |

## 4. Agents and galopin

| ID | Title | Status | Next step |
|---|---|---|---|
| G18 | `galopin launch <tool>`: today only `launch opencode` exists; add Claude Code, Codex, pi, Mistral Vibe, goose, per-tool config, trust list (also answers C80) | Partly built | 2–3 days for the rest |
| C82 | ADR 0109 follow-ups: re-send Auto map to machines offline at save; optional admin caps | Open (verify) | |
| C128 | galopin upgrade follow-ups (#238 re-review): pid re-scan, `/proc` scan with a space, saved `upgrade-*` cleanup, XDG vars, `was-running` marker | Low | Backlog |
| C130 | opencode 2 follow-ups (#239 re-review): project-config + provider pair via re-enroll; `checkFloor` only at start; npm integrity for the CLI | Open | |
| C119 | Sandbox follow-ups (#231): warm pool, staging document-tool files, usage into quotas, shared lease map, rich outputs, start-up ordering | Backlog | |
| C120 | Browser use phase 2a: live view and takeover (PR [#214](https://github.com/paoloviviani/Cerea/pull/214) open) | On hold by owner until the UX is settled | |
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

**2026-11-21:** C152 relayed coordination across a user's computers (ADR 0121, Cerea #331, ships in v0.61.0); C155 parallel tool-call join (#323, v0.60.5); P32/P33 (Pystino #73, 0.33.6); audio Opus/M4A (#324/#325); placeholders second pass (#327); mobile terminal copy (#330).

**v0.60.1 to v0.60.4 (2026-11-19/20):** connector file references made unambiguous with sent-file notes (#308); phone composer keeps the box on screen with many attachments (#310); vision: EXIF-upright photos, 2048 px images, `view_image` tool, request-wide image budget (#311); skeleton placeholders and all-at-once loading (#312); message image thumbnails with group reveal (#316); galopin resync no longer drops a running turn's text, per-part merge, browser text correction, tombstones, serialized resyncs (#317, #320); flakes fixed at the cause: C143 slides fullscreen (#314), parity retry-reload (#314/#317), C124 transcript paging (#317), galopin link harness and permission-floor test (#315, with `checkFloor` hardening), knowledge retry spec (#318). C153: test renamed, no recurrence found; closed.

**v0.60.0 / Pystino 0.33.5 (2026-11-19):** C73 secret-value guard (#303), C99 (a)+(c) withheld-file follow-ups (#304), C139 large attachments + 32 MiB reader (#302, Pystino #72), failed-turn re-attach loop and orphan reaper (#301), connector `$file` references + truncation message + sliced read-back (#305), composer model pill without effort (#306). C154 shipped in v0.59.1 (#299).

About 70 rows plus the releases v0.55.0 to v0.59.0 are listed with their PR or version in `backlog-archive-2026-11-19.md`. Highlights: share links (v0.55.0), prune artifact versions C122 (v0.56.0), artifact-aware history (v0.57.0), Italian, Mistral Vibe, failed-turn fix and any text file (v0.58.0), UI polish step 2 (v0.59.0), self-hosted servers C141 (Pystino 0.33.4, v0.54.1), large content C138, sandboxes C72/C118.
