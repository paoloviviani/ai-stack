# Privacy pipeline advisory: redaction as rules with routing, not a workflow engine (2026-11-08)

Read-only advisory, about two hours. Sources are the Pystino and Cerea checkouts in `~/workspace`, the ADRs in `ai-stack/docs/adr`, the GLiNER spike report, and the public pages cited inline. Nothing was run; the N5105 figures are the spike's estimates, not measurements. External facts checked today are marked with their URL; facts stated from memory are marked as such.

## Executive summary

1. **Keep the line where it is: Cerea describes, Pystino decides.** Cerea adds a small, fixed set of request annotations (source, purpose, file name, MIME, document hash) as `x-pystino-*` headers on the `/v1` calls it already makes. Pystino treats them as evidence that can only *tighten* a decision, never loosen one, so a forged or missing header costs nothing. Everything policy-shaped (which engine, which modes, whether bytes may leave) stays in Pystino, as the owner prefers.
2. **Cerea's planned workflows (backlog C83) should not touch redaction.** Workflows are user-authored recipes with open "run-as" questions; redaction is administrator policy with a tighten-only user layer (ADR 0112). The only coupling worth having is that a workflow step carries the same annotations as a chat turn does. Separate is better, and the argument is in §1.
3. **Narrow the "workflow" idea to two things that already have shapes in Pystino.** (a) A short, ordered list of **routing rules** (first match wins, administrators only) whose actions are *where text goes and which detector reads it*: route a document to the local extractor, refuse or reroute egress, pick a detector profile. (b) The existing **policy fold** (strictest wins, user rules last) for *what happens to each entity*. Do not merge them into one rule language: the fold is safe because it is monotone, and a general "ordered rules with arbitrary actions" model would lose that property and the reasoning that comes with it. Of the owner's three examples, the second ("if the extracted content matches a rule, don't send it anywhere") **already works today** as a custom pattern in mode `block`; only the first and third need new machinery.
4. **Classification is three tiers, and only the third is expensive.** Metadata (globs, MIME, source, purpose, group, model) is free and runs in the gateway; RE2 patterns are cheap and already run in the gateway; a model classifier (GLiNER with 3–4 labels, or a language detector) runs in the sidecar and should run **once per document at ingest** (`/v1/ocr`), with the verdict cached by content hash in Pystino and referenced by hash on later turns. Fail closed for anything whose action protects.
5. **Engines by target.** Pattern-only Presidio everywhere as the floor (150 MB, shippable). spaCy `en_core_web_*` for English team deployments (MIT). The Italian spaCy models stay personal-use only (CC BY-NC-SA). GLiNER (`urchade/gliner_multi_pii-v1` or the E3-JSI fine-tune, Apache-2.0) as the opt-in high-recall engine **scoped by rule to documents**, on 10–12 GB boxes. OpenAI Privacy Filter (Apache-2.0) is a credible candidate for **English** team deployments and worth a one-day spike, but it is "primarily English", has 8 categories with **no medical or health category**, no confidence score in its JSON, and its CPU cost is unmeasured; it does not replace GLiNER for Italian medical PDFs.
6. **Extraction.** markitdown + pypdfium2 is adequate for born-digital Office and PDF files and should stay the default. Its real gap is **scans**: the honest answer today is `no_text_layer`. Add **RapidOCR** (Apache-2.0 code and models, ONNX Runtime on CPU, PP-OCRv6 multilingual recognition includes Italian) as an optional OCR step inside the extractor, triggered only when a PDF page has no text layer. Docling is MIT code but its layout and table weights are tagged CDLA-Permissive-2.0 alongside Apache-2.0 on the Hub; CDLA-Permissive is not on the OSI list, so treat Docling as a **team-deployment option behind the existing `/v1/ocr` provider seam**, not as a kit default, and confirm the weights' licence before bundling. Exclude PyMuPDF, marker, surya and MinerU (AGPL/GPL). Extraction *routing* belongs in the rule pipeline; extractor internals do not.
7. **Admin UX without a policy language**: a form per rule (WHEN conditions, THEN one action set), a test box that accepts a file or a text plus a user and model and answers "which rule fired, which engine ran, what would be hidden", an **observe-only** flag per routing rule (log the match, take no action), and attribution (`routing_rule`, `engine`) in the redaction log and the per-response summary so Cerea's info dot can show it.
8. **Build order**: Phase 0 annotations and attribution (days, no risk); Phase 1 routing rules for `/v1/ocr` and detector profiles (the first real value: "medical PDFs never leave, and get the slow engine"); Phase 2 ingest-time classification with a hash cache and GLiNER productised; Phase 3 RapidOCR for scans and the Privacy Filter spike; Phase 4 reroute-to-local-model and user-level "keep my documents local" as a tighten-only user rule.

## 1. The responsibility line between Pystino and Cerea

### What Pystino can see today, and what it cannot

Pystino's redaction knows the principal, the group, the key, the model and its provider (`_metered.redaction_policy`, `apps/gateway/src/gateway/routers/_metered.py:1051`), and it tags where a span was found as `message`, `tool_result` or `document` (`redaction/report.py:28-30`; `document` only on `/v1/ocr`). It does not know:

- that a message part **came from an attachment**. Cerea inlines the extracted text as a `text/markdown` part under the document's own name (`src/lib/server/endpoints/preprocessMessages.ts:44-62`); `prepareFiles` then merges it into the user message, so Pystino sees "message". The same is true of retrieved passages, which Cerea fences inside the system prompt (`src/lib/server/textGeneration/untrusted.ts:110-115`), and of project context (up to 100,000 characters, `docs/knowledge.md:90-103`);
- the **file name or MIME** on a chat turn (on `/v1/ocr` the gateway forwards `x-filename` and `content-type` to the sidecar, `gateway/extraction.py:123-129`, but a chat turn carries neither);
- the **purpose**: chat, knowledge ingest (`/v1/embeddings` from `knowledge/embed.ts`), title or summary generation, a scheduled run, a coding-agent turn;
- the **document identity** across calls: Cerea stores extracted text by hash (`file.type === "hash"`, `preprocessMessages.ts:39`), but Pystino never learns the hash, so it cannot connect the `/v1/ocr` call that read a document with the chat turns that quote it.

Cerea, for its part, decides which extractor reads a PDF (`knowledge/extractorResolution.ts`: env, then the Knowledge screen's stored choice, then the gateway's local extractor, then the first OCR model). That is the "setting" the owner's first example wants Pystino to be able to override.

### Recommendation: Cerea annotates, Pystino decides

Cerea should send, on every `/v1` call it makes for a user, a fixed and small vocabulary of **request annotations**, as headers (the `x-pystino-*` convention already exists: `x-pystino-redaction-summary`, `x-bill-to`, `x-request-id`). Headers rather than the OpenAI `metadata` body field, because `/v1/embeddings` and `/v1/ocr` have no such field, and because Pystino already excludes `metadata` from redaction and from its own semantics.

| Header | Values | Why Pystino wants it |
|---|---|---|
| `x-pystino-purpose` | `chat`, `ingest`, `title`, `summary`, `schedule`, `agent` | a rule can say "ingest of medical documents runs the slow engine" without slowing chat |
| `x-pystino-source` | one or more of `message`, `document`, `retrieved`, `tool_result`, `project` | attribution in the log, and conditions such as "documents only" |
| `x-pystino-filename`, `x-pystino-mime` | as uploaded (on `/v1/ocr` these already travel as `x-filename` and `content-type`; on a chat turn that quotes a document, the names of the documents quoted) | the owner's first example: glob on the file name |
| `x-pystino-document` | the content hash(es) Cerea already stores | lets Pystino reuse a verdict it computed at ingest (§3) |

Two rules make this safe to accept from a client:

- **Annotations only tighten.** A missing or wrong annotation means "treat as the plain case". No rule may say "if purpose is `title` then skip redaction": the fold's monotonicity extends to annotations. Concretely, a routing rule condition on an annotation can select a *stricter* action (local extractor, block, slower engine); the absence of the annotation selects the default, which an administrator sets as strict as they like. A forged header can at most make a request slower or refused.
- **Pystino never trusts the client for the verdict.** Cerea may say "this is a document named `referto.pdf`"; it may not say "this document is not medical". Verdicts are Pystino's own (§3).

What Pystino alone decides: the detector engine and labels, the modes per entity, whether bytes may leave, which backend reads a document (overriding Cerea's `model` on `/v1/ocr` when a rule says so, and reporting the served backend honestly in `served_model`), the placeholder scheme, and what the log holds. Cerea's "extractor choice" becomes a *preference* that Pystino honours unless a rule overrides it. That is exactly the owner's "regardless of the setting".

### Should Cerea's planned workflows touch this? No.

C83 ("multi-step recipes with typed outputs, per-step tools, approval gates, shared definitions run as the starter") is a **user-authored** feature with its run-as model still open. Redaction is **administrator policy**, with a user layer that can only add protection (ADR 0112). Letting a workflow definition carry redaction settings would create a second place where policy is written, by people who are not administrators, and either (a) it could loosen, which breaks the invariant that kept every past redaction bug inert instead of dangerous, or (b) it could only tighten, in which case it is just a user rule by another route, and ADR 0112 already provides those with one owner, one store, one UI.

The one synergy worth keeping is trivial: a workflow step is a `/v1` call like any other and sends the same annotations (`purpose: workflow:<name>` is a reasonable value). If a user wants "everything in this workflow stays local", the right primitive is a Pystino **user rule** "refuse egress of documents" (Phase 4), which the workflow runs under. Pystino also gains nothing by knowing a workflow's structure.

Candidly: the owner's instinct ("maybe separate is better") is right, and the reason is not taste but the monotonicity argument above.

## 2. A rule and pipeline model for Pystino

### What exists, restated as a pipeline

Today's request path is already a fixed pipeline: resolve subject → fold the applicable `redaction_rules` (strictest wins; ADR 0038) → fold the user's rules (tighten-only; ADR 0112) → detect with the one configured engine (`redaction_config`, ADR 0033) → substitute, or block → log counts without values. On `/v1/ocr`: read with the backend the `model` names → redact the returned text under the same fold.

What is missing is the step **before** the fold: nothing chooses the engine per request, nothing routes a document, nothing refuses egress on a condition other than an entity match.

### Proposal: routing rules in front of the fold

Add one table, `redaction_routes` (name is yours), with an **ordered list of a few rules**, administrators only, first match wins. Each rule is:

- **Conditions** (all must hold; each optional): surface (`chat`, `embeddings`, `ocr`, `responses`, `messages`); purpose; source; file name glob; MIME; group, user, key; model or provider; **classifier label** (§3; from the hash cache or computed); language (from the request or detected).
- **Actions** (one set, applied together):
  1. `extract_locally`: on `/v1/ocr`, read with the local extractor whatever `model` the caller named; the response reports the local backend as served. (Owner's example 1.)
  2. `egress`: `allow` (default), `refuse` (a 403 that names the rule, never the content; like `block` today), or `reroute: <alias>` (serve from a named local model or alias instead; only valid when that alias is served by a provider flagged local). (Owner's "refuse egress or reroute".)
  3. `detector_profile`: a named profile (`pattern`, `spacy`, `gliner-medical`, `privacy-filter`) that the sidecar advertises in `/healthz` (§4); plus optional labels for engines that take them. (Owner's example 3.)
  4. `policy`: the name of an existing `redaction_rules` row whose `RedactionPolicy` is **added to the fold** for this request (so it can only tighten). Never a replacement.
- **Observe only** flag: log "would have matched" and take no action (§6).
- **Fallback** for the detector profile: `fail_closed` (default) or a named weaker profile, recorded as a weakening when saved (same convention as same-length placeholders, `docs/redaction.md:313-317`).

The rest of the pipeline is unchanged: the fold computes the modes, the chosen profile detects, substitution happens in the gateway with the HMAC placeholders, the log gets `routing_rule` and `engine` in addition to what it holds.

### Why this composes cleanly with the fold and user rules

- Routing rules **never change a mode**. Modes come from the fold, which stays monotone. A routing rule can add a policy to the fold, which is the union/max direction; it cannot remove one.
- Routing rules choose **among detectors and destinations**, where "stricter" is well defined and can be enforced at save time: local over remote, refuse over allow, a profile that advertises more entity types over one that advertises fewer. A rule whose action is weaker than the default is accepted but flagged "weakens" with the same warning the console already uses.
- **First match wins is fine here** because the actions are not cumulative protections but choices. Keep the list short (a soft cap of, say, 20, with a warning) so an administrator can read it top to bottom. If two rules could both apply, the first one is the one the administrator ordered first, and the test box says so.
- User rules remain where they are: last in the fold, tighten-only. Add exactly one user-level routing capability later (Phase 4): "refuse egress for my documents", which is monotone.
- **Attribution stays single-sourced.** `redaction_detail` grows `routing_rule: {id, name}` and `engine: {profile, name, version}`; the per-response summary carries the same two fields; Cerea's overlay shows them. "Why did this take 40 seconds" and "why was this refused" become answerable from the request, as "why was this redacted" is today (`docs/redaction.md:384-391`).

### What to say no to

- **No expression language.** Globs for file names, exact match or sets for everything else, RE2 for content. The console builds a sentence from the form ("For group Clinic, when a PDF named like `*referto*` is ingested: read it locally, detect with GLiNER (medical), and apply the policy 'Medical'").
- **No per-request engine choice by the client.** The profile is a rule's decision, never a header's.
- **No "most specific wins" across the two tables.** Routing is ordered; the fold is monotone. Mixing them is how policy becomes unreadable.
- **No per-conversation state in Pystino.** The hash cache (§3) is keyed on content, not on sessions.

## 3. Local classification

### Tiers, cost and where they run

| Tier | What | Where | Cost | Caching |
|---|---|---|---|---|
| A. Metadata | file-name glob, MIME, source, purpose, surface, group, user, model, provider, declared language | gateway, in memory with the rules (ten-second poll, like today) | nil | none needed |
| B. Patterns | RE2 regexes over the text (the existing `CustomPattern` machinery, plus "any of these words" lists for a cheap topical flag, e.g. `diagnosi|referto|anamnesi|terapia`) | gateway, outside the detection cache as today | microseconds | none needed |
| C. Models | a language detector (to choose `it` vs `en` per document, since `GATEWAY_REDACTION__LANGUAGE` is one value per deployment, `config.py:1141`); GLiNER with 3–4 labels (`medical condition`, `medication`, `health insurance number`) as a *classifier* (any hit above a threshold on the first N characters means "medical"); optionally a small sentence classifier later | the sidecar (it already holds the weights and runs CPU work off the event loop) | GLiNER: 4 ms/token on 4 cores here, 10–20 ms/token on the N5105 (spike §3); a 1,200-character head is 1–5 s | **by content hash**, once per document |

A language detector is the cheapest model tier and probably the most valuable one for the owner's own box: an Italian PDF under an `en` deployment is detected with the wrong model today. Candidates (from memory, not checked today): `lingua-py` (Apache-2.0) or fastText `lid.176` (the model is CC BY-SA 3.0, so not shippable under the project's policy; prefer lingua). Verify before adopting.

### Classify once, at ingest

The moment Pystino holds the whole document is `/v1/ocr`. Cerea calls it once per upload and stores the result by hash (`extractDocument.ts`, "It runs at upload and its result is stored"). So:

1. On `/v1/ocr`, after extraction and before the response, run the tier-C classifiers a routing rule asks for on the extracted text, and store the **verdict** (labels and scores, never text) keyed by `sha256(extracted text)` in a small Pystino table or in Valkey with a long TTL. Return the hash in the response (`pystino_document: {hash, labels}`), so Cerea can store it next to the text it already keeps.
2. On later chat or embeddings calls, Cerea sends `x-pystino-document: <hash>` for each quoted document. Pystino looks up the verdict (one indexed select, or a cache hit) and evaluates routing rules against it. An unknown hash is "no verdict", which selects the default, which is as strict as the administrator wants.
3. The gateway may additionally verify the hash against the inlined text when the part is marked as a document, to keep the hash from being a free-form claim; if the hashes disagree, "no verdict".

The cost model then matches the economics in the spike: the slow engine runs once per document, not once per turn, and chat latency does not pay for it. It also answers the spike's "scoping" prerequisite ("the economics only work if redaction is scoped", spike §7.3).

### Failure behaviour

- A classifier that a rule depends on is unavailable: **fail closed** for that rule, meaning take the rule's protective action as if it matched (route locally, refuse egress, or run the strict profile), and if the strict profile is itself unavailable, refuse with a 503-class error that names the rule. This mirrors `fail_open=false` today (`config.py:1139`) and the resolver's "a failed poll changes nothing" stance.
- A classifier that is not needed by any rule is never called.
- Verdicts are never written with values, and the hash cache holds labels and scores only (keeps `test_redaction_visibility.py`'s table scan honest).

## 4. Engines

### Facts

| Engine | Licence | Languages | Entities | Cost on CPU | Memory | Source |
|---|---|---|---|---|---|---|
| Presidio patterns only (`-pattern` image) | MIT | n/a | cards, IBAN, email, phone, the five Italian identifiers | 0.1–0.2 ms/token (Presidio's recognisers dominate; spike §3 note) | ~150 MB | `docs/redaction.md:99-133` |
| spaCy `en_core_web_md/lg` | MIT | en | PERSON, LOCATION, ORG, DATE_TIME, NRP | 0.185 ms/token (1 core) | 0.7–1.3 GB | spike §3; ADR 0026 |
| spaCy `it_core_news_*` | **CC BY-NC-SA 3.0** | it | same | same | same | ADR 0026; recall 0.49 on the medical set (spike §4) |
| GLiNER `urchade/gliner_multi_pii-v1`, `E3-JSI/gliner-multi-pii-domains-v1` | Apache-2.0 (encoder MIT) | en, fr, de, es, pt, it (+ sl, el, nl) | free labels; adds MEDICAL_CONDITION, MEDICATION, HEALTH_INSURANCE_ID | 4 ms/token (4 cores here); est. 10–20 ms/token on the N5105; int8 does not work | 2.4 GB steady, 4.2 GB load peak | spike §1–3 |
| OpenAI Privacy Filter `openai/privacy-filter` | Apache-2.0 | "primarily English; selected multilingual robustness evaluation reported"; Italian not named | 8: `account_number`, `private_address`, `private_email`, `private_person`, `private_phone`, `private_url`, `private_date`, `secret`; **no medical** | unmeasured; 1.5B total / 50M active (MoE, 128 experts top-4, 8 layers, d=640, banded attention window 257), so linear in length; CPU via `--device cpu`; ONNX and Transformers.js variants exist (q4 shown with WebGPU) | weights ~3 GB in bf16, ~1.5 GB at q8 (arithmetic from 1.5B, not measured) | model card and docs: https://huggingface.co/openai/privacy-filter, https://huggingface.co/docs/transformers/main/model_doc/openai_privacy_filter, repo https://github.com/openai/privacy-filter (OUTPUT_SCHEMAS.md: spans with `start`/`end` character offsets and `label`, a `placeholder`, no confidence score; released 2026-04-22 per https://www.helpnetsecurity.com/2026/04/23/openai-privacy-filter-personally-identifiable-information/; 97.43% F1 on a corrected PII-Masking-300k per the same article) |

Typosquat: `Open-OSS/privacy-filter` trended in May 2026 with a malicious loader (reported in the search results above). Pin `openai/privacy-filter` by revision at image build, as the spike does for GLiNER.

### Assessment of the Privacy Filter for this project

Strengths: Apache-2.0, strong English PII recall, a `secret` class (API keys, which today need a custom pattern), a `private_*` distinction that avoids redacting public figures and well-known URLs (the "ilpost.it" failure of ADR 0037), character offsets in its output (fits the spans-only contract), long context so no chunking, and fine-tuning tooling in the repo.

Weaknesses for the owner's main case: Italian is not a stated language; there is **no medical, organisation or location-as-institution category**, so "ASL Roma 1", "Diabetologia" and "metformina" are out of scope by design; the label set is static ("changing it requires fine-tuning"); the JSON has no score, so Pystino's per-type thresholds cannot apply (the repo mentions preset operating points instead); CPU latency is not published, and MoE expert gathering on CPU is not free despite the 50M active figure.

Verdict: **candidate engine for English team deployments, and a possible second opinion for `secret`**, pending a one-day spike that measures ms/token on CPU (fp32 and q8), memory, and recall on the spike's Italian set. Do not plan the Italian medical path around it.

### Which engine for which target

| Target | Floor | Add | Not |
|---|---|---|---|
| (a) This 5-core server (dev, demos) | patterns | spaCy en for demos; GLiNER for testing the medical path; Privacy Filter spike | nothing permanent |
| (b) N5105, 8–12 GB, 1–2 users, Italian medical PDFs | patterns (the five Italian identifiers are pattern-based, ADR 0026) | **GLiNER, only through a routing rule on documents at ingest** (10–12 GB VM; not on 8 GB: load peak 4.2 GB); language detection; RapidOCR for scans (§5). Italian spaCy only as a personal-use local build | Privacy Filter (English, no medical); Docling (torch, weights licence) |
| (c) Team deployments | patterns + spaCy en (MIT) in the kit | Privacy Filter if the spike is good, as a profile; GLiNER for teams with Italian or medical content and the memory for it; a Docling service behind `/v1/ocr` where layout matters | Italian spaCy in a shipped image |

### Running a slow engine only where a rule says so

The sidecar should host **profiles**, not one engine: a profile is a name, an engine, its labels, its threshold and its chunking, declared in the sidecar's configuration and advertised in `/healthz` (`capabilities` already reports models, languages and entities per deployment; extend it with `profiles[]`). `DetectionRequest` gains an optional `profile` field; absent means the deployment default, as today. The gateway's detection cache key already includes everything the detector was asked (`redaction/http.py:106`); add the profile to it. The spike's hybrid mode shows two engines in one process is feasible; on the N5105 run **one** GLiNER instance and keep the pattern recognisers in the same process.

Fallbacks: an engine not running is, by default, a 502 and a refused request, as today (`fail_open=false`). A rule may name a weaker fallback profile, and saving that is recorded as a weakening with a visible warning, so an administrator who accepts "patterns only when GLiNER is down" has said so on the record. Never fall back silently.

### Licences for the kit

Shippable in published images: Presidio (MIT), spaCy and `en_core_web_*` (MIT), GLiNER package and the two PII checkpoints (Apache-2.0), mdeberta (MIT), Privacy Filter (Apache-2.0), RapidOCR and its models (Apache-2.0, per https://github.com/RapidAI/RapidOCR; per-model attribution in its MODEL_LICENSES.md, not opened), Tesseract and tessdata (Apache-2.0, from memory). Not shippable, local build only: `it_core_news_*` (CC BY-NC-SA 3.0), `urchade/gliner_multi` v1 and `gliner_base/small-v1` (CC BY-NC 4.0), `nvidia/gliner-PII` (NVIDIA licence). Uncertain: `docling-models` (Hub tags `cdla-permissive-2.0` and `apache-2.0`, https://huggingface.co/docling-project/docling-models; CDLA-Permissive-2.0 is a data licence not on the OSI list, so under AGENTS.md rule 2 it needs the owner's call), `onnx-community/gliner_multi_pii-v1` (no licence field; export your own, spike §1).

## 5. Extraction

### Is the current extractor adequate?

For born-digital documents, yes, and its design decisions are right for a PII service: an allowlist of types, bytes-over-declared-type, zip-bomb guards, no plugins, no ML sniffing, `antiword` out of process for `.doc`, and the honest `ExtractionKind` (`services/redaction/src/llmp_redaction/documents.py:1-70`, `505-617`). Three gaps:

1. **Scans.** A scanned PDF is `no_text_layer`, and the only answer today is "choose an upstream OCR model" (`docs/knowledge.md:27`), which for a medical PDF is exactly the egress the owner wants to avoid. Page images can be rendered (pypdfium2) and handed to a vision model, which is the same egress.
2. **Tables and layout in PDFs.** markitdown reads PDFs through pdfminer (MIT; from memory): text order is often fine, tables become lines. For lab reports (tables of analyte, value, range) that costs the model accuracy, though not privacy.
3. **No page boundaries** from markitdown for PDFs (`gateway/extraction.py:10-15`), so `pages[]` is one page; a per-page path would help both billing fidelity and the redaction of long documents in chunks. pypdfium2 can give per-page text (`page.get_textpage()`), which may be a cheap improvement without a new dependency; untested here.

### Candidates that run on an N5105 (no AVX2, 4 cores)

| Option | Licence | Fit | Notes |
|---|---|---|---|
| **RapidOCR** (`rapidocr` + `onnxruntime`) | Apache-2.0 code and models | **Good.** ONNX Runtime CPU, mobile detection and recognition models; PP-OCRv6 `small`/`medium` multilingual recognition lists Italian (https://rapidai.github.io/RapidOCRDocs/main/model_list/) | Trigger only on `no_text_layer` pages rendered by pypdfium2 at ~1,500 px long side. Expect seconds per page on the N5105 (not measured). Keep in the extractor service, optional extra, behind a build arg like the spaCy models. Note the typo-risk of `onnxruntime` ignoring `taskset` (spike §3): set its thread count explicitly. |
| **Tesseract** (`tesseract-ocr` + `ita` traineddata) | Apache-2.0 (from memory) | Acceptable; slower and less accurate than PP-OCR mobile on CPU in most reports (from memory); mature, packaged by Debian, a subprocess like `antiword` | A fine second option if RapidOCR's ONNX models are unwanted; the `pytesseract`/`tesserocr` bindings are Apache-2.0 / MIT. |
| **Docling** (`docling`, `docling-serve`) | MIT code; weights tagged CDLA-Permissive-2.0 and Apache-2.0 | **Team deployments only.** Torch, RT-DETR layout, TableFormer; "extensive OCR support" via EasyOCR, RapidOCR, Tesseract, OcrMac, OnnxTR (https://docling-project.github.io/docling/getting_started/installation/); the base package always includes RapidOCR | Too heavy for the N5105 and it duplicates what RapidOCR gives for scans. ADR 0055 already left the seam: a `/v1/ocr` provider plugin for `docling-serve`'s wire shape. Confirm the weights' licence first. |
| **unstructured** | Apache-2.0 code | No gain. Its PDF path is pdfminer (fast) or layout models plus Tesseract (hi_res); system deps poppler and tesseract (https://github.com/Unstructured-IO/unstructured) | More dependencies than markitdown for the same born-digital result; the hi_res models (detectron2/yolox lineage) are heavy and their licences need checking. |
| PyMuPDF, marker, surya, MinerU | AGPL-3.0 / GPL-3.0 (marker and surya have a commercial exception) | **Excluded** from shipped images; personal-use local build only | Already recorded in `services/redaction/pyproject.toml` for PyMuPDF (ADR 0001). |
| OCRmyPDF | MPL-2.0 | Flag | Depends on Ghostscript (AGPL) at runtime; from memory. Not worth it when RapidOCR on page images does the job. |

### Should extraction choice be in the same rule pipeline?

**Routing, yes; internals, no.** The rule actions in §2 cover "read this locally", which is the policy-relevant decision. Which library reads a `.docx`, and whether OCR runs on a page without text, are extractor configuration (build args and one or two environment variables), the same way `REDACTION_NLP_ENGINE` is a deploy-time choice (`docs/redaction.md:119-124`). One exception worth a rule condition: "scanned" (the extractor's `no_text_layer` outcome) is a useful classifier verdict, because a scan that is sent to a vision model is egress of the page image; a rule "scanned medical documents: refuse unless local OCR is available" is a real need on the N5105.

## 6. Admin UX

- **Rules as forms, read back as sentences.** Each routing rule is a card: WHEN (chips for surface, purpose, source, group, model, a file-name glob field, a MIME picker, a classifier label picker populated from `/healthz`), THEN (three selects: extraction, egress, detector profile; and a policy picker listing existing `redaction_rules` by name). The console renders the sentence shown in §2 and a "weakens" warning where the fallback or profile is weaker than the default.
- **Ordering** by drag, with the list capped and the cap explained ("more than 20 routing rules is a sign that conditions should be merged").
- **Test box, extended.** The admin test box takes either a text or a file, plus a user, a group, a model and a purpose, and runs the real path with no side effects: it answers "routing rule X fired because file name matched `*referto*`; detector profile `gliner-medical` (available); 7 spans: 2 PERSON (anonymise_restore, rule 'Medical'), ..." with offsets only, as `POST /api/me/redaction/test` already does (`docs/redaction.md:436-440`). Rate-limited the same way, because it runs the slow engine. A run of the test box against a document should also show the estimated time ("about 40 s on this machine for 4,500 tokens"), computed from a per-profile ms/token the sidecar reports after warm-up.
- **Observe only** per rule: the rule evaluates and logs `would_fire` in `redaction_detail` without acting. This is how an administrator tries "all PDFs from group Clinic are medical" for a week before enforcing it.
- **Attribution everywhere the log already is.** `redaction_detail` and the per-response summary gain `routing_rule {id, name}` and `engine {profile, name, version}`; the Redactions page shows them per request; Cerea's info dot overlay (C95) shows "Read locally; detected with GLiNER (medical); rule: Medical PDFs" and, when a request was slow because of a rule, says so. A refused request's 403 names the routing rule as a blocked entity names its rule today.
- **Health in one place.** The planned Services panel in Cerea (C94) should list each detector profile with green/red and the fallback that would apply, so "GLiNER is down, medical documents are refused" is visible before someone uploads one.

## 7. Migration

Nothing in today's tables changes meaning. `redaction_rules` and `user_redaction_rules` stay as they are; `redaction_config` keeps the default engine. The additions are one table (`redaction_routes`), one hash-cache store, two fields in the log, one optional field in `DetectionRequest`, and headers Cerea sends. A deployment that writes no routing rules behaves exactly as today, which is the migration: there is none.

### Phases, ranked by value over risk

| Phase | What | Value | Risk | Effort (owner's Sonnet workers, rough) |
|---|---|---|---|---|
| **0. Annotations and attribution** | Cerea sends `x-pystino-purpose`, `-source`, `-filename`, `-mime`, `-document`; Pystino records `source` from them (`document` and `retrieved` on chat turns), and `engine` in `redaction_detail` and the summary; Cerea's overlay shows them; document that example 2 already works via `block` patterns | Immediate visibility; prerequisite for everything | Nil (additive, ignored when absent) | 2–3 days across both repos, one contract bump |
| **1. Routing rules for `/v1/ocr` and detector profiles** | `redaction_routes` with conditions on metadata and actions `extract_locally`, `egress refuse`, `detector_profile`, `policy`; sidecar profiles in `/healthz`; `DetectionRequest.profile`; console form, sentence, test box, observe-only | The owner's examples 1 and 3; "medical PDFs never leave" on the N5105 | Medium: a new table and console page; the save-time "weakens" check must be right | 1.5–2 weeks |
| **2. Ingest-time classification and GLiNER productised** | Tier-C classifiers in the sidecar (language, GLiNER-as-classifier); hash cache with verdicts; `x-pystino-document` lookup; GLiNER engine from the spike branch with the productising list in spike §7 (label validation, `date` label, request guard, image diet, kit build arg, memory limit) | The slow engine runs once per document; Italian recall from 0.49 to 0.90 on documents | Medium-high: memory on 8 GB hosts, image size (4.8 GB), CPU starvation during ingest on the N5105; mitigate with a concurrency of one for the slow profile and a per-request character guard | 2 weeks |
| **3. Scans and the Privacy Filter spike** | RapidOCR optional step in the extractor for `no_text_layer` pages (build arg, Italian recognition model); a one-day Privacy Filter spike (CPU ms/token, memory, Italian recall on the spike set); add it as a profile if English teams want it | Scanned referti readable without egress; a cheap English engine for teams | Low-medium: OCR CPU time on the N5105; the Privacy Filter may simply not fit the Italian case, in which case the spike is the deliverable | 1 week + 1 day |
| **4. Reroute and user-level locality** | `egress reroute: <local alias>` using the existing alias and routing machinery (`routing.py`, `serve_with_failover`); a user rule "refuse egress of my documents" (tighten-only, ADR 0112 style); Services panel health for profiles | Lets a deployment keep medical conversations on a local model without refusing them | Medium: reroute interacts with quotas, aliases and session stickiness; needs the live checks | 1–1.5 weeks |

Do Phase 0 and the Phase 3 spike first if a worker is free: both are cheap and both change what Phases 1–2 should look like (Phase 0 reveals how often documents are quoted in chat turns; the spike decides whether English teams get a cheap engine).

## Risks

- **Policy becomes hard to reason about.** The whole value of ADR 0038 is that a wrong rule is inert. Routing rules re-introduce order and choice. Mitigations: monotone actions where possible, a save-time "weakens" check, observe-only, a short list, the sentence rendering and the test box. Do not add conditions beyond the list in §2 without a case.
- **Caller-supplied metadata.** Headers from Cerea can be wrong or forged by any `/v1` client. Mitigation: annotations only select stricter actions; verdicts are Pystino's own; unknown hashes are "no verdict".
- **CPU starvation on the N5105.** One 6,000-token document at 10–20 ms/token is 1–2 minutes of all four cores (spike §3). Mitigation: ingest-only, one slow job at a time in the sidecar, a character guard per request, honest time estimates in the UI, and no slow engine on chat turns.
- **Memory on 8 GB hosts.** GLiNER does not fit safely (spike §5). The kit should refuse the profile below a memory threshold or print a loud warning.
- **Fail-closed availability.** With fail-closed semantics, a crashed sidecar makes medical uploads fail. That is the right default; the Services panel and a 503 that says "GLiNER profile unavailable; rule 'Medical PDFs' refuses egress" make it a visible outage instead of a silent leak.
- **Licences.** `docling-models` CDLA-Permissive-2.0 is not OSI-approved; Italian spaCy and the v1 GLiNER checkpoints are non-commercial; a derivative ONNX export with no licence field must not be shipped. All already handled by the "build arg, never published" pattern of ADR 0026.
- **Over-redaction by GLiNER** ("paziente", "Gentile collega" as PERSON, spike §4). Mitigation: the per-type thresholds, the allow-list, and the policy picked by the routing rule (a document policy can use `anonymise_restore` so the user still reads the real text).
- **The Privacy Filter does not fit the main case.** It is English-first with no medical category. The risk is spending effort on it because it is new; the spike is bounded to one day for that reason.
- **Two repositories, one contract.** Headers, the summary fields and `/healthz` profiles are contract changes; Cerea's `pystino-contract.env` and the kit pin must move together (AGENTS.md, "How Pystino and Cerea relate").

## Draft ADR outline: ADR 0113, privacy pipeline

**Title.** Privacy pipeline: routing rules in front of the redaction fold, request annotations from the chat, detector profiles, and ingest-time classification.

**Status.** Proposed. Builds on 0012 (spans only), 0026 (detection is a plugin; licences are build flags), 0033 (engine is an admin decision), 0038 (the fold tightens only), 0039 (rules, no deployment policy), 0055 and 0083 (`/v1/ocr`, one shape), 0112 (user rules, the log, the summary).

**Context.** One engine per deployment; nothing chooses an extractor, an engine or an egress decision per request; the chat knows what a text is (a document, a passage, a tool result) and the gateway does not; GLiNER is 50 times slower than spaCy and must be scoped to earn its recall; the Italian models are not shippable; scanned documents are unreadable without egress.

**Decision.**
1. The chat annotates requests with purpose, source, file name, MIME and document hash, as `x-pystino-*` headers. Annotations can only select stricter handling. The gateway never takes a verdict from a client.
2. A short ordered list of administrator routing rules, first match wins, evaluated before the fold. Conditions: surface, purpose, source, file-name glob, MIME, group, user, key, model, provider, classifier label, language. Actions: extract locally; egress allow, refuse or reroute to a local alias; detector profile with an optional fallback; add a named policy to the fold. Observe-only flag. Actions weaker than the default are accepted and flagged as weakening.
3. The fold is unchanged and remains the only place modes are decided; user rules remain last and tighten-only. A later user-level routing rule is limited to "refuse egress of my documents".
4. The detection sidecar hosts named profiles (engine, labels, threshold, chunking) advertised in `/healthz`; `DetectionRequest.profile` selects one; the detection cache key includes it.
5. Classification runs once per document at `/v1/ocr`; verdicts (labels and scores, never text) are cached by content hash; later requests reference the hash. Unavailable classifiers fail closed for protective actions.
6. Attribution: `redaction_detail` and the per-response summary carry the routing rule and the engine profile; the 403 for a refused egress names the rule and never the content.
7. Extraction: markitdown and pypdfium2 remain the default; RapidOCR is an optional, build-time OCR step for pages with no text layer; Docling is a `/v1/ocr` provider option for team deployments pending a licence check on its weights; AGPL and GPL extractors are never shipped.
8. Engines by target: pattern-only as the floor; spaCy English for teams; GLiNER as the opt-in profile for documents on 10–12 GB hosts; OpenAI Privacy Filter as a candidate profile for English deployments after a spike; Italian spaCy remains a local build.

**Consequences.** One new table and one hash store; two log fields; one optional field in the detection contract; new headers in the Cerea contract and a contract-pin bump; a console page with a form, a sentence rendering, ordering, observe-only and an extended test box; kit build args and memory guidance for GLiNER and RapidOCR; the Services panel lists profiles. A deployment with no routing rules behaves exactly as before.

**Alternatives rejected.** A general rule language (loses the monotone fold and admin readability); redaction settings inside Cerea workflows (second home for policy, written by non-administrators); per-request engine choice by header (clients choosing protection); running GLiNER on chat turns (unaffordable on the target hardware); embedding detection in the gateway (ADR 0012 and `docs/redaction.md:32-52` still hold).

**Open questions for the owner.** Whether CDLA-Permissive-2.0 weights are acceptable under rule 2; whether `reroute` should exist before a local chat model is part of the kit; the cap on routing rules; whether `x-pystino-document` hashes should be verified against inlined text in Phase 2 or trusted as tighten-only hints.

## Files relied on

Pystino: `docs/redaction.md`, `docs/performance.md`, `AGENTS.md`, `apps/gateway/src/gateway/routers/_metered.py` (`redaction_policy`), `apps/gateway/src/gateway/routers/ocr.py`, `apps/gateway/src/gateway/extraction.py`, `apps/gateway/src/gateway/redaction/{resolver,http,report,base,user_rules}.py`, `apps/gateway/src/gateway/config.py` (`RedactionPolicy`, `EntityPolicy`, `CustomPattern`, `EffectivePolicy`, `Contributor`, `fail_open`, `language`), `packages/shared-py/src/llmp_shared/{redaction,documents}.py`, `services/redaction/src/llmp_redaction/{app,documents,detector}.py`, `services/redaction/pyproject.toml`.

Cerea: `src/lib/server/files/extractDocument.ts`, `src/lib/server/knowledge/{extractorResolution,service,embed}.ts`, `src/lib/server/endpoints/preprocessMessages.ts`, `src/lib/server/textGeneration/untrusted.ts`, `src/lib/server/gatewayServer.ts`, `docs/chat.md`, `docs/knowledge.md`, `kit/compose.yaml` (redaction and extractor services).

ai-stack: `docs/adr/0012, 0026, 0033, 0037, 0038, 0039, 0055, 0083, 0103, 0112`, `reports/2026-11-08-gliner-spike.md`, `reports/backlog.md` (C83, C94, C95, P19).

External: the URLs cited inline in §4 and §5.
