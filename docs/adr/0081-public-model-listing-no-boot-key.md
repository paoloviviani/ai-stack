# 0081 — `GET /v1/models` is public; nothing is minted to boot the chat

- Status: accepted, built
- Date: 2026-09-19
- Amends [0045](0045-public-models.md), whose "unauthenticated callers still
  see nothing" is corrected below for the *listing* only — everything else in
  0045 (a public model is not a free model, billing is unchanged, access is a
  column read) stands.
- Related: [0027](0027-inference-providers.md) (the grant predicate this
  exempts one endpoint from, not changes), [0040](0040-bearer-tokens-on-v1.md)
  (`USE_USER_TOKEN`, the mechanism that made the boot key unnecessary for
  inference), [0031](0031-model-capabilities.md) (what a `ModelCard` carries —
  the exposure surface this decision reasons about).

## Context

Two things were conflated under one description, "the chat needs a gateway
key to boot," and only one of them is true:

**(a) The chat's generic OpenAI-compatible key machinery.** Cerea speaks
`OPENAI_BASE_URL` plus `OPENAI_API_KEY` (or the legacy `HF_TOKEN` alias) to
any OpenAI-compatible backend, sent as a bearer header when configured. This
exists for backends that are not Pystino — the HuggingFace router, or any
other rate-limited upstream that needs a credential to serve more than a
trickle of anonymous traffic. **This stays.** Nothing about `getApiToken` or
its runtime callers changes.

**(b) Pystino minting and handing the chat a key at boot/deploy time.**
Against Pystino specifically, this is what goes away. Both installers
(`Cerea/installer/install.mjs`, `Pystino/install.sh`) used to pause phase 1
and require an operator to open the console, create a `gwk_` API key whose
user could see every model, and paste it back in as `CHAT_CATALOGUE_KEY` —
which `docker-compose.chat.yml` then wrote into the chat container as
`OPENAI_API_KEY`. Against Pystino, the chat now boots with **no key at all**.

### Why the key existed, and why it was more than the job needed

`src/lib/server/models.ts`'s `buildModels()` fetches `GET /v1/models` once at
process start, before anyone has signed in — there is no user yet to hold a
credential. `USE_USER_TOKEN=true` (ADR 0040) means that key was never used for
an actual inference call; every real request already carries the signed-in
person's own access token, billed to their own group. The catalogue key's
entire job was answering one `GET` with no user behind it.

But a gateway API key resolves to a full `Principal` with no scopes
(`deps.py`) — there is no such thing as a read-only or listing-only key. A
credential minted to read a list was, structurally, exactly as spend-capable
as one minted to run inference: whoever held the deployment's `deploy/.env`
held a key that could bill the group it was pinned to for anything the
catalogue's models were priced at. That mismatch between what the key was
*for* and what it actually *could do* is the reason this needed fixing rather
than documenting.

### What a card actually exposes

`ModelCard` (`schemas.py`): `id`, `object`, `created`, `owned_by`,
`context_window`, `max_output_tokens`, `max_input_tokens`, `display_name`,
`kind`, `input_modalities`, `output_modalities`, `supported_features`. No
price, no grant, no usage, no user data — brochure-level fields a deployment's
own console page already shows anyone who loads it without signing in. Listing
which models a deployment *offers* was never the sensitive half of this
surface; billing and using one already are, and neither changes here.

## Decision

**`GET /v1/models` (list only) is exempted from authentication.** Unauthenticated,
it returns the full, unfiltered catalogue: the same kind-filtering
(`?include=` and the SEARCH-tier exclusion, ADR 0071) and the same
non-caller-facing provider exclusion as the authenticated path, but with grant
filtering skipped entirely rather than run against an absent caller — skipping
the filter is not the same operation as running it against a caller with no
grants, which would (correctly) return nothing. `access.all_active_models()`
is the unauthenticated half of `access.accessible_models()`, factored out
rather than duplicated, per that module's own rule about one predicate written
in one place.

Authenticated, the endpoint is **unchanged**: a real caller still gets the
grant-filtered view unioned across their groups, exactly as ADR 0027 and 0045
describe. The exemption widens who may *ask*, never what a given caller is
shown. `gateway.deps.get_optional_principal` is the new dependency — it
resolves a `Principal` exactly as `get_principal` does when a credential is
presented, and only returns `None` when *no* credential was presented at all.
A bad credential still 401s; presenting one and having it rejected is not the
same as presenting none.

**`GET /v1/models/{name}` (detail) stays authenticated.** Resolving one named
model is the step a caller takes once it already holds a credential to spend
— chat, embeddings, images, OCR are all requested by name — and that is
exactly the step this exemption does not cover.

### Why the picker stays exactly correct

Cerea's `src/routes/api/v2/models/+server.ts` intersects the boot catalogue
with the *caller's own* token per request; the gateway enforces the real grant
at send time regardless of what either list showed. A public superset
therefore cannot make the picker offer something a caller cannot reach — it
was already just the left-hand side of an intersection, and a wider left-hand
side still intersects down to the same right answer. This endpoint was not
touched.

`src/lib/server/models.ts:259-280` (`buildModels`) already supported keyless
boot before this decision: it sends the bearer header only when a token is
configured, and only throws on a 401 when it had no token to try. Against a
public list endpoint this simply works — confirmed with a test
(`src/lib/server/models.keyless-boot.spec.ts`), not redesigned.

## What was removed

- The phase-1 pause in both installers that asked an operator to mint a
  `gwk_` key and paste it back in — deleted, not stubbed. Phase 1 (postgres +
  gateway, the admin password, the chat database) is otherwise unchanged: it
  still has to run before phase 2 for those two reasons, just not for a key
  anymore.
- `CHAT_CATALOGUE_KEY` — from `requiredKeysFor` in `install.mjs`, from
  `deploy/.env.example`, from `docs/deployment.md`'s variable table.
- The `OPENAI_API_KEY=${CHAT_CATALOGUE_KEY:?...}` line in
  `docker-compose.chat.yml`'s `DOTENV_LOCAL` block. `OPENAI_API_KEY` is simply
  absent now for a Pystino-backed chat container.

## What stays, deliberately

- (a) above: `OPENAI_API_KEY`/`HF_TOKEN` as a *configured, per-deployment*
  credential for a non-Pystino backend. `Cerea/.env`'s comment now says so
  explicitly — "only for non-Pystino backends; unset against Pystino" — rather
  than presenting it as something every deployment needs.
- The satellite shape this was already meant to support —
  `OPENAI_BASE_URL=https://central/v1`, `USE_USER_TOKEN=true`, OIDC against
  the central deployment, **no key** — is now actually reachable end to end
  against a Pystino backend; nothing in the installers or compose files forces
  one anymore.

## Accepted cost

Anonymous boot is specifically a *Pystino* fact (a deployment we control the
auth exemption on). Against a non-Pystino OpenAI-compatible backend — the HF
router, or any other rate-limited upstream — an unauthenticated `GET /models`
is still whatever that provider decides, typically a stricter rate limit or a
401. That is exactly why (a) is not removed: `buildModels` still sends
`OPENAI_API_KEY`/`HF_TOKEN` when one is configured, and an operator pointing
Cerea at such a backend still needs to configure one. This decision only
removes the credential that Pystino itself no longer requires for its own
public listing.

## Consequences

- A deployment's model catalogue (names, limits, modalities, features — never
  prices) is readable by anyone who can reach `GET /v1/models`, signed in or
  not. Treated as brochure-level information on purpose; see "What a card
  actually exposes" above.
- No `deploy/.env` on a Pystino-backed deployment holds a spend-capable
  `gwk_` key whose only job was listing models. One fewer standing credential
  to rotate, back up, or leak.
- `Pystino/install.sh` and `Cerea/installer/install.mjs`'s phase split is
  shorter by one operator round trip (open console, mint key, paste it back);
  phase 1 still exists for the admin password and the chat database.
