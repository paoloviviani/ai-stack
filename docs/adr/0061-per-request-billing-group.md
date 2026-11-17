# 0061 — A request may choose which group pays: `x-bill-to`

- Date: 2026-09-09
- Status: **accepted, built.** Gateway side complete and verified live; the
  chat client's half is the follow-on work.
- Asked while wiring the chat application to OIDC: *"if a user logs into the
  chat with oidc, to which group will they be billed? of course the default
  one, but we need to implement a switch somewhere. I would avoid exchanging
  keys manually between chat and pystino."*
- Amends the rule [ADR 0040](0040-bearer-tokens-on-v1.md) left in place, and
  depends on [ADR 0057](0057-group-ownership-and-sync.md) for *which* groups
  count.

## The problem

`resolve_billing_group` said it plainly before this change:

> A bearer caller has no key and so can never pin: the user's default is the
> only answer.

An API key can be minted against a group, so a program has a way to say who
pays. A person signing into a chat application with OIDC has no such lever:
every message bills `users.default_billing_group_id`, and the only way to
change it is `PUT /api/me/default-billing-group` — a management route behind a
session cookie, which a chat client holding an access token does not have.

Minting a key per user per group and handing it to the chat was the obvious
alternative and was rejected in the request itself. It would reintroduce
credential exchange between two services that already share an identity
provider, and every such key is a long-lived secret in a second database.

## Decision

Two pieces, no new state, no credentials exchanged.

**A request header, `x-bill-to: <group name>`,** honoured for callers
authenticated with an OIDC access token. It names a group, and
`resolve_billing_group` takes it exactly where a key's pin already went.

**A `/v1` endpoint, `GET /v1/billing/groups`,** listing the groups this caller
may bill, which is default, and which one the present request is billing.

## Why this grants no new capability

The load-bearing argument, and the reason this is not a loosening:

`resolve_billing_group` already re-checks membership on every request, by
design — *"membership is re-checked here rather than trusted from when the key
was minted, so leaving a group immediately stops you billing it."* The header
passes through that same check. So it can only ever name a group the caller is
a member of **right now**, and any such group could already be billed by
changing the default through the management API. The header removes a round
trip, not a restriction.

Everything below is a way that could stop being true, which is why each has a
test.

## Four refusals, and why each is not merely defensive

**A group the user does not belong to.** The check itself. 403.

**A group that does not exist — refused identically.** Resolution walks the
user's own memberships rather than querying `groups` by name. That is not an
optimisation: a distinguishable "no such group" would turn a billing header
into a directory of every group name in the deployment, readable by any
authenticated user.

**A disabled group.** Membership is not sufficient — `resolve_billing_group`
also requires `is_active`, and `GET /v1/billing/groups` filters on it for the
same reason. Offering a choice in a dropdown that fails on use is worse than
not offering it.

**An API key caller — refused, not ignored, and for every key rather than only
a pinned one.** A key already carries its answer: the group it pins, or the
user's default at request time. That is a property of a credential an
administrator issued, and letting a request override it is a separate decision
with a different blast radius. Ignoring the header instead was the alternative
and is worse: a caller who asked to bill one group and was quietly billed
another finds out from an invoice.

The refusal also happens during authentication, before any reservation, so a
refused request writes no ledger row — otherwise it would bill for a call that
never went upstream.

## The mistake this was one line away from making

The chat client already holds the user's `groups` claim. Building the dropdown
from it would have cost the gateway nothing and needed no endpoint at all.

It is wrong, and ADR 0057 already records why for three other features. A claim
is what the *directory* believes; `memberships.source` distinguishes `oidc`
from `manual`, and a group an administrator granted by hand appears in no
token. `oidc.py` says it in place:

> Reading the token here would have told a manually-added user that the group
> they are in is not one of theirs.

`is_admin`, the default billing group and the sole-group rule were all changed
to read effective memberships for exactly this reason. A claim-derived dropdown
would have hidden precisely the group that had just been granted. The unit
suite has a test that fails only for that implementation — the header names a
group absent from the token — and the live check reproduces it against real
PostgreSQL with a `source=manual` membership.

## Sticky belongs to the client

The header is transient; the gateway persists nothing. The client remembers the
user's choice and sends it on every request, which is how chat-ui's existing
`billingOrganization` setting already behaves.

The alternative — a second stored preference in the gateway — duplicates
`default_billing_group` with worse semantics: two fields that both answer "who
pays", disagreeing, with no rule for which wins. And a header that rewrote the
stored default would mean one client's choice silently changed where a
*different* client's next request was billed.

## The name, and what it is not

`x-bill-to`. Lowercase, no vendor segment, matching `x-filename` and
`x-request-id`, the two request headers this gateway already defines.

The deliberate contrast is HuggingFace's `X-HF-Bill-To`, which chat-ui sends
today. A client that must name a product in order to say "bill this to that
account" is welded to one server; the concept is not vendor-specific and
neither is the spelling, so another gateway could honour this unchanged. That
mattered because the chat has to stay viable as a standalone tool, and the
first proposal — `X-Pystino-Bill-To` — would have put the gateway's name
through the client's own code. It is also why the client keeps its neutral
`billingOrganization` vocabulary and maps to this header at the boundary: one
file knows which gateway it is talking to.

`X-` at all is against RFC 6648's advice, and is kept because consistency with
the two headers already here is worth more than correctness about a convention
this codebase has already chosen.

## What `GET /v1/billing/groups` deliberately does not report

No spend, no quota, no remaining allowance. That keeps it clear of the two
problems recorded against usage reporting on `/v1`: "remaining" is the minimum
over five scopes of cost- and token-based rules, and cost has no standard
header, so a figure shaped like OpenAI's and meaning something subtly different
would be worse than none.

Group names a caller already belongs to carry no such ambiguity. This is the
safe slice of that deferred work, not a down payment on the rest — and it does
not commit the eventual `/v1/usage` to any shape.

## Known consequence, deliberately not fixed here

The sole-group rule sets a default only for a user with exactly **one** group.
A directory user who lands in two gets **no** default, and their first message
fails with *"No billing group is set for this key or user"* — a 403 from a chat
box, fixable only through a management API they cannot reach.

Asked, and answered: the client picks one arbitrarily and does not change the
gateway. The refusal stays, because an arbitrary choice recorded in the ledger
is a billing decision nobody made; the same arbitrary choice made in a settings
dropdown is a default the user can see and change. The arbitrariness belongs in
the interface, not in the money.

## Verified

Unit: 14 tests in `test_bill_to.py`, one of which fails for a claim-reading
implementation and passes for this one. Full suite 1255 passed, 4 skipped, with
the per-request query budget in `test_query_counts.py` unchanged —
`Membership.group` is already `lazy="joined"`, so neither the header nor the
endpoint costs a round trip.

Live, against real PostgreSQL and a real Keycloak token: the endpoint lists a
`source=manual` group that appears in no token; `x-bill-to` naming it returns
200 and the ledger row reads `billed_group = finance-live`, `api_key_id IS
NULL`; a group the user is not in returns 403.
