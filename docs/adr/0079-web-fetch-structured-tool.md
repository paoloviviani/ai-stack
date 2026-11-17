# 0079 — `web_fetch_structured`: one more browser tool, gated from birth, built against `run-server` directly rather than `@playwright/mcp`; why no screenshot tool ships

- Status: accepted, built
- Date: 2026-09-18
- Extends ADR 0075's gated set (`web_fetch` and MCP tools) to include one new
  builtin. Builds on the renderer ADR 0075 assumes but does not itself define
  — `docs/browser.md` in the Cerea repository, and the `web_fetch` fixes
  (bounded settle past `domcontentloaded`, Readability extraction) that
  preceded this one in the same file, `src/lib/server/fetching/playwright.ts`.

## Context

`web_fetch` reads a page as prose. One need it cannot serve: reading a
page's *structure* — controls, roles, navigation — rather than its writing,
for a model reasoning about a page's shape instead of its content.

`run-server`, the headless-browser container `web_fetch` already speaks to,
exposes the full Playwright API over its WebSocket protocol; `page.ariaSnapshot()`
is already reachable from anything holding a connection. Adding this tool is
exposing capability already present at the transport, not adding new
capability to the renderer.

Two more tools were designed and built alongside this one, `screenshot` and
`page_to_pdf`, and both were removed before shipping. Their sections below
record why, because the reasoning is durable and the alternative is
somebody re-proposing them without the context that killed them the first
time.

### Why not `@playwright/mcp`

Microsoft publishes an MCP server that wraps this same Playwright surface.
It was considered and rejected, for reasons specific to this deployment's
threat model rather than a general objection to MCP:

1. **No capability gap to close.** `run-server` already exposes the full
   Playwright API to a connected client (this app). `@playwright/mcp` would
   wrap the same API in a second protocol on top of one already in hand.
2. **Its core tool set ships `browser_evaluate` and
   `browser_run_code_unsafe`** — model-supplied JavaScript, executed on the
   server side of the connection. This project forbids server-side execution
   of model output outright (the browser sandbox in ADR 0073 is the one place
   the model's own code runs, and it runs client-side, per-user, with no
   server in the loop). The upstream project itself documents these tools as
   RCE-equivalent. Holding them back with a tool allowlist is one
   configuration mistake away from exposing them — the allowlist has to be
   right every time; a hole has to be found once.
3. **Writing the tool ourselves means `browser_evaluate` simply does not
   exist in this codebase.** Not disabled, not allowlisted-out — absent.
   There is no flag to flip, no config to misread, no future refactor that
   silently re-enables it. That property is the entire reason this ADR chose
   the harder path of hand-writing a tool over importing one package.
4. **Adopting it would have meant relaxing the SSRF guard.** `@playwright/mcp`
   would run as a separate MCP server this app connects to, reachable only
   through `isValidUrl`/`isLocalMcpHost`'s allowance for compose-internal MCP
   hosts — an allowance that exists for user-configured MCP servers on the
   compose network, not for a component this app itself depends on
   structurally. Widening that allowance for a bundled dependency blurs a
   line that currently separates "servers the user chose to trust" from
   "infrastructure this app requires," for a capability already reachable
   without it.
5. **It would contradict "we host no MCP servers."** This deployment connects
   to MCP servers; it does not run them. `@playwright/mcp` as a bundled,
   always-on server would be the first exception to that, for no capability
   gain (point 1).

None of this is a judgment on `@playwright/mcp` as a project — it is a
general-purpose browser-automation server, and `browser_evaluate` is a
reasonable thing for a general-purpose tool to offer. It is not a reasonable
thing for *this* deployment to offer, given what it already refuses to let a
model do server-side.

## Decision

### The tool that ships: `web_fetch_structured(url)`

Returns `page.ariaSnapshot({ mode: "ai" })`: an accessibility tree of roles,
names and stable `[ref=eN]` element references, Playwright's own
purpose-built shape for handing a page's structure to a model. Checked at
source rather than assumed from memory: `page.accessibility` (the older
`AccessibilitySnapshot` API) is absent entirely from installed Playwright
1.61.1's types; `ariaSnapshot()` is its replacement.

It shares `renderWithPlaywright`'s isolation and wait strategy — a fresh
browser context per call, `domcontentloaded` navigation followed by a
bounded, swallowed wait for `networkidle` so client-rendered content has a
chance to appear without a polling/analytics page ever failing the call
outright — through one `withRenderedPage` helper in
`src/lib/server/fetching/playwright.ts`, extracted so this isolation and
settle logic has exactly one place to audit rather than one per capture
function.

Its result is plain text, capped at the same `MAX_FETCH_RESULT_CHARS` as
`web_fetch`. No deliverable, no persistence, no vision question: the model
reads the snapshot directly, the same way it reads `web_fetch`'s prose.

### Gated from birth, with no trusted-URL exemption

`web_fetch_structured` joins ADR 0075's gated set: every call parks under
`manual` policy and runs straight through under `always-allow`, identically
to `web_fetch` and MCP tools. Unlike `web_fetch`, it carries no trusted-URL
exemption (`web_fetch` skips the prompt for a URL the user already supplied
or `web_search` already returned). Two reasons:

- **It never had a legacy auto-run behavior to preserve.** `web_fetch`
  existed and ran unprompted before ADR 0075; grandfathering trusted
  provenance kept it from becoming strictly more annoying to use than it was
  the day before. This tool is new — there is no prior behavior a trust
  carve-out is protecting.
- **ADR 0075 already found this kind of carve-out to be theater risk once a
  real approval card exists** (its point 5, removing the "auto-verified"
  search check). Repeating the pattern here would repeat the risk for no
  benefit a real approval prompt doesn't already cover.

Grants are per tool name, unchanged from ADR 0075's rule: approving
`web_fetch_structured` for a conversation adds `"web_fetch_structured"` to
`conv.approvedTools` and nothing else — not `web_fetch`, not any MCP tool.
The approval card already renders whatever arguments the call carries
(`toolApproval.args`, shown as formatted JSON, generic across every gated
tool); passing the full `{ url }` argument object through unfiltered —
exactly as `web_fetch`'s call already does — is what makes the card show the
URL. No tool-specific card logic was needed or added.

**The defence in depth**: mirroring `web_fetch`'s own re-check inside
`execute()`, the tool re-verifies the gate at the top of its own `execute()`
(`toolApprovalPolicy === "always-allow" || approvedTools.has(name)`) before
doing anything. `toolInvocation.ts`'s pre-call checkpoint is what actually
opens the approval prompt; the re-check is what happens if a future caller
ever dispatches the tool without routing through that checkpoint first — it
fails closed rather than running silently.

**The bug this exposed, kept regardless of which tools exist.** The non-MCP
branch of the resume path (`resumeElicitation.ts`, `runApprovedCall`) was
hardcoded to `web_fetch` — `if (!call.mcp)` assumed `performFetch`
unconditionally, for any non-MCP call at all. It now dispatches by the
call's own tool name against a small table of the non-MCP gated tools'
standalone `performX` functions, so an approved `web_fetch_structured`
re-issues correctly instead of being run as a `web_fetch` call for whatever
`url` argument it happened to share the shape of. This was a latent bug in
ADR 0075's own framework — `web_fetch` was the *only* non-MCP gated tool
until this ADR, so nothing had ever exercised the branch with a second one.
It is a correctness fix independent of which builtin exposed it, and would
stay even if `web_fetch_structured` itself were later removed.

### Deliberately still ungated: `execute_code` and `load_skill`

`execute_code` runs client-side, in the person's own browser sandbox — no
server-side effects, nothing for a server-side gate to protect against. This
was ADR 0075's own reasoning and is unchanged by this ADR. `load_skill` loads
prompt text the model reads next round; nothing about it reaches an exec API
or a network call. Their absence from the gated set is not an oversight this
ADR fixes — it is a decision, restated here so the next reader of
`toolInvocation.ts`'s gate resolver does not "fix" it into being gated.

### Offered only where the renderer is configured *and* reachable

`web_fetch_structured` needs a real, answering browser — `page.ariaSnapshot()`
only exists because a page was actually rendered. `getEnabledBuiltinTools`
withholds it unless **both**:

1. The configured fetch backend is specifically `playwright`. `direct` has
   no browser at all; `pystino` is a deliberate stub that refuses with a
   message rather than working. `web_fetch` needs no such check — `direct`
   is a perfectly good way to read a static page — so it stays offered on
   every backend.
2. A recent liveness probe of the renderer succeeded (below). Selecting
   `playwright` is configuration a deployment can hold before the overlay is
   even deployed, so the backend being *configured* is not evidence it
   *works*.

Both conditions are read fresh per call rather than cached at module scope:
`FETCH_BACKEND` is the one config key the admin panel writes at runtime
(Administration → Fetching), and the tool list is rebuilt once per turn, so
a live change must take effect on the next turn, not after a restart.

### The liveness probe, and the rule that splits configuration from advertisement

**The mechanism.** `run-server`'s own container healthcheck is a plain HTTP
GET expecting 200 on its port
(`require('http').get({host,port,timeout:4000}, r => r.statusCode === 200)`).
`probePlaywrightHealth` (`$lib/server/fetching/playwright.ts`) does exactly
that — one HTTP request, not a Playwright handshake and not a spawned
browser — with host and port parsed from `PLAYWRIGHT_WS_ENDPOINT` rather than
a second hardcoded address, so the probe and the real connection can never
point at different places. The result is cached for 30 seconds so assembling
a tool list (once per turn) or loading the admin screen does not probe on
every call, while a renderer that just came up is noticed within that
window.

**Deliberately not a one-time startup check.** This was considered and
rejected: `run-server`'s healthcheck has a 60-second start period, and this
chat routinely finishes booting before the renderer is ready. A boot-time
snapshot would report "not deployed" against a stack about to become
healthy, and stay wrong until somebody restarted the chat — and it fails in
the other direction too, since a renderer stopped after boot would leave a
cached "available" advertising a tool that no longer works. `initServer`
(`src/lib/server/hooks/init.ts`) still logs one boot-time probe result
(`playwright_renderer_boot_check`) for diagnosis, fire-and-forget and never
awaited — but that log line decides nothing; the per-turn cached probe is
the only thing the tool list ever consults.

**The rule: configuration is permissive and honest; capability advertisement
is strict.** Conflating these two is how you get either a locked-out
operator or a model calling a dead tool:

- **Administration → Fetching** (`routes/admin/fetch/+page.svelte`,
  `routes/api/v2/admin/fetching/+server.ts`) shows the live probe result next
  to the `playwright` option — a green "Reachable" pill, or an amber
  "Unreachable: `<reason>`" one — computed on every `GET`, regardless of
  which backend is currently selected, so an operator deciding whether to
  switch *to* playwright can see its status before picking it. It **never**
  disables the option or refuses the `PATCH`: a transient probe failure must
  not lock somebody out of a configuration that works, and configuring
  before the overlay is deployed is a legitimate, common order of
  operations. Refusing the selection would turn a warning into an outage.
- **The tool list** is the strict half: `web_fetch_structured` is offered
  only when the backend is `playwright` **and** the probe recently
  succeeded. An advertised tool that cannot work costs the model a wasted
  round and a confusing failure, which is exactly the case worth refusing
  outright rather than warning about.

`renderWithPlaywright`'s own "may not be deployed" connection error is
unchanged and still the backstop for a renderer that dies between the probe
and the actual call — the probe narrows how often that path is hit, it does
not replace it.

`getEnabledBuiltinTools` stays a synchronous decision function: the probe is
an async network call, so `runMcpFlow.ts` resolves it once per turn (only
when the backend is actually `playwright`, to avoid a wasted probe against a
`direct`/`pystino` deployment) and passes the boolean in as
`playwrightReachable` — the same pattern already used for `searchModelIds`,
another async value a caller resolves before this otherwise-synchronous
function runs.

### Removed before shipping: `screenshot`

`screenshot` was proposed on the premise that a vision-capable model could
read a page that defeats text extraction — a chart, a canvas, a dashboard —
by looking at a render of it. That premise does not hold on this stack, or
on any OpenAI-compatible one, and this is the most durable finding to come
out of this work:

**Tool results cannot carry images on an OpenAI-compatible backend.** The
Chat Completions protocol types a tool-role message's `content` as
`string | ChatCompletionContentPartText[]` — no image content part is valid
there at all. Image parts (`ChatCompletionContentPartImage`) are valid only
on `user`-role messages, and this app only ever builds them from a persisted
user message's own file attachments (`prepareFiles.ts`). A model calling a
screenshot tool therefore never sees the image it asked for; it would get a
paragraph naming dimensions and a download path, and the actual bytes would
go to a person who could have taken that screenshot themselves. (A
`MessageFileUpdate` type exists in `MessageUpdate.ts` that looks like it was
meant for a tool to attach a file to its own message — it has no consumer
anywhere in the codebase, dead scaffolding, not a working path.)

Once the vision premise fell away, what remained was a file-production tool
the model gains nothing from reasoning about — the same weaker case
`page_to_pdf` was removed for (below), now true of `screenshot` too — while
still paying for a gated approval flow, a deliverable-storage path, and a
vision-capability check (`model.multimodal`) whose own justification
depended on the model seeing a result it never would. All of that
infrastructure was removed with the tool: nothing in
`$lib/server/fetching/playwright.ts`, the deliverable store, or the builtin
tool registration exists solely to support it.

**If a screenshot-shaped tool is proposed again**, the question to ask first
is not "can Playwright capture this" (it can) but "how does the result reach
the model" — today's honest answers are a text description only (judged not
worth the surface area here), or a synthetic `user`-role message carrying
the image on a *later* round (unbuilt; touches the round loop, replay, and
the history-budget accounting in `utils/prepareFiles.ts`, well beyond a
builtin-tool addition).

### Removed before shipping: `page_to_pdf`

A pure export operation: the model learns nothing from producing a PDF, and
it duplicated what `execute_code`'s browser sandbox already produces (Python
document libraries in the per-user sandbox can already generate a PDF as a
run output file, persisted through the same deliverable store). Two ways to
make a file, one of them barely used, is how tool surface accumulates for no
reason. Removed along with `pdfWithPlaywright` in `playwright.ts`, its
gating entry, and its dispatch-table entry in `resumeElicitation.ts`.

## Consequences

- `toolInvocation.ts`'s gate-resolver comment, which asserted that anything
  other than `web_fetch` and MCP tools "is outside ADR 0075's gated set and
  returns `null` here regardless," is now wrong and is updated to name
  `web_fetch_structured` and restate that `execute_code`/`load_skill` remain
  outside by decision.
- `getEnabledBuiltinTools` gained a `playwrightReachable` input, resolved by
  its caller rather than fetched internally — the function stays
  synchronous, consistent with how `searchModelIds` is already handled.
- The `execute_code` deliverable store
  (`$lib/server/execution/deliverables.ts`) and its download route are
  **unchanged** — neither surviving tool persists anything, so there was no
  second caller to fold into that module's header after all.
- No change to the version pin, the SSRF guard, or the accepted protocol set
  (`https:` only) anywhere in this path.

## Verified

Against the live renderer container (`llm-platform-playwright-1`, reachable
from the host at its compose-network IP on port 3000 — no port published, per
`docs/browser.md`): `page.ariaSnapshot({ mode: "ai" })` on a page whose
content loads via client-side AJAX after `domcontentloaded`
(quotes.toscrape.com/scroll) returns the populated accessibility tree, not
the pre-load placeholder — confirming the shared settle logic from
`withRenderedPage` reaches this tool too.

Unit: `webFetchStructuredTool.spec.ts` (gating, the defence-in-depth
refusal, always-allow, an existing grant, truncation, empty-snapshot
refusal), `toolInvocation.spec.ts` (the tool parks under `manual`, dispatches
straight through under `always-allow` or an existing grant, and a grant on
it does not clear an MCP tool), `resumeElicitation.spec.ts` (an approved
`web_fetch_structured` call re-issues through the generalized dispatch table
rather than being run as `web_fetch` — written first against the unfixed
`if (!call.mcp)` branch and confirmed it failed for the right reason),
`playwright.spec.ts` (the capture function shares `withRenderedPage`'s
settle/cleanup behavior; `probePlaywrightHealth` reports reachable/
unreachable/timeout/connection-error correctly and respects its cache
window), `builtinTools.spec.ts` (the tool is withheld on `direct` and
`pystino`, withheld on `playwright` with an unreachable renderer, withheld
with no reachability probe resolved at all, and offered only once both the
backend and the probe agree). `npm run check` and `npm run test` (server +
ssr projects) both pass, modulo the pre-existing `replayRoundTrip` failure
and Pyodide `SystemExit` traces this work did not touch.
