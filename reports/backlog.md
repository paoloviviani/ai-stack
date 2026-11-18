# Backlog

Rewritten 2026-11-06 from a verified audit (`backlog-audit-2026-11-06.md`): every row checked against `origin/main`, release tags (Cerea v0.42.2, Pystino v0.27.0), the code, issue states and recent CI. The previous file, with each item's full history and notes, is `backlog-archive-2026-11-06.md`; IDs are stable, look an ID up there for detail. Update this file, don't keep lists in chat.

**State on 2026-11-06 after Cerea 0.43.0 + Pystino 0.28.0.** Day notes moved to `backlog-notes-2026-11-06.md`. Done today: ADR 0108 (diffs, history, gateway cost, connectors for agents), ADR 0109 (no machine limits, per-user auto-approval), G11, C69, C76, C77 (quota messages), C27–C29, C48, C52–C54, C65, schedules on grant expiry, Playwright 1.65.0. Dropped: P19, P21, C34, C74.

## 0. Current priorities

| ID | Item | Status | Next step |
|---|---|---|---|
| P31 | **Classifier provider allowlist (next Pystino release, priority).** Owner decision 2026-11-09: privacy classifiers may use only models of providers an admin ticks in "Providers classifiers may use" (empty by default; per-provider remote warning kept). Replaces PR #61's "Allow remote classifiers" switch, whose built-in-only "local" left the list always empty (ADR 0113 has no local notion: scope by provider). Keep from #61: fail closed for a stored classifier on a provider no longer allowed, migration 0086 slot, docs, i18n. Revert #61's PUT /settings omitted-`user_entity_types` change. Fix #61's tests (chat model on the extractor provider cannot exist). | Parked: owner short on tokens; do not start until asked | Rework PR #61 (branch feat/local-classifiers) |
| P32 | Console Privacy → "What users may add": replace the free-text comma list of entity types (`user_entity_types`) with a multi-select of the types the detectors offer, grouped Patterns / NER, not-installed ones disabled; clearer title ("Entity types allowed in users' own policies"), hint "blank = all"; a typo today silently allows nothing. Owner 2026-11-10. | Backlog | Build with P31 |
| P33 | Privacy rule editor follow-ups (owner 2026-11-10, cut from 0.32.1): (1) **selectable** per-rule match all/any (`match` field, evaluate.py all()/any(), "and"/"or" row labels, "is any of"/"is none of" within a condition, "Is a scan" as is/is not); (2) remove the amber "Check" badge from the pipeline list (the in-editor message is enough); (3) read rules' "Redact with (on the returned text)": unclear and overlaps the chat/embedding pipelines; what a Restore policy means there is undefined (one-way at read): decide relabel ("before it is stored, one-way", restrict to non-restore modes) or remove. | Backlog, priority | Owner decision on (3); build with P31/P32 |
| C99 | Privacy-withheld files follow-ups (after #193): (a) chat-kind (vision) refusal of an image doesn't mark it withheld, so it stays mountable on a later turn; (b) no backfill for files stored before #193 (incl. the 2026-11-10 incident file): find via gateway logs and mark; (c) owner download of a withheld file through a tool-unreachable route (one-time token after a user click; the sandbox is same-origin with cookies). | Backlog, priority | After 0.48.1 |
| — | Pair dialog stray note + plain project-config text | PR #135, CI running | Merge; next patch |
| C60 | Admin connectors phone-tap snapshot flake | **Fixed** (PR #142): Inter loads lazily with font-display: swap; the swap re-wrapped text mid-measurement. The test now awaits document.fonts before measuring. Apply the same settle step to other layout-measuring client tests (C43, C45, C57) | Done; follow-up for siblings |
| C66 / C78 | Parity file-editor timeout; second test machine's opencode exits 1 | Recurring | Capture opencode stderr in the harness; per-machine cache |
| C73 [#113](https://github.com/paoloviviani/Cerea/issues/113) | Secret value in an outbound command comes to the user | Queued | Build |
| G18 | `galopin launch <tool>` (was `galopin opencode`): run opencode, Claude Code (via Pystino's Anthropic endpoint), Codex, pi, Mistral Vibe, goose against galopin's local proxy, unsupervised by Cerea; generated per-tool config under galopin's config dir, inherited provider credentials stripped, model tiers main/secondary/lightweight, per-workspace trust list (also answers C80), `tools install/diagnose`. Inspired by the Melious CLI (2026-11-06). | Not started (owner idea) | About 2–3 days |
| C72 [#184](https://github.com/paoloviviani/Cerea/issues/184) | Sandbox ADR (the hard limit after ADR 0109) | Next big item | Write ADR |
| C80 | Per-workspace switch for a project's own opencode setup / AGENTS.md (today an enroll flag) | Suggested 2026-11-06 | Owner decision |
| C81 | ADR 0108 follow-ups: pi connector extension; per-turn cost after reload (`x-pystino-turn`); real-opencode e2e for `connector_*`; connector picker at session creation | Open | Schedule |
| C82 | ADR 0109 follow-ups: re-send Auto map to machines that were offline at save; optional admin caps | Open | Schedule |
| C87 [#185](https://github.com/paoloviviani/Cerea/issues/185) | Sidebar redesign for 0.45.0 (owner 2026-11-06): try the thick ridge logo (brand/logo_thick_black.svg + _white, PR #141) as the top-left logo, both themes, replacing the pixel-art small mark; Chats/Agents switch at top; New chat → "New agent session" in Agents mode (machine/folder dialog, defaults to last; Pair if none); Workspace only fixed link, with an icon; user menu (a small quota summary at the top: spend vs limit with a thin bar and reset time, or spend only when no limit, from the same source as Settings → Usage & billing, links there; Settings, Admin, a "Console" link to the Pystino console when the deployment has one and the user has console access, theme, refresh, Sign out); Schedules moves down next to Workspace (owner), one row identical in both modes + one Schedules page for both kinds (badge + filter preselected by mode, attention badge only); ⌘K palette; quieter counts; "Regenerate title" in chat ⋯ menu; Workspace tabs 8→6: Local connectors into Connectors ("On your machines" section), Custom models into Models ("Your custom models" section), old ?tab= links redirect; no pinned "Needs you" line (owner: keep the badge only) | **Done** (PR #143, #208; triage 2026-11-16). Queued; starts when a worker slot frees | **Done**: merged #143 (sidebar redesign), #144 (⌘K palette, retitle), #145 (Workspace tabs 8→6, floating save bar). |
| C88 [#186](https://github.com/paoloviviani/Cerea/issues/186) | Project page: clicking a table-of-contents entry scrolls the whole app window (sidebar cut, sticky "Save changes" over content); scroll only the content column with an offset for the sticky bar (owner screenshot 2026-11-06). Also the full-width white "Save changes" bar is ugly: replace with a compact floating bar shown only when there are unsaved changes ("Unsaved changes · Discard · Save"), no white band | Bug + polish, queued with C87 | **Done**: merged #145 (TOC scrolls its own column, floating save bar). |
| C89 [#187](https://github.com/paoloviviani/Cerea/issues/187) | Stale UI after ADR 0109: the code panel still shows "Re-enroll this machine to set limits…" for machines whose policy predates ceilings (`isLegacyMachine` in src/lib/utils/permissionRules.ts, message `code.permissions.legacy_title`, CodeNavTree and PermissionsDialog) — remove it | **Done** (PR #145; triage 2026-11-16). Bug, found by the docs pass 2026-11-06 | **Done**: merged #145 (stale re-enroll notice removed). |


| C92 [#188](https://github.com/paoloviviani/Cerea/issues/188) | Phone UI density (owner, 2026-11-07, for 0.46.0). 1) Agents session header on one row: status as a coloured dot after the name, with a word only for "Waiting for you" or on tap; engine label moved out of the header. Panes (Tasks/Changes/Files/Terminal) behind one Panels button opening a sheet (phone) or drawer; desktop keeps the inline labelled buttons when they fit. 2) Sidebar: New chat / New session the same height as the Chats/Agents switch; on phones only, list titles one step smaller with tighter rows (desktop font unchanged) | **Done** (v0.53.0; triage 2026-11-16). Queued; start when a worker slot frees | **Done**: merged ui/phone-density (one-row agent header with Panels sheet, denser phone sidebar). |

| C93 [#189](https://github.com/paoloviviani/Cerea/issues/189) | Flaky tests: slides PDF, galopin diff/deny, agent-sessions details, two component waits FIXED in #167 (2026-11-08). Still open: chat-slides server-PDF download timeout recurred after #167 (2026-11-08, PR #169 shard 1, passed on rerun) — the probe-settle fix was not the whole cause; client job "route.fulfill … collected/closed" unhandled rejection from @vitest/browser mock routes during teardown (~1 in 3 full client runs); next step a verbose run to find the late mocked import, or a vitest upgrade. Also recurring: e2e-full build `npm run build` dies with a Node heap OOM at the 4 GB limit (PR #170 twice, #172 once on 2026-11-09); raise NODE_OPTIONS max-old-space-size in the e2e build step or split the build | Test reliability | Leftovers checked in #229: heap OOM already mitigated (6aba8380, 6144 MB, tight); route.fulfill fixed by fcb4db41/59841416; chat-slides see C114. |

| C96 [#190](https://github.com/paoloviviani/Cerea/issues/190) | Postgres-only knowledge specs fail when `TEST_DATABASE_URL` is set (skipped in CI): `ingestBackground.spec.ts` (4, reproduced on origin/main) and `deleteDerived.spec.ts` (extractDocument mock lacks `documentMime`). Also: admin Knowledge screen does not poll after the now-async reindex (shows pending until refresh) — found by #170 worker, 2026-11-08 | Test reliability / UI | **Done** (specs) in #229: mocks keep the real exports; CI `check` now runs Postgres-only specs. Open: admin Knowledge screen polling after async reindex (needs a pending count from the server). |
| C98 [#191](https://github.com/paoloviviani/Cerea/issues/191) | Cosmetic: an approval card's "Show details" collapses when the first turn's message id is swapped for the server id after the stream (ChatMessageColumn keys by message.id, so ToolApprovalCard remounts and loses its local state). The re-key is intentional; keep the open state across it. Found by Cerea PR #183 | Cosmetic | **Done**: merged as Cerea #227 (open state kept by conversation + elicitation id). |
| C94 | **Done**: merged as Cerea #226 (Administration → Services, 18 rows, manual Check for updates). Admin "Services" panel in Cerea (owner, 2026-11-08, after 0.46.0): one page summarising every service active in the deployment with green/red health — gateway, extractor/OCR, embedding model, redaction (and which modality: pattern vs Presidio), documents/Gotenberg, fetch browser, web search backend, image generation, transcription, MCP servers, blob store, galopin dist/opencode pins, schedules worker, mail. Plus a "Check for updates" button: admin-triggered only, one request to the GitHub releases API for the latest Cerea (and Pystino) release, compared with the running versions; no background checks, no telemetry, nothing sent beyond the plain request | Feature | Medium |

| P30 [#60](https://github.com/paoloviviani/Pystino/issues/60) | Pystino live checks failing on a fresh stack on main (seen 2026-11-08 by the routing worker): test_redaction_live (8: expect an admin redaction rule / summary on a fresh stack), test_providers_live (1: model_substituted=t), test_reporting_live (1: research group missing, maybe seeding). Fix the scripts' setup or the code; live checks must be green before releases touching request path | Test reliability | Small–medium |

## Ideas under discussion (owner)

| ID | Idea | Status |
|---|---|---|
| C79 | Session sharing: `galopin attach` (opencode live in a terminal/VS Code), goose shared history | Owner thinking; report `2026-11-06-session-sharing-goose-opencode.md` |
| C83 | Workflows: multi-step recipes with typed outputs, per-step tools, approval gates, shared definitions run as the starter | Discussed; owner questions open (first process, run-as) |
| C84 | Meeting notes: import/record → transcript → template summary → actions via connectors, per project | Discussed; online vs in-person open |
| C85 | Memory as a knowledge graph (reuse the MCP memory server's tool design natively, per user/project) | Proposed |
| C86 | VS Code extension as a thin bridge: galopin install/pair/status and "start an agent session in this folder"; agent edits live in the editor, native diff view, approvals as notifications; send selection/file/diagnostics to a chat or project; Cerea panel embedded (browser sign-in via URI handler); open-in-Cerea / open-in-VS Code. No autocomplete. First try an off-the-shelf extension (Continue/Cline/Roo) against Pystino. MVP 4–6 days, +2 for the embedded panel | Idea (owner, 2026-11-06) |
| G19 | galopin tray app: macOS menu-bar icon (and Windows tray, Linux status icon): status (paired/online/offline), proxy and engine up, sessions waiting for you (Needs-you count), pause/resume, open Cerea / open session, start `galopin launch`, update available, logs; doubles as the login-item/service manager. Design: separate `galopin-tray` over a local control channel; headless vs desktop install flavours; macOS signing/notarization + Windows signing are the main cost. Estimate 6–10 days + signing accounts | **Parked** (owner, 2026-11-06); build the control channel first if C86 starts |
| G1 | opencode 2.x / alternative engines | goose as an opt-in supported engine: ADR 0110, in progress (`feat/goose-engine`); opencode 2.x still to assess |

## 1. Open

### Pystino
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| P2 [#3](https://github.com/paoloviviani/Pystino/issues/3) | Decision models as a routing selection | Only the metered kind shipped (0.16.0). `docs/decision-models.md` says routing belongs to the deployment; no decider-picks-target rule exists. Issue open. | Build it on P1's selection interface, or park explicitly. |
| P3 [#4](https://github.com/paoloviviani/Pystino/issues/4) | vLLM semantic-router spike | Issue open, no code, no spike. | Stays long-term; needs heavier hardware. |
| P8 [#8](https://github.com/paoloviviani/Pystino/issues/8) | Multi-tenancy | Idea stage, no code, issue open. | Owner to schedule or park. |
| P13 [#14](https://github.com/paoloviviani/Pystino/issues/14) | Console language picker | No second language exists, issue open. | Wait for the first translation. |

### Cerea bugs
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| C36 [#41](https://github.com/paoloviviani/Cerea/issues/41) | Composer draft edge cases | 0.32.1 fixed the main cases (2e2fc45c). The three leftovers are unfixed and the issue is open. | **Partly done** in #227: refused edit restores its text; leaving mid-send keeps the draft. Open: saved-then-502 duplicate (needs reconciliation design). |
| C39 [#43](https://github.com/paoloviviani/Cerea/issues/43) | Pill leftovers on the code panel | `NeedsYouInbox` and others still do not use the shared PILL. 0.32.1 moved only some pills (c8fdf926). | **Partly done** in #227: NeedsYouInbox, CodeNavTree, EnrollPolicyControls, MountedChips on the shared PILL. Open: long-label ellipsis on PILL itself + 390 px/130% font test. |
| C41 [#40](https://github.com/paoloviviani/Cerea/issues/40) | Skills-first before connector tools | No `tools:` frontmatter field in the skills code. Issue open. | Parked. |
| C50 | mrl-truncate low items | `mrl.ts:66` still has the "cut to fit" wording, and the source is still `mixedbread.ai`. | Batch with the next knowledge change. |
| C61 [#56](https://github.com/paoloviviani/Cerea/issues/56) | Assistant creates and fills KBs | `kb_create`, `kb_list` and `kb_add` are not on main. | Owner to schedule. |

### Cerea features
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| C1 [#9](https://github.com/paoloviviani/Cerea/issues/9) | Kit: Dex in front of Authelia | Only the spike branch `feat/kit-dex-authelia` exists; no Dex in `kit/configure`. Blocked on Pystino groups-from-claim. | Stays parked. |
| C13 [#10](https://github.com/paoloviviani/Cerea/issues/10) | Kit: Dex alone with break-glass | Not started, issue open. | After C1. |
| C12 [#18](https://github.com/paoloviviani/Cerea/issues/18) | Euro-Office backend | Not on main (no references in docs, kit or src). | Long-term. |
| C17 [#28](https://github.com/paoloviviani/Cerea/issues/28) | Open Design / CoDesign | No references on main, issue open. | The spike is not done. |
| C30 | Office docs step 4 (`doc_convert`) | Steps 1-3 shipped (0.30.0 to 0.32.x). No `doc_convert`; `convert_document` exists. Step 5 depends on C12. | Decide whether step 4 is still wanted. |
| C40 [#39](https://github.com/paoloviviani/Cerea/issues/39) | PDF forms, step 3 | Steps 1-2 shipped (0.32.2). Step 3 needs `look_doc` (shipped 0.32.3). | Schedule step 3. |
| C42 [#44](https://github.com/paoloviviani/Cerea/issues/44) | MCP Apps | No `ui://` rendering in src. Needs an ADR first. | Stays parked. |
| C63 | M365 / Google connector reference | Parked, no tenant to test. | Parked. |
| C59 | Chat to /code bridge | Idea only. | Parked. |
| C71 [#50](https://github.com/paoloviviani/Cerea/issues/50) | OpenTelemetry for agent activity | No OTel in src, kit or docs. Interim: review log page (#104). Issue #50 (observability) is open. | Needs a pipeline in the kit first. |
| C72 [#184](https://github.com/paoloviviani/Cerea/issues/184) | Sandbox ADR for coding agents | No sandbox ADR; the last ADR is 0107. G3 is the same area. | Write the ADR and merge it with G3. |
| C73 [#113](https://github.com/paoloviviani/Cerea/issues/113) | Secret value in an outbound command | Issue open, no commit. Owner says "next release". | Queued. |
| C75 [#115](https://github.com/paoloviviani/Cerea/issues/115) | Provenance note on repeated text | Issue open, no commit. Owner says "later". | Later. |
| C100 | Sidebar "Recents" selector | Owner request 2026-11-10. A third selector beside Agents and Chats: every chat (including chats inside projects) and every agent from the last couple of days, newest first. | **Done**: merged as Cerea #208 (v0.51.0). |
| C101 | Schedules: per-user cap race | **Done**: merged as Cerea #207 (atomic per-user slot counter, self-healing downward). |  |
| C103 | galopin link drops every ~15 min | **Done**: merged as Cerea #202 (galopin refreshes the token over the open link, so the link stays up through token refreshes). |  |
| C104 | Kit: bump MongoDB 8.0.34 → 8.0.37 | CVE-2026-118383 (pre-auth use-after-free, replica sets only) and CVE-2026-120822 (replication admin command auth check) are fixed in 8.0.37. Kit stacks run a standalone mongod with no host port, so they are not exposed; this is hygiene. | **Done**: #227 pinned 8.0.37, which does not exist on Docker Hub (caught by the v0.52.0 fresh-kit check); #233 moves to 8.0.38. The CVE claims in this row were never verified. |
| C105 | /code: dev-server previews through galopin | Idea from Open WebUI Computer and OpenChamber: show a port that an agent's machine is serving (e.g. `npm run dev`) in a Cerea tab, over the galopin relay, visible only to the owner. The owner wants it **after the browser-use work** (ADR 0116). | Design after browser use ships. |
| C106 | web_fetch site allow/deny lists | Owner request 2026-11-12, **not to be implemented yet**. Design:
| C107 | Schedules: per-device active-agent cap race | Found in the C101 review (#207): `machineCalls.ts` (~391-403, `MAX_ACTIVE_AGENT_SCHEDULES`) still creates, counts and then withdraws, so it can exceed the cap by one. | **Done**: merged as Cerea #227 (atomic per-device claim counter; heal only when still for 60 s). |
| C108 | "Cerea connector" macOS menu-bar app | **Done**: merged as Cerea #209 (2026-11-13), with the Opus review fixes (release job only uploads to release.sh's release, Docker builds copy third_party, macOS child reaper, installer hardening). Owner decisions 2026-11-12. The target user is non-technical (the owner's wife, on an Intel Mac).
- A Go tray app (`fyne.io/systray`, Apache-2.0), `Cerea connector.app`, Node bundled, separate arm64 and amd64 zips, macOS 12+.
- No notarization: a zip download plus the documented first-open step (right-click Open on macOS 14 and older, Open Anyway on 15+), or the curl one-liner (no quarantine flag); ad-hoc signed.
- Menu: status, browser, Pair (device flow, connectors-only), set up browser, open Cerea, start/stop, start at login, logs.
- **v1: PR #209**, built in CI (`macos-app.yml`), untested on a real Mac.
- **Next round:** an "Edit connectors…" item that opens `mcp.json` in TextEdit (created from a commented template if missing; galopin reloads it by itself).
- Windows and Linux later reuse the tray code. | Test v1 on the Intel Mac; then the next round. |
| C110 | Schedules: per-user cap race test flaked in CI | **Done**: merged as Cerea #213 (real race: the self-heal lowered the counter under in-flight claims; heal now waits until the counter has been still for 60 s). Seen 2026-11-13 on #209 CI: `src/lib/server/schedules/scheduler.spec.ts` "per-user cap holds when creates race" got 5 fulfilled, expected 3; passed on rerun. Either the C101 atomic counter (#207) still races, or the test does. Reproduce in a loop at unit level, fix at the cause. |  |
| C111 | browser-runtime: popup task-page test flake | **Done**: merged as Cerea #224 (endTask waits for in-flight popup adoptions and closes of dropped pages; not reproduced locally, fixed from the two races found). Seen 2026-11-13 on #210 CI: `browser-runtime/test/tasks.test.ts` "follows a popup as a task page and reports it" failed once, passed on rerun. Likely races the async `adopt()` of the popup. Reproduce in a loop, fix at the cause. |  |
| C112 | e2e: code-machine-terminal flake | Seen 2026-11-13 on #210 CI: `code-machine-terminal.spec.ts:241` (e2e-full shard 2) failed once, passed on rerun. Up to 3 e2e repeats to reproduce, then fix at the cause. | Not reproduced (#229, 3 local runs). Failure was in pairAndOpenWorkspace ("repo" not visible 15 s after Add workspace). If it recurs, keep the failing attempt's screenshot/video/galopin log. |
| C113 | Cerea desktop app (Electron), macOS first | ADR 0117, accepted 2026-11-13. Electron shell on the user's Cerea, galopin managed inside (replaces the C108 menu-bar app), built-in Chromium browser driven by the ADR 0116 runtime over CDP. Phase 1 is a spike: attach without an open TCP debugging port. Not started. |  |
| C114 | e2e flakes: chat-agent-sessions, chat-slides | Seen 2026-11-13 on #217 CI (e2e-full shard 1/4): `tests/chat-agent-sessions.spec.ts` and `tests/chat-slides.spec.ts` failed once, passed on rerun; #217 touched neither. Up to 3 e2e repeats to reproduce, then fix at the cause. | Not reproduced (#229). chat-agent-sessions:210 "Allow once" card never appeared; chat-slides:100 is the leave-presenting toPass (maybe exitFullscreen pending under CI video). Keep artifacts of the failing attempt next time. |
| C115 | e2e flake: chat-turn-info grey dot | Seen 2026-11-13 on #223 CI (run 43476415936, e2e-full shard 1/4): `tests/chat-turn-info.spec.ts:54` "a plain answer has a grey dot with the turn's numbers": `turn-info-panel` not found within 15 s. Main green at the same base; #223 does not touch turn info. Reproduce (≤3 repeats), keep the failing attempt's artifacts, fix at the cause. |  |
| C116 | Sandboxes phase 2: hosted galopin machines (ADR 0115 class P) | Owner 2026-11-13: separate phase, own switch `SANDBOX_MACHINES_ENABLED`. Includes: the egress proxy (default-deny, per-class allow-list, credential injection at egress), persistent volume per user, auto-enrolment as the user's "Cloud machine", idle stop, "continue in /code" and export, OpenShell evaluation first (ADR 0115 §OpenShell). | Not started |
| C117 | Sandboxes: PyPI installs in execute_code | Design agreed 2026-11-13, **owner: keep in backlog, do not start yet**. Wheels only (`--only-binary=:all:`, no build, no setup code), `--dry-run` check first with a clear refusal for packages without a wheel, the image pins as `--constraint` so preinstalled packages never change, install into the conversation sandbox workspace with a size cap. Network: minimal egress proxy pulled forward from phase 2, only pypi.org + files.pythonhosted.org (or a configured mirror). Admin policy: Ask (default: approval card per install, allow-listed packages skip it) | Allow-list only | Off. Import-time failures from missing system libs come back as normal Python errors. Today: admin-curated image via `SANDBOX_EXEC_IMAGE`. | Backlog (on hold) |
| C118 | Sandboxes: shared CPU/RAM budget | Owner 2026-11-13: personal box, at most 2-3 sandboxes together, never more than 1.5 cores / 1.5 GB in total. Fractional CPUs already work (`SANDBOX_EXEC_CPUS=0.5`). To build: a total budget so each sandbox can burst (e.g. up to 1 CPU / 1 GB) while all together stay under the cap — manager admission on reserved memory plus a fixed cgroup parent (systemd slice with CPUQuota/MemoryMax, created once by the operator), documented; per-sandbox reservation..limit ranges (memory-reservation, cpu-shares). | **Done**: #234 (v0.52.2): totals + reservations + optional cgroup slice; also fixed two proxy bypasses found in review (duplicate JSON keys, shipped in v0.52.1; non-finite numbers). Follow-up: require `Init === true` in the proxy (`"Init": null` drops tini). |
| C119 | Sandboxes follow-ups from #231 | Warm pool (`SANDBOX_WARM_POOL_SIZE`); stage files made by the document tools; usage (`UsageSink`) into Pystino quotas and the turn cost; one lease map shared across chat replicas; restore a staged file the code overwrote; rich outputs (DataFrames as HTML) via the daemon seam; at chat start the first "[code-execution] … runs in the person's browser" warning is logged before the first health probe (misleading when the manager is healthy a few ms later); chat should wait for the manager (compose depends_on: service_healthy) so the first calls do not fall back. | Backlog |
| C120 | Browser use phase 2 UI: live view and takeover screens | Plumbing is PR #214, **on hold by owner** until the UX is settled (agents: browser opened on request like the terminal; chat: live view opens when the agent needs the user; always show where it runs). Phase 2b H.264 stream later. ADR 0116 §6. | On hold |
| C121 | Browser extension as an entry point for chat-only users | Discussed 2026-11-13: an extension could replace the connector for browser-only users (chrome.debugger, sign-in to Cerea, runtime logic in the extension); ~1-1.5 weeks; yellow debugging bar; Web Store review. ADR 0116 option C. | Idea, not decided |
| C122 | Prune old artifact versions | **In progress** (owner go 2026-11-18; versions with an active share link are always kept). Owner 2026-11-13. Today versions go only with the chat or the file retention (`CHAT_FILE_RETENTION_DAYS`, all versions alike). Build: (1) per artifact, "Delete older versions" in the side panel's version menu, keeping the current one; old chat cards pointing at a removed version say it was deleted; (2) per deployment, a "keep at most N versions" admin setting (env + Administration → Storage), older versions swept by the deliverable sweep. Covers text artifacts and file artifacts (blobs freed). Docs: artifacts.md, chat-admin.md, configuration.md. | Backlog |
| C123 | Conversation-scoped memory; session/workspace memory for agents | Owner go 2026-11-13: build it, agents get NO global memory at all. Brief `reports/briefs/2026-11-13-scoped-memory.md`. Scopes conversation/project/global for chat (narrowest by default, global only when explicit), visible Notes control, notes injected every turn; agents via galopin MCP tools with session and workspace scopes only, enforced server-side. | **Parked** 2026-11-14: owner unsure chat memory is useful. PR #236 open, not merged (head 2ef6503e, chat side only; agent parts removed). Next idea if resumed: pins + a `check_notes` pull tool, nothing injected. WIP simplification on branch `wip/scoped-memory-simplify`. |
| C124 | e2e flake: code-transcript-paging | Seen 2026-11-13 on #234 CI (e2e-full shard 3): `tests/code-transcript-paging.spec.ts` failed once, passed on rerun; #234 does not touch it. Reproduce (≤3 repeats), keep artifacts, fix at the cause. 2026-11-14: failed 3× in a row on a #236 commit when the agent screen fetched the notes count on mount; #236 now loads the count only after Notes is first opened (badge hidden until then) — likely timing-sensitive, find the real cause and restore the always-visible badge. |  |
| C125 | Flake: execd timeout test | Seen 2026-11-13 on #234 CI (`sandbox` job): `sandbox/exec-image` test_execd `Client.test_a_timeout_replaces_the_interpreter_not_just_its_namespace` IndexError on empty daemon output (start-up timing); passed on rerun. Fix the wait-for-daemon-ready in the test. | Recurred 2026-11-17 in the v0.54.3 release CI (`test_a_timeout_replaces_the_interpreter_not_just_its_namespace`: empty stdout → IndexError). |
| C126 | Prompt cache: project knowledge passages in the system prompt | Found by the C123 worker 2026-11-14: project knowledge-base retrieval passages (`projectContext`) are built from the current question and ride the system prompt, so a project with knowledge bases changes its prefix every turn (no prompt caching). Move them to the uncached tail like the C123 notes block. |  |
| C127 | Project context for coding agents (ADR 0118) | Owner 2026-11-14: ADR written, **kept warm, not starting now**. Workspace ↔ project link; generated git-ignored `.cerea/PROJECT.md` read at session start; read-only `project_search`/`project_file`/`project_chats` tools via galopin; "Continue in code" handover brief and report-back. Replaces the agent half of C123. | **Parked** 2026-11-14 (owner) |
| C128 | galopin upgrade follow-ups (#238 re-review) | Low, not blocking (machines are disposable): re-scan pids just before kill; `/proc` scan with a space in the install dir (compare `readlink /proc/PID/exe`, NUL-split cmdline); check the re-fetched script's header and prune saved `upgrade-*.sh`/`.log`; pass `XDG_DATA_HOME`/`XDG_CONFIG_HOME` to the detached run; clear the `was-running` marker after a successful restart in `upgrade_failed`; `--show` shebang check. | Backlog (low) |
| C129 | Client tests leak the viewport | #243 pinned ChatInput's own viewport (the victim). The leaking files remain: `SettingsShell.svelte.test.ts` (1400, never restored), `AgentHeaderRow.svelte.test.ts` (1200), `InstructionsSection.svelte.test.ts`. Restore the viewport in their `afterAll`, or reset it in a shared client setup `afterEach`. Also: `PairDeviceDialog` "remembers nothing" fails locally when the vitest UI writes to localStorage. |  |
| C130 | opencode 2 follow-ups (#239 re-review) | (1) The project-config + opencode-provider pair can still arise via a re-enroll that keeps an allowing policy, or an already-enrolled machine: check the resulting policy, and have `run` refuse or warn. (2) `checkFloor` only runs at opencode start: a repo's custom agent in a workspace opened later is not patched (only with --allow-project-config), and saved approvals created while running (launch TUI) are removed only at the next restart. (3) npm integrity for `@opencode/cli`. |  |
| C131 | Agent sessions without a name show an empty name (since v0.53.0) | Owner 2026-11-14, for the next patch batch. New /code sessions not given a name used to get a default (opencode's generated title, or the 1.x "New session - <date>" title, plus galopin's subagent suffix); on opencode 2.3.0 the name stays empty. Suspects: (1) the #239 floor denies opencode 2's hidden agents (compaction, title, summary), which may stop the title agent from naming sessions; (2) 2.x creates sessions with an empty title and galopin's adapter maps it through as-is. Fix: let the title agent run (it uses no tools) or have galopin/Cerea fall back to a default name (e.g. first prompt words, or "Session <date>"); add a test on the real binary. | **Done**: #245 (v0.53.1): not the floor; opencode 2 creates untitled sessions, galopin now names from the first prompt until the real title arrives; workspaces named by folder. |
| C132 | Phone top bar: content cut off abruptly under it | Owner 2026-11-14 (screenshot), next patch batch. In chat and in the agent view on a phone, scrolled content (answer boxes) is clipped hard at the top bar's edge, so rounded boxes lose their corners abruptly. Preferred: a short fade, so content dissolves as it scrolls under the bar (a mask-image / gradient on the scroll container's top edge, in the bar's background colour for both themes); alternative: let content pass visibly under a translucent bar. Same treatment in chat and /code; keep safe-area insets. | **Done**: #245 (v0.53.1): top fade on phone scroller once scrolled. |
| C140 | History budget across turns | Several turns each under the 25% large-content cutoff (C138) can still add up past the window; the history budget should account for it. |  |
| C141 | Pystino: self-hosted servers (vLLM, SGLang, llama.cpp) | **Done** (Pystino 0.33.4 #70, Cerea #254, released in v0.54.1) (owner go 2026-11-16; Pystino feat/self-hosted-servers + Cerea fix/search-without-tools-hint). Adds vLLM, SGLang, llama.cpp catalogue presets. Original scope: probe the server kind and read the real context window (vLLM/SGLang `max_model_len`, llama.cpp `/props` per-slot n_ctx); warn when tool calls arrive as text (missing `--tool-call-parser`, e.g. DeepSeek V4 DSML on SGLang needs `--tool-call-parser deepseekv4 --reasoning-parser deepseek-v4`); llama.cpp `timings.cache_n` for cache counts. Detection only, no fallback parser unless the owner asks. Live test with llama.cpp on CPU. Also (2026-11-16, DeepSeek V4 on SGLang at the sslip.io deployment): probe and propose capabilities for a self-hosted model on add (empty `supported_features` made Cerea treat it as tool-less, so no web_search); a per-model default reasoning effort in the catalogue (SGLang thinking is off unless an effort is sent); Cerea hint when web search is on but the model has no tools. Report: reports/2026-11-16-sglang-deepseek-v4-compliance.md. |  |
| C146 | Share links for artifacts (ADR 0120) | Owner go 2026-11-17: snapshot links, per-link audience (signed-in default / anyone), expiry, revoke, Settings + admin lists; on by default via env, admin panel global toggle (no per-group); ./configure sets subdomain or path prefix (path warns); HTML sandboxed with band. In progress. |  |
| C145 | CI/build depends on jsdelivr for Pyodide wheels | `scripts/sync_pyodide_wheels.mjs` fetches every wheel from cdn.jsdelivr.net on each build; a jsdelivr 503 outage (2026-11-16) failed every e2e job and would fail a release. Cache the wheels (actions/cache keyed on the Pyodide version) and retry transient 5xx with backoff in the sync script. |  |
| C144 | Cerea never read the gateway's `context_window` | **Done** #255 (v0.54.1): `models.ts` read only HF-router `providers[].context_length`, so every gateway model had no window and all window-based budgets (history, large-content cutoff, sub-agents) used fallbacks. Now reads top-level `context_window`, min of positive values; a provider reporting 0 no longer fails the listing. Same PR: prose/data classification for large-content notes, inlined attachments marked as already read. |  |
| C143 | Flake: `tests/chat-slides.spec.ts:32` slides fullscreen exit timeout | Failed on #246 and twice on #254 (unrelated changes); passes on retry. Fix at the cause after the next release. |  |
| C142 | Configure + Pystino: no default upstream, agents on, origin hints, console view switch | **Done** Cerea #252, Pystino #68 #69 (Pystino 0.33.3, Cerea v0.54.0). Old seeded `default` placeholders on existing deployments left in place. |  |
| C138 | Large content reaches the model as a file read with code (ADR 0119) | **Done** #253 (v0.54.0). Owner go 2026-11-15: >25% of window → sample + note + `/mnt/data`; prose chunking prompted (ask user, sub-agents), not coded. Coded chunking dropped. Pre-flight token estimate, card (chunks / switch model / edit), sequential sub-agents with rolling notes. |  |
| C139 | Pystino local document reader caps at 25 MB | `services/redaction/src/llmp_redaction/documents.py:92` `MAX_BYTES = 25 MiB`; Cerea now takes 30 MB attachments (#250), so 25–30 MB docs via the local reader get "larger than the extractor will inspect". Raise to 30 MiB in a Pystino release + kit pin. Also: server holds ~3 copies of a 30 MB file in extractDocument (base64 JSON); no client-side total check vs the 100 MB body limit (4+ big files give an opaque 413). |  |
| C135 | Flake: `tests/code-machine-terminal.spec.ts` "on a phone, a swipe scrolls the scrollback" | Failed once on e2e-full shard 2 in #246 (unrelated change), passed on rerun. Test-only until shown otherwise; fix after the release. |  |
| C136 | Chat archive | **Done** #246 (v0.53.2): Archive in the ⋯ menus, /chats Archived tab, project chats leave the project, a new message unarchives. No undo toast (no action-toast pattern yet); archived chats' artifacts stay in the Artifacts tab. |  |
| C137 | `.jsonl` / `.ndjson` attachments | **Done** #248 (v0.53.2): chat, agent sessions, project files, knowledge bases; stored as text by extension. |  |
| C134 | Browser use: long pages ended the run ("too large to read") | **Done** #247 (2026-11-15): galopin re-encoded results with HTML escaping (up to 6x), tripping the 1 MiB link cap. Now no escaping, 8 MiB cap, runtime result limit 7.5 MB; an oversize result is a tool error the model reads, not a stop. Needs galopin upgrade. Model-facing text limits unchanged. |  |
| C133 | galopin: opt-in opencode Code Mode (`--allow-code-mode`) | **Held by owner 2026-11-15.** Design: approve a Code Mode script as a whole (user card, or the reviewer model under Auto, escalating when unsure), inner calls covered, hard denies win. Blocked on opencode 2.3.0: `execute` raises no permission ask (script only visible once running), and `opencode.*` inner utilities (session_rename/move, worktree_create/remove, MCP resources) never ask. Inner MCP and fetch asks do carry the parent callId. Unblock when opencode adds an `execute` ask or a way to deny `opencode.*` inner tools (watch the daily `latest` job). Plumbing parked uncommitted in `Cerea-wt-codemode` (branch feat/allow-code-mode; `CODEMODE_FINDING` placeholder; delete `probe_it_test.go`). |  |
| C109 | Open the browser from Cerea, and computer choice | **Done**: merged as Cerea #210 (v0.51.0). 
- **Button:** in the composer + menu, "Open browser…" (optional address), tied to the chat as its kept page, so no use_tab approval is needed. Also "Open browser" on each computer's Connectors card for setup; that page is a user tab.
- **Computer choice**, shared with the browse tool:
  1. one ready computer: use it;
  2. a chat sticks to its computer;
  3. a per-user default ("Use for browsing by default");
  4. otherwise a "Which computer?" card, with Remember ticked; the model never picks;
  5. an offline choice stops the task, with no fallback.
- The browse tool's `machine` becomes a hint used only when the user named a computer. | In progress after #204. |
| C25 | Audit of sliding-panel and leaky tests | A class of work; no completion marker. | Fold into per-flake fixes. |
| C32 [#32](https://github.com/paoloviviani/Cerea/issues/32) | Client harness noise and hangs | `wrapDynamicImport` TypeError is still in the failing client run of 2026-11-05 (42026034710). | Parked. |
| C37 [#42](https://github.com/paoloviviani/Cerea/issues/42) | CodeNavTree flake | No fix commit; no recurrence in the last 200 runs. | Fix at the cause. |
| C43 | ChatInput cascade-submenu flake | No fix commit; no recurrence in the window. | Fix at the cause. |
| C45 / C57 | ToolUpdate thumbnail flake | No fix commit; no recurrence in the window. | Fix at the cause. |
| C49 | `TEST_DATABASE_URL` specs never run in CI | `deleteDerived.spec.ts` still skips without it; no workflow supplies it (grep). | **Done**: #229 adds a pgvector service and TEST_DATABASE_URL to the `check` job. |
| C56 | Pin `listKnowledgeFiles` URLs | `attachmentMountBase.svelte.spec.ts` exists. Whether it has the fifth case is not verified (only 2 hits for "knowledge"). | Check, then add the case. |
| C60 | Client flakes | The connectors "tapped on a phone" snapshot failed again on 2026-11-05 (run 42026034710, `feat/read-only-fast-path`), after the v0.37.0 fix. The KB submenu was fixed in v0.38.0. OfficePreviewWiring is local-only and unverified. | Re-open the connectors snapshot; see the correction list. |
| C66 | code-machine-parity timeout | Recurred in the 2026-11-05 runs. 41947602648 and 42008000219 were on main, 42069030503 on a branch, at `:674`, `:136` and `:172`. The sibling `code-stop-permission` and `code-auto-review` specs failed in the same runs. | Fix at the cause; it is no longer rare. |
| C68 | V8 start-up crash in CI | Mitigation shipped (f52bc052, v0.41.0: a retry only on exit 133). No exit-133 failure in the window. | Mitigated; keep watching. |
| C69 | CSV download carries a partial artifact | `chat-artifact-table.spec.ts:26` failed on main (42015100418) and in 42015426072 on 2026-11-05. The 3daf5e7f revoke change is in v0.42.0, and the failures came before that release; no run after the release is available to check. | Cause unknown; wait for another run. |
| (new) | Galopin `opencode` workflow failed on main | `TestPassthroughP3CeilingWinsAndAlwaysBecomesOnce` failed in run 42076436648 on `eeb5a72e`. The later commit 413ee66b ("Always allow over ask limit") may be the cause. It is not in the backlog. | Check against 413ee66b and give it a row. |

### Cerea chores
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| C19 [#36](https://github.com/paoloviviani/Cerea/issues/36) (Pystino [#20](https://github.com/paoloviviani/Pystino/issues/20)) | Coverage gaps; users API capability flags | Pystino #20 open. No WebKit run exists. | Parked. |
| C21 [#33](https://github.com/paoloviviani/Cerea/issues/33) | Shrink AGENTS.md | **Done** (7dada3c4; triage 2026-11-16). It is 1595 lines against a ~400 target. | **Done**: #232, AGENTS.md 1703 → 477 lines, subsystem detail moved to docs/dev/ (excluded from the public site). Nothing deleted; overlaps with MAINTAINING.md §5 and user docs left for a later pass. |
| C22 [#34](https://github.com/paoloviviani/Cerea/issues/34) (Pystino [#21](https://github.com/paoloviviani/Pystino/issues/21)) | Split the largest modules | Pystino `routers/admin.py` is still 7414 lines. | Parked. |
| C23 [#35](https://github.com/paoloviviani/Cerea/issues/35) | Shrink the chat image | Not done (issue open). | Needs the owner's package list. |
| C46 | OSM maps skill caveat | No "street" caveat in the OSM skill (grep). | Optional. |
| C51 | "users" vs "people" wording | `docs/writing.md` still says "people" and is unchanged. | Owner decision. |
| C52 | Sidebar folder delete on others' chats | In progress (see below); the other half is open (error paths without specs). | **Done**: fix/small-ui-bugs merged. |

### galopin
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| G1 [#19](https://github.com/paoloviviani/Cerea/issues/19) | opencode 2.x | The pin is still 1.19.3 (`agent/packaging/opencode-version`). Issue open. | **Done**: #239, opencode 2.3.0 (background subagents), v0.53.0. |
| G3 [#21](https://github.com/paoloviviani/Cerea/issues/21) | OS sandbox | Not built. Overlaps C72. | Merge with C72. |
| G12 [#24](https://github.com/paoloviviani/Cerea/issues/24) | Machines show offline after a restart | Issue open; not investigated in git. | Low priority. |
| G14 | `TMPDIR` inside the galopin tree | Still the case; per memory, `TMPDIR` points to `~/.config/galopin/opencode-tmp`. | Low priority. |
| G15 [#49](https://github.com/paoloviviani/Cerea/issues/49) | Opencode compatibility (standing) | The pin is 1.19.3 (`agent/packaging/opencode-version`; the kit changelog says the same). #49 is now the single standing issue (retitled 2026-11-09); the daily check reports 1.19.5 passes the real-opencode suite, so a bump is possible. #30 and #37 (superseded) and the earlier per-release issues are closed. From now on no issue is opened per opencode release: the standing issue replaces them. | **Done**: #239, opencode 2.3.0 (background subagents), v0.53.0. |
| G16 [Pystino #19](https://github.com/paoloviviani/Pystino/issues/19) | Spurious ERROR on standalone Pystino | Issue open. | Parked. |
| G7 | Document machine-installed skills | `docs/agent-machines-reference.md:176` documents it, so the docs half is Done (v0.17.0). | Move to Done. |

### Design / long term
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| P1 follow-ups | Routing | P1 itself is done; P2/P3 hold the rest. | See P2/P3. |
| C71, C72 | OTel and sandbox | See above. | ADR first. |

### Owner decisions
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| C51 | users vs people | Open (see above). | Owner. |
| C63, C59, C42, C41 | Parked ideas | Owner has parked them. | Leave parked. |

---

## 2. In progress

| ID | Title | Branch / evidence |
|---|---|---|
| C95 | Redaction visibility (ADR 0112, owner 2026-11-08): user rules tighten-only after the admin chain; per-user redaction log with no values; console "Redactions" page; per-response `pystino_redaction` summary (opt-in header; values only with a second header + OIDC, never stored); Cerea info dot (tokens, speed, cost; yellow/red on redaction/block) with overlay and "show hidden values" setting | **Done**: merged feat/turn-info-redaction (ADR 0112) and the Pystino side. |
| C90 | Slides artifact (reveal.js, Markdown in, Cerea presets + accent/font/logo, org default, asks "present here or PowerPoint file?") — ADR 0111 | **Done**: merged feat/slides (ADR 0111). |
| G11 | "Always allow" on a file edit covers the whole session | **Done**: fix/edit-always-scope merged. |
| C27 | Slash command echo monospaced | **Done**: fix/small-ui-bugs merged. |
| C28 | Message actions vanish mid-turn | **Done**: fix/small-ui-bugs merged. |
| C29 | "Something else" shown twice | **Done**: fix/small-ui-bugs merged. |
| C65 | Refused 410 shows nothing | **Done**: fix/small-ui-bugs merged. |
| C52 | Sidebar folder delete | **Done**: fix/small-ui-bugs merged. |
| C48 | `search` 500 on an unreachable width | **Done**: fix/small-server-bugs merged. |
| C38 | `look_doc` | **Done**: v0.32.3. Remove "in progress". |
| C73 | Secret value in outbound command | Issue #113, queued for the next release; no branch yet. |

---

## 3. Done since the backlog was written (or never marked)

### Pystino
| ID | Title | Release |
|---|---|---|
| C91 | Pre-commit hook used the shared git stash (lint-staged); now `--no-stash` (race reproduced 5/220 before, 0/160 after) | #156, 2026-11-07 |
| P1 | Routing policies, stickiness, fallback | v0.14.0 |
| P4 | YAML provider catalogue | v0.15.0 |
| P5 | Chat completions over native Messages | v0.23.0 (issue #6 closed 2026-11-09) |
| P7 | Per-user quota ceiling | v0.14.0 |
| P9 | Admin audit log | v0.13.0 |
| P10 | Empty `/v1/models` on a scoped key | v0.13.0 (not reproduced) |
| P11 | Quota admission race | v0.13.0 |
| P12 | `packages/ui` i18n | v0.13.0 |
| P14 | Live checks with a non-admin | v0.13.0 |
| P15 | AGENTS.md open items | v0.13.0 |
| P16 | Per-size image pricing | v0.13.0 |
| P17 | Request log | v0.13.0 |
| P18 | Usage charts, per-provider | v0.15.0 |
| P20 | PG test conftest drops per-test databases | v0.15.0 (e57137c) |
| [#18](https://github.com/paoloviviani/Pystino/issues/18) | Speech-to-text (transcription) models: `/v1/audio/transcriptions` and translations, priced per minute of audio | v0.21.0 (issue closed 2026-11-06) |

### Cerea
| ID | Title | Release |
|---|---|---|
| C2 | Chat i18n foundation | v0.25.0 |
| C3 | web_fetch cross-turn cache | v0.17.0 |
| C4 | gatewaySession fold race | v0.17.0 |
| C5 | MongoDB 8 default (4.4 fallback) | v0.17.0, kit follow-up v0.24.0 |
| C7 | Keep the fresh-kit log | v0.17.0 |
| C8 | `as unknown as` audit | v0.17.0 |
| C9 | Exclusive model-access modes | v0.17.0 |
| C10 | Office previews (Gotenberg, pptx-glimpse) | v0.18.0 |
| C15 | Voice input (browser speech recognition) | v0.21.0 |
| C16 | Push notifications | v0.21.0 |
| C18 | Opt-in location | v0.21.0 |
| C24 | Playwright 1.64.1 | v0.25.0 |
| C31 | Connector modes and `load_tools` | v0.32.0 |
| C33 | NavMenu and CodeTerminal flakes | v0.18.0 / v0.21.0 |
| C35 | Admin connector description | v0.32.1 |
| C38 | `look_doc` | v0.32.3 |
| C44 | Delete in the chats-list row menu | v0.32.4 |
| C47 | Docs nav tabs | v0.32.4 |
| C53 | Attachment "current" version | v0.32.4 |
| C55 | Dead `draftEmitAt` store | `draftEmitAt` is now used (`runMcpFlow.ts:1139`); the other two notes are unverified |
| C58 | HTML artifact load errors | v0.35.0 |
| C62 | Mobile keyboard/PWA | v0.37.0 |
| C64 | /code file editor (#78, #69) | v0.39.0 |
| C67 | Chat drives coding-agent sessions | v0.40.0 |
| C70 | Shared projects list own chats | v0.41.0 |
| C20 [#31](https://github.com/paoloviviani/Cerea/issues/31) | Ask card resets a pick | v0.24.0 (`fix/ask-question-reset`; issue closed 2026-10-24; the app-level race was not re-verified) |
| C54 | Sandbox mount "current" exceptions | Done (#119) |
| C97 | Reader choice: past-chats embedding picker, per-base and per-user document readers, "Re-read with…" (Cerea [#178](https://github.com/paoloviviani/Cerea/pull/178), [#179](https://github.com/paoloviviani/Cerea/pull/179), [#181](https://github.com/paoloviviani/Cerea/pull/181)) | 0.48.0 |

### galopin
| ID | Title | Release |
|---|---|---|
| G2 | Coordination over MCP | v0.19.0 |
| G4 | Delegate profiles and recipes | v0.19.0 |
| G6 | opencode pin 1.19.3 | merged (d8f71a87) |
| G7 | Machine-skills docs | v0.17.0 |
| G8 | Cancelled background tasks reported | v0.17.0 |
| G13 | Re-enroll keeps policy flags (ADR 0107) | v0.41.0 (issue #25 closed 2026-11-09) |
| G17 | `files.*` ops (list, stat, read, status, write) | v0.39.0; `fileSearch` and `fileWatch` stay reserved |
| G11 (relabel half) | "Always allow edits (this session)" | **Done**: fix/edit-always-scope merged. |

---

## 4. Dropped / Parked

| ID | Item | Decision |
|---|---|---|
| C26 | Move-to-project on the open chat page | Dropped 2026-10-25 |
| C74 | Workspace config that runs code on open | Dropped by the owner 2026-11-06; issue #114 is closed |
| P19 | Redaction allow-list combine | Dropped (owner plan, 2026-11-09): taking the allow-list from the first policy is the design (ADR 0038) |
| P21 | `pystino_postgres-data` volume check | Dropped (owner plan, 2026-11-09): not verifiable from git |
| C34 | Reused login code gives 500 | Dropped (owner plan, 2026-11-09) |
| P6 | Refuse Anthropic server tools on `/v1/messages` | Rejected |
| G5 | Billing group per session | Rejected |
| G9 | Report to opencode upstream | Rejected |
| G10 | Free-model sessions | Not a leak |
| C6, C14 | MongoDB EOL plan; DocumentDB/FerretDB | Rejected or merged into C5 |
| C1 | Dex in front of Authelia | Parked; spike branch only |
| C42, C41, C59, C63 | MCP Apps, skills-first, chat/code bridge, M365 reference | Parked |
| G1, G3 | opencode 2.x, OS sandbox | Parked or long-term |

---
