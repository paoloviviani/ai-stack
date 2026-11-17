# 0100 — Decision models through the gateway

- Date: 2026-10-16
- Status: **unparked 2026-11-04** (owner): built now, first used by ADR 0105's auto mode as the permission reviewer; the live check with a scoped Cortecs key comes first. Was: parked 2026-10-16. The owner wants this, but not now. Pick it up
  with a Cortecs key, so the wire format and the cost units can be checked
  against the live beta before any code.
- Related: 0032 (provider-reported cost, ADR decision 6: both figures
  recorded), 0054 (currency conversion of reported cost), the OCR and
  embeddings routers (the pattern this follows), 0098 (quota rules that would
  apply unchanged).

## Context

Cortecs added a **Decisions API** (beta,
<https://docs.cortecs.ai/api/decisions.md>) for a new class of models:
**decision models** such as Cloudflare's Clef (27B, plus a 9B flash variant,
Apache-2.0) and Convai's Laya (421M, Apache-2.0). A decision model does not
generate text. It takes a piece of text and typed questions, and returns
calibrated probabilities. That makes routing, triage, moderation and
classification far cheaper and faster than asking a chat model and parsing
its prose.

The wire contract, from Cortecs's reference (no model ids or cost units are
documented, and there are no examples):

- `POST /v1/decisions` (OpenAI-style): `model` (a model tagged "Decision"),
  `input` (a string or messages), and `questions` (1–128). Each question is a
  `predicate`, a `choice` (2–255 options, each with a `value` and an optional
  `description`) or a `score` (2–10 ordered levels).
  - The response is `answers[]`: `probability`, `choice`/`score`,
    `confidence`, and per-option `probabilities`; an answer may also be a
    `refusal`.
  - It also returns `usage`, with token counts plus `usage.cost` and
    `cost_details`. These are integers, presumably micro-EUR as in chat.
- `POST /v1/systemone`: the same in the TypeSafe ("System One") format, with
  `state` and `questions` keyed by caller ids, and `noul`, `choice` and `score`
  questions. `/v1/decisions` also accepts this shape and answers in kind.
- Routing fields in the body: `preference`, `allowed_providers`, `eu_native`,
  `provider_order`, `quantizations`, `allow_zero_data_retention`,
  `enable_model_fallback` and `fallbacks`.
- No streaming. Errors are 400 and 500 only.

Pystino has four model kinds (`chat`, `embedding`, `image`, `ocr`), and each
non-chat kind has its own metered router. None of them can carry this shape,
so today a deployment cannot offer these models at all.

## Decision

1. **A `decision` model kind and two routes.** `POST /v1/decisions` and
   `POST /v1/systemone` are routed and metered like `/v1/ocr` and
   `/v1/embeddings`:
   - access: per-user tokens and API keys, group access to the model;
   - limits: quotas reserved before the call and settled after;
   - cost: the provider-reported figure in `provider_reported` mode, with the
     price table as the fallback and as the reservation estimate;
   - records: one usage record per request.
   The request is passed through in the format it arrived in, and so is the
   response.
2. **Routing belongs to the gateway, not the caller.** `allowed_providers`,
   `eu_native`, `provider_order`, `quantizations`,
   `allow_zero_data_retention`, `enable_model_fallback` and `fallbacks` are
   refused with a 400 naming the field. They are the provider's settings in
   Pystino, as for chat. `preference` (speed / cost / balanced) passes through.
3. **Redaction applies.** `input`/`state` is text sent to an upstream, so it
   goes through the deployment's redaction policy exactly as a chat message
   does. The answers carry no free text to un-redact, except a refusal's
   reason, which is passed through as is.
4. **The provider plugin owns the shape.** The Cortecs plugin forwards both
   routes and reads `usage.cost`. That is authoritative if the live check
   confirms micro-EUR; otherwise the reported cost is recorded but not
   billed. A provider whose plugin has no decision support refuses to serve
   a `decision` model (the console says so when the model is created).
5. **Catalogue and console.**
   - `/v1/models` lists decision models with `kind: "decision"` (excluded
     from the chat picker, like `ocr`).
   - The console's model form offers the kind, with prices per million input
     and output tokens.
   - Usage reports show the kind like the others.
6. **Out of scope:**
   - Cerea using decision models (to choose a model, triage uploads, or
     moderate) — except the permission reviewer of ADR 0105 (owner, 2026-11-04);
   - self-hosted Laya or Clef through the local extractor or an Ollaya-style
     server: a generic plugin pointed at it would work, but nothing here is
     built for that;
   - streaming.

## Verified live (2026-11-04)

With a scoped Cortecs key (report an internal decision-reviewer trial report (not published)): decision models are listed by `GET /v1/models?tag=Decision` (`clef-flash`, `laya`; pricing EUR per million input tokens, output free); `usage.cost` is **micro-EUR** (as for chat), so the plugin's reported cost is authoritative; a predicate answer has `probability` and no `confidence`; an unknown model answers 404 with an OpenAI-style error body; no `refusal` seen in 50 calls; `/v1/systemone` not exercised. The catalogue's `review` flag of ADR 0105 is dropped: Cerea's admin picks the reviewer among `kind: decision` models.

## Before implementation (why it was parked)

Using a temporary, scoped Cortecs key, confirm:
- the model ids;
- the units of `usage.cost`;
- whether `/v1/systemone` returns `usage`;
- the error bodies;
- that `refusal` answers occur.

The plugin's authority flag depends on the cost units, and the price table
needs real numbers.

## Consequences

- API-key users and agents get cheap, calibrated classification through the
  same keys, quotas and reports as everything else.
- Two more routes to keep in step with a beta upstream; the plugin isolates
  that.
- Redaction now runs on non-chat text as well. It costs the same per request
  as for chat.

## Rejected

- **Expose decisions through chat completions** (a prompt that asks for a JSON
  verdict). It loses the calibration, which is the point.
- **Pass routing fields through.** That would let a caller pick providers the
  deployment excluded (e.g. outside the EU).
