# 71 — The gateway meters search; it does not translate it

Date: 2026-09-13

## Status

Accepted. Supersedes the normalisation layer built with the search surface
(phase 2 of `docs/web-search-plan.md`) and records the pieces the
[search backends are not models](0070-the-vector-store-belongs-to-the-chat.md)
decision started.

## Context

The first search route translated. One request shape and one response shape —
query, tier, normalised results — with each vendor's plugin building the
request and reading the answer, so that swapping Linkup for Exa would be an
administrator's edit and no caller would parse two shapes.

That is a broker, and a broker is a layer: every vendor difference it
absorbed was knowledge maintained in this repository forever, every vendor
feature it did not model was a field the route had to grow before a caller
could ask for it, and the vocabulary drifted anyway (Exa's live schema has
six search types where a rendering of their docs still serves three). The
caller that actually consumes this deployment's search is one application —
the chat, which turns a model's tool call into a search and the results back
into a citation. One consumer is not a fleet.

## Decision

The gateway meters; it does not translate.

- **`POST /v1/search/{backend}`** — an authenticated, metering passthrough.
  The gateway resolves the backend, checks the caller's grant, counts the
  request, attaches the backend's own credential, and forwards the body to
  the vendor **verbatim**, returning the vendor's answer **verbatim** —
  including their errors, including the `x402` payment challenges both
  Linkup and Exa now answer unfunded accounts with. The caller that can act
  on those answers is the one that assembled the request.

- **The chat speaks each vendor's API.** One adapter per backend lives in the
  caller — Linkup's `q`/`depth`/`outputType`, Exa's `query`/`type`/
  `numResults`, each vendor's response fields — building the request and
  reading the results. Which depth words mean what, which response field
  holds the title: the vendor's vocabulary, in the vendor's adapter.

- **Common search APIs are out of scope.** Developing and maintaining one is
  precisely the layer this decision removes.

- **The grant is per backend.** One model row per backend — named after it,
  created with the provider — carries the group or personal grants, and that
  row is what `/v1/search/{backend}` resolves. A tier is a body field now; no
  tier rows, no tier-granular grants, because reading the body to enforce
  them would be vendor knowledge in the one place this design refuses it.
  Request ceilings (owned-search counts) bound volume as before; the vendors'
  pricing differences between tiers are the operator's to reconcile against
  the count.

- **Search backends stay off `/v1/models`.** There is no industry consensus
  for listing search backends as models — the reference APIs ship web search
  as a tool or parameter, never as a model entry — and an
  OpenAI-compatible client reading the list would present a backend as a chat
  model. The default listing excludes them; `?include=search` is the opt-in,
  and grants still bound what it returns.

- **The console gives search its own screen.** Backends, and who may search,
  are managed under Web search — not on the providers and models screens,
  which are for generative models and their counterparties. Creating a
  search backend creates its grant anchor; there is nothing to import.

## Cost, stated rather than hidden

**Egress redaction does not cover search on this route.** The translated
route redacted the query, because it knew which field held it. A passthrough
that promises not to read the body cannot redact the query inside it, and a
per-vendor "query field" config table is the first plank of the layer this
decision removes. A caller that screens its own query may do so before
calling; the gap lives in the route's docstring where the next reader will
find it.

## Consequences

- The plugins shrink to the minimum the passthrough cannot infer: the
  endpoint path and the auth header scheme. Linkup's and Exa's request and
  response vocabularies moved into the chat's adapters, beside the tool that
  uses them.
- A vendor change — a new depth, a renamed response field — is a change to
  the chat's adapter, deployed when the chat deploys, without touching the
  gateway.
- Metering is unchanged in kind: one request is one
  `OWN_SEARCH_REQUESTS` count, taken before the call and kept on failure,
  reconcilable against a vendor's dashboard with no currency and no rounding.
- `own_search_tier` is written null; a passthrough never reads the body that
  would name one.
