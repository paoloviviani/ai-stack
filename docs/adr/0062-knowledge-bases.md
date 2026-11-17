# 0062 — Knowledge bases live in the gateway, and so does sharing

- Date: 2026-09-09
- Status: **accepted, being built.** The vector store, the schema, the sharing
  ACL, ingestion, retrieval, the admin surface and the console screen are done
  and tested; agents and the chat's own half are the follow-on work.
- Asked as a feature list, not a design question: *"projects (groups of chats
  with initial context, text only, and with rag over previous chats) /
  knowledge bases (rag over documents, attachable to projects) / custom
  models/agents (models with some tools enabled by default and possibly
  knowledge bases attached) / all of these concepts can be shared among
  users/groups by the owner"*, plus an admin panel, file upload, a configurable
  vector store with manual reindexing, configurable text extraction and
  configurable embedding — the last three admin-only.
- Implements the shape [ADR 0018](0018-vector-store.md),
  [ADR 0019](0019-document-conversion.md) and
  [ADR 0020](0020-embeddings-and-reranking.md) recorded, and **corrects a
  consequence 0020 got wrong**. Depends on
  [ADR 0057](0057-group-ownership-and-sync.md) for which groups count, and on
  [ADR 0061](0061-per-request-billing-group.md) for the door problem it shares.

## The decision that shapes everything else: where these things live

The feature list mixes two kinds of thing, and separating them is the whole
design.

**The gateway owns the infrastructure and everything shareable**: file storage,
extraction, chunking, embedding, the vector store, knowledge bases, agents, and
one generic sharing ACL. **The chat owns projects and conversations.**

Four reasons, in the order that decided it:

1. **The gateway already owns two of the three configurable stages.**
   `/v1/ocr` has the built-in extractor *and* upstream OCR models (ADR 0055);
   `/v1/embeddings` exists and meters per token. Asking for "configurable text
   extraction, default on the built-in one, selectable OCR models" is asking
   for a setting over machinery that is already here.
2. **Sharing needs users and groups, and only the gateway has them.** The chat
   has no notion of a group, a role or an ACL: its single authorisation
   primitive is `authCondition`, used in 67 places, and it means exactly "is
   this document's `userId` mine". Building sharing there means building
   groups there, in a second database, with a second answer to "who is in this
   group" — and the first answer is already load-bearing for billing.
3. **Indexing is billable and must land on the ledger.** ADR 0020's sharpest
   consequence is that a large ingestion run can cost more than the chat
   traffic it serves. Inside the gateway, extraction and embedding go through
   the same reserve → record → settle path as a chat completion. Outside it,
   they are invisible to every quota and report.
4. **An agent belongs to `/v1`, not to one client.** "A model with tools and a
   knowledge base attached" resolves to a served model. Putting it in the
   gateway means every `/v1` client gets agents; putting it in the chat means
   the chat has them and nothing else ever will.

The cost of this split, stated plainly: the chat has to make HTTP calls for
things that would otherwise be local reads, and a project's *membership* lives
in a different database from the project. That is accepted because the
alternative is two group models, and two group models is how a deployment ends
up with somebody who can read a document through one door and not the other.

### The door problem, and why the answer is OpenAI's own API

Every `/api` route is behind `get_management_user`, which reads **only** a
session cookie. A chat client authenticating with an OIDC access token cannot
present one. That is the problem ADR 0061 solved for billing groups by adding a
`/v1` endpoint, and it recurs here for everything a knowledge base needs.

The answer is better this time, because **OpenAI already specifies the surface
we would have had to invent**: `/v1/files`, `/v1/vector_stores`,
`/v1/vector_stores/{id}/files`, `/v1/vector_stores/{id}/search`. A knowledge
base *is* their vector store. Using their names and object shapes costs nothing
and means a client written against the OpenAI SDK works unchanged.

Four routes are ours, each because the OpenAI surface has no equivalent:
`POST .../text` (a passage with no file behind it — what "RAG over previous
chats" needs, since the chat has a transcript rather than an upload),
`POST .../reindex`, `.../shares`, and `GET .../status`.

**Admin-only configuration belongs to the chat's own admin console**, not the
gateway's — corrected on request, having been built the other way first. The
reasoning that put it in the gateway console was "administrators have session
cookies, and `/api` needs one", which is a fact about the *plumbing* rather
than about whose decision it is. Which embedding model a deployment uses, and
what reads its documents, is a decision about the **product**: the gateway
supplies extraction, embedding and a vector store the way it supplies models
and quotas, and choosing among them belongs to whoever runs the application
people actually use. The gateway console keeps gateway concerns — providers,
models, prices, quotas, redaction, users.

So there are **two admin consoles**, and the boundary between them is *whose
decision is this*, not *which service implements it*.

That forced the surface to move rather than merely be copied, and the reason is
the door problem again: `/api` reads a session cookie and nothing else, so a
chat authenticating its users with an OIDC access token could not call
`/api/admin/knowledge` at all. The configuration therefore lives at
`/v1/knowledge/config`, and **one new rule comes with it**: an API key is
refused there even when its owner is an administrator. `is_admin` is a property
of a user and both credentials resolve to one, so gating on the flag alone
would let any key held by an administrator repoint the extractor at a host of
the holder's choosing. A key is what a program holds, often in a config file;
an access token is evidence a person signed in minutes ago. Spending money with
a key is what keys are for; changing where documents get sent is not.

## What was measured, and what it changed

### ADR 0020 is wrong about the dimension, and the correction is the feature

0020 recorded: *"Dimension count is a schema concern for pgvector: the column is
typed with a fixed dimensionality, so switching to a model with a different
output size is a migration, not a configuration change"*, and warned that a
mismatch *"is the single most common way a RAG system starts quietly returning
garbage"*.

Measured against pgvector 0.8.6, both halves are false:

- `vector` accepts **no dimension modifier**, and rows of different lengths
  coexist in one column (`vector_dims` per row; verified with a mixed table);
- comparing two lengths raises `ERROR: different vector dimensions 4 and 3`. It
  **refuses rather than ranking wrongly** — the opposite of quiet garbage.

So the embedding model is a genuine configuration setting, and the design that
follows is: **each knowledge base pins the model it was indexed with.** Changing
the deployment default is then safe by construction. Existing bases keep
answering from their own vectors; an administrator reindexes each when they
choose. A single deployment-wide dimension would have made that setting an
outage.

`dimensions` is **learned from the length of the first embedding**, never
configured. A model's output size is not something an operator should have to
look up, and a number typed by hand is a number that can be wrong.

### The approximate index is a partial expression index, cast to halfvec

Three more measurements, none of them guessable:

| Measured | Result |
|---|---|
| HNSW on `vector` | refuses above **2000** dimensions |
| HNSW on `halfvec` | refuses above **4000** |
| Planner on a halfvec-cast `ORDER BY` against a halfvec-cast index | uses it (`Index Scan using ix_knowledge_chunks_hnsw_3072`) |

OpenAI's `text-embedding-3-large` is 3072-dimensional, so it **cannot be
indexed as `vector` at all**. The index is therefore
`((embedding::halfvec(N)) halfvec_cosine_ops) WHERE dimensions = N`, one per
common dimension (384, 512, 768, 1024, 1536, 3072), created by migration 0027
on partitions that are empty until something uses that length.

Storage stays full precision; **ranking happens in half precision**. That costs
nothing that matters for a top-k ordering and buys one query path instead of a
branch at 2000 dimensions that no test would ever exercise. A base of any other
length still works — the query is an exact scan, correct and slower.

`dimensions` is denormalised onto the chunk because it is the index predicate,
and an index predicate cannot be a join.

### pgvector's licence, and the image swap

0018 left the licence *"not read directly this session"*. Read now: the
`LICENSE` file is the **PostgreSQL Licence** (BSD-style, OSI-approved). The
Python binding `pgvector` is **MIT** with no dependencies of its own, and needs
no `register_vector` call over asyncpg — it binds the literal and PostgreSQL
casts it (verified end to end through SQLAlchemy 2.0 + asyncpg).

`deploy/compose` moves from `postgres:18-alpine` to `pgvector/pgvector:pg18`
(pgvector 0.8.6, satisfying 0018's `>= 0.8.2` pin for CVE-2026-3172). It is the
official `postgres:18` with the extension compiled in — same entrypoint, same
PG 18 layout, volume unchanged. Alpine to Debian would normally put text-index
collations at risk across libc implementations; here it does not, because
`POSTGRES_INITDB_ARGS` already pins `C.UTF-8`, which is code-point order in both
musl and glibc.

## What redaction does to a durable store

The first genuinely new question. Every other surface here handles text that
passes through and is forgotten; a knowledge base keeps it.

- The text **sent to the embedding provider is redacted**, because that is an
  egress and every egress is redacted. It works only because placeholders are
  deterministic: an indexed document and a later query substitute the same
  entity to the same placeholder, so the vectors still compare. That property is
  what `embeddings.py` was documenting, and this is the thing it was for.
- The text **stored in the chunk is what was extracted**, unredacted. Storing
  placeholders would be theatre while `file_blobs` holds the original document
  three tables away, and it would hand a reader `<PERSON_a1b2>` in place of a
  name in their own file. Retrieval returns it to someone who already owns it,
  and the moment it heads for a model it passes through the ordinary redaction
  on `/v1/chat/completions`.

The protection stays at the boundary, where it already is, rather than being
duplicated into the store.

## The sharing ACL

One table, `resource_shares`, and one predicate in `sharing.py` — deliberately
the same shape as `access.py`, because the rest of the gateway has exactly one
access question and a second one that behaved differently would mean two mental
models for one word.

    a caller may reach a resource if they own it, or it is shared with them
    personally, or it is shared with one of their groups

Inherited from `access.py`: access is the **union**, **absence means no access**,
and **there are no denial rows** — an explicit deny overriding a group grant
turns "why can this person not see that" into a search rather than a look.

New, and both consequences of the owner living on the resource rather than in the
grant table:

- **the owner is not a share.** A resource with no grants is still reachable by
  exactly one person, so revoking every grant can never orphan it, and "who can
  delete this" has one answer at all times;
- **membership is re-read per request**, never taken from a token. That is the
  ADR 0057 trap: a group an administrator granted by hand appears in no
  directory token, so a share to that group would be invisible to a
  claim-reading implementation. `test_a_manually_granted_membership_still_reaches_a_group_share`
  is the test that fails for one.

Two roles, `viewer` and `editor`, because three would be guessing. Neither may
re-share, delete, or reindex: deleting stays with the owner so exactly one
principal can make a resource disappear, and **reindexing stays with the owner
because it spends the owning group's budget** — not a right that "may add
documents" implies.

`resource_shares` has **no foreign keys**. Both of its addresses are
polymorphic: the resource is one of three kinds, one of which (`chat_project`)
lives in the chat's MongoDB, and the principal is a user *or* a group. That is
what lets sharing have one implementation instead of two. The cost is that
deleting a resource must delete its grants by hand, and `sharing.py` is the
single place that does it and the single place that tolerates a grant pointing
at something gone.

## A bug worth recording, and why writing the test was not enough

`may_reach` built its user-principal match with `or_` where `and_` belongs. A
principal is a *pair* — the kind says which id space the id is in — so ORing the
halves matches "shared with any user at all": a resource becoming readable by
everybody the moment it is shared with anybody.

The part worth keeping is what happened next. Reintroducing the bug on purpose,
**all 14 tests still passed.** Every negative test failed closed for an
unrelated reason — no share at all, the wrong resource kind, the wrong role. The
arrangement that exposes it needs the caller to not be the owner (which
short-circuits), a share that exists but belongs to *someone else*, and no group
grant. None of them had it.

Writing a test and watching it pass is not evidence. Reintroducing the fault and
watching the test fail is, and it is now the practice for anything in this file.

## Consequences

- **Ingestion is a detached task, not a request.** ADR 0019 says OCR belongs
  nowhere near a request path, and a 200-page PDF would hold one of two uvicorn
  workers for minutes. `POST` returns `in_progress` and the document's status is
  the progress bar — which is how OpenAI's vector-store file API behaves anyway.
  There is no queue service, so it is an `asyncio` task holding a strong
  reference on `app.state.background_tasks`, for the reason `chat.py` needs the
  same set (ADR 0060): asyncio keeps only a weak one, and a collected task
  abandons a document in `extracting` with no error to show for it.
- **`_metered.begin` no longer takes a `Request`.** It never used one for
  anything but `app.state.fx` and `app.state.session_factory`. Taking those
  explicitly is what lets ingestion bill through the same pipeline instead of a
  second private copy of the money code — the one duplication this project
  cannot afford. Six call sites; `test_query_counts.py` confirms the round-trip
  budget is unchanged.
- **The extracted text is kept beside the vectors.** It is the largest column in
  the schema and it earns its space: re-embedding after a model change then costs
  one call per batch and no extraction, where re-extracting a scanned PDF costs
  real money per page. Only an extractor change needs the original bytes.
- **File bytes go in PostgreSQL**, in a table of their own. One backup story and
  one restore story — the same argument that chose pgvector over a second
  stateful service — no new credential or bucket, and metadata and content commit
  together. The admission is that a large corpus does not belong in a relational
  database; the separate table is what makes moving it a change to one module.
- **A file belongs to one person and is never shared.** Sharing happens on the
  base, so "who can read this document" has one answer. Indexing *someone
  else's* upload is refused even by an editor of the base, because indexing makes
  text retrievable and would otherwise be a way to read a colleague's file back
  out through search.
- **`knowledge_config` is the third append-only config row**, after
  `redaction_config` (ADR 0033) and `oidc_config` (ADR 0048). It matters more
  than either: changing the embedding model breaks nothing at the moment of the
  change and makes every base indexed before it incomparable with every base
  after, so "who moved the default, and when" gets asked while staring at
  results that have quietly stopped making sense. Migration 0028 seeds nothing —
  writing today's environment value in would silently pin it — and null means
  "this row does not decide", never "off".
- **A reason is required for exactly one change**: replacing the built-in
  extractor with a model that sends documents to a third party. It is the only
  edit that alters *where user documents go*. Demanding a sentence for every
  change trains people to type "x" (ADR 0033, item 1).
- **The feature is off by default** and the surfaces answer **404** until it is
  on — not 403, which would say the feature is here and this caller may not use
  it, a different and untrue statement.
- **Enabled but with no embedding model is *unfinished*, not broken.** Bases can
  still be created; indexing is refused with the reason, and `status` says which
  decision is missing. Falling back to "some embedding model" would pick one at
  random and index a corpus with it.
- **Retrieval is metered too**, and billed to the **base's** group rather than
  the searcher's: the corpus is what is being used, and charging the searcher
  would put a shared base's cost on whoever happened to ask.
- **A search embeds its query with the model the base was indexed with**, never
  the current default. A dimension change would raise; a same-dimension change
  would mis-rank silently, and the second is the dangerous one.
- **`ExactStore` exists only so the suite can run.** SQLite cannot express
  vector distance, so retrieval sits behind a contract with a Python cosine
  implementation beside the real one. It is the `InMemoryCounterStore` bargain
  and carries the same caveat: it proves the callers correct and proves nothing
  about the SQL, which is what `scripts/test_knowledge_live.py` is for. It is
  also an exact oracle, so a live script can measure what recall the approximate
  index is costing.
- **`ruff format` must not be run across this repository.** Verification is
  `ruff check`; the tree was never `ruff format`-clean, and running it touched 27
  unrelated files. Format only files you created.
- Dead code removed while passing: the console's `useSetRedactionPolicy` called
  `PUT /api/admin/redaction/policy`, which has never existed in the gateway, and
  nothing referenced the hook. Since ADR 0038 the per-entity policy is a scoped
  rule, so that endpoint was never going to be built.

## Still to build

- ~~**Agents**~~ — built. A served model plus a system prompt, default tools
  and attached knowledge bases, shared through this same ACL. Three things
  about the shape are worth knowing:

  * **an agent is addressed as a model**, as `agent:<name>`, and appears in
    `/v1/models`. That is the whole reason it lives in the gateway: any
    OpenAI-compatible client uses one by picking it from the model list, with
    no code that knows agents exist. A bespoke `/v1/agents/{id}/chat` would
    have given agents to the chat and to nothing else;
  * **it launders nothing.** Being shared an agent is not being granted its
    model — `access.py` is still consulted, so an agent cannot reach a model
    its user was refused. And retrieval re-checks the *caller's* access to each
    attached base per request, so sharing an agent is not a way to publish a
    document without sharing the document. Both have tests whose only job is
    that;
  * **the caller's instructions survive.** The agent's system prompt goes in
    front of theirs rather than replacing it, and a sampling parameter they set
    is left alone. An agent supplies defaults, not overrides.

  It is not a billing entity: the request is billed against the underlying
  model at that model's prices, and the injected prompt and passages land in
  the token count before the reservation, so an agent cannot become a way to
  spend money nothing accounts for. Retrieval failure **degrades rather than
  failing the chat** — logged as `retrieval_degraded` — because refusing to
  answer because a knowledge base is unavailable trades a slightly worse answer
  for no answer.
- ~~**The chat's half**~~ — **projects are built**, and one part of them
  departs from what this section predicted. See "Projects, and why their
  sharing is not the gateway's ACL" below. The **in-conversation** upload path
  is built too — see "Attachments, and the reason extraction is not lazy".
- **Reranking**, which ADR 0020 notes has no OpenAI standard and is therefore
  less portable than embedding, not more.
- **Retrieval at scale.** `scripts/test_knowledge_live.py` now covers the
  pgvector query, the real extractor and the ledger, and it found the bug
  recorded below. What it does *not* prove is that the HNSW index is used: at
  eight rows PostgreSQL correctly prefers a sort, so index selection has been
  demonstrated only on a synthetic probe. A corpus large enough to make the
  planner choose it is the missing measurement.

## The bug the live script was written for, found before it had one

`PgVectorStore.search` bound the vector width as a parameter —
`::halfvec(:dims)`. PostgreSQL requires a type modifier to be a literal and
answers `type modifiers must be simple constants or identifiers`. It is a
**syntax** error raised when the statement is prepared, so it cannot be reached
by a test on another dialect: the query passed all 24 SQLite cases and returned
500 on the first real search against the deployment.

This is the sharpest instance so far of a trap this project already knew about
— "SQLite is more forgiving than PostgreSQL in ways that hide real bugs" — and
the useful generalisation is narrower than that: **anything that has to be
spelled into SQL rather than bound is invisible to a portable test.** The width
is now formatted into a named constant (an `int()` in a checked range, with
every caller-influenced value still bound), and the live script exists so the
next person cannot reintroduce it quietly.

## Projects, and why their sharing is not the gateway's ACL

Projects are built, in the chat: a `projects` collection, standing instructions
prepended to the system prompt of every conversation in the project, gateway
knowledge bases attached by id, retrieval per turn, and optional retrieval over
the project's own past conversations. `scripts/test_projects_live.py` covers it
end to end — 29 checks, and what it asserts about the prompt is read from the
smoke upstream's *recorded request*, not from the answer.

**The departure.** The "Still to build" list above said a project would be
shared "through `resource_shares` with kind `chat_project`". It is not. A
project's content lives in Mongo, so that shape means a gateway row that exists
only to be an ACL anchor — a row with no resource behind it, a `chat_project`
kind the gateway can say nothing about, and a second place to keep in step
every time a project is created or deleted. What it would have bought is group
resolution, and it turns out that is already available without it:
`GET /v1/billing/groups` reports the *caller's own* memberships (ADR 0061), so
"is this project shared with a group you are in" is answerable from the
viewer's own token. Sharing therefore lives beside the project, as an array of
principals, and access is decided against the reader's identity.

What that costs, recorded because it will otherwise be filed as a bug: **a
share names a principal rather than resolving one.** A typo'd address and a
colleague who has not signed in yet are indistinguishable, and both stay
pending until somebody with that address opens the project. The alternative —
resolving addresses — needs a route that answers "does this person exist" for
anyone but the caller, which is a directory-enumeration surface handed to a
chat client. The owner sees the list of shares they wrote and never a list of
people it resolved to.

Three further rules, each chosen for a failure it prevents:

* **a shared project is a shared workspace** — everyone who can see it sees
  every conversation in it, including ones other people started. That is the
  difference between sharing a project and sharing a chat, and the page says it
  rather than leaving somebody to find their own thread in a colleague's list;
* **sharing a project shares no documents.** Retrieval runs with the reader's
  own token, so they see passages only from bases they could already read. The
  same rule as an agent, enforced the same way, which is the payoff of having
  put the bases in the gateway;
* **deleting a project deletes nothing else.** Its conversations return to the
  ordinary list and its knowledge bases — gateway resources with their own
  owner — are untouched. Cascading either would make "delete this project" a
  destructive act somebody performs to tidy a sidebar.

Retrieval over past chats writes the transcript to the gateway under
`source_ref = chat:conversation:<id>`, which **replaces** rather than appends
(that field was added for exactly this). Without it a ten-turn thread leaves
ten overlapping copies in the base and every search returns all of them. The
write happens after the answer has been streamed and is not awaited — the same
judgement as ADR 0060, for the same reason — and swallows its own failures,
logged as `project_memory_index_failed`.

## What the live script found, and one of the three is not a test's fault

`scripts/test_projects_live.py` cost three rounds to get green, and the
findings are worth more than the script:

1. **A turn is a multipart post** with the JSON in a `data` field, needing an
   `Origin` header past the CSRF guard, and a first user message still needs
   its parent id — the create puts a system message at the conversation's root
   and `addChildren` refuses to guess. A JSON body there is a 500 raised by
   undici before any application code runs.
2. **The prompt assertion cannot use the echo.** The smoke upstream echoes the
   last *user* message, and a project's context is a *system* message. It has
   to be read from `GET /_last_request` — and that has an ordering trap of its
   own: with past-chat indexing on, the transcript's embedding overwrites the
   recorded request before a client that read the whole stream can look at it.
   The assertion therefore runs in a second project with indexing off.
3. **The chat's model catalogue is global, and that defeats the agent
   hiding.** It is built once at startup with the deployment's own key, so
   every account sees the same list — including agents whose underlying model
   that account may not use. The gateway hides those per caller on
   `/v1/models`; the chat never asks per caller, so it shows them and the call
   answers 404.

   The 404 is the *designed* behaviour for an agent shared across a model
   restriction, and this does not launder anything: the refusal is still the
   gateway's. What is wrong is only the list. Fixing it means the catalogue
   stops being module state, which is not a small change and is not done. It
   is recorded here because the first symptom is somebody's own live check
   picking an agent off the top of the list and spending an hour on a 404 that
   is not about projects at all.

## Attachments, and the reason extraction is not lazy

Attaching a PDF or an Office document to a chat message now works: the chat
sends it to `POST /v1/ocr` and puts the markdown in the prompt in place of the
bytes. That surface already existed for ADR 0055 and needed nothing added —
including the `data:` URI form, which is the one that matters here, because the
alternative has the *provider* fetch the document and this deployment then
never holds it and cannot redact it.

**Extraction happens once, at upload, and the text is stored.** This is the
only interesting decision in the feature and it is a billing decision, not a
caching one: `/v1/ocr` is priced per page, so extracting during prompt
assembly would charge for the same twelve-page PDF again on the second
question about it, and again on the third. Nothing in the price table stops
that — an unpriced local extractor bills nothing either way, and the trap only
appears the day somebody configures an upstream OCR model. So the count is
asserted from the gateway's own ledger in `test_attachments_live.py`, which is
the only place that can distinguish "extracted once" from "extracted per
turn"; a client-side count only proves what the client believes it asked for.

**A document with no readable text is not dropped.** The model is handed a
sentence saying so. An attachment silently omitted makes the assistant answer
as though nothing was attached, while the person watching sees their file in
the transcript beside an answer that ignores it — and that is
indistinguishable, from the outside, from a model that read the document and
disregarded it.

Which model extracts is the deployment's choice (`CHAT_OCR_MODEL`), defaulting
to the first `kind: ocr` model the caller may use. With only the built-in
extractor installed that is the built-in extractor, which never sends the
document anywhere; naming an upstream model does, which is why it is a setting
and not a preference for whichever reads best.

One small thing the live script found, recorded because it cost a round trip:
`OcrDocument.type` is **required** and is the counterparty's own discriminator,
so `{document_url: ...}` alone is a 400 (`document.type: Field required`). It
is passed through rather than reinterpreted, which is right, but it means a
client cannot infer it from the field it filled in.
