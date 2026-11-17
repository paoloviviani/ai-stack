# Spike: Cortecs Decisions API (live beta, 2026-10-22) and OpenRouter notes

No secrets or account identifiers in this file. Raw responses: probe1.txt, probe2.txt, probe3.txt (key redacted).

## Cortecs

Base: https://api.cortecs.ai/v1 (Bearer). Routes: POST /v1/decisions, POST /v1/systemone.

### Models
- Decision models are NOT listed by GET /v1/models (49 models with the key, 105 unscoped; tags seen: Instruct, Tools, Reasoning, Vision, Document, Audio, Safety-guard; no "Decision" tag). They appear only on cortecs.ai/serverlessModels?tags=Decision.
- Ids (work as `model`): `laya` (Convai, 421M), `clef-flash` (Cloudflare; its fallback_model is `clef`). `clef` itself returned 404 "No endpoint passed allowed_providers_filter" for this key (project settings exclude its provider); laya and clef-flash worked.
- Website price: 0.042 EUR per M input tokens, 0 output, for laya and clef-flash. Context 66K. Provider (berget) is shown on the website only, never in the API response.
- Consequence: the admin must create decision models by hand (model id, prices); the provider's /models cannot be used to discover them.

### Wire format (confirmed against docs and live)
/v1/decisions with `input` (string, or messages `[{role:"user",content:[{type:"input_text",text}]}]`) and `questions` array of predicate/choice(`choices[{value,description}]`)/score(`levels[{label,description}]`):
```
200 {"model":"laya","answers":[
 {"type":"choice","name":"route","choice":"facilities","probabilities":[{"value":"facilities","probability":0.7764},...],"confidence":0.66},
 {"type":"score","name":"urgency","score":1.2398,"probabilities":[{"value":0,"label":"low","probability":0.0577},...],"confidence":0.4672},
 {"type":"predicate","name":"inspect","probability":0.0915}],
 "usage":{"input_tokens":143,"input_tokens_details":{"cached_tokens":0,"cache_write_tokens":0},"output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":143,"cost":7,"cost_details":{"prompt_cost":7,"completion_cost":0}}}
```
Unnamed question: `"name": null`. Messages form accepted (143 tokens incl. 3 questions).

System One (`state` + keyed `questions` with noul/choice/score) on /v1/systemone and also on /v1/decisions (answered in kind):
```
200 {"model":"laya","answers":{"inspect":{"type":"noul","noul":0.0323},
 "team":{"type":"choice","choice":"facilities","confidence":0.981,"probabilities":{"facilities":0.9905,"billing":0.0095}},
 "urg":{"type":"score","score":1.30,"confidence":0.339,"legend":{"0":"low","1":"medium","2":"high"},"probabilities":{"0":0.068,...}}},
 "usage":{"input_tokens":124,"output_tokens":0,"cost":6,"cost_details":{"prompt_cost":6,"completion_cost":0}}}
```
/v1/systemone DOES return usage (a slimmer one: no *_details, no total_tokens). Sending `input`+array to /v1/systemone is a 400.

### Cost units
- usage.cost is an integer in micro-EUR, rounded UP per request: 32 tokens -> 1.344 -> 2; 143 -> 6.006 -> 7; 140 clef-flash -> 5.88 -> 6; 28 -> 1.18 -> 2; 124 -> 5.2 -> 6. cost == prompt_cost + completion_cost. Matches 0.042 EUR/M exactly (output is free, output_tokens always 0).
- So the ceiling rounding makes tiny requests cost 1-2 micro-EUR; the reported figure is >= price-table figure. Authoritative as micro-EUR (same as chat), currency EUR.
- Price table fallback (tokens * price/1e6) will differ from the reported figure by < 1 micro-EUR (rounding): do not treat as a mismatch.

### Served model
- Same as chat: response HEADERS `x-cortecs-provider: berget` and `x-cortecs-model: laya` (also in access-control-expose-headers). The body `model` is the requested id echoed. So the existing Cortecs `read_served_by` (headers) works unchanged for decisions. No header on /systemone probed separately (same router; assumed identical, not verified).

### Errors (shape `{"error":{"message","type","param","code"}}`, code is a string)
- unknown model: 404 `invalid_request_error` "NotFoundError: Model not found."
- model whose provider the project excludes: 404 "No endpoint passed allowed_providers_filter ..."
- bad question type / wrong format: 400 `invalid_request_error`, message is a long pydantic dump ("Invalid Decisions request: ...").
- bad key: 401 `{"error":{"message":"Unauthorized","type":"auth_error","param":"None","code":"401"}}`
- The docs say only 400/500; 401 and 404 occur. No 429/500 seen.

### Routing fields
- `preference: "cost"` accepted. `eu_native:true` accepted with 200 and no visible effect. Unknown extras not probed. (Gateway refuses the provider-routing ones per ADR.)

### Latency
0.10-0.12 s for errors, 0.22-0.50 s for answers (3 questions, ~140 tokens: 0.46-0.50 s).

### Refusals
Not elicited (empty input, adversarial instruction, all answered normally). Shape from docs: answer `type:"refusal"` with `name`; reason field name is undocumented. Code must tolerate unknown answer shapes (pass-through) and never parse answers except usage.

### Not verified
No `fallbacks`/`allowed_providers`/`quantizations` behaviour (would be refused by the gateway); no 500; refusal body.

## Verdict on ADR 0100
Confirmed: served model/provider in headers as for chat; micro-EUR integer cost (authoritative in provider_reported mode), /systemone returns usage, both formats, errors are 400-class (plus 401/404). No contradiction that changes the design. Notes to fold in: models are not discoverable via /models (manual creation), served model = echoed id, reported cost is ceil-rounded so the table estimate can be 1 micro-EUR lower.

## OpenRouter (docs only)

- Routers as models: `openrouter/auto` (Not Diamond was the old engine; now "powered by the market": a lightweight classifier assigns one of ~30 task types, ranks models by trailing-7-day spend share, `cost_tier` low..max, fallbacks). Per-request settings via `plugins:[{id:"auto-router", cost_tier, allowed_models, excluded_models}]`; `openrouter/auto-beta` uses plugin id `auto-beta-router`. Other router slugs: `:nitro/:floor` variants, `pareto`, `bodybuilder`, `fusion`, "latest" resolution, model `fallbacks` (`models:[...]`), `provider` preferences object (order, only, ignore, allow_fallbacks, data_collection, zdr, quantizations, sort).
- Served model reporting: chat response `model` = the model actually selected (e.g. `anthropic/claude-sonnet-4.5` for a request to `openrouter/auto`); `provider` field names the upstream provider; `id` = generation id (`gen-...`). Opt-in header `X-OpenRouter-Metadata: enabled` adds `openrouter_metadata` (requested, strategy: direct/auto/free/latest/alias/fallback/pareto/..., endpoints, attempts, pipeline with router `task_type`).
- Cost: `usage.cost` is a float in credits (USD), always present now (`usage:{include:true}` is deprecated/no-op); `cost_details.upstream_inference_cost` only for BYOK. Asynchronous: `GET /api/v1/generation?id=gen-...` returns usage and cost, also the real served model/provider and native token counts.
- Decisions: OpenRouter has an ALPHA decisions route `POST /api/alpha/decisions` (System One shape only: `state` + keyed `questions`, types noul/choice/score/box (image bounding box)); model ids like `typesafe/jev-1.13` (TypeSafe's Jev; bare `jev-1.13` mapped into `typesafe/`); there is also an SDK `systemOne.create`. Request carries `provider` (routing prefs object), `session_id`, `user`, `trace`. Response: `{id, model, provider, answers{}, usage:{input_tokens, output_tokens, cost (double)}}`. Errors: 400/401/402/403/404/413/429/500/502/503/524/529.
- Provider-agnostic design must accommodate: (1) both request shapes (array/`input` and keyed/`state`), box questions and unknown question types: pass-through, no parsing of answers; (2) cost as integer micro-EUR (Cortecs) or float USD credits (OpenRouter): the plugin owns the unit conversion, the core takes micro-units of the deployment currency through the existing conversion (ADR 0054); (3) served model: echoed id (Cortecs) vs. real selected model plus `provider` (OpenRouter), record `model` as reported and `provider` if present; (4) routing fields differ (flat fields vs `provider` object, `plugins`): the gateway must strip/refuse the provider's whole routing vocabulary, so the list lives in the plugin; (5) route path differs (`/v1/decisions`, `/v1/systemone` vs `/api/alpha/decisions`): the plugin owns the upstream URL; (6) a wider status set (402/403/413/429/5xx) - map like chat; (7) decision models not discoverable via /models.
- An OpenRouter key would help verify: whether `usage.cost` is returned for the alpha decisions route in practice and its units (credits vs. USD), the served `model`/`provider` values for `typesafe/jev-*`, and the generation endpoint for a decisions id. Not needed to build the Cortecs-first design.
