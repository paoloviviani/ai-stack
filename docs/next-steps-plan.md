# Next steps — the chat deployment (2026-09-11)

Resolves the open questions in Pystino's `docs/handoff-2026-09-11.md` and sets
the order of work for the test environment. The two authentication rules below
are the constraints every step assumes; the discussion that settled them is
summarised in [Authentication](#authentication).

## Authentication

Two rules, settled 2026-09-11, **landed on `pystino@knowledge-bases` the same
day** (uncommitted at the time of writing):

1. **OIDC is a possibility, not a requirement.** A deployment with zero
   identity providers is *complete*, in the sense [ADR 0044](adr/0044-keycloak-removed.md)
   already claims. The gateway half is built: local sign-in ([0043](adr/0043-local-authentication.md)),
   bootstrapped by `gateway passwd`, and the gateway issuing `/v1` credentials
   for its own accounts ([0046](adr/0046-local-api-credentials.md) — opaque
   refresh/access credentials, explicitly *not* an OIDC issuer).
   **The gap is the chat.** The fork dropped `apps/chat-api`, and its local
   door went with it: Cerea signs in through OIDC only. **Decided
   2026-09-11:** the gateway is promoted to a **minimal IdP for
   browser-facing clients** (supersedes the browser-facing half of
   [0046](adr/0046-local-api-credentials.md), whose credential machinery is
   kept as the substrate, per that ADR's own escape hatch): discovery,
   authorization-code + PKCE, `id_token`, JWKS, userinfo, RP-initiated
   logout. Access tokens stay **opaque** — introspected key rows as today, no
   JWT on the `/v1` hot path; API keys and M2M clients are untouched.
   Tight coupling with the chat is accepted as the product shape: Cerea is
   not a standalone product, and no bundled Keycloak returns
   ([0044](adr/0044-keycloak-removed.md) stands).
   The credential-minting endpoints are **internal-only** — reachable on the
   compose network by the chat's backend, never published (see
   [Network classes](#network-classes)). *ADR 0068 to cut when this lands.*
2. **Groups and roles are a gateway fact; the IdP authenticates and never
   administers.** [ADR 0057](adr/0057-group-ownership-and-sync.md) built the
   machinery — membership provenance, a per-provider sync mode whose `first_login`
   answers once, at provisioning, and never again. This rule makes
   `first_login` the stance for every provider added here: the directory
   creates the account and may seed its groups on the way in; everything after
   — membership, the default billing group, **the admin flag** — is decided in
   this console and survives every login. The automatic admin path goes away:
   `GATEWAY_OIDC__ADMIN_GROUPS` ([0043](adr/0043-local-authentication.md)'s
   "only automatic admin path") is removed; an administrator is made in the
   console or by `gateway passwd --admin`, never by a group claim. Admin and
   membership are console facts, exactly [0050](adr/0050-group-management.md)
   said; the difference is that no provider may be configured to claim them.
   Cost, named: an account the directory has stopped naming still keeps its
   groups here — the directory had its one answer.

## Network classes

Three classes of endpoint, settled with the IdP decision:

| Class | Endpoints | Reachability |
|---|---|---|
| **Minting** — where a credential is born | `POST /auth/login` (the password grant), `POST /auth/token` (refresh → access), `POST /auth/revoke`, the IdP's `POST /token` (code exchange) | **Internal only.** Served on a compose-network listener with no published port; the chat backend is the intended caller. The edge's path allowlist refuses them as defence in depth |
| **Browser-by-necessity** — the IdP must meet the user at its own UI | `/authorize`, the login UI, discovery, JWKS, `end_session` | Published at the origin, like the console's login page today. Protected by PKCE, one-time codes, state, the first-party client allowlist and the existing throttle |
| **Management** — unchanged | `/v1`, `/api`, `/console`, `/chat` | As ADR [0035](adr/0035-public-tls-exposure.md) already shapes them |

The security gain is real: the password grant **leaves the public internet
entirely** — today `POST /auth/login` is publicly reachable in the
[0035](adr/0035-public-tls-exposure.md) shape, because the console's form
posts to it; after the promotion, only the login *UI* is public and every
minting POST rides the compose network. The console's login form is the one
piece that keeps its public door at first (it is not the chat's concern); it
may adopt `/authorize` later — client `console`, exchanged by the gateway
itself — and then the raw grant goes internal for everyone.

And the deployment switch, the remark settled alongside the question: the IdP
is **off unless enabled** (`idp.enabled`, the house pattern of
[0043](adr/0043-local-authentication.md)'s feature switch and
[0065](adr/0065-unmetered-deployments.md)'s off-means-absent). Disabled means
the routes are not registered and discovery does not resolve — a standalone
gateway deployment (console + API keys + external OIDC as today) never grows
a federating surface because the feature shipped. The management doors are
not part of the IdP and are not touched by the switch.

ADR 0040's bearer path is untouched: a token from any configured issuer still
works on `/v1`, audience-gated as before.

## The steps

In order:

1. **Commit and push Cerea's rename** (Cerea → the app's name; 8 files,
   done 2026-09-11, uncommitted).
2. **Agents move to the chat side.** This resolves the contradiction the
   handoff recorded between ADR [0062](adr/0062-knowledge-bases.md)'s
   gateway-side agents and "agents are only within the chat": the chat wins.
   Remove the gateway's `agents` table, `agent:<name>` model cards and routes;
   Cerea owns agents (Mongo, the projects precedent). Knowledge bases stay in
   the gateway — only the agents half of 0062 is corrected. **Sharing agents
   is deferred and disabled**: they belong to the user; no publish routes even
   where the [0066](adr/0066-publishing-and-platform-ownership.md) machinery
   would make them additive. *ADR 0067 to cut when this lands.*
3. **The Playwright deployment moves to the chat.** Its only consumer is
   Cerea; the overlay (`docker-compose.playwright.yml`, `docs/browser.md`)
   moves from Pystino's compose to Cerea's. Publishing no port, as before.
4. **Credential rotation is dropped** as an open item: this box has no prior
   deployment, so the handoff's six exposed credentials are not exposed
   anywhere. (Closes that handoff line.)
5. **Topology of the development box:** loopback-only, reachable only through
   the NetBird overlay; the reverse-proxy setting publishes the box's
   `localhost:8443` to the internet as **cerea.example.org**. The development
   deployment is exposed there. This makes the public exposure of ADR
   [0035](adr/0035-public-tls-exposure.md) a standing property of this box
   rather than a one-off — the "nothing else on a routable address" rule and
   its live check stay.
6. **Wire web search to the chat.** The gateway's `POST /v1/search`, the
   Linkup/Exa backends and the per-search metering all exist ([0058](adr/0058-per-search-pricing.md));
   the chat's side — requesting search inside the generation loop, surfaces
   the results, and the ledger showing the per-search charge — is what the
   handoff called the next task and was not started.
7. **Stand up a test environment** at `cerea.example.org`: gateway + chat +
   redaction (+ the moved Playwright service), the IdP enabled with no
   external provider configured — the gateway's own issuer is the way in —
   first administrator bootstrapped, plain HTTP behind the NetBird edge. Step
   1 of the authentication rules is what makes this shape possible, and this
   deployment is the first one to prove it.

## Open questions, blocking 7 only — answered 2026-09-11

- **Where TLS terminates**: at the NetBird edge. The stack serves **plain
  HTTP** on the box's 8443; the browser sees the edge's HTTPS, so `Secure`
  cookies still work. Implementation check: the gateway must be told the
  external origin is HTTPS (Secure-cookie and CSRF `Origin` checks behind a
  plain-HTTP hop need the public host configured, not sniffed).
- **The upstream behind the test env**: the fake smoke upstream. Real keys
  will be exercised manually.
- **Sync mode**: `first_login` is the stance for when an IdP is added (the
  directory answers once, at provisioning; the gateway owns everything after).
  **The test deployment is built local-only first**; the IdP is added manually
  afterwards, as [0051](adr/0051-settings-identity-and-email.md) already
  allows.

## ADR follow-ups

- **0067 — agents belong to the chat** (corrects 0062's agents half; records
  that sharing agents is deferred, not designed). *To cut when step 2 lands.*
- **[0068](adr/0068-minimal-idp.md) — the gateway is a minimal IdP for
  browser-facing clients** — written; implemented on the branch with tests.
- **[0069](adr/0069-authorisation-is-a-gateway-fact.md) — authorisation is a
  gateway fact** — written; implemented on the branch with tests.

Per the series' rule, both are cited by number from wherever the code lands.
One mechanism deviation from the 0068 draft is recorded in the ADR's
*Tested* terms and in `docs/idp.md`: the minting surface is enforced by
**discovery advertising the compose-internal token URL** plus **client
authentication**, rather than a second unpublished listener — a standard
OAuth client cannot be taught a custom header or a second port, and the
effect (only the compose network can mint) is the one the classes describe.
The edge's path refusals remain the deployment-side second layer.

Per the series' rule, both are written here, numbered next, and cited by
number from wherever the code lands.

## Backlog

- **Knowledge bases: download and inspect uploaded documents.** The chat's
  Knowledge screen stores the bytes (its own GridFS) and the extracted
  markdown, but offers neither back: a base's documents can be listed and
  deleted, not opened. Two surfaces to build, both gated by the store's
  existing reach rules (owner or viewer share): a *preview* — the extracted
  markdown is already on the row, so inspecting what retrieval actually
  sees is a read of `knowledge_documents.text` — and a *download* of the
  original bytes from GridFS, with the attachment disposition the gateway's
  old `files.py` used and a size cap worth keeping. Recorded 2026-09-13,
  after ADR 0070 moved the store into the chat and made it this
  application's to build.
