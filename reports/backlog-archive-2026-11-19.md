# Backlog archive, 2026-11-19

Rows closed out of `backlog.md` on 2026-11-19 after a check against `origin/main`, release tags (Cerea v0.59.0, Pystino 0.33.4) and issue states. Detail for older IDs is in `backlog-archive-2026-11-06.md`; the 2026-11-06 rewrite had its own Done list, kept below as section B.

## A. Done since 2026-11-06

### Shipped releases (no row before)

| Item | PR / version |
|---|---|
| Artifact-aware history: stubs for old versions, current versions at the tail, artifact read | #291, v0.57.0 |
| Italian interface, language picker, checks | #293, v0.58.0 |
| Mistral Vibe as a coding engine (galopin) | #294, v0.58.0 |
| Failed turns keep partial output; Retry/Continue; no request ends on an assistant message | #295, v0.58.0 |
| Accept any text file as an attachment, decided by content | #296, v0.58.0 |
| UI polish: Warm default tone, Neutral grey tone, no dots; composer with only +, model and shield; web search always on with a Settings opt-out; top fade | #298, v0.59.0 |
| Share links for artifacts (ADR 0120) | #276, #279, v0.55.0 |
| Review log sign-in-again card; delete older versions on artifact lists | #287 |
| File browser: chunked upload to 200 MB, folder upload, folder zip; Workspace screen with Terminal and Files | #271, #273 |
| Docs: landing page, accuracy pass, screenshots, AGENTS.md refresh | #280, #282, #284, #285 |

### Rows

| ID | Title | PR / version |
|---|---|---|
| C21 | Shrink AGENTS.md (1703 to 477 lines, subsystem detail to docs/dev/) | #232 |
| C27 | Slash command echo monospaced | fix/small-ui-bugs |
| C28 | Message actions vanish mid-turn | fix/small-ui-bugs |
| C29 | "Something else" shown twice | fix/small-ui-bugs |
| C48 | `search` 500 on an unreachable width | fix/small-server-bugs |
| C49 | Postgres-only specs run in CI | #229 |
| C51 | "users" vs "people" wording (owner chose "users"; `docs/writing.md`) | docs/writing.md |
| C52 | Sidebar folder delete on others' chats | fix/small-ui-bugs |
| C60 | Admin connectors phone-tap snapshot flake | #142 |
| C65 | Refused 410 shows nothing | fix/small-ui-bugs |
| C72 | Sandbox ADR (ADR 0115; class E `execute_code` sandboxes shipped) | #225, #231, v0.52.x |
| C87 | Sidebar redesign, Command palette, Workspace tabs 8 to 6 | #143, #144, #145, #208 |
| C88 | Project page TOC scroll and floating save bar | #145 |
| C89 | Stale "re-enroll" notice after ADR 0109 | #145 |
| C90 | Slides artifact (ADR 0111) | feat/slides |
| C92 | Phone UI density | #160, v0.53.0 |
| C94 | Admin Services page | #226 |
| C95 | Redaction visibility (ADR 0112) | feat/turn-info-redaction, Pystino #50 |
| C98 | Approval card "Show details" kept across re-key | #227 |
| C100 | Sidebar Recents selector | #208, v0.51.0 |
| C101 | Schedules per-user cap race | #207 |
| C103 | galopin link drops every ~15 min | #202 |
| C104 | Kit: MongoDB patch bump (8.0.38 after 8.0.37 turned out not to exist) | #227, #233 |
| C107 | Schedules per-device cap race | #227 |
| C108 | Cerea connector macOS menu-bar app (including the Edit connectors item) | #209 |
| C109 | Open the browser from Cerea; computer choice | #210, v0.51.0 |
| C110 | Per-user cap race test flake | #213 |
| C111 | browser-runtime popup flake | #224 |
| C118 | Sandbox shared CPU/RAM budget | #234, v0.52.2 |
| C122 | Prune old artifact versions | #286, v0.56.0 |
| C131 | Agent sessions without a name | #245, v0.53.1 |
| C132 | Phone top bar fade | #245, v0.53.1 |
| C134 | Browser use: long pages ended the run | #247 |
| C135 | Phone swipe terminal flake | #251 |
| C136 | Chat archive | #246, v0.53.2 |
| C137 | `.jsonl` / `.ndjson` attachments | #248, v0.53.2 |
| C138 | Large content as a file read with code (ADR 0119) | #253, v0.54.0 |
| C141 | Pystino: self-hosted servers (vLLM, SGLang, llama.cpp) | Pystino #70 (0.33.4), Cerea #254, v0.54.1 |
| C142 | Configure + Pystino: no default upstream, agents on, console view switch | Cerea #252, Pystino #68 #69, v0.54.0 |
| C144 | Cerea reads the gateway's `context_window` | #255, v0.54.1 |
| C145 | Pyodide wheel sync retries transient CDN failures | #262 |
| C146 | Share links for artifacts (ADR 0120) | #276, v0.55.0 |
| G1 | opencode 2.x; goose engine (ADR 0110); Mistral Vibe | #239 (v0.53.0), #294 (v0.58.0) |
| G7 | Machine-skills docs | v0.17.0 |
| G11 | "Always allow" on a file edit scoped to the file | fix/edit-always-scope |
| G15 | opencode compatibility (standing issue closed) | #239, v0.53.0 |
| C38 | `look_doc` | v0.32.3 |
| (PR #135) | Pair dialog stray note and plain project-config text | #135 |

## B. Done before 2026-11-19 (the 2026-11-06 rewrite's list)

### Pystino
| ID | Title | Release |
|---|---|---|
| C91 | Pre-commit hook uses `--no-stash` | #156 |
| P1 | Routing policies, stickiness, fallback | v0.14.0 |
| P4 | YAML provider catalogue | v0.15.0 |
| P5 | Chat completions over native Messages | v0.23.0 |
| P7 | Per-user quota ceiling | v0.14.0 |
| P9 | Admin audit log | v0.13.0 |
| P10 | Empty `/v1/models` on a scoped key | v0.13.0 |
| P11 | Quota admission race | v0.13.0 |
| P12 | `packages/ui` i18n | v0.13.0 |
| P14 | Live checks with a non-admin | v0.13.0 |
| P15 | AGENTS.md open items | v0.13.0 |
| P16 | Per-size image pricing | v0.13.0 |
| P17 | Request log | v0.13.0 |
| P18 | Usage charts, per-provider | v0.15.0 |
| P20 | PG test conftest drops per-test databases | v0.15.0 |
| Pystino #18 | Speech-to-text models | v0.21.0 |

### Cerea
| ID | Title | Release |
|---|---|---|
| C2 | Chat i18n foundation | v0.25.0 |
| C3 | web_fetch cross-turn cache | v0.17.0 |
| C4 | gatewaySession fold race | v0.17.0 |
| C5 | MongoDB 8 default | v0.17.0 |
| C7 | Keep the fresh-kit log | v0.17.0 |
| C8 | `as unknown as` audit | v0.17.0 |
| C9 | Exclusive model-access modes | v0.17.0 |
| C10 | Office previews | v0.18.0 |
| C15 | Voice input | v0.21.0 |
| C16 | Push notifications | v0.21.0 |
| C18 | Opt-in location | v0.21.0 |
| C20 | Ask card resets a pick | v0.24.0 |
| C24 | Playwright 1.64.1 | v0.25.0 |
| C31 | Connector modes and `load_tools` | v0.32.0 |
| C33 | NavMenu and CodeTerminal flakes | v0.18.0 / v0.21.0 |
| C35 | Admin connector description | v0.32.1 |
| C44 | Delete in the chats-list row menu | v0.32.4 |
| C47 | Docs nav tabs | v0.32.4 |
| C53 | Attachment "current" version | v0.32.4 |
| C54 | Sandbox mount "current" exceptions | #119 |
| C55 | Dead `draftEmitAt` store | `draftEmitAt` is used |
| C58 | HTML artifact load errors | v0.35.0 |
| C62 | Mobile keyboard/PWA | v0.37.0 |
| C64 | /code file editor | v0.39.0 |
| C67 | Chat drives coding-agent sessions | v0.40.0 |
| C70 | Shared projects list own chats | v0.41.0 |
| C97 | Reader choice | #178, #179, #181, v0.48.0 |

### galopin
| ID | Title | Release |
|---|---|---|
| G2 | Coordination over MCP | v0.19.0 |
| G4 | Delegate profiles and recipes | v0.19.0 |
| G6 | opencode pin 1.19.3 | d8f71a87 |
| G8 | Cancelled background tasks reported | v0.17.0 |
| G13 | Re-enroll keeps policy flags (ADR 0107) | v0.41.0 |
| G17 | `files.*` ops | v0.39.0 |

## C. Dropped (earlier decisions, moved here from the old Dropped / Parked table)

C26 (move-to-project on open chat, 2026-10-25); C74 (workspace config that runs code on open, owner 2026-11-06); P19 (allow-list combine, ADR 0038 is the design); P21 (volume check, not verifiable from git); C34 (reused login code gives 500); P6 (refuse Anthropic server tools on `/v1/messages`, rejected); G5 (billing group per session, rejected); G9 (report to opencode upstream, rejected); G10 (free-model sessions, not a leak); C6, C14 (MongoDB EOL plan; DocumentDB/FerretDB, rejected or merged into C5).
