# ADR 0114: Privacy rules model v2 (two kinds, rules "When policies + conditions -> mode", claim order)

- Status: accepted 2026-11-10 (owner approved the design); shipped in Pystino 0.33.0 (migration 0086)
- Supersedes: ADR 0113, section 0 (the first-match pipeline with a fixed last rule, the ladder with `pass`/`refuse`,
  `redact with`, `observe_only`) and the "strictest mode wins" fold of ADR 0038 as the way hiding is combined. The rest of
  0113 stands: statelessness, scope, the conditions' meaning, the fail-closed rule, the extractor models (0085).
- Renamed on 2026-11-10 by the owner: the `read` kind is **`extract`** ("default extractor < extract with <extractor> < block").

## Context

0113 had one object that both found and decided (a policy with a mode on every item) and pipelines whose rules named a
policy twice (once in a `finds` condition, once in `redact with`), with a first-match search inside a pipeline, a fixed
"everything else", a `pass`/`refuse` ladder and a separate `observe_only` flag. Administrators could not read a pipeline
aloud, the same policy needed two editions (one that only counts, one that hides), and "what hid this span" depended on a
fold nobody could trace.

## Decision

**Kinds: `extract` and `content`.** `content` is chat, responses, messages, embeddings and rerank. A content pipeline's
target has an optional **model type** filter (chat, embedding, rerank; empty is any), part of the scope.
**Policies keep only what to look for** (items, engine, thresholds, allow-list, placeholder style): no `mode`, no
`default_mode`. User policies lose the per-entry mode the same way.

**A rule is a sentence: "When <policies> + <conditions> -> <mode>".**

- `policies`: one or more; what the rule looks for and hides. A content rule needs at least one, **except a rule that blocks (any conditions, or none: "block everything in scope") or records under at least one condition (`detect_only`)**, which hides nothing and may have none ("classified as X -> block"). An extract rule needs none.
- `conditions`, optional, with `match` all or any (default all), each negatable. `finds` is "at least N distinct items found
  by the rule's own policies combined" and names no policy. `classified` (administrators) is unchanged. Extract conditions
  (`filetype`, `scan`, `filename`) are unchanged. With no conditions a content rule fires when its policies find one item.
- `mode`: `off` < `detect_only` < `anonymise_restore` < `anonymise` < `redact` < `block`, with optional per-type
  `overrides`. `block` refuses (`RoutingRefusedError`, `routing_refused`, unchanged for Cerea); `off` does nothing;
  `detect_only` records (this replaces `observe_only`).
- An extract rule has an `action` (`default` | `extract_with` | `block`) and optional hiding (policies + mode) applied to
  the text the extractor returns.

**Evaluation (stateless, per request).**

1. Every rule of every pipeline in scope is evaluated (no first match): administrator pipelines in console order
   (`position`), then the user's own, each pipeline top to bottom.
2. All conditions are judged on the original text.
3. **Block first**: a matching rule in mode `block` (or an override that blocks a type that was found) refuses, naming
   the first such rule.
4. Otherwise hiding is applied in that order and **the first rule to hide a span decides how**; later rules only see text
   not already claimed (overlaps with claimed text are dropped; within one rule, score then length, as ever). `off` and
   `detect_only` never claim. One detection pass over the original text per request; placeholders stay HMAC-stable
   (`placeholder_for`), restore works for `anonymise_restore` spans, nothing is detected again on placeholder text.
5. An undecidable condition never fails open: a rule that does not protect (`off`, `detect_only`) does not match; a
   protecting rule treats a non-negated condition as a match; a negated one is a 503 `privacy_undecidable`. (The old
   "at least as strict as every later rule" clause is gone with first match.)
6. The trace lists every pipeline and every rule (matched or not), the items found, and which rule claimed which span.

**Extract.** The first matching `extract_with` rule wins, an administrator's before a user's, with the existing hop logic
(the pipelines guarding a new extractor also run); `block` wins over any extractor.

**User pipelines** need no tighten-only machinery any more: administrators come first, the first hider decides how, a
block refuses, the administrator's extractor holds. A user can add protection and cannot remove any. A user's own policy
(patterns and entity types to look for) is applied by their rule's mode.

**Detection.** Each rule's policies are stamped with the rule's mode and overrides into the engine-level
`RedactionPolicy` (`PolicyDefinition.stamp`), so thresholds and allow-lists stay per policy, and one `detect` call asks
for the union. `finds` counts each policy once per request (remembered) and merges distinct (type, value) items.

**Log.** `routing.kind` stays `read`/`embed`/`chat` in old rows; new rows say `extract`, `embed` or `chat` (embed covers
rerank), plus `observed.model_type`, and every pipeline lists all its matched `rules`. The redaction log's `rule` is now
the privacy rule that claimed the type (it was the policy).

## Migration 0086

Merges `chat` and `embed` into `content`; `read` becomes `extract`; the old `otherwise` column is dropped.

- A chat and an embed pipeline of one owner with the same name, scope, enabled flag and converted rules become one with
  model type any. Otherwise each is converted alone (model type chat, or embedding + rerank), a name clash gets a
  "(chat)" / "(embedding + rerank)" suffix, and positions are renumbered per owner and kind (chat first on a tie).
- Each rule: `finds` conditions name policies, which become the rule's policies; `refuse` is `block`; `pass` + `redact with
  P` is a rule over P whose mode is P's most common item mode, the other item modes overrides (the stricter mode on a tie);
  `observe_only` is `detect_only`; `otherwise` with a policy is a final "Everything else" rule with no condition,
  `otherwise: pass` is dropped. Extract rules keep their conditions, `read_with` is `extract_with`, `refuse` is `block`.
- Policies and user policies lose `mode`/`default_mode` only after being converted.

**Lossy cases (each is logged as `privacy rules v2 0086: ...`):**

1. *First-match shadowing is gone.* A rule after one that matched used to be skipped; it now also applies. This only ever
   adds protection (and a `pass` rule that did nothing but shadow is dropped, logged).
2. *`refuse` with no policy* (classifier-only, or refuse everything in scope) migrates **enabled** as a no-policy `block`
   rule: with its classifier condition, or with no condition (block everything in scope). An observe-only one with nothing to
   look at is dropped.
3. *Several `finds` conditions on one rule.* None negated: one count over the union of their policies, with the largest count
   (fires at least as often). Any negated (mixed, or all negated): one count cannot say it, so the rule is kept **switched off
   with a note** and the log line says "some negated".
4. *A rule that decided on X and hid with a different P* becomes two rules: "X + threshold -> detect_only" and "P -> modes"
   unconditionally (the gate on X cannot be expressed); it hides more than before. A negated `finds` gate on another policy is
   dropped with the first rule (stricter); a classifier gate is kept on the hiding rule. Split names are cut to 120 characters.
5. *Items that were `off`* are dropped from their policy. A name in two tables keeps its strictest mode.
6. *A policy with `default_mode` other than `off`* is written out as explicit entries for every format the service reports
   without a model (29) and the NER types (PERSON, LOCATION, ORGANIZATION, NRP; no NRP for GLiNER). A type an engine or the
   service adds later is no longer covered, and an old default meant "every type", so this is a snapshot.
7. *Per-item modes* inside one policy used by different rules become overrides on each rule; `detect_only` items stay
   `detect_only` overrides.
8. *Observe-only extract rules* are kept as a rule whose action is `default` with a note (they only recorded).
9. *`otherwise: refuse` / `read_with X`* (content and extract) is rebuilt as "none of the rules above matched": a rule with
   every earlier condition negated, match all, when each earlier rule has a single condition (extract: conditions of one key
   are merged, "not in A or B"; content `finds` only over one policy and count). Otherwise it is added **switched off with a
   note**, never enabled with no condition. If an earlier rule matches everything, it never applied and is dropped.
10. *`otherwise` that hides* (a policy, action default) hides unconditionally now (stricter).
11. *A rule that hid with a missing policy* keeps a hiding mode (`redact`) naming it, so the request path fails closed with a 503
    as before. An extract rule's hiding part never has mode `block` (clamped to `redact`; block stays the action).
12. *Twin chat/embed pipelines* are paired explicitly (each chat copy with at most one embed copy), whatever the row order.
13. *Cross-pipeline order now decides.* The old fold took the strictest mode per type across pipelines; now the first matching
    rule that hides a span decides, so the first administrator pipeline by position claims it. Where two pipelines gave one type
    different modes, the result can be **less strict** than before (the earlier pipeline's mode wins even if the later was
    stricter). Reorder pipelines to put the stricter first, or give the strict one a `block`.
14. *Policy item `block`* becomes a rule-level block (`routing_refused` naming the rule), not `content_blocked` naming the type.
15. *User policies' entry modes* move to the user's rules like any policy's.

**Irreversible.** The downgrade raises: merged pipelines, moved modes and the dropped first-match order cannot be told
apart again. Take a database backup before upgrading (the dev stack's was taken as the brief required).

## Consequences

- API: pipelines carry `rules[{policies, match, conditions, mode, overrides, action?}]` and `target.model_types`; `otherwise`
  and `observe_only` are gone (400 on send); policy bodies carry no `mode` (400 on send); the Test result has `claims`
  instead of `ladder` and `policy_types`.
- Rotating `GATEWAY_REDACTION__PLACEHOLDER_KEY` invalidates embeddings indexed with old placeholders: knowledge bases must
  be re-embedded (said once in docs/redaction.md).
- Nothing in the seeds or the UI names a subject (no medical or other topic defaults).
