# 0101 — Model aliases: the first step towards routing

- Date: 2026-10-18
- Status: **Accepted** 2026-10-18. **Implementation parked** at the owner's request. Design by the owner; details agreed the same day.
- Related: 0045 (public access), 0098 (per-member quotas), 0100 (decision models, parked). Routing with several targets, fallback and weights will build on this.

## Context

Callers name a model, and the gateway serves the model it names. An operator
who wants a stable name, such as `fast`, `default-chat` or `eu-reasoning`,
whose meaning they can change without every client changing, has no way to
get one. They also have no way to offer a model under terms different from
the model's own: today, anyone who can use a name can use exactly that model,
and nothing else.

The owner wants this as the foundation for model routing:
- an **alias** is a model name an administrator defines;
- it points statically at one **target** model;
- callers see the alias as a model and use it like one;
- access to an alias is granted **independently** of access to its target;
- billing follows the **target**.

## Decision

1. **An alias is a row in the `models` table**, marked `is_alias`. An alias
   row has no provider and no upstream model of its own, so `provider_id` and
   `upstream_model` become nullable. A check constraint requires exactly one
   of these: either an alias (`is_alias`, with no provider and no upstream
   model) or a served model (a provider and an upstream model, and not
   `is_alias`).

   **Its target lives in a child table, `model_route_targets`**, not in a
   column on the alias. Each row holds the alias, the target model (a foreign
   key with `ON DELETE CASCADE`) and a `position`. For this step the save
   path enforces exactly one row per alias. A routing policy later is then
   more rows plus a selection rule on the alias, not a schema rewrite (see
   "Designed for routing" below).

   Why the same table:
   - Aliases and models share **one name namespace**: a name is unique across
     both, and a caller cannot tell them apart.
   - They use the **same access mechanism**: `is_public`, group grants and
     user grants (`group_model_access`, `user_model_access`) apply to an
     alias row exactly as to a model, with the same console controls.
   - They share **one catalogue**: `/v1/models` and the chat's model picker
     need no second source.
   - `display_name` and `description` come for free.

   The cost is that some code assumes every model row has a provider.
   Implementation step 1 is an audit of every reader of `ModelDef.provider`
   and `upstream_model`.

2. **Resolution.** `resolve_model` (in `routers/_metered.py`, with the access
   predicate in `access.py`) checks access against the **name the caller
   sent**. For an alias, that means the alias row's access only. The caller
   needs no access to the target: the alias *is* the grant. It then
   dereferences the alias to its target and continues with the target as the
   served model:
   - the target's provider, upstream model, prices, redaction policy, input
     limits and kind.

   The dereference is one level deep: **an alias cannot target an alias**.
   This is refused when the alias is saved, and again at resolution as a
   backstop.

3. **Billing and the ledger follow the target.**
   - The usage record's `model_id` and `model_name` are the **target's**, so
     prices, reports and quotas that name the target behave as if the target
     had been called.
   - A new nullable column on the usage record, `requested_model`, keeps the
     alias name. Reports can then show "via alias", and the ledger stays
     readable after an alias is deleted or retargeted.

4. **Quotas.** Rules that name the target model apply, because the usage is
   the target's. Rules naming an alias are out of scope for this step: the
   quota form does not offer aliases. A later step may add them.

5. **Unavailability.** An alias is **unavailable** when:
   - its target was deleted (the alias has no route target left);
   - its target is inactive;
   - its target's provider is inactive.

   An unavailable alias:
   - is left out of `/v1/models`;
   - refuses requests with a clear error: `503`, code `alias_unavailable`,
     message "The model alias 'X' has no available target." (the exact
     status is a decision for the implementation, with tests);
   - is marked **Unavailable**, with the reason, in the console.

   It is never silently pointed at anything else.

6. **What callers see.** An alias card in `/v1/models` carries:
   - the alias name as `id`;
   - the alias's own `display_name` and `description`;
   - the target's capabilities: kind, modalities, supported features,
     context window.

   Nothing in the card reveals the target: retargeting is invisible to
   clients by design, and the target may be a model the caller cannot see.

7. **Console: a new "Routing" tab** (in the admin area, next to Models), with:
   - a list of aliases: name, display name, target, visibility and status
     (Available, or Unavailable with the reason);
   - a create and edit form: name, display name, description, target (any
     active non-alias model of any kind: aliases are an administrator tool),
     and visibility, using the **same controls as the model page** (public,
     groups, users);
   - delete.

   Retargeting takes effect on the next request; there is no cache to
   invalidate. Every create, retarget and delete is audited like the other
   admin changes. New console strings go through the message catalogue
   (`i18n:check` enforces it).

8. **The model screens stay about served models.** The Models list does not
   show aliases. A model's page shows "Aliases pointing here: …", so deleting
   or deactivating a model shows which aliases it will make unavailable. The
   delete confirmation names them.

9. **Cerea needs no change.** Aliases arrive as ordinary model cards. A
   conversation stores the alias name, so retargeting an alias changes what
   new turns run on, and that is the point. A card with `display_name: null`
   is handled since 0.15.6.

## Designed for routing

The owner's model of routing is an alias whose single target becomes **a
list of targets with a selection rule**. This step keeps that path open:

- **Targets are rows, not a column.** A policy is a `selection` value on the
  alias plus more `model_route_targets` rows, each able to carry `weight`
  and conditions. Possible selections: first available, weighted, cheapest,
  lowest latency, residency or ZDR filtered. "Unavailable" generalises from
  "the target is gone" to "no target in the list is usable".
- **Targets of one alias must be interchangeable.** At save time, every
  target must have the same kind and serve the same API surfaces (a
  Messages-only target cannot back a chat-completions alias). The step with
  one target already validates the kind against the alias's.
- **The card needs a capability rule.** With one target, the card shows that
  target's capabilities. With several, it shows their intersection, and the
  smallest context window and output limit. Otherwise a caller can be
  promised a feature that the chosen target lacks.
- **Admission and billing follow the target actually served.** Admission
  must run per attempt: a fallback to a more expensive target re-reserves
  against that target's price. The ledger records the served target, as
  this step does. Fallback adds the attempts (which targets were tried and
  why), either as attempt rows or on the record.
- **Fallback has limits.** Retry only on errors that say the target, not
  the request, failed: connection errors, 5xx, 429, timeouts. Never retry a
  4xx caused by the content. For streams, retry only before the first byte
  reaches the client. Redaction runs once, before selection, and placeholder
  restoration works per target as today.
- **A session sticks to a single upstream** (owner, 2026-10-18: a
  requirement for routing, not an option). Switching targets between turns
  forfeits prompt-cache hits and changes the model mid-conversation. The
  selection rule runs once per session, and every later request in that
  session goes to the same target, unless that target becomes unusable.
  Routing therefore needs a session key on requests (the chat's conversation
  id, or a caller-supplied header for API clients), and a place to remember
  session → target, such as Valkey with a TTL.
- **Health and latency need shared state.** Latency-based or health-based
  selection needs per-target health (a circuit breaker) and latency
  averages, shared across workers in Valkey.
- **Residency and ZDR rules need provider metadata** that Pystino does not
  record yet (region, retention). The provider-catalogue idea (YAML
  descriptions of providers) is where it would come from.

Everything in this section is deferred to the routing step. The only part
built now is the child table: with one target there is nothing to select,
retry or pin.

## Consequences

- Operators get stable names and per-alias terms, such as "everyone may use
  `fast`; only Research may call the model behind it". Retargeting is a
  single edit.
- Routing later (several targets, fallback, weights, residency-aware
  choices) adds rows to `model_route_targets` and a selection rule to the
  alias: one target becomes a list. Callers keep
  using the same names.
- The `models` table now holds two shapes, and every reader of
  `provider`/`upstream_model` must handle a null. The check constraint, the
  audit in implementation step 1, and tests on the request path carry that
  risk.
- `/v1/models` grows. `test_query_counts.py` pins its select count, and the
  alias join must stay within that pin, or move the pin knowingly with a
  stated reason.

## Rejected

- **A separate `model_aliases` table with its own access tables.** It
  duplicates the access mechanism, the namespace and the catalogue, and the
  owner asked for "the same mechanisms" as models.
- **An alias as a second name for the same row.** Its access cannot be
  granted independently, which is the owner's central requirement.
- **Requiring access to the target as well as to the alias.** It would remove
  the ability to offer a model under the alias's terms.
- **Pointing an alias at another alias.** Chains make "what serves this?" and
  unavailability harder to reason about, for nothing the first step needs.

## Out of scope

- Several targets, fallback, weights, and choosing by price, latency or
  residency.
- Quota rules naming an alias.
- Aliases defined per group or per tenant.
- Aliases created by non-administrators.
