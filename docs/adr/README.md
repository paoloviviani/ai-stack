# Architecture Decision Records

Each ADR states the context, the options considered, the decision and its
consequences. Where a decision rests on a version, a licence or a security advisory,
that evidence is written into the ADR with its date — so it can be re-checked rather
than re-researched, and so a reader months from now can tell what was true when the
choice was made.

**Everything here was verified against primary sources on 2026-08-14** (repositories,
licence files, release pages, advisories), not from memory. Anything that could not be
verified is marked as such in the ADR that depends on it.

## Foundational

| # | Decision |
|---|---|
| [0001](0001-licensing.md) | OSI-approved licences for first-party code (which one: 0094, Apache-2.0); inbound dependency licence policy |
| [0002](0002-monorepo-tooling.md) | Monorepo layout; uv + pnpm workspaces, no orchestrator |
| [0003](0003-build-vs-adopt-gateway.md) | Build the gateway rather than adopt LiteLLM |

## Gateway — implemented in Phase 1

| # | Decision |
|---|---|
| [0004](0004-gateway-runtime.md) | Python 3.13 + FastAPI, and why streaming load is not the constraint |
| [0005](0005-persistence.md) | PostgreSQL as ledger of record; SQLAlchemy 2.0 async; Alembic |
| [0006](0006-counter-store.md) | Valkey, not Redis, and why counters are never authoritative |
| [0007](0007-sse-streaming.md) | The SSE architecture: event boundaries, forced usage, disconnect |
| [0008](0008-accounting-model.md) | The accounting model, and never reporting zero |
| [0009](0009-quota-model.md) | Quota rules, rolling windows, reserve-then-settle, overrun policy |
| [0010](0010-api-keys.md) | API key format, SHA-256 rather than a slow KDF, revocation |
| [0011](0011-oidc-integration.md) | OIDC for the management API; the configurable group claim |
| [0012](0012-redaction-interface.md) | The redaction interface and deterministic placeholders |
| [0013](0013-upstream-http-client.md) | httpx, its timeout traps, and a maintenance risk |
| [0014](0014-model-catalogue-and-pricing.md) | The model catalogue and the Cortecs pricing importer |
| [0022](0022-administration-surface.md) | Administration is an API; admin follows an IdP group (UI stance superseded by 0023) |
| [0023](0023-admin-console.md) | The console: a SPA served by the gateway, optional at build time |
| [0024](0024-billing-periods.md) | Billing periods are calendar-based, and are not rolling quota windows |
| [0025](0025-quota-model-v2.md) | The quota model: stacked, multi-granularity, resettable |
| [0026](0026-pluggable-detection.md) | Detection is a plugin; the Italian NER model is a build flag |
| [0027](0027-inference-providers.md) | Inference providers as configurable records, with keys encrypted at rest |
| [0028](0028-embeddings-and-served-model.md) | Embeddings, and recording what actually served a request |
| [0029](0029-pagination.md) | Pagination on the management listings, and server-side search |
| [0030](0030-more-surfaces.md) | Responses, Anthropic Messages and image generation, over one metering path |
| [0031](0031-model-capabilities.md) | Model capabilities: imported from the catalogue, exposed to callers, editable |
| [0032](0032-provider-plugins.md) | Providers versus routers, and a plugin seam that returns facts rather than computing money |
| [0033](0033-redaction-engine-selection.md) | The redaction engine becomes an admin decision, on an append-only record |
| [0034](0034-bauhaus-design-language.md) | **Superseded by 0042, then 0047.** Bauhaus as the design language, and a self-hosted geometric sans |
| [0035](0035-public-tls-exposure.md) | A TLS reverse proxy, and the four holes that made "never on a routable address" the rule |
| [0036](0036-model-page.md) | A model's price belongs on the model's page, not on a screen of its own |
| [0037](0037-redaction-policy.md) | One engine, and a per-entity redaction policy an admin can set |
| [0038](0038-scoped-redaction.md) | Redaction scoped per provider, model, group, user and key, where a scope can only tighten |
| [0039](0039-redaction-rules-only.md) | There is no deployment policy, only rules; the catch-all is one of them, and the default protects nothing |
| [0040](0040-bearer-tokens-on-v1.md) | OIDC access tokens as a `/v1` credential, gated by audience |
| [0042](0042-material-design-3.md) | **Superseded by 0047.** Material Design 3, tuned for reading (supersedes 0034) |
| [0043](0043-local-authentication.md) | Optional local email + password sign-in beside OIDC; one session, two doors |
| [0044](0044-keycloak-removed.md) | Keycloak leaves the stack; OIDC against any provider, local login as the default way in |
| [0045](0045-public-models.md) | Public models: any authenticated caller may use one, billed to their own group |
| [0046](0046-local-api-credentials.md) | The local door issues `/v1` credentials: the gateway as issuer for its own accounts |
| [0047](0047-tailwind-base-ui-modern-refresh.md) | The UI restyles on Tailwind v4 + Base UI, with a dark theme (supersedes the no-Tailwind stance of 0023/0042) |
| [0048](0048-oidc-policy-configuration.md) | Users are created and deleted in the console; the OIDC identity policy is a runtime decision (amends 0011, 0022, 0043) |
| [0049](0049-password-reset.md) | Self-service password reset by email, opt-in and environment-configured (amends 0043) |
| [0050](0050-group-management.md) | Groups are created, deleted and given members in the console; manual groups only (bounds 0048) |
| [0051](0051-settings-identity-and-email.md) | The Settings screen: identity providers (multiple) and the mail server as console decisions (supersedes 0048's connection boundary) |
| [0052](0052-quota-notifications.md) | Quota notifications: the rule is the administrator's, the threshold is the user's |
| [0053](0053-model-pricing-sources.md) | Where model prices come from: native catalogues, the LiteLLM file, manual entry |
| [0054](0054-currency-conversion.md) | USD-priced models convert at the decision and aggregation points; breakdowns stay native (supersedes 0014's currency refusal) |
| [0055](0055-ocr-surface.md) | `/v1/ocr` as a metered surface, priced per page, with a local markitdown backend so office documents never leave — and the response, not the request, is the half that gets redacted |
| [0056](0056-account-linking.md) | An identity provider may adopt the local account with the same **verified** address, per provider and off by default — recorded beside the identity rather than rewriting it, because `issuer = "local"` is what eight places read as "this account has a password" |
| [0057](0057-group-ownership-and-sync.md) | A directory owns the memberships it granted and no others, so an administrator's group assignment survives a login — plus Keycloak's three sync modes, per provider |
| [0058](0058-per-search-pricing.md) | Provider-side web search is a third non-token unit, priced per search and capped by writing `max_uses` into the outgoing tool — the count read only from what the counterparty reports, never from counting response blocks |
| [0059](0059-citation-offsets.md) | Restoring a placeholder moves every character after it, so the citations that point past it move too — one `shift_citations` per surface, and the streamed case needs the whole answer |
| [0060](0060-settle-after-the-response.md) | The final ledger write and the counter settle ride on the response instead of blocking it: −16% p50 and −33% p95 with headroom, and a worse p95 under saturation because awaiting them was accidental backpressure |
| [0061](0061-per-request-billing-group.md) | A request may choose which group pays — `x-bill-to`, honoured for OIDC callers and refused for keys, granting no capability because membership is re-checked anyway; the list comes from effective memberships, never the token's claim |
| [0062](0062-knowledge-bases.md) | Knowledge bases, files, retrieval and one generic sharing ACL live in the gateway; the chat keeps projects and conversations. Corrects ADR 0020: an unconstrained pgvector column makes the embedding model a setting rather than a migration, and a mismatch refuses rather than returning garbage |
| [0063](0063-connectors-through-toolhive.md) | **Rejected.** An MCP gateway (ToolHive) for connectors: adopted, built into the stack, measured and removed. Its per-user OAuth lives in the Kubernetes operator only — compose gives one credential per workload, a localhost redirect and no token persistence — and a gateway exists to *run* MCP servers, which we do not. Read before reaching for LiteLLM's |
| [0064](0064-mcp-connector-oauth.md) | The chat is the OAuth client for MCP connectors: discovery, RFC 7591 registration, PKCE, a callback on our own origin, and tokens stored per user server-side. No gateway — we host no MCP servers. DCR rather than CIMD because a provider cannot fetch our metadata over `tls internal` |
| [0065](0065-unmetered-deployments.md) | A deployment may keep no ledger: `accounting.enabled=false` writes no `usage_records` at all, and the report says metering is off rather than showing an empty table. Off means *no row*, never a row of zeros. Quotas without a ledger are refused at startup — counters rebuild from `usage_records`, so every ceiling would silently pass |
| [0066](0066-publishing-and-platform-ownership.md) | Shared with everyone, and owned by the platform: two independent things. Publishing is a third principal kind (`everyone`, nil-UUID id) so the publisher keeps ownership and a grant keeps its role and provenance; platform ownership is a **null** `owner_user_id`, with the foreign key kept `CASCADE` so erasure never *creates* one. An administrator may unpublish anything and publish nothing of anybody else's. One mutation of seven survived and produced the test that now covers it |
| [0067](0067-agents-belong-to-the-chat.md) | Agents belong to the chat: owner-only, no sharing, resolved in the chat's generation loop. Corrects the agents half of 0062 — knowledge bases stay in the gateway; `agent:<name>` on `/v1` means nothing any more |
| [0068](0068-minimal-idp.md) | The gateway is a minimal IdP for browser-facing clients: discovery, authorization-code + PKCE, `id_token`, JWKS, userinfo, `end_session` — built on 0046's credential machinery, which it supersedes in its browser-facing half. Access tokens stay opaque; the minting endpoints leave the public internet; the IdP is off unless enabled |
| [0069](0069-authorisation-is-a-gateway-fact.md) | Authorisation is a gateway fact: the IdP authenticates, once — `first_login` is the sync stance and the automatic admin path (`GATEWAY_OIDC__ADMIN_GROUPS`) is removed, not deprecated |
| [0070](0070-the-vector-store-belongs-to-the-chat.md) | The vector store belongs to the chat: the gateway keeps embedding and document-reading endpoints, the chat keeps documents, chunks, vectors, sharing and reindexing |
| [0071](0071-the-gateway-meters-search-it-does-not-translate-it.md) | The gateway meters search and passes it through verbatim; the chat speaks each vendor's API; search backends stay off `/v1/models` and get their own console screen |
| [0072](0072-skills-phase-1.md) | Skills in the open SKILL.md format, stored in Mongo and loaded in stages: frontmatter every turn, bodies on trigger, no matcher; owner-only plus a deployment catalogue; execution client-side only (amended by 0073) |
| [0073](0073-the-browser-runs-python-the-model-heals-the-rest.md) | The browser sandbox stays Pyodide (WASIX considered and deferred); the model heals non-Python skill steps at run time; packages are served same-origin with a default-deny PyPI opt-in, not tunnelled over sockets; skills carry bundled files loaded on demand and run client-side (amends 0072; reaffirms 0021) |
| [0074](0074-gateway-specific-capabilities-live-under-v1-pystino.md) | Gateway-specific capabilities live under `/v1/pystino`, bearer-authenticated and off the OpenAI-standard paths; the first is `GET /v1/pystino/usage`, the caller's own quota rules and spend in one JSON (raw per-rule values, no synthesized "remaining"), sharing the `/api/me/*` query logic — which is why it does not reopen the deferred OpenAI-shaped `/v1` usage decision |
| [0076](0076-deployment-profiles.md) | Deployment profiles: one stack from homelab to enterprise, as env fragments plus a derived overlay list — never new compose topology; no profile selects smoke, exposure has no loopback option, and both installers consume the derivation |
| [0077](0077-shared-design-tokens.md) | One look for chat and console: the chat's values on the token mechanism, shared by vendoring with a drift test (partly reverses 0047's no-decoration stance; 0047's readability requirements and token ownership survive) |
| [0078](0078-first-group-becomes-the-default-billing-group.md) | A user's first group becomes their default billing group on every membership-granting path, not just the two that already had the rule; the console gets a self-service picker instead of an admin-for-another-user setter, which 0061 already argued against |
| [0079](0079-web-fetch-structured-tool.md) | `web_fetch_structured` (an accessibility-tree read of a page) joins the gated tool set 0075 defined, built against `run-server` directly rather than `@playwright/mcp` (its `browser_evaluate`/`browser_run_code_unsafe` core tools being the deciding factor); records why a `screenshot` tool was designed and then not shipped — tool results cannot carry images on an OpenAI-compatible backend — and gates the tool's availability on a cached liveness probe of the renderer, not just the configured backend |
| [0080](0080-user-memory-is-a-list-not-a-store.md) | User memory is a short list injected whole into every prompt, never searched — the retrieval pipeline 0070 built is for corpora, and a list that is entirely sent is the only kind a person can audit; the `remember`/`forget` tools stay outside 0075's gate on purpose (no external reach, and an approval card per fact would train people to dismiss approval cards), showing the write with an undo instead; deployment flag on, per-person opt-in off, with the switch on the tab rather than in settings |
| [0081](0081-public-model-listing-no-boot-key.md) | `GET /v1/models` (list only) is exempted from authentication — the full, unfiltered, brochure-level catalogue, grant filtering skipped rather than run against no one; detail stays authed. Corrects 0045's "unauthenticated callers see nothing" for the listing only. Pystino no longer mints the chat a spend-capable `gwk_` key just to boot; the generic `OPENAI_API_KEY`/`HF_TOKEN` machinery for non-Pystino backends is untouched |
| [0082](0082-satellite-and-generic-profiles.md) | Two standalone deployment profiles that run no gateway: `satellite` (Cerea against a central Pystino — central's IdP, `USE_USER_TOKEN=true`, and no stored key at all, which 0081 made possible) and `generic` (any OpenAI-compatible third party with one shared key and `USE_USER_TOKEN` forced false in code, because user-token mode would send the signed-in person's IdP access token to a third party). Records why a cut-down local gateway was rejected, that there are no satellite-local administrators by construction, and that divergent *policy* — not reachability — is the boundary where a local gateway would become necessary |
| [0083](0083-ocr-one-shape-direct-endpoint.md) | Pystino, Mistral and Cortecs already serve one OCR shape, so the generic profile reads documents by posting to a configured `{base}/ocr` directly rather than through a gateway; amends 0055 with an inclusive `pages` range string (whose `len()`-on-a-string reservation bug is fixed — `"0-100"` reserved 7 pages) and a declared `include_image_base64`, and puts on the record that Cortecs' `usage_info.credits` is deliberately never read, since credits are not money |
| [0084](0084-bundled-idps-authelia-keycloak.md) | **Partly superseded by 0088** (the house IdP and bundled Keycloak went; Keycloak was withdrawn as a provider kind in Pystino 0.17.0, 2026-10-23). The installer can deploy the identity provider alongside the gateway: bundled Authelia or Keycloak join the team/enterprise sign-in menus (house stays default) and satellite gains a local-Authelia shape whose shared-key billing the installer enforces, because central's `/v1` will never accept a local issuer's token. Audience `pystino-api` and the issuer are derived from the public origin and never prompted; the provider ships in phase 1 so discovery answers before the gateway that reads it restarts; the live installs surfaced and fixed three latent deployment bugs recorded at the end (phase-1 redaction variables, the chat route missing from the proxy shape, and Keycloak's import rejecting unknown fields) |
| [0085](0085-paseo-daemon-relay-adopt-vs-build.md) | **Superseded by 0089.** Adopt the paseo daemon and a self-hosted paseo-relay for the coding-agent panel: a PoC decision, verified live, whose tripwires (release churn, an unsupported internal SDK, a single-user trust model) then fired |
| [0086](0086-one-stack-two-image-sources.md) | One static compose project with profiles and one `.env`; development and distributed modes differ only by a `compose.build.yaml` in `COMPOSE_FILE`. One Caddyfile baked into `pystino-proxy` (`TLS_MODE=acme\|internal\|upstream`), server-to-server OIDC over internal URLs (no CA bundle), and a `pystino` CLI in the gateway image (`init`, `bootstrap`, `doctor`, `upgrade`, `adopt`) replaces both bash installers |
| [0087](0087-two-repos-pystino-is-the-distribution.md) | Keep two repositories: Pystino owns the stack and pins the Cerea image by digest in `deploy/stack/release.env`. Lockstep comes from contract tests, a fresh-install job on the pinned pair, and an additive gateway API with capability detection. Revisit a monorepo on a stated trigger |
| [0088](0088-oidc-only-identity-with-directory-sync.md) | Humans sign in with OIDC only: the house IdP goes, and Authelia is the one bundled IdP. Providers gain a capability-driven `kind`, per-provider group source/claim/refresh and admin source with provenance, and batch directory sync (Authelia file, Keycloak admin REST — withdrawn in Pystino 0.17.0, 2026-10-23 — and inbound SCIM) into a mirror with a dry-run-first reconciler. Cerea reads authorisation from `/v1/me` |
| [0089](0089-owned-machine-agent-over-opencode-serve.md) | The coding-agent host is an owned Go machine agent (`pystino-agent`, since renamed galopin and moved into Cerea `agent/`) that holds the machine's one enrollment credential, supervises `opencode serve` (or any ACP agent) behind a generic, ACP-shaped backend interface, and dials out to Cerea over WSS, validated locally (`iss`, `aud`, `azp`). Pairing is confirmed in the browser and revocable; nothing capability-bearing is stored in Cerea; the machine's own policy vetoes free models, auto-accept and workspace roots. Supersedes 0085 |
| [0090](0090-machine-file-explorer-and-terminal.md) | Files and a terminal on galopin (the machine agent, 0089), as machine ops advertised in `hello.machine`, each behind a double veto: the machine's enroll-time policy (files read on by default, confined by `os.Root` and redacted; writes and terminals off) and a deployment switch. Terminals run over binary frames with credit flow control and a ticketed, Origin-checked browser WebSocket, need a recent OIDC login, and are audited on both sides without content. Amends 0089's C4 consequence for terminal-enabled machines |
| [0091](0091-deploy-repo-cerea-deploy.md) | A code-free deployment repository (private for now), `cerea-deploy`: the moved `compose.yaml`, a documented `.env.example`, a stdlib-only `./configure` (with `--check`, replacing `doctor`), stock Caddy and Authelia with their config mounted from readable files (a `cerea.config-rev` label makes compose recreate them), pins inside `compose.yaml` so nobody types a version, and `dev/build.sh` for local images. `init`/`set`/`upgrade`/`doctor` leave the gateway image; `bootstrap` stays. A Pystino-only compose lives in Pystino. Supersedes parts of 0086, amends 0087 |
| [0092](0092-cerea-apache-2.0.md) | Cerea, galopin included, is Apache-2.0 like upstream chat-ui: the second licence file goes, `NOTICE` credits Hugging Face. Names Cerea's licence under 0001; the other repositories followed in 0094. |
| [0093](0093-env-authoritative-single-idp-and-local-accounts.md) | One IdP, set only in `.env` and re-seeded into the gateway on every start (the previous row is disabled, never deleted); provider CRUD and its UI are removed. External IdPs need an env admin rule (`OIDC_ADMIN_EMAIL`, or `OIDC_ADMIN_CLAIM` with its value) or the gateway refuses to start. The gateway user id is the person, and the chat keys on it. Link-by-email is an env switch, off by default and never onto an admin; admins merge users in the console. Bundled Authelia accounts are managed from the Users page, with groups only in the console. Also: `./configure --break-glass`, last-admin guards, no bootstrap re-arm, an append-only `identity_events` table. Supersedes parts of 0051, 0056 and 0088 |
| [0094](0094-apache-2.0-for-all-repositories.md) | Pystino, cerea-deploy and ai-stack move to Apache-2.0 (owner's decision, sole copyright holder); `LICENCE` becomes `LICENSE`. Supersedes 0001 decision 1; the dependency policy stands. |

**0015, 0016 and 0041 — the chat frontend decisions — moved to the `chat`
branch with the chat application itself** (A Vite SPA on `packages/ui` with
assistant-ui; Next.js 16 + AI SDK superseded by 0041; the PWA). They are
recorded there, with that branch's copy of this index.

## Decisions recorded now, implemented later

**Status 2026-10-23: only 0020 holds as recorded** (embeddings are configurable OpenAI-compatible endpoints, served through the gateway's `/v1/embeddings`). The desktop shell (0017) never started; the chat's knowledge pipeline uses pgvector without a Qdrant interface (0018); document conversion is the gateway's `/v1/ocr` plus optional Gotenberg (0019); the code sandbox is Pyodide in the browser and galopin on the person's machine, not gVisor (0021). Read them as background, not as plans.

| # | Decision | Phase |
|---|---|---|
| [0017](0017-desktop-shell.md) | Tauri v2 (v3 is alpha only) | 4 |
| [0018](0018-vector-store.md) | pgvector first, Qdrant behind an interface | 3 |
| [0019](0019-document-conversion.md) | Document conversion behind an HTTP endpoint; Docling as reference | 3 |
| [0020](0020-embeddings-and-reranking.md) | Configurable OpenAI-compatible endpoints, no bundled model | 3 |
| [0021](0021-code-sandbox.md) | gVisor first; WASM rejected as the security boundary | 4+ |

## Where an assumption was argued against

Worth knowing which of the starting assumptions changed, and why:

- **Bauhaus → Material Design 3** ([0042](0042-material-design-3.md)) — an
  authentic poster idiom, applied to pages of figures, was hard to read.
- **Redis → Valkey** ([0006](0006-counter-store.md)) — licence history and distro default.
- **Qdrant → pgvector first** ([0018](0018-vector-store.md)) — one less stateful service.
- **Python 3.12 → 3.13** ([0004](0004-gateway-runtime.md)) — and *not* 3.14.
- **`packages/shared` → also `packages/shared-py`** ([0002](0002-monorepo-tooling.md)) —
  two languages cannot share one package.

Everything else in the brief's assumptions was validated as correct.

## Plans

- [phase-2-plan.md](phase-2-plan.md) — redaction and the console, sequenced.
- [web-search-plan.md](https://github.com/paoloviviani/Pystino/blob/main/docs/web-search-plan.md) — search: priced and capped (0058), then backends, then the loop.
- The chat application's plan (`phase-3-plan.md`) lives on the `chat` branch.

## Writing a new one

Copy the shape of an existing ADR. Number sequentially, never renumber, never delete —
supersede instead, and say which ADR supersedes which. An ADR whose decision was reversed
is more useful than one that was quietly removed, because the reversal is the thing worth
knowing.
