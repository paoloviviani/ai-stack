# 0063 — An MCP gateway for connectors: built, measured, removed

- Date: 2026-09-10, reversed 2026-09-11
- Status: **rejected.** ToolHive was adopted, built into the stack, exercised
  against a real connector, and taken back out the following day. Nothing of it
  remains in the tree; this ADR is the record of why, kept because the next
  person to reach for an MCP gateway — LiteLLM's, Docker's, or ToolHive
  again — should read the measurements before repeating them.
- Asked as an opinion, decided, then reversed on evidence: *"I was considering
  including toolhive as part of the stack, which could play for connectors the
  role that the gateway plays for models. what do you think?"* → *"go for it!
  ... the only assurance I need is that it supports oauth passthrough for
  remote mcps already accepting oauth"* → *"let's keep toolhive on the side
  now. remove everything you deployed or implemented and keep only
  documentation of what we did and why it didn't work."*
- The requirement it failed to meet, as the user put it: **MCP with
  browser-friendly OAuth inside the chat, for remote connectors, either OAuth
  or static tokens.** That requirement stands.

## What was actually wrong, and still is

Not a missing feature — a credential in the wrong place. The chat's MCP support
is a URL and a bag of static headers per server, and custom servers
**including their `Authorization` headers are kept in browser
`localStorage`** (`src/lib/stores/mcpServers.ts`). A long-lived third-party
bearer token therefore sits where any XSS on the origin can read it. There is
an `authRequired` flag on the server record and it only ever *detected* that a
server wanted OAuth; nothing was behind it.

That is the problem to solve. This ADR records an attempt that did not solve
it.

## Why a gateway looked right

ToolHive is to MCP servers what our gateway is to models, on paper: it holds
the counterparty's credential and hands the client one of its own —
[ADR 0032](0032-providers-and-routers.md)'s rule applied to a different kind of
counterparty. It is Apache 2.0, actively developed, and its OAuth surface is
real: `POST /api/v1beta/workloads` takes a remote `url` plus an `oauth_config`
carrying `issuer`, `authorize_url` / `token_url`, `use_pkce`, `resource`
(RFC 8707, which the MCP spec requires) and `client_secret` as a secret
reference. All of that was verified against the running API rather than read in
documentation, and all of it is true.

It is open-core. That was asked about under ground rule 1 and approved, with
the finding that the parts we needed were in the open-source half. The
instructed fork policy was to track upstream one-to-one and diverge only on a
licence change or a forced modification.

## Why it was removed

**The capability we needed lives in a different deployment shape.** ToolHive
has two OAuth paths and they are not equivalent:

| | compose / CLI (`thv serve`, `thv run`) | Kubernetes operator |
|---|---|---|
| credential scope | **one per workload**, shared by every caller | per user — "issues JWTs that identify only the user" |
| redirect URI | always `http://localhost:<port>/callback` | externally reachable |
| token storage | none available in a container | a real token store |
| token exchange | — | RFC 8693 |

`pkg/authserver` — the embedded authorization server that does all of the
right-hand column — is imported by **`cmd/thv-operator` and nothing else**,
checked across all four binaries (`thv`, `thv-operator`, `thv-proxyrunner`,
`vmcp`). So per-user, browser-friendly OAuth is not a flag we failed to find;
it is the operator's feature.

**A fork would not have closed the gap.** `oauth.Config.RedirectURL` already
exists and is simply never populated — exposing it is about eight files of
mechanical plumbing, well within the sanctioned light fork. But with the
redirect fixed the credential is still per-*workload*, the callback listener
still binds container loopback, and tokens still do not persist. Three patches
to arrive at **one shared Notion identity for every chat user**, which in a
multi-user chat is an access-control defect rather than a feature.

**Token persistence is impossible in a container.** Measured, not inferred:
`thv secret provider encrypted` refuses with *"OS keyring is not available"*
and no environment variable substitutes for the keyring; `environment` is
read-only and so cannot hold a token ToolHive *obtains*; `1password` needs an
account. The workload log says it outright — *"Secret manager not available,
OAuth tokens will not be persisted"*. Stacklok's own documentation offers no
headless path and suggests raising an issue.

**And the fit was wrong anyway.** What an MCP gateway is for is *running* MCP
servers: container isolation, a registry, Cedar policies, per-server network
profiles. Our connectors are remote SaaS endpoints — Notion, GitHub,
Atlassian — so we would have paid for the half we do not use, in a Docker
socket, a fork, and a service. The user's summary is the right one: a gateway
"makes sense if we host MCP servers", and we do not. The same reasoning applies
to LiteLLM's MCP gateway and should be read before adopting it.

## Four things that cost time, two of which are ours and will come back

**It will not start without a container runtime** — not even to print
`--help`, and it does not care that only remote servers are wanted, which spawn
nothing. In compose that means the Docker socket, which is root-equivalent
control of the host. Mounting it `:ro` buys nothing, because the Docker API is
spoken *over* the socket.

**Unauthenticated it assigns every caller a synthetic local-user identity**, by
its own startup warning. Pointing it at our Keycloak issuer and `pystino-api`
audience worked first time and gave models and connectors one identity — the
one part of the design that landed exactly as intended.

**An internal plain-http JWKS URL fails silently, and this one is ours.** It
answered `failed to lookup JWKS: resource "http://keycloak:8080/..." is not
ready` inside a 401 whose body is identical to a bad token — while that URL
answered 200 to curl from inside the same container's network namespace.
Measured across three instances with one token: issuer-only works, an https
JWKS URL works, the http one does not. So `SSL_CERT_FILE` pointed at Caddy's
root is load-bearing for anything in this stack that validates our tokens —
and Go *replaces* the system pool with that file rather than adding to it, so
such a bundle is not sufficient for anything that also dials the public
internet.

**A published port cannot reach a service bound to container loopback**, which
is generic and worth remembering the next time something here "is published but
does not answer". The OAuth callback bound `127.0.0.1:8666` inside the
container — measured with `ss -ltnp` in its namespace — so publishing 8666
answered nothing while the same address inside answered 400. A `socat`
forwarder sharing the namespace bridges it.

Two smaller ones. **Sourcing `deploy/.env` mangles `CHAT_OPENID_CONFIG`**: it
holds JSON and `set -a` strips the quotes, so a script that parses it breaks in
exactly the documented way of running it — build tokens from `GATEWAY_OIDC__*`
instead. And **Notion's `/.well-known/oauth-authorization-server` answers 403
to urllib** and 200 to anything browser-ish, which reads like an authorisation
problem and is a user-agent filter.

## What was learned that the successor keeps

**Notion needs no registered application.** It advertises both
`registration_endpoint` and `client_id_metadata_document_supported`, so a
client can either register itself (RFC 7591) or *be* a hosted metadata
document. ToolHive chose the latter, presenting
`https://toolhive.dev/oauth/client-metadata.json` as its `client_id`.

One consequence for us: **CIMD is not available from the address-only
deployment**, because the provider must *fetch* our metadata document and our
origin serves `tls internal` — a CA nothing has heard of. DCR works either
way, since that is us posting to them. Recorded because it looks like a free
win until the certificate stops it.

**The redirect URI is ours to choose, and that removes the whole difficulty.**
Every problem above with `localhost` callbacks disappears once the thing
running the flow is a service on our own published origin, because then the
redirect is a route we own. That is the argument for doing this in the chat
rather than behind a third service — and the chat is already the MCP client,
whereas the gateway does not speak MCP at all.

## What replaces it

The requirement is unchanged: browser-friendly OAuth for **remote** MCP
connectors, plus static-token connectors, with the credential held server-side
and never in the browser. The successor covers implementing the MCP
authorization spec as a client inside the chat — metadata discovery, dynamic
client registration, PKCE, a callback on the chat's own origin, and per-user
token storage with refresh.

No gateway, because we host no MCP servers.
