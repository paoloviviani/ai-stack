# 74 — Gateway-specific capabilities live under `/v1/pystino`; usage and quota are the first, in one bearer-readable document

Date: 2026-09-17

## Status

Accepted. Reworks the "usage reporting on `/v1` is deferred" note in the
gateway's working guide (which pointed all spend and quota at `/api` behind a
session cookie): the deferral stands for an *OpenAI-shaped* `/v1/usage`, and
this is deliberately not that. Consumed by the chat's Usage & billing tab
(ADR 0073 amendment), whose Pystino usage provider reads the endpoint below.

## Context

A caller's quota rules and spend live only under `/api/me/*` — the management
API, authenticated by a **browser session cookie** (`get_management_user`),
which rejects bearer credentials. That was fine while the only reader was the
console, a browser on the gateway's own origin.

It is not fine for the chat, or for any `/v1` client. Two things break:

- **Cross-origin.** The chat is a separate application, plausibly on a separate
  domain (`cerea.x.y` and `pystino.x.y` are a normal deployment). A same-origin
  trick — the browser calling `/api/me/*` and letting its gateway cookie ride
  along — depends on the two sharing an origin, which we will not assume. A
  bearer token travels across origins; a cookie does not.
- **Programmatic callers.** A holder of a `gwk_` key cannot read its own limits
  at all today. "How close am I to my ceiling" is a fair question for the same
  credential that spends against it, and answering it only in a browser is a
  gap, not a policy.

The gateway's own guidance deferred a `/v1` usage surface, for a real reason:
quotas are cost *and* tokens across five overlapping scopes where all rules must
pass (ADR 0009, ADR 0025), so there is no honest single "remaining" number, and
a response that *looks* like OpenAI's usage API but means something subtly
different is worse than none. That reasoning is about **shape and mimicry**, not
about whether the data may leave over a bearer token.

## Decision

**Gateway-specific capabilities get their own namespace: `/v1/pystino/…`.**
OpenAI-standard routes (`/v1/chat/completions`, `/v1/models`, `/v1/embeddings`,
…) stay uncontaminated, so a standard OpenAI client never trips over a
vendor-specific path; anything under `/v1/pystino` is, by its address, declared
non-standard. It authenticates like the rest of `/v1` — the bearer principal
(`get_principal`): an OIDC access token or an API key, never the management
cookie.

**The first capability is `GET /v1/pystino/usage`** — the caller's own quota
and spend, as **one JSON document**:

```json
{
  "limits":  [ { "id", "name", "scope", "metric", "window_label",
                 "limit_value", "current_value", "notification_thresholds" } ],
  "usage":   { "window_seconds", "requests", "total_tokens", "cost",
               "currency", "estimated_requests" },
  "groups":  { "<group name>": { …same shape as usage… } }
}
```

- **One document, one round trip.** A caller belongs to a handful of groups and
  has a handful of applicable rules, so there is nothing to paginate and no
  reason for an index-then-subpaths dance; the whole thing is small. This is a
  read, and fewer queries beats granularity nobody needs.
- **Raw per-rule values, never a synthesized "remaining".** Each rule reports
  its own `current_value` / `limit_value` (and `current_value` is **null**, not
  zero, when the counter store is unreachable — a budget shown untouched because
  Valkey is down is worse than one shown unknown). The client decides what
  "nearest ceiling" means across euros, tokens and requests, because that
  comparison cannot be made honestly here. This is exactly why the endpoint does
  **not** reopen the deferred decision: it is the gateway's own shape under a
  clearly-custom path, not an OpenAI look-alike.
- **The API key reads its own principal's data, never admin.** `get_principal`
  resolves a key to a user and their groups (ADR 0065), so a key sees the same
  limits and spend its own requests are counted against — and, as everywhere,
  a key is never `is_admin`.
- **The query logic is shared with `/api/me/*`.** The console's cookie-authed
  routes and this bearer route read quotas and usage through one factored
  function and return identical shapes; there is one source of truth for what a
  limit or a usage summary is, tested once (ground rule 3).

## Consequences

- The chat's Pystino usage provider (ADR 0073 amendment) calls this endpoint
  **server-side with the caller's bearer token** — no same-origin assumption, no
  cookie. Cerea becomes one `/v1` client of a general capability, not a special
  case.
- **Existing custom `/v1` endpoints are not retrofitted.** `/v1/me` (identity),
  `/v1/billing/groups` and `/v1/search/{backend}` are also non-standard and, by
  this principle, "should" sit under `/v1/pystino` too — but moving them is a
  breaking change for current clients (the chat included), so the namespace rule
  applies to **new** endpoints and the retrofit is a separate, later migration,
  not a silent break now.
- A programmatic caller can finally read its own ceilings
  (`curl -H "Authorization: Bearer gwk_…" …/v1/pystino/usage`), which the
  quota-refusal path could only tell it by refusing.
- A live script covers it — the quota reads are dialect-shaped and the auth is
  the bearer principal, neither of which the SQLite unit suite reaches.
