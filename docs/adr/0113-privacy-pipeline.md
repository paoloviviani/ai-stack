# ADR 0113: Privacy routing in Pystino (per-request rules by kind, detector profiles, no state between requests)

- Status: accepted, revised 2026-11-08 (section 0: policies plus scoped pipelines); phases 0–1 built on Pystino #52 (owner direction applied 2026-11-08: Pystino-only, stateless; see "Decided")
- Builds on: Pystino ADR 0012 (spans only), 0026 (detection is a plugin; licences are build flags), 0033 (the engine is an
  admin decision), 0038 (the fold tightens only), 0039 (rules, no deployment policy), 0055 and 0083 (`/v1/ocr`, one
  shape), 0112 (user rules, the log without values, the per-response summary). Background: `ai-stack/reports/2026-11-08-privacy-pipeline-advisory.md`
  (its ingest-time classification carried by `x-pystino-document` is superseded here).
  UX: `ai-stack/reports/2026-11-08-privacy-pipeline-prototype/` (prototype `index-v4.html` and design note).

## Context

One detector per deployment; nothing chooses a reader, a detector or an egress decision per request. GLiNER is about 50
times slower than spaCy and only earns its recall where it is needed. The Italian spaCy models are not shippable, and a
scanned PDF is unreadable without sending its pages to a provider. Administrators want to say, in plain terms, "these
files are read here, that text is checked with this detector, this never leaves", and users want to see what happened.

Redaction and routing belong to Pystino and must work for **any generic OpenAI-compatible client, without Cerea**.
Reading a file, embedding and chat are separate requests that can happen at different times from different clients. There
is no multi-step workflow for the gateway to follow.

## Decision

**Each request is judged on its own, by kind, from what Pystino itself can observe in it. No state is carried between
requests.** An ordered list of administrator routing rules sits in front of the unchanged tighten-only fold. Cerea may
add optional descriptions later; they only ever tighten or speed up (section 5).

### 0. Revision (owner, 2026-11-08, later the same day): policies plus scoped pipelines

This section supersedes the parts of sections 2, 3 and 9 that contradict it. Where they disagree, this section holds.

**Two objects, one job each.**

- **A policy is what to hide, and nothing else.** It is a named set of detections and modes:
  - patterns, built in and custom;
  - entity types, and the detector profile that finds them;
  - a mode for each: anonymise and restore, anonymise, redact, block.

  A policy has no scope: no user, group, provider or model. Today's redaction rules lose their scopes and become policies.
- **A pipeline is when and how.** It has:
  - a kind: read, embed (including `/v1/rerank`) or chat;
  - a scope:
    - who: all, users, groups or keys;
    - target: all, providers or models (read targets the OCR model or provider);
  - an ordered list of rules (conditions → action), where **the first match wins** within the pipeline;
  - a last "everything else" rule, which cannot be deleted.

  A pipeline runs only on requests inside its scope. For example, a facility vLLM or an own TEI is left out of the scope
  of the pipelines that guard remote providers. **Pystino has no notion of a "local" model.** A provider is just a
  provider, and scope is how an administrator treats one differently.

**Actions per kind (replaces section 3).**

| Kind | Where it is handled (the ladder) | What is hidden |
|---|---|---|
| Read | default reader (the model the caller named) < **read with** a chosen reader (any `/v1/ocr` model: the built-in extractor, or a reader deployed elsewhere and configured as a provider; overrides the named model; fails closed if not possible) < refuse | apply a policy to the returned text |
| Embed | pass < refuse | apply a policy to the input |
| Chat | pass < refuse | apply a policy to messages and tool results |

**Other action rules:**
- A read rule that chooses the built-in reader may also name the engine (markitdown, OCR, Docling). The engine is quality,
  not privacy, so it is **not on the ladder**.
- Observe-only stays as it was: the rule is logged and the search continues.
- "Built-in" means only what ships with the stack: the extractor and the redaction detectors.
- **Read is scoped by provider like the other kinds.** A reader deployed elsewhere in the facility is just a provider:
  leave it out of the scope of the pipelines that guard remote readers.
- **Choosing the reader.** The administrator's choice holds; a user's choice applies only if no administrator pipeline
  chose one. A user may only choose readers they are granted. After a reroute, the pipelines whose scope covers the new
  reader also run, so a reroute can never escape a pipeline that guards that reader.
- **There is no reroute between models for embed or chat.** An embedding rerouted to another model breaks the vector
  space, and choosing the provider is the caller's job. This removes the provider `is_local` flag and its checks, the
  embed "local" action, and phase 4.

**Combination: all in-scope pipelines run, and their results combine.**
- **Where it is handled:** the highest level on the ladder wins, across all pipelines.
- **What is hidden:** the policies chosen by each pipeline add up, and for each entity type the strictest mode wins (the
  tighten-only fold of 0038, unchanged).
- **Engine:** an administrator pipeline's choice holds. A user pipeline's choice applies only if no administrator
  pipeline chose one. Otherwise the deployment default applies.
- **Failure:** if the built-in reader wins but cannot read this request (a link, or no reader available), the request is
  refused. Refuse is also the top of the ladder.
- **Attribution and the 403** name the rule that set the winning level. On a tie, the administrator's rule is named.
  The trace lists every pipeline that was in scope and the rule that fired in each.

**User pipelines (replaces the 0112 user rules).**
- A user may create pipelines whose who-scope is fixed to themselves. Target and kind are free.
- Their actions only tighten: built-in reader, refuse, apply a policy, choose an engine. There is no "default reader" or
  "pass" action for them, because those are what happens anyway.
- They may apply shared policies or their own. An own policy uses custom patterns and the entity types and profiles the
  administrator makes available to users.
- Because the combination is monotone, a user pipeline can never loosen anything. A value an administrator policy hides
  stays hidden whatever the user's policies say.
- Example: Mistral OCR is the default reader. A user adds the read rule "file name `*referto*` → built-in reader", and
  their reports are read by the extractor instead. The file-name warning still applies.

**Choosing the embedder up front (clients).** The embedder is chosen per knowledge base by its owner; the
administrator only sets the default. To make that choice informed, Pystino exposes, for the calling user, a short
read-only summary per embedding model of the pipelines in scope (for example "refuses health data"). A client such as
Cerea shows it beside each option when a knowledge base is created or edited. There is no after-the-fact "switch and
reindex" prompt.

**Migration.**
- Every existing redaction rule becomes one policy (its families and modes) plus one administrator pipeline per kind it
  applied to, with the old scope and an "everything else → apply that policy" rule.
- A deployment-wide rule becomes the pipelines scoped to all.
- 0112 user rules become user pipelines in the same way.
- Requests are handled exactly as before; a contract test proves it.

### 0b. Revision (owner, 2026-11-09): conditions are request facts or detector verdicts

This section supersedes the content conditions of section 2 (health data, IDs, language, quick check) and the
hard-coded health word list. Where they disagree, this section holds.

**Policies and conditions do different jobs.** A redaction policy finds items in the text and hides them, and its
`block` mode refuses a request in which an item is found. A condition decides about the whole request: pass, refuse,
read elsewhere, or redact with a stricter policy. A condition that only repeats "this entity is present → block"
adds nothing; conditions exist for request facts, and for verdicts that drive an action other than hiding.

**Two kinds of condition.**

1. **Request facts** (no content). For reading: file type, file name glob, "is a scan". Who and target are the
   pipeline's scope, not conditions.
2. **"Classified as <detector>"**, with "is" and "is not". It is the only content condition, and it is topic-agnostic:
   nothing in Pystino is specific to health or any other subject. A *detector* is a named, visible object that an
   administrator defines. Detectors are split by method, and a detector never mixes methods; a rule can combine
   detectors of different kinds with AND (several conditions):
   - **Patterns** (fast, deterministic; works on any box). Words and phrases (exact, whole words, case- and
     accent-insensitive), regular expressions, and built-in formats validated by checksum where one exists (fiscal
     code, IBAN, card, VAT, health insurance number, email, phone). Classified when at least N distinct items match.
     It always answers, so it has no failure mode.
   - **Entities (NER)** (slower, probabilistic). Entity types recognised by the deployment's NER engine (person,
     location, organisation; more with an extended profile later), with a confidence threshold and "at least N
     found". If the NER service is unavailable, the condition follows the fail-closed rule.
   - **Decision model** (large deployments). A configured provider and model, plus a topic described in plain words.
     It decides on meaning, not on words, reading the whole text in chunks; any chunk positive makes the text
     positive. Classifying sends the text to that provider: the console says so when the provider is chosen.
     Shipped as scaffolding: configuration, call path, fail-closed handling and tests against a fake upstream. No
     model is bundled.
- **Policies and detectors stay separate objects.** A policy hides what it finds; a detector decides about the whole
  request. The editors say so in one line each.
- **Where it runs:** for reading, on the text after a local read (the scan-probe flow); for embedding, on each input
  in full; for chat, on the messages.
- **Fail closed.** If the detector is unavailable or did not finish, the condition matches only on a protective rule
  that is not negated; otherwise the request is refused with a 503 naming the rule (as in section 0).
- **Caching** by `sha256(text)` and detector version, for performance only.
- **Visible.** Each condition row states in one line what it checks, with a link to the detector. The Test tab names
  the words or entity types that triggered it. A user pipeline may use the detectors the administrator shares.
- **Removed:** the "contains health data", "contains IDs" and "language" conditions, the hidden quick check, and
  detector profiles on conditions. Detector profiles stay a policy matter (which NER engine finds entities).

### 0c. Revision (owner, 2026-11-09, later): one detection vocabulary for policies and conditions

Supersedes the separate "detectors" of section 0b, except the decision model. Where they disagree, this holds.

- **One object finds things: the redaction policy.** Its items are, in two groups that are never mixed:
  - **Patterns** (fast, deterministic, evaluated in the gateway or by the service's pattern recognisers): built-in
    formats (checksummed where possible), custom regular expressions, and **keyword lists** (comma-separated words
    and phrases, whole words, with a case-sensitive checkbox).
  - **Entities** (NER, probabilistic): the entity types the selected NER engine exposes, each with a confidence
    threshold. The list comes from the redaction service's capabilities for that engine. An engine that accepts
    labels at inference (GLiNER) lets the administrator add custom entity types (a label plus a short description).
- **Engine selection per policy:** spaCy or GLiNER, among the engines installed in the redaction service (the
  service advertises them). Patterns always run.
- **Modes per item** gain `detect only`: the item is found and counted, nothing is hidden.
- **Conditions use policies:** "**<policy> finds at least N items**" (is / is not). The same editor defines what is
  looked for in both uses; a policy used only for decisions sets its items to `detect only`. The Test trace lists
  each item found with its group, and the score for entities. If the NER part cannot run, the fail-closed rule of
  section 0 applies.
- **Decision model** stays a separate object (a classifier: provider, model, topic in plain words), scaffolding
  only, used by "classified as <classifier>".
- Request-fact conditions (file type, name, scan) are unchanged, and **they are the only conditions for reading a file** (owner, 2026-11-09): reading rules decide from the file, not its content. Content is checked when the text is embedded or sent to chat, where "finds" and "classified as" apply.

### 1. Kind of request

The kind comes from the endpoint and is the first, required part of every rule. A request only meets rules of its kind;
first match wins within a kind.

| Kind | Endpoint | Pystino observes |
|---|---|---|
| Reading a file | `/v1/ocr` | file name, MIME/type, "is a scan" (found while reading), principal |
| Embedding | `/v1/embeddings` | principal, target embedding model/provider, content verdicts |
| Chat | `/v1/chat/completions` and the other chat surfaces | principal, target model/provider, content verdicts |

### 2. Conditions available per kind

All must hold (AND); each is optional; several values in one condition are OR; "is not" is allowed except where noted.
No expression language. A rule with no conditions matches every request of its kind.

| Condition | Reading | Embedding | Chat | Source |
|---|---|---|---|---|
| File name (glob) | yes | | | request |
| File type (from MIME), "a scan" | yes | | | request, found while reading |
| User, group | yes | yes | yes | sign-in |
| Target model or provider (alias; local or cloud from the provider config) | | yes | yes | request, config |
| Contains health data, contains IDs | | yes | yes | Pystino classifier on this request's text |
| Language | | yes | yes | Pystino classifier on this request's text |
| Client says: user message, retrieved passage, tool result, connector (optional, section 5) | | | yes (no "is not") | client |

**How to decide (per condition).** For content conditions (health data, IDs, language) the administrator chooses, per
rule and per condition, how the verdict is reached: a *quick check* (patterns and word lists: instant, can miss plain
wording) or a *model* (a detector profile such as GLiNER Medical: slow, accurate). The editor shows a cost hint next to
each choice (for example "~15 ms/word here"). If the chosen model is unavailable (not installed or down), the condition
follows that profile's fallback setting: *refuse* fails closed (the rule takes its protective action: the request is
refused); *fall back* uses the fallback profile's method and records it. This applies to every kind that offers
verdicts, embedding included. The default is the quick check.

Verdicts are never the client's. A classifier runs only if some enabled rule of that kind uses its verdict. There is no
folder or connector condition, and no "purpose" condition (the kind replaces it).

### 3. Actions per kind

| Kind | Actions |
|---|---|
| Reading | choose the reader: `server` (markitdown), `server_ocr` (markitdown plus RapidOCR for pages without text), `docling`; or refuse. Overrides the `model` the caller named; the response reports the reader that ran. |
| Embedding | use a local embedding model (a configured local provider); or refuse |
| Chat | detector profile (section 7); add one named `redaction_rules` policy; or refuse. Later (phase 4): reroute to a local model. |

- **One policy per rule.** A policy is added to the fold, never a replacement.
- **No action means default handling;** there is no "let it go as usual".
- **Local is unavailable until a local model exists.** The console shows it as unavailable; a rule that needs it fails
  closed (the request is refused with a 403 naming the rule, never the content).
- **Observe only.** The rule is evaluated and logged as `would_fire`, takes no action, and evaluation continues.
- **Fall-through.** "Everything else" is last for each kind, cannot be deleted, and means today's behaviour.
- **Save-time checks, in plain words.** Errors block saving: no kind, no actions, an empty glob. Warnings do not: *never
  fires* (an earlier enabled rule of the same kind matches everything this one does; a hint, not a proof), *weakens* (a
  profile that finds fewer entity types than the default, or a fallback), *unavailable now* (profile, extractor or local
  model missing), *clients that say nothing* (a protective rule whose only protection is a client-says condition), and
  *soft cap of 20 rules* (a warning, not a limit).
- **File name is convenience, not protection.** A refusing reading rule that depends only on file name or type shows:
  "A renamed file won't be caught. To protect content wherever it comes from, add rules for embedding and chat that use
  'contains health data'." Protection rests on content verdicts, which judge the text itself.
- Routing rules never change a mode. Modes come from the fold, which stays monotone; user rules stay last in it.

### 4. Statelessness guarantees

- No session, document or workflow memory is required for correctness. Every outcome is a function of the request, the
  rules and the configuration.
- Extraction, embedding and chat are not linked. A file read at one time does not affect a chat request at another; a
  chat request containing text from a document is classified by its own text.
- An optional verdict cache keyed by `sha256(text)` is allowed **only as a performance optimisation**, so identical text
  is not classified twice. A miss recomputes the same answer. It stores labels and scores, never text, and never changes
  the outcome. Pystino keeps nothing else between requests.
- **Failure.** A classifier a rule depends on is unavailable: fail closed for that rule (take its protective action; if
  even that is unavailable, refuse with a 503 naming the rule). A classifier no rule uses is never called.
- Costs: patterns microseconds; a language detector milliseconds; GLiNER with 3 or 4 labels on the first N characters
  1 to 5 s on the target box. A rule that depends on the slow classifier makes every matching request pay it; the console
  says so.

### 5. Optional enrichment by clients (Cerea, later)

A client may describe what Pystino cannot infer. These are hints with these semantics:

| Header | Meaning |
|---|---|
| `x-pystino-source` | which part of a chat request a piece of text is: `message`, `retrieved`, `tool_result`, `connector` |
| `x-pystino-document` | `sha256` of the source text; a cache key and hint |
| `x-pystino-filename` | the source document's base name (never a local path) |
| `x-pystino-connector`, `x-pystino-tool`, `x-pystino-path` | attribution only, for the log (limits and sanitising as before: at most 64/64/256 characters, no query strings, no ID or token-like segments, never an absolute local path) |

- **Tighten or speed up only.** A hint may select stricter handling (a stronger profile, refusal) or save work (a cache
  hit). It may never loosen, skip a check or lower a mode. There is no "is not" on a client-says condition, so a missing
  hint can never make a rule match.
- **Never required.** Every rule works, more coarsely, for a client that sends nothing: a rule that depends on a hint
  simply does not match, and the next rule or default handling applies. Protection must also exist without hints, which
  is why it rests on content verdicts.
- **Verdicts are never the client's.** A client may say "this is a retrieved passage"; it may not say "this is not
  medical".
- Invalid, over-long or non-ASCII values are ignored and recorded as absent; the call still succeeds.
- Attribution-only fields are never rule conditions.

### 6. Attribution

For every request Pystino records, in `redaction_detail` and in the opt-in per-response summary (`pystino_redaction`,
which any client can request): what it observed (kind, file type, scan, verdicts if computed, target) and what handled it
(reader, detector profile, routing rule or none, fallback used, timings), plus any client hints received. No values, no
offsets, as 0112. A refusal 403 names the rule. The same words appear in three places:

- **The log** (Redactions pages, admin and user; users see the administrator's rule names): one line per request, "Rule
  *Health text: medical detector* fired, Medical profile, 3 conditions, 2 names hidden", with a warning when a fallback
  ran or the request was slow because of a rule.
- **The summary**, for any client.
- **Cerea's info dot**, which only displays the fields.

### 7. Detector profiles and extraction engines

The sidecar hosts named profiles (engine, labels, threshold, chunking), advertised in `/healthz` with status, estimated ms
per token and memory. `DetectionRequest.profile` selects one; absent means the deployment default; the detection cache
key includes it. The client never picks one. Candidates: **Fast** (patterns plus spaCy), **Medical** (GLiNER with labels),
**English team** (OpenAI Privacy Filter, after the CPU spike). Pattern recognisers always run beside any profile.

- **When unavailable,** the administrator chooses per profile: **refuse** (default) or **fall back to a named weaker
  profile**. A fallback is recorded as a weakening, with a reason, in the append-only config row (the convention of 0033),
  and on every request that used it. Never silent.
- Extractors: **markitdown** (default), **markitdown plus RapidOCR** (optional build extra; OCR only for pages without a
  text layer), **Docling** (a `/v1/ocr` provider via ADR 0055's seam). AGPL and GPL extractors are never shipped.

### 8. Test box

The admin test box chooses the kind first, then takes text or a file, user and target; it runs the real path with no side
effects and returns what Pystino saw, the rule trace, reader or profile, spans (type, offsets, deciding rule; never
logged), the estimated time, and whether anything would leave. Rate limited; it can run the slow engine.

### 9. Phases

0. **Pystino observation and attribution. Pystino only; no behaviour change; no Cerea work.** For every request record
   what Pystino observed (kind, file type, scan, verdicts if computed, target) and what handled it (reader, detector
   profile, routing rule: always none for now). Expose it in the per-user redaction log and the opt-in per-response
   summary. Cerea's info dot already shows the summary and just displays the new fields. Done when a contract test covers
   each kind and the log and summary carry the fields, and a request behaves byte-for-byte as before.
1. **Rules for reading and embedding, plus detector profiles:** the rule table, kind, conditions and actions for reading
   and embedding, profile hosting with per-profile fallback, console (list, editor, test box, profiles, observe-only).
2. **Chat rules and content classifiers productised:** chat conditions and actions, verdict classifiers, the GLiNER
   profile, optional hash cache.
3. **Cerea enrichment:** the section 5 headers, client-says conditions, attribution fields. Optional; tighten/fast only.
4. **Local-model reroute:** `local` actions become available, user-level "refuse egress", profile health in Cerea's
   Services panel.

## Consequences

- One new table, two log fields, one optional detection field, one optional verdict cache. A deployment with no rules
  behaves exactly as before, and every OpenAI-compatible client gets the same protection.
- The console gains the per-kind rule lists, the sentence editor, the extended test box, the profiles page, and routing
  attribution on the Redactions page.
- Memory and CPU of the slow profiles are a deployment concern: concurrency one for them, a per-request character guard,
  a warning below the memory threshold.
- No Cerea change is needed before phase 3.

## Alternatives rejected

A pipeline carried across steps (extraction, then embedding, then chat) with per-document state (couples requests, fails
for generic clients); client-supplied verdicts (clients choosing protection); a general rule language (loses
readability and the monotone fold); policy inside Cerea workflows (a second home for policy); a client-chosen engine;
GLiNER unconditionally on chat (unaffordable); embedding detection in the gateway (0012 holds); a visual flow graph (the
list is the model).

## Decided (owner, 2026-11-08)

1. **Redaction and routing are Pystino's concern,** for any generic OpenAI-compatible client, without Cerea.
2. **Stateless:** each request is judged on its own; an optional content-hash verdict cache is a performance
   optimisation only.
3. **Conditions are only what Pystino observes** (kind, file name/type/scan, principal, target, own content verdicts);
   actions depend on the kind.
4. **Cerea enrichment is optional, later, and may only tighten or speed up;** every rule works, more coarsely, without it.
5. **Fallback per profile** (refuse by default); **users see administrator rule names;** **observe-only continues the
   search;** **one policy per rule.**
6. **A local reroute is unavailable until a local model exists, and fails closed;** no "let it go as usual."
7. **Soft cap of 20 rules;** no folder or connector conditions; file name is convenience only, with the warning.
8. **Content conditions choose how they are decided, per case:** quick check (patterns, instant) or a model profile
   (slow, accurate), with a cost hint; an unavailable model follows that profile's fallback (refuse fails closed). Applies
   to every kind, embedding included.
9. **Revision (section 0):** policies hold what to hide, with no scope. Pipelines hold scope (who, target) and rules,
   with the first match within a pipeline. All in-scope pipelines combine on the ladder (read: default < built-in <
   refuse; embed and chat: pass < refuse), and their policies add up, strictest mode wins. Users get their own
   tighten-only pipelines. "Built-in", not "local". No reroute for embed or chat; no phase 4.
10. **Conditions (section 0b, 2026-11-09):** request facts plus "classified as <detector>"; detectors are split by method: Patterns (words, regexes, checksum formats; deterministic), Entities (NER with a confidence threshold; probabilistic), or a decision model (scaffolding, large deployments). A detector never mixes methods. Topic-agnostic; no shipped topic templates. Patterns and Entities must work without a model. The hidden health list, IDs and language conditions are removed.
11. **One vocabulary (section 0c):** policies are the only item-finding object (patterns incl. keyword lists with a case checkbox; entities from the chosen engine, spaCy or GLiNER, with custom GLiNER labels); conditions say "<policy> finds at least N"; mode `detect only`; decision model stays separate.

## Open questions

1. Are CDLA-Permissive-2.0 weights (Docling) acceptable under the OSI-only licence policy?
2. Should the admin test box be open to every administrator, given it can run the slow engine (rate limit proposed)?
3. Should embedding requests also be offered content verdicts that run a model (GLiNER), or only patterns, given volume?
