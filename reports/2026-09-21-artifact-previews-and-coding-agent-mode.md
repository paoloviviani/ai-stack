# Research report — artifact previews & the coding-agent mode

Night of 2026-09-21, for review over coffee. Two topics as asked: what we can
preview today and how far that stretches, and how the chat can drive remote
coding agents the way paseo.sh does. Everything below is verified against the
Cerea working tree (paths named) or the vendors' current docs (2026-09-21).

---

## Topic 1 — What can we preview, and how do we expand it?

### The head start: previews are not a gap, they are a system

The exploration finding that reframes the whole topic: Cerea (via its
chat-ui lineage) already ships a complete artifact pipeline, client-side.

- **Tag protocol**: models emit `<artifact identifier type title>` inline;
  `src/lib/utils/artifacts.ts` parses streaming-safe, tolerates doubled
  brackets and swapped closers, folds rewrites and `old_str/new_str` updates
  into a versioned registry per message.
- **Six kinds exist today**: `ArtifactKind = "html" | "svg" | "code" |
  "markdown" | "react" | "mermaid"` (`artifacts.ts:21`) — so SVG and Mermaid
  are already "yes". Mermaid renders via the ESM build from jsdelivr with
  `securityLevel: "strict"` (`previewSrcdoc.ts:507-511`), and a reusable
  `buildMermaidSrcdoc()` is exported at line 490 — the inline-mermaid idea
  reuses existing infrastructure.
- **Panel**: `ArtifactPanel.svelte` (945 lines) — preview/code tabs, version
  navigation with line diffs, screenshot → annotate → send-back loop, HF
  Space deploy, download, fullscreen.
- **Security model worth keeping**: previews run in a sandboxed iframe with
  `sandbox` **without** `allow-same-origin`, `connect-src 'none'`, script-src
  limited to unpkg/jsdelivr/tailwind CDN, `form-action 'none'` (`previewSrcdoc.ts:49-94`),
  plus DOMPurify on every completed code block and an html renderer that only
  passes `video/audio/source` tags. DOMPurify + sandbox means our defense is
  two independent layers.

**Verified in-tree, not assumed**: `CodeBlock.svelte:69-82` already shows a
Preview button for strict-HTML5 doctype and SVG documents.

### The catalogue, present to future

| What | Status | Where |
|---|---|---|
| Markdown (GFM+KaTeX+mhchem) | Done | `marked.ts`, off-main-thread worker pool |
| HTML / React / SVG / Mermaid artifacts | Done | `previewSrcdoc.ts` |
| Code, 20 languages highlighted | Done | `CodeBlock.svelte`, hljs vendored theme |
| Images in chat (URL or attachment) | Done | lightbox, `UploadedFile`, tool-result `<img>` |
| Video/audio | Done | inline players via `sanitizeHtmlForMultimedia` |
| Files (text/image/pdf/docx) | Done, one real caveat — see the docx note below | `FileCard.svelte` |
| Pyodide fence execution (Python) | Done | vendored runtime, network-gated worker |
| PDF artifacts | **Not a gap — already covered**: generated PDFs preview (iframe, any byte source) as deliverables; `markdown` kind serves long reports | `FileCard.svelte:77,281` |
| CSV/JSON data artifacts (sortable/filterable table) | **Gap** | nothing |
| Tool-returned images → artifact (see below) | **Half** | tool images render inline but aren't first-class artifacts |
| Image *generation* artifacts | **Gap — but the backend exists**: Pystino exposes `POST /v1/images/generations` metered (`routers/images.py:55`) | needs a chat-side kind |

### Expansion ideas, ranked by value-to-effort

1. **Make `mermaid` inline (cheap, high polish)**: today Mermaid only previews
   via an `<artifact>` or the artifact panel. A fenced ```` ```mermaid ````
   block renders as highlighted text, not a diagram. A small renderer hook in
   `CodeBlock.svelte` (same pattern as the HTML/SVG Preview button — validate,
   render to SVG via the existing strict-mode pipeline, show inline with a
   code/code toggle) gives us diagrams in the message flow. The security
   posture is already solved: `securityLevel: "strict"` escapes all text and
   blocks external links.
2. **PDF artifacts**: dropped after review — generated PDFs already
   preview as deliverables on any byte source, and a text-authored `pdf`
   artifact kind has no coherent content model. The `markdown` kind
   covers long reports.
3. **CSV/JSON artifacts → an interactive table**: cheap to reach " sortable
   table", genuinely useful for data work alongside the Python fence (pandas
   in Pyodide is already vendored — a fence can produce a CSV artifact in the
   next message). Best done as a FileCard/deliverable enhancement (where
   CSVs actually land) rather than a sandbox-iframe artifact kind. Keep the
   existing `connect-src 'none'` posture.
4. **Tool-returned images and image *generation* — one project, not two**:
   both need the same new `image` `ArtifactKind` plus a preview path, so
   build them together. `ToolUpdate.svelte:202-211` already renders base64
   tool-result images inline; the upgrade promotes them into the
   `ArtifactRegistry`. For image *generation*: Pystino already meters
   `/v1/images/generations`, but note the chat's `models.ts:338-367` reads
   only `input_modalities` today — an `imageOutput` capability means
   consuming `output_modalities`, a field the app currently ignores.
   Preview design must stay inside `previewSrcdoc.ts`/`ArtifactPanel`
   (data-URL content, lightbox as the panel's viewer — not a bypass).
5. **Geo/3D and other exotica (leaflet, plotly, three.js)**: possible through
   the same iframe sandbox, but each adds a vendored bundle and a CSP
   exception. Defer until asked for by real usage; the sandbox pattern makes
   each one a contained, additive project.

### One architectural caution

Everything above stays client-side. The artifact content model is derived
from message text — there is no server artifact store (only `execute_code`
deliverables persist, in GridFS with a 30-day TTL). Keep it that way:
previews are a *rendering* concern, and the sandbox discipline is what lets
us render model-authored content without a security review per kind. New
kinds should extend `previewSrcdoc.ts` + `ArtifactPanel`, never bypass them.

### The docx caveat (operator-reported: previews not seen in practice; reviewed and corrected)

The operator generates docx documents regularly and has never seen a
preview. The reviewer-verified diagnosis:

- The docx preview (`FileCard.svelte:181-228`) extracts `word/document.xml`
  with stdlib zipfile inside the live Pyodide sandbox. It is therefore
  offered **only when the file's bytes live in the live sandbox** — the
  condition is `inlineContent === undefined && downloadUrl === undefined`
  (`FileCard.svelte:84-86`).
- **Persisted replay loses exactly the docx preview, nothing else**: a
  reloaded message renders deliverables with `downloadUrl`, and
  `previewKindFor` gates only docx on the byte source — text, image and
  PDF previews still work from `downloadUrl` bytes (`FileCard.svelte:75-81`).
  So on reload a PDF or PNG still previews; the docx alone drops to
  metadata + download. That matches the operator's experience (docx is
  what they generate).
- Direct-emission titled fences never carry office files at all:
  `executionPrompt.ts:37-38` routes office files through the sandbox code
  path and forbids base64 — so that path is moot for docx, not a fix target.
- A second no-preview surface: the **DeliverablesPanel side pane**
  (`DeliverablesPanel.svelte:227-245`) lists every persisted file with
  Open/Download only — no preview for anything, ever.
- Even in the live window the "preview" is the first 4000 chars of
  concatenated paragraph text, no formatting (`FileCard.svelte:190,194`).

**Fix (scoped to the real pain — the persisted/`downloadUrl` path):**
replace the sandbox-only docx branch with a byte-source-agnostic
extractor over `readBytes()` (which already fetches `downloadUrl`
bytes), and allow docx whenever bytes are reachable. Note the one
non-trivial bit: `.docx` is a ZIP container, and `DecompressionStream`
only does deflate — so a minimal ZIP reader (central directory lookup,
STORED vs DEFLATED) must be hand-rolled around it. Doable in contained
client code, no Python needed. Extending to xlsx/pptx (no preview today)
is the same reader plus one parser each.

---

## Topic 2 — A coding-agent mode: paseo-relay + opencode driven from the chat

### The idea, restated so we design the right thing

You want what paseo.sh has: agents (opencode, Pi, …) living on a machine
somewhere, driven from anywhere — except "anywhere" is **our chat**, and
"the machine" is the user's box (or ours), and the connective tissue is a
**self-hosted paseo-relay** instead of their cloud.

### What the research found (all verified against docs, 2026-09-21)

**Paseo's architecture fits our stack unusually well:**

- **Daemon**: a client-server control plane ("like Docker") that manages
  agent lifecycles, worktrees, terminals, schedules, heartbeats. Listens on
  `127.0.0.1:6767` by default; password auth (bcrypt in `config.json`);
  official Docker image `ghcr.io/getpaseo/paseo:latest` bundles daemon +
  web UI; child images add agent CLIs (`npm install -g opencode-ai`).
- **paseo-relay**: open-source (Apache-2.0) Elixir service, self-hostable in
  one container, **designed to be untrusted**: daemon connects *outbound*
  (no open ports), clients meet it there; all traffic is E2E encrypted
  (Curve25519 ECDH → NaCl box), the relay sees only IP/timing/sizes. This is
  the exact trust model we want between "our chat server" and "user's
  machine running an agent".
- **API surface for us**: the daemon's HTTP/WS API is what its own clients
  (web UI, mobile, CLI) speak, and there's a **TypeScript SDK**
  (`/docs/sdk`), MCP tools, and a REST surface — meaning the chat's
  SvelteKit server can be *just another Paseo client*. We do not need to
  re-implement agent control; we implement a client + UI mode.
- **39 agents supported**; custom providers via `extends` (point opencode at
  a different base URL — *our gateway*, see below), ACP for anything else.
  The daemon **does not manage agent credentials** — each CLI uses its own
  env vars/auth files. Good: our gateway mints per-user `/v1` credentials and
  that's all an agent needs (ADR 0010's API keys, or ADR 0040's device
  flow where a real IdP exists — see the credential note below).

**OpenCode specifically is the ideal first agent:**

- `opencode serve` = headless HTTP server with **OpenAPI 3.1 spec** at
  `/doc`, sessions/messages/permissions SSE events — a complete programmatic
  surface, incl. permission requests (approval flows!).
- **Custom providers are trivial**: an `opencode.json` provider entry with
  `npm: "@ai-sdk/openai-compatible"`, `options.baseURL: <our gateway's /v1>`,
  models from our catalogue — opencode then uses *our* models, our quotas,
  our redaction. It's a client of our stack, exactly like the chat is.
- Runs anywhere Node runs; Docker-friendly; ACP support if we ever want the
  Zed-style editor integration instead.

**The synergy that makes this *our* feature, not a bolt-on:**

The gateway (Pystino) sits in the middle of everything:

```
Cerea chat ──(OIDC session)──> SvelteKit server ──┐
                                                  ├─> Paseo daemon API ──> opencode ──(/v1)──> Pystino gateway ──> providers
paseo-relay (self-hosted, untrusted-middle) <─────┘
```

- The user's opencode talks to our `/v1` with a gateway-issued credential
  (ADR 0010's API keys — minted once by a logged-in human via
  `POST /api/me/keys`, revocable, budget-attributed; or ADR 0040's OIDC
  bearer via opencode's device flow where a real IdP is deployed — note
  ADR 0046's session credentials are chat-SPA-scoped and deliberately do
  *not* cover programmatic clients, so the one-time interactive login is a
  prerequisite in every shape). **Coding-agent usage lands in the same
  billing/quota/redaction ledger as chat usage.** That's a differentiator
  no bolt-on has.
- The chat drives the daemon through the same SSE/park-resume machinery it
  already has (MessageUpdate types for tool/plan/turn-state exist; the
  ML-Assistant mode is a working template for a whole conversational mode
  with its own tools and strips).
- Authelia/SSO already fronts the chat; the daemon gets its own password +
  network position, and the relay is E2E so it can live anywhere (even our
  box) without becoming a trust problem.

### The blueprint (what I'd actually build, in order)

**Phase A — PoC, one weekend of work, no installer changes:**
1. `docker compose` on this box: `ghcr.io/getpaseo/paseo:latest` child image
   with `opencode-ai` installed; `PASEO_PASSWORD`; `/workspace` = a scratch
   repo; opencode configured with a custom provider pointing at our gateway
   (`baseURL: https://cerea.example.org/v1`, model IDs from our catalogue,
   key minted per test user).
2. Host-side Python/TS script exercising: create workspace → create agent
   (provider `opencode`, initial prompt) → SSE the timeline → respond to a
   permission request → read the diff. This is the integration risk retired
   early: does the daemon's HTTP surface do everything we need?
3. Nothing here touches Cerea. Success = a script that drives opencode on
   this box, through our gateway, from outside the container.

**Phase B — the chat mode:**
1. Server: SvelteKit routes under `/api/v2/paseo/...` proxying the daemon
   API, with the daemon's password in server env; SSE bridged from daemon →
   JSONL (the chat's existing stream format) or a new MessageUpdate kind
   (`"agent"` block type in ChatMessage.svelte, sibling of `tool`/`plan`).
2. Client: new conversation mode, following the ML-Assistant pattern exactly
   (mode pill → conversation property latched at creation → dedicated
   preprompt/toolset → message blocks → side-pane view). Side pane shows:
   agent tree (workspaces/agents), live transcript with tool calls,
   diff viewer (opencode `GET /session/:id/diff` → our existing diff
   renderer), permission approval buttons wired to
   `POST /session/:id/permissions/:permissionID`.
3. The mode's "model picker" is the agent/provider picker (opencode profile,
   model from our catalogue — same list the chat shows, since the agent
   talks to our gateway anyway).

**Phase C — installer story (this is where Cerea-the-installer earns it):**
1. New installer profile fragment: `deploy/paseo/` with a compose service
   (daemon + child image with opencode, optional relay), wired into the
   same Caddy edge (`paseo.example.org { reverse_proxy ... }`) or kept
   internal + relay-only.
2. Auth: the installer mints a daemon password like it mints the
   break-glass admin password today; opencode's `opencode.json` gets the
   gateway `/v1` baseURL + a gateway-minted per-user key — the
   `ensure_bundled_admin` precedent applies.
3. Fleet: nothing stops the daemon living on a *different* machine than the
   chat (that's the point) — installer gets a `--paseo-remote` shape where
   only the relay is ours and the daemon is on the user's homelab box,
   paired by QR/link.

### Honest risks / open questions

- **Scope creep is the real risk.** Paseo's own UI (web/mobile/desktop) is
  excellent and free. Our value is *not* "rebuild Paseo's UI in Svelte" —
  it's (a) one SSO/login for chat + coding agent, (b) the same billing/
  quotas/redaction/audit ledger, (c) the chat as the place where a coding
  task can be discussed with a *model* and delegated to an *agent* in the
  same conversation. If we ever find ourselves rebuilding worktree UIs, we
  should stop and just embed/link Paseo's web UI for the deep management
  work.
- **The daemon API is not a frozen public contract.** Paseo documents SDK /
  MCP / CLI surfaces; the HTTP API the web client uses is de-facto stable
  but the project moves fast (v0.8.x). Mitigation: pin a version, wrap it
  behind our `/api/v2/paseo/*` proxy so the chat never talks to the daemon
  directly.
- **Permission UX is where trust lives.** opencode can run shell commands
  and write files. The chat must never auto-approve; every permission
  request must land as a blocking Elicitation-style card (machinery exists).
  Default modes should be read-only/plan until the user explicitly opts in.
- **E2E pairing between chat-server and user's daemon**: the relay model
  pairs a *human's device*. Our "device" is the chat server. Options: (a)
  chat server acts as one paired client holding a pairing secret (simplest;
  the server is then trusted with everything the user's phone would be), or
  (b) per-user pairing where each chat user pairs their own daemon and the
  chat proxies per-user. (b) is more honest but needs the daemon to support
  multiple identities — open question to verify in the PoC.
- **Trust boundary with `/workspace`**: agents read/write whatever the
  daemon sees. The installer must scope mounts (Paseo's own docs say the
  same). No mounts of `.env`-bearing dirs; dedicated worktree roots.

### Alternatives considered, and why relay+daemon still wins

- **Talk to opencode's HTTP server directly** (no Paseo at all): simpler, and
  opencode's `serve` API is genuinely complete — but then *we* own the
  "agent lives on another machine" problem (exposing a port, TLS, auth,
  reconnects, multiple agents, worktrees, terminals). Paseo's daemon+relay
  solves exactly that, battle-tested, in an untrusted-middle pattern we
  could not design better ourselves. The PoC (Phase A) can and should
  *start* with `opencode serve` directly for the in-chat experience, then
  graduate to the daemon for remote/multi-agent.
- **ACP straight into the chat**: opencode speaks ACP (`opencode acp`) — but
  ACP is stdio, meant for editors on the same machine. Not for remote.
- **Claude Code / Codex instead of opencode**: first-class in Paseo too, but
  their auth drags in external accounts (Anthropic OAuth / OpenAI), which
  fights our self-hosted-credential story. opencode with our gateway as its
  *only* provider is the clean shape. (Paseo's `extends`/custom-provider
  machinery means adding them later is config, not code.)

---

## TL;DR for tomorrow's conversation

1. **Previews**: we already have a six-kind artifact system with a solid
   sandbox; Mermaid/SVG are done *as artifacts*. The cheap wins are inline
   mermaid fences (reusing `buildMermaidSrcdoc`), a CSV table view, and
   tool-images + image-generation as one shared `image`-kind project. PDF
   needs nothing — deliverables already preview. The one concrete
   user-reported defect is **docx-on-reload** (sandbox-only extraction);
   fix = byte-source-agnostic ZIP reader in the FileCard, plus the
   DeliverablesPanel's no-preview-at-all surface.
2. **Coding platform**: paseo daemon + self-hosted relay + opencode pointed
   at our gateway's `/v1` is a uniquely good fit — SSO via existing Authelia
   chat login, agent credentials via ADR 0010 API keys (or ADR 0040 device
   flow with a real IdP — both need a one-time interactive login; ADR 0046
   does *not* cover this), billing/redaction via the same ledger, E2E
   agents via paseo-relay. Build order: Phase A PoC (script-driven, one
   weekend, resolves the chat-server pairing-trust question), Phase B chat
   mode (ML-Assistant pattern + side pane), Phase C installer profile.
   Watch scope: our value is integration and ledger unity, not rebuilding
   Paseo's UI. Vendor-doc claims (relay crypto, daemon API) are pinned at
   v0.8.x and go behind our `/api/v2/paseo/*` proxy, never direct.

---

## Approved direction + build log (2026-09-21, operator-approved in chat)

The operator converged the strategy to: **one trigger, one surface, one
sandbox.** Every renderable block — titled fence, plain fence, artifact
tag — gets the same fence-level `▶ Preview` affordance opening the same
side panel through the same sandboxed srcdoc builders, keyed on content
type, never on emitting construct. Inline keeps code/text/download/run;
all rendered views move to the panel. Images keep the lightbox (explicit
exception: pinch-zoom beats a panel for photos). No versioning for
transient fence previews (fences are message content); artifacts keep
registry/diffs. Screenshot-annotate stays panel-side for now.

**Built same morning (Cerea `f2b1eebc`, Pystino `ee9824d`, both pushed,
live on the operator's test stack):**
- `SidePane` gains a 4th view, `"preview"`: a transient single-item view
  (`FencePreview { kind: html|svg|mermaid, title, content }`), outside the
  pane-item nav axis like the library view. New `PreviewPane.svelte`:
  self-gated, sandboxed iframe via `buildArtifactSrcdoc`, header with
  title + close, error capture + ask-to-fix, external-link confirm — full
  parity with the modal's safety posture, none of its surface.
- `CodeBlock.svelte`: titled fences render inline as code + filename
  header (name, byte size, download) instead of a separate file-card
  chrome — same body, same Preview/Copy pills either way. Preview pill
  (html/svg by content, mermaid by language) opens the panel; the
  fullscreen `HtmlPreviewModal` no longer opens from fences
  (ArtifactPanel keeps its own panel→fullscreen zoom, a different
  affordance, untouched). Titled python still never runs.
- `fileBlock.ts`: shared `downloadTextAsFile` / `fileBlockByteSize` /
  `formatFileSize` (the fence download cannot go stale — no sandbox).
- `MODELS` is now reachable from `deploy/.env` (Pystino compose
  passthrough, empty = no overrides, malformed logs-and-ignores); the
  test stack sets `supportsArtifacts` on its chat model so the model
  learns the artifact protocol.
- Tests: `CodeBlock.svelte.test.ts` rewritten to the converged behavior
  (panel payload assertions on the store, no modal), new
  `PreviewPane.svelte.test.ts` (render/close/srcdoc/sandbox flags);
  svelte-check 0/0, eslint clean, client suites green (24 + 48 + 3),
  production build clean. The 77 server-test file failures are the
  pre-existing mongod-SIGILL environment issue (no AVX on the VM),
  untouched by this client-only diff.
- Docx follow-up, same morning (Cerea `6e409a7b`, pushed, live):
  `FileCard` docx previews now render as formatted documents (mammoth,
  BSD-2-Clause, dynamically imported — ~400KB lazy chunk, never in the
  entry bundle) in the side panel as kind `html` through the same
  sandboxed builders; DOMPurify sanitizes before paneling. Byte-source
  agnostic (live sandbox, persisted store, replay — the button is offered
  everywhere except inline content, which can't be a zip), 8 MB cap with
  the download left working, conversion failures surface inline. The
  sandbox-Python extraction branch is deleted: one preview path instead
  of two. 14 FileCard tests green (6 new), check/lint/build clean.
- SSR fix, same morning (Cerea `a65d8ef3`, pushed, live): the new pane
  mounts unconditionally, so its setup runs during server rendering —
  and Svelte executes `onDestroy` after SSR (`onMount` is client-only,
  `onDestroy` is not). The bare `window.removeEventListener` 500d every
  full page load while client-side navigation kept working (`/chat`
  broken, open conversations fine). Fixed with the standard `browser`
  guard; pinned by a new SSR test that renders the pane open and closed
  in Node and fails with the production ReferenceError when the guard is
  removed (verified by toggling it).
- Chrome convergence, same morning (Cerea `34b5e741`, pushed, live):
  generated-file boxes (`FileCard`) wore gray + blue text links next to
  fences' white cards + pill/icon buttons. Now both draw from one module
  (`codeChrome.ts`: pill, icon button, card surface mirroring the
  `.prose pre` tokens) — white hairline-bordered card, play-icon Preview
  pill (Hide when an inline preview is open), icon-only Download keeping
  its title/aria so every role/name assertion passes unchanged.
- Pdf blob typing, same morning (Cerea `f984d02d`, pushed, live): the
  preview blob was built typeless, and Chrome's viewer only engages for
  `application/pdf` — clicking Preview downloaded the file and left a
  blank frame. An extension→MIME lookup types the blob; pinned by a test
  capturing the `createObjectURL` blob.
- Pdf to the panel, same morning (Cerea `f49d009a`, pushed, live): the
  last inline holdout. Preview hands the panel a typed data: URL framed
  directly (no srcdoc builder — no HTML to build), same 8 MB cap, same
  inline error slot; images stay on the lightbox by explicit exception.
- Skills same-name fix, same morning (Cerea `f28e1c1b` + `b30deef5`,
  pushed, live): an admin importing a deployment skill named like one of
  their own user skills hit a duplicate key — deployment rows store the
  creating admin's userId and the unique key was `{userId, name}` with no
  scope, though same-name coexistence is the designed state (prompt
  assembly already prefers the personal row). Key is now
  `{scope, userId, name}` (deployment namespace stays guarded by its
  partial index + the service's readable pre-checks). Two lessons paid
  for in debugging: the drop must sequence after the create resolves
  (firing both at once can fail the drop against the hybrid build), and
  the migration must be awaited — `initDatabase` floated every index op,
  so `ready` could resolve mid-migration (observed as flaky pass/fail on
  identical reseeds). Pinned by same-owner regression tests both orders,
  verified failing on the old key with the production E11000, 47/47
  skills tests green on throwaway mongos. The operator's blocked admin
  import should now succeed — retry it.
- mammoth → docx-preview swap, same morning (Cerea `9ff4c901`, pushed,
  live): the operator's call, taken from the trade-off laid out earlier —
  fidelity over graceful degradation. mammoth extracted semantics (unstyled
  headings/tables needing a hand-written wrapper); docx-preview renders the
  document's own layout — page geometry, fonts, sections, images — and is
  smaller anyway (~175KB with shared jszip vs ~400KB). Its API renders into
  a live element, so the preview renders offscreen in a detached container
  and the wrapper's HTML travels to the panel; DOMPurify + the sandboxed
  iframe unchanged. Options pinned by name (0.x defaults drift):
  headers/footers/footnotes/comments off — a throw inside experimental
  surface loses the whole preview — and `useBase64URL` so images inline as
  data: URLs, which the preview CSP allows. 16/16 client tests green (mock
  plays renderer, fills the container), plus a real-renderer smoke test on
  a hand-built docx with the exact production options. mammoth is gone from
  the bundle entirely.
- Mobile pdf pop-out, same morning (Cerea `8310f3d3`, pushed, live): mobile
  engines ship no in-frame PDF viewer — Chrome Android's placeholder "Open"
  is a top-level navigation, impossible under the preview sandbox (and
  Chrome blocks top-level data: URLs besides), so the whole mobile
  "preview" was one dead blue button. Desktop (PDFium/pdf.js) draws
  in-frame and never sees the change. No capability probe exists for this,
  so the platform is read from the UA (coarse, standard, graceful
  wrong-read: a misread desktop gets an unnecessary chip, never a broken
  preview; iPadOS's desktop masquerade caught via maxTouchPoints). The
  incapable path shows a document tile plus "Open in a new tab", converting
  the data: URL to a blob URL — the unconverted form is as dead as the
  placeholder it replaces. Pinned by a test faking the mobile UA end to
  end: no iframe, chip click converts data:→blob:, window.open receives it.
- Desktop pdf blank/blocked fix, same morning (Cerea `c4790b53`, pushed,
  live): Chrome's "this page has been blocked by Chrome" panel and Safari's
  white box on desktop were the same refusal the mobile placeholder had
  foreshadowed — the browser's own PDF viewer will not attach to a
  sandboxed opaque-origin frame, so the sandbox containing generated code
  was breaking the one preview that executes none. The pdf is now the one
  deliberately unsandboxed frame in the pane (typed application/pdf by us,
  8MB cap, no HTML to sanitize; every other kind keeps the full
  PREVIEW_SANDBOX), with the absence pinned by test against
  well-meaning consistency edits, plus an SSR test holding the pdf branch
  navigator-free — which also fixed an unguarded navigator.maxTouchPoints
  read the UA helper could hit server-side.
- Admin panel console link, gated per profile (Cerea `f3143e49`, Pystino
  `fbde521`, pushed, live): a top link in the chat's admin panel to the
  Pystino console at /console — deliberately styled as a link, not a tab,
  because it is a way out of the panel, not a section of it (the split is
  whose decision: the console owns providers/models/prices/quotas/users,
  the panel owns product choices). Gated on a new deployment flag,
  CHAT_CONSOLE_ENABLED, in the house pattern: gateway profiles set it
  true (their origin serves /console), the standalone profiles leave it
  empty — satellite's Pystino is central's and its console lives at
  central's origin, generic has no Pystino at all — so no shape links to
  a 404 wearing a feature's name. Carried through the compose overlay
  (default on, operator-reachable), all five profile fragments (each
  with its reason beside it), the installer, and FeatureFlags.
  Pinned by installer tests on both shapes and endpoint tests in both
  states. Found and fixed in passing: test-flags.sh carried a block
  below its summary line, so under set -e the deliberate subshell failure
  killed the file after "0 failed" had printed — the runner exited 1 with
  every suite green (pre-existing, since d57c6198).
- Rotating Turin-dialect phrases, same evening (Cerea `7692ac5c`, Pystino
  `9aca4ae`, pushed, live): the new-chat screen prints one of four Turin
  greetings beside the logo — Com'è?, Va bin, Facciamo che iniziare?, Oh
  basta là — a new one per page load. Carried by PUBLIC_TURIN_PHRASES
  through the existing public-config channel (the compose overlay maps
  CHAT_TURIN_PHRASES, default on; "false" or empty restores the plain
  Cerea; malformed JSON degrades to the plain name rather than guessing).
  The pick lives in onMount, not the script body — the script runs during
  SSR too, and a Math.random() there ships one phrase in the payload and
  usually another after hydration, a mismatch warning every load. SSR
  tests pin the payload carries no phrase (and no empty slot markup to
  flash); client tests pin the pick, both off-switches, and the
  misconfiguration degradation.

**Still queued (unchanged order):** DeliverablesPanel previews via the
same transient items, CSV table view, image-kind unification. (Mammoth
docx rendering — previously queued first — is built and live, above.)

---

## Review provenance

Reviewed 2026-09-21 by a claude-opus-4-8 agent against both trees and the
ADR record. Its corrections are folded in above: six kinds (not five);
only docx loses preview on reload (text/image/PDF still preview from
`downloadUrl`); docx never arrives via direct-emission fences
(`executionPrompt.ts` routes office files through the sandbox); the
`DecompressionStream` fix needs a hand-rolled ZIP reader (deflate only);
credential story re-cited from ADR 0010/0040 (ADR 0046 is chat-SPA-scoped
and explicitly excludes programmatic clients); PDF-kind idea dropped as
redundant; tool-images + image-gen merged into one project;
DeliverablesPanel named as the second no-preview surface.
