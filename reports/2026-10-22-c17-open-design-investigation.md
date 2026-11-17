# C17 spike: Open Design and Open CoDesign (2026-10-22)

Read-only. Clones were `--depth 1`, nothing installed or executed. Paths are relative to each repo root (OD = nexu-io/open-design v0.25.1 package, release 0.26.0; OCD = OpenCoworkAI/open-codesign v0.2.0 package, release v0.2.2).

## Summary
- Both licences are as claimed (Apache-2.0, MIT). Neither is copyleft at the top level. Dependency licences were not audited, because that needs an install.
- Open Design (OD) is the better fit and is much more active (103k stars, releases every 1 to 3 weeks). Its `byok-opencode` agent is a plain `opencode run` spawn with an `@ai-sdk/openai-compatible` provider at an arbitrary baseUrl. That is the same shape galopin already writes for opencode, so pointing it at galopin's local shim (`http://127.0.0.1:41871/v1`) works with no gateway change. This is the only route to Pystino billing under the person's own identity without minting tokens.
- Open CoDesign (OCD) can also be pointed at an OpenAI-compatible base URL (config.toml / Settings UI). But it is a desktop Electron app with no headless run (its CLI says "Unsupported: run"). It has no daemon, so it cannot be a galopin backend.
- OD's daemon does not talk to an existing `opencode serve`. It spawns its own `opencode run --format json` per run. So "galopin runs OD's daemon" is feasible but is a second agent runtime next to galopin's. It would sit outside galopin's permission model (OD passes `--dangerously-skip-permissions`) and outside the Cerea code panel.

## Recommendation
Do (a) now, then (b). Skip (c) and (d).
1. (a) Document both tools against Pystino: about 0.5 day, no risk. For OD, use BYOK with protocol "openai", baseUrl = the galopin shim, apiKey = the shim secret. For OCD, add a custom OpenAI-compatible provider. Include the caveat that this is the user's own local app, and that the shim secret is a localhost credential.
2. (b) A native Cerea "design" skill/artifact pattern: about 3 to 5 days. Both prompt sets are reusable (OD is Apache-2.0, OCD is MIT; keep attribution). Cerea already renders HTML/React/SVG artifacts, so it needs the methodology and anti-slop rules, not an app.
3. Do not take (c) or (d) before there is demand. (c) is 2 to 3 weeks plus ongoing upkeep: OD releases weekly, its daemon is about 18k lines in `server.ts` alone, and it needs Node 24 and pnpm. (d) is a fork-and-maintain burden for a fast-moving upstream.

Open point: the feature freeze (memory) means (b) is a new feature and needs the owner's say-so. (a) is docs only.

## 1. Licence, dependencies, maturity
| | OD | OCD |
|---|---|---|
| LICENSE | Apache-2.0 full text (`LICENSE`); `package.json:8` "Apache-2.0" | MIT, "Copyright (c) 2026 OpenCoworkAI Contributors" (`LICENSE`); `package.json:6` "MIT" |
| Notices | no NOTICE file | `NOTICE` lists pi-ai, Electron, pptxgenjs, dom-to-pptx, esbuild (all MIT) |
| Stars / age | 103,132; created 2026-04-28 | 8,091; created 2026-04-18 |
| Last push | 2026-10-22 | 2026-10-21 |
| Releases | 0.22.2 (09-10), 0.23.0 (09-20), 0.24.0 (09-22), 0.24.1 (09-24), 0.25.0 (10-15), 0.26.0 (10-20) | v0.1.2 to v0.1.4 (04-21 to 04-23), v0.2.0 (05-09), v0.2.1 (05-23), v0.2.2 (09-19); a 4-month gap, then branch work |
| Maintainers | Company-run (`MAINTAINERS.md`: Core Team internal roster, external maintainers cannot merge). About 100 contributors. | Small org "OpenCoworkAI". Few contributors, WeChat group. |

Bundled content licences (OD): `skills/README.md:15` says skills are Apache-2.0 unless their own LICENSE says otherwise. `README.md:735` lists MIT exceptions: `design-templates/guizang-ppt` (@op7418), `design-templates/html-ppt` (@lewislulu), `skills/web-clone` (@Jane-xiaoer). `skills/frontend-design/LICENSE.txt` is Apache-2.0. All permissive. If reusing templates, copy each LICENSE.

Dependencies of note:
- OD daemon: `better-sqlite3`, `pdf-lib`, `@ffmpeg-installer/ffmpeg` (`apps/daemon/package.json`). The ffmpeg installer downloads an ffmpeg binary that may be GPL or LGPL. Check this before shipping or embedding. It is irrelevant if we only reuse prompts.
- OD telemetry: `PRIVACY.md:16`, "Safety and reliability telemetry is always enabled in builds configured with a telemetry destination", and usage telemetry/session replay is on by default after a first-run prompt (`PRIVACY.md:26`). This conflicts with a redaction-focused deployment, so document how to disable it.
- OCD: `@mariozechner/pi-ai`/pi-agent-core (MIT), puppeteer-core (Apache), electron-builder, smol-toml. Nothing copyleft seen at top level.

## 2. How they talk to models
OD:
- Two modes. (i) Local agent CLIs (about 27 definitions: Claude Code, Codex, OpenCode, Cursor, Qwen, ...; `apps/daemon/src/runtimes/registry.ts`). (ii) BYOK: `byok-opencode` (`runtimes/defs/byok-opencode.ts`, `runtimes/byok-opencode.ts`) plus a REST proxy `POST /api/proxy/{anthropic,openai,azure,google,ollama,senseaudio}/stream` (`routes/chat.ts:986-2365`).
- OpenAI-compatible base URL and key: yes. `ByokChatProviderConfig` {protocol: anthropic|openai|azure|google|ollama|senseaudio|aihubmix, baseUrl, apiKey, apiVersion, requiresApiKey}. `docs/headless-byok.md` says "Use 'openai' for a custom OpenAI-compatible gateway" and that baseUrl includes `/v1`. It is set in the UI (Settings, Models & providers) or per run in the REST body. The key travels to the child as env `OPEN_DESIGN_BYOK_API_KEY`, and the config goes in `OPENCODE_CONFIG_CONTENT` (`server.ts:14949`). The provider is `@ai-sdk/openai-compatible` for custom hosts (`byok-opencode.ts:buildProviderEntry`).
- Streaming: yes (SSE). Tool calling: required for the opencode path, since opencode owns the loop and uses Read/Write/Edit. The plain proxy mode returns one `<artifact>` block with no tools (`README.md:294`).
- Capabilities assumed: model id must be explicit ("default" is rejected). It declares 128k context, 16,384 output, and image input allowed (`byok-opencode.ts:7-8,80-90`). Vision is not required, but images are forwarded if present.
- Custom headers: none in `ByokChatProviderConfig` that I found, so x-bill-to cannot be set per request. The shim adds it.

OCD:
- Wire protocols: anthropic, openai-chat, openai-responses, openai-codex-responses, azure-openai-responses, google (`packages/shared/src/config.ts:6-40`), via pi-ai.
- OpenAI-compatible: yes. `ProviderEntrySchema` (`config.ts:158-205`) has `baseUrl`, `wire`, `envKey`, `httpHeaders` (custom headers, so `x-bill-to` could be set directly), `queryParams`, `requiresApiKey`, `contextWindow`, `tlsRejectUnauthorized`. Set in Settings or in `~/.config/open-codesign/config.toml` (`apps/desktop/src/main/config.ts:15-28`, plaintext keys). `README.md:232` documents "No API key required" and Responses wire.
- Streaming: yes (`streamSimple`, `packages/core/src/agent.ts:1407`). Tool calling: required (agent loop with about 20 tools: str_replace_based_edit_tool, scaffold, preview, done, tweaks, ask, web_search...; `packages/shared/src/tool-manifest.ts`). Vision is used only for the optional ui-kit visual parity check and image input. Long context is helped by context pruning (`context-prune.ts`).

## 3. Pystino /v1 under the person's identity
Cerea's mechanism (`docs/agent-machines.md:1220-1300`, `agent/serve.go:109-141, 500-545`): `galopin enroll` writes an `opencode.json` with a provider `npm: @ai-sdk/openai-compatible`, `baseURL: http://127.0.0.1:41871/v1`, and a per-install shim secret as `apiKey`. The shim drops the caller's Authorization, injects a fresh OIDC bearer and the recorded `x-bill-to`, and requires Host=loopback plus the shim secret. So any local OpenAI-compatible client can be metered as the person with no token handling of its own.
- OD: works as is. OD blocks private IPs for provider URLs (SSRF guard, `README.md:365`), but loopback is carved out (`connectionTest.ts:113-180`). The `OD_ALLOWED_INTERNAL_HOSTS` allowlist exists for non-loopback hosts. The model name must be one from `GET /v1/models` (Pystino aliases are fine), with the id typed in, because "default" is rejected. Nothing in OD requires OpenAI-only models. What breaks: model-name assumptions in OD's fallback lists (`defs/opencode.ts` lists anthropic/openai ids, irrelevant for BYOK); `limit` of 128k/16k may not match a Pystino model; no OD header injection, so group billing relies on the shim.
- OCD: a custom provider with `httpHeaders = { "x-bill-to": ... }` could talk directly, but a static `apiKey` expires (OIDC), so use the shim URL and secret, as opencode does. OCD's "local/private endpoint" test asks for a network confirmation. config.toml keeps the secret in plaintext, which is acceptable for a localhost-only shim secret.
- Unmet: a Cerea-minted per-person token for the web chat flow is not needed for either. Both are local apps run by the person, so they use the machine's enrolment. A hosted deployment of OD in Cerea's infrastructure would need a per-person token or shim per session, which does not exist.

## 4. OD daemon and agent CLIs
- Launch: per run it spawns `opencode run --format json [--dir CWD] --dangerously-skip-permissions [-m open-design-byok/<model>]` with the prompt on stdin (`defs/byok-opencode.ts`; plain `opencode` in `defs/opencode.ts`). It never uses `opencode serve`. The "AMR" runtime does start a private opencode server but only through a vendor bridge (`defs/amr.ts`).
- Could OD talk to an existing opencode server? No code path for that. Options: (1) set `OPENCODE_BIN` to a wrapper that talks to galopin's server (hacky, because the output format `--format json` must be reproduced); (2) run OD's daemon on the person's machine next to galopin, with galopin's shim as the provider (works today, but galopin's permission broker and audit are bypassed and the code panel does not see OD's sessions); (3) add an ACP adapter (OD has ACP runtimes, `agent-protocol/acp/`, `docs/new-agent-runtime-acp.md`) and have galopin speak ACP. That is the clean route, and its size is unknown (galopin already supervises ACP agents, `agent-machines.md:158-160`).
- Daemon exposure: default bind 127.0.0.1, port 7456 (`daemon-startup.ts:31,55`; `OD_PORT`, `OD_BIND_HOST`). A non-loopback bind requires `OD_API_TOKEN` (`server.ts:3217-3236`). With a token set, loopback peers still skip auth (`server.ts:3330`), so any local process (or anything behind a reverse proxy on the same host) is authenticated. API: `POST /api/runs`, `GET /api/runs/:id[/events|/agui]`, `/cancel`, `/steer`, `/api/projects/...` (`routes/runs.ts`, `routes/project/`). Docker deploy exists (`deploy/`, mem limit 384m default).
- Security posture: the agent runs with permissions skipped and an arbitrary shell if the CLI offers one. File scope is the project dir via `--dir`; the daemon has `OD_SANDBOX_MODE` for the data dir (`sandbox-mode.ts`) and `external_directory` permission handling, but there is no OS sandbox in the code read. Imported-folder projects give access to arbitrary host folders. Treat as equal to a trusted local coding agent, not a multi-tenant service.

## 5. Outputs and Cerea artifacts
- OD: real project files on disk (HTML, JSX components, `DESIGN.md`, tokens CSS, decks), previewed in a sandboxed iframe (`README.md:294,337`). Exports: HTML (inlined), PDF, PPTX (agent skill), ZIP, Markdown, MP4 (`README.md:194,549`). An MCP stdio server exposes the project files to other agents (`README.md:345`). Storage: SQLite plus per-project directories in the daemon data dir.
- OCD: workspace folder per design with pi-session JSONL history (`README.md:337`); sources `index.html`, `App.jsx`/`.tsx`; exports HTML, PDF (local Chrome), PPTX, ZIP, Markdown (`README.md:324`, `packages/exporters/`). CLI can `export html` offline (`apps/cli`).
- Mapping to Cerea: single-file HTML or JSX results map directly onto Cerea HTML/React artifacts (copy the file text). Multi-file projects and PPTX/PDF map to file artifacts, and the code panel can browse them if the project dir sits under a machine workspace. A pull flow (read files from a machine into an artifact) is plausible but not built, and needs a feature decision. Single-file HTML is the cheap, safe case.

## 6. Options
| Option | Effort | Risk | Notes |
|---|---|---|---|
| (a) Document pointing at Pystino | 0.5 day | None | Needs the shim secret copy step and the OD telemetry opt-out note. Meters spend under the person's identity. |
| (b) Native Cerea design skill reusing prompts | 3 to 5 days | Low; quality depends on model; freeze exemption needed | OCD prompts: `packages/core/src/prompts/sections/*.md` (about 14 KB: design-methodology, anti-slop-digest, workflow, output-rules, tweaks/editmode protocol; MIT). OD: `apps/daemon/src/prompts/`, `skills/`, `design-systems/` (154), `design-templates/` (116) (Apache-2.0 plus a few MIT; notes in section 1). Keep attribution in NOTICE. OCD's README says its prompts are an original rewrite, with no external skill text bundled. |
| (c) galopin backend for OD | 2 to 3 weeks plus upkeep | Medium to high | Needs ACP adapter or wrapper, Node 24 and pnpm on the machine, telemetry off, permissions bypass reconciled with galopin's ask-everything policy, weekly upstream drift. |
| (d) Embed OD or OCD in Cerea | 4+ weeks | High | OD is a daemon and app stack, not a library. OCD's core is workspace-bound and Electron-coupled. Fork-and-track burden. Not recommended. |
