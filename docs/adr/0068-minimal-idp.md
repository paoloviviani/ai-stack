# 0068 — The gateway is a minimal IdP for browser-facing clients

- Date: 2026-09-11
- Status: **accepted — implementation starting**
- Supersedes: the browser-facing half of [0046](0046-local-api-credentials.md),
  by that ADR's own escape hatch: *"if a genuine requirement for the gateway
  to be an IdP ever appears, this ADR's credential machinery is the substrate
  to promote, and only the browser-facing flow changes."*
- Related: [0043](0043-local-authentication.md) (the login UI and the session
  this reuses), [0044](0044-keycloak-removed.md) (no bundled IdP — this is
  not one), [0040](0040-bearer-tokens-on-v1.md) (the `/v1` path the tokens
  ride), [0056](0056-account-linking.md) (whose linking question this ADR
  answers by not needing it), [0035](0035-public-tls-exposure.md) (the
  publishing discipline the network classes extend), [0010](0010-api-keys.md)
  (the key machinery that is *not* superseded).

## Context

[ADR 0046](0046-local-api-credentials.md) built the gateway's local door as a
private protocol — `POST /auth/login {client}` → refresh credential →
`POST /auth/token` → opaque access credential — and rejected the gateway as
an IdP on two grounds: a real IdP is a large permanent security surface, and
the flow it would have replaced rested on the password grant, deprecated in
OAuth 2.1. Both grounds were correct for the client that existed then.

The requirement has now appeared, from three directions at once:

1. **The client was lost.** The chat fork dropped `apps/chat-api`, and the
   only consumer of the private protocol went with it. Rebuilding that door
   re-implements, per client, glue that exists as battle-tested libraries for
   OIDC — and the product decision of 2026-09-11 is that more clients are
   coming (desktop shell, ADR [0017](0017-desktop-shell.md)), not fewer.
2. **The flows cannot exist.** No `id_token`, no discovery, no JWKS, no
   RP-initiated logout, no device flow — ADR 0046 itself records that
   `opencode`'s device flow still needs a real IdP, which on a local-only
   deployment means it does not work at all. "OIDC optional" is currently
   asymmetric: without an external IdP you do not get a lesser standard
   surface, you get a private one.
3. **The product shape settled.** Cerea is not a standalone product; tight
   coupling with the gateway is the way, not something to escape. The chat
   will always have a gateway behind it, and that gateway should speak the
   interface every human-facing client already speaks — without importing
   Keycloak, which [0044](0044-keycloak-removed.md) removed as the largest
   component for what it did.

## Decision

**The gateway promotes its credential machinery to a minimal IdP for
browser-facing clients.** The substrate stays exactly as 0046 built it; only
the browser-facing flow changes, as predicted.

- **Standard surface, standard shape**: discovery
  (`/.well-known/openid-configuration`), authorization-code + PKCE at
  `/authorize`, `POST /token`, JWKS, `/userinfo`, `end_session` with
  `id_token_hint`. The `id_token` is a JWT — the only JWT the gateway mints,
  signed at login, never on the request path.
- **Access tokens stay opaque.** `/v1` continues to receive key rows,
  introspected by the lookup 0046 already pays for, revocation still a row
  deletion, the `test_query_counts.py` budget untouched. OIDC does not
  require JWT access tokens, and self-contained tokens would reintroduce the
  revocation problem the opaque design solved.
- **First-party clients are registered server-side** — a client registry
  naming redirect URIs, with `cerea` first. No public dynamic client
  registration: a public registry is how client squatting starts. No consent
  screens: first-party clients are auto-approved. SSO is the existing
  `gw-session` cookie — 0043's "one session, two doors" becomes one session,
  *N clients*: signing in at the console is signing in at `/authorize`, and
  the chat's redirect completes without a second prompt.
- **Issuer identity is settled by aliasing, not linking.** Users are keyed on
  `(issuer, subject)`; a gateway-issued `id_token` carries `iss` equal to the
  deployment's public origin, and at the resolution seam an `iss` equal to
  the gateway's own issuer resolves to `issuer="local"` with the casefolded
  email as subject. One row per person, forever — no second row for an
  account that changed doors, no adoption decision, no
  [0056](0056-account-linking.md) machinery for our own issuer. An external
  issuer cannot claim this alias: tokens bearing it must verify against the
  gateway's own JWKS to be accepted at all.
- **Network classes.** Endpoints sort into three, and the sort is enforced:

  | Class | Endpoints | Reachability |
  |---|---|---|
  | Minting | `POST /auth/login`, `POST /auth/token`, `POST /auth/revoke`, `POST /token` | Internal only — the IdP's `/token` is advertised in discovery at the deployment's *internal* base URL, which drives a standards client onto the compose network, and it demands client authentication, which only the deployment's services hold; the ADR 0046 family is guarded by the `x-mint-token` internal credential. The edge's path refusals are the second layer, and the deployment's to configure |
  | Browser-by-necessity | `/authorize`, the login UI, discovery, JWKS, `end_session` | Public at the origin, as the console's login page already is |
  | Management | `/v1`, `/api`, `/console`, `/chat` | Unchanged, per [0035](0035-public-tls-exposure.md) |

  The mechanism is worth recording against this ADR's first draft, which
  imagined a second, unpublished listener. A standards OAuth client cannot be
  taught a custom header or a second port — it follows discovery and it
  authenticates the way the spec says — so the enforcement moved into the two
  things a client *does* do: the URL it was given (internal, advertised) and
  the credential it presents (the client secret). The effect is the one the
  classes describe: only the compose network can mint.

  The gain is concrete: the password grant leaves the public internet. Today
  `POST /auth/login` is publicly reachable in the [0035](0035-public-tls-exposure.md)
  shape because the console's form posts to it; after this ADR only the login
  *UI* is public and every minting POST rides the compose network. The
  console's own form keeps its public door at first; it may adopt
  `/authorize` later (client `console`, exchanged by the gateway itself),
  and then the raw grant is internal for everyone.
- **The IdP is off unless enabled.** `idp.enabled`, default false — the house
  pattern of [0043](0043-local-authentication.md)'s feature switch and
  [0065](adr/0065-unmetered-deployments.md)'s off-means-absent. Disabled
  means the routes are not registered and discovery does not resolve; a
  standalone gateway deployment (console, API keys, external OIDC as today)
  never grows a federating surface because the feature shipped. The
  management doors are not part of the IdP and the switch does not touch
  them.

## What was rejected

- **JWT access tokens.** They would put JOSE parsing and claim validation on
  the hot path and turn revocation into a TTL — the two things the opaque
  design exists to prevent. The `id_token` carries the identity; the access
  credential carries only its own lookup.
- **A full IdP** — consent screens, dynamic client registration, claims
  parameter, certification. Nobody has asked for a third-party client; each
  of these is a surface added before a requirement exists. The authorization
  endpoint is the substrate; if a real requirement arrives, device flow
  (RFC 8628) and friends are additive.
- **An off-the-shelf IdP service.** [0044](0044-keycloak-removed.md)'s
  judgement stands, and holds for the smaller alternatives too: a second
  stateful service to operate, whose user store would then be *another*
  store to reconcile with the ledger's accounts.
- **Rebuilding the private protocol's chat door.** It keeps the per-client
  tax forever and the flows still cannot exist. The protocol served the
  chat-api it was built for; that client is archived.

## Consequences

- A JOSE signing dependency enters the gateway, and a signing key becomes a
  deployment secret with a rotation story (`kid`-keyed; rotation adds a key,
  never flips one). Library and algorithm choices are researched at primary
  sources at implementation time — never from memory, per ground rule 2.
- `/authorize` is the classic CVE surface — redirect-URI validation, state,
  PKCE enforcement, code single-use and short TTL — and gets the tests named
  below. The first-party registry bounds it: an unknown client or an
  unregistered redirect is refused before any session check.
- `end_session` clears the `gw-session` cookie it is handed; front/back
  channel logout is not built. A client that needs its own session gone
  revokes its refresh credential — 0046's machinery, unchanged.
- The chat deploys with the IdP enabled and no external provider: its OIDC
  client points at the gateway's discovery URL, and "local-only deployment"
  stops being a special shape — it is OIDC against the house issuer.
- The console's login page remains as it is; its eventual move to
  `/authorize` is additive and would retire the last public minting route.

## Tested

Named now, per ground rule 3: discovery shape and absence when disabled;
PKCE required and downgrade refused; code single-use, short-lived, bound to
client and redirect; unregistered client and unregistered redirect refused
before authentication; `id_token` claims (`iss`, `aud`, `exp`, `nonce`) and
signature; the issuer alias resolving to the pre-existing local row, never
minting a second one; `/token` and `/auth/token` refused from the public
listener and answered from the internal one; end_session clearing the
session; the switch-off leaving management doors and API keys fully working.
