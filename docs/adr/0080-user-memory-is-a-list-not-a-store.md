# 0080 — User memory is a short list injected whole, not a store to search; and the write is shown rather than asked

- Status: accepted, built
- Date: 2026-09-19
- Sits beside ADR 0070's vector store and ADR 0062's projects rather than on
  top of them: this is deliberately the *other* thing from retrieval, and the
  reason it is not built on the pipeline those two ADRs describe is most of
  this document. Declines ADR 0075's gated set on purpose, and says why at
  length so the refusal is not mistaken for an oversight. Adds a deployment
  flag in the shape ADR 0076 established.

## Context

A conversation ends and everything the person said about themselves goes with
it. They re-explain their role, their language, their standing constraints,
every time. The fix is a small store of facts that outlives the conversation.

The awkward part is that this chat **already has** a retrieval pipeline that
could hold them. ADR 0070 moved bases, documents, chunks and vectors into the
application; ADR 0062's projects already index finished exchanges into a
knowledge base (`Project.memoryBaseId`) and search it per turn. Adding
"memory" as one more base, searched with the question, is a few hours of work
against machinery that is built, tested and deployed.

That is the design this ADR rejects, and the reasoning is worth recording
because the rejected option is the one that looks obviously correct.

### What the field actually does

Five implementations, and they disagree in a way that turns out to be
informative:

- **ChatGPT** keeps two layers: *saved memories*, an explicit user-editable
  list, and *reference chat history*, a rolling summary built from past
  conversations. The detail that matters: saved memories are **not**
  vector-searched. The list goes into the system prompt wholesale.
- **Claude's memory tool** is files with six operations — view, create,
  str_replace, insert, delete, rename — and **no embeddings at all**. The
  model does its own bookkeeping.
- **LibreChat** runs a memory agent per request with `set_memory` /
  `delete_memory` over a key/value store, constrained to declared valid keys
  and a token limit, and instructs the agent to write only when asked.
- **Open WebUI** is the one that does go vector: a per-user collection, top-k
  retrieved per request. Its own issue tracker is the argument against it —
  there are open requests both for adding reranking and for bypassing
  retrieval entirely and injecting the whole thing.
- **mem0** is the heavyweight: an extraction model per turn distilling atomic
  facts, reconciled against existing ones for deduplication and contradiction,
  in a vector store with a provenance history.

The pattern is that the implementations with the longest production exposure
converge on **not retrieving**, and the one that does retrieve has users
asking it to stop.

## Decision

### Memory is injected whole, every turn, and never searched

Four reasons, in ascending order of importance:

1. **It is the wrong size for retrieval.** A person accumulates dozens of
   short sentences, not a corpus. Ranking forty lines is not a search problem.
2. **Retrieval costs a metered embedding per turn**, charged to the person's
   own token, to decide which six of forty sentences to show. Injecting all
   forty costs a few hundred prompt tokens and no round trip.
3. **The fact somebody needs is frequently the one that does not resemble
   their question.** "Reply in Italian" never matches a question about
   Postgres, and a preference that only applies when you mention it is not a
   standing preference. Semantic similarity is precisely the wrong selector
   for the things worth remembering about a person.
4. **The decisive one: because the whole list goes in, the screen showing it
   is exact rather than indicative.** "Here is what the assistant knows about
   you" is a true sentence only if everything listed is actually sent. Under
   retrieval that screen becomes a guess, and a guess is a bad foundation for
   the one screen whose entire job is letting somebody audit and correct what
   a machine believes about them.

**The cost, stated because it is real:** this does not scale. Past the block's
character budget the oldest facts stop being sent. Somebody who wants a
thousand remembered things wants a knowledge base, and this chat has those —
that is the division of labour, not a gap.

### The budget is shared code, not a number repeated twice

`fitMemoriesToBudget` (`src/lib/utils/memoryBudget.ts`) is pure, takes the
facts oldest-first, and returns which indices fit. The server builds the
prompt block from it; the Memory screen marks the omitted rows with it. Two
copies of that arithmetic would drift, and the drift would be invisible in
the worst direction: the screen would claim a fact is reaching the model
while the prompt had dropped it.

A budget is needed at all because **nothing else enforces one**.
`utils/prepareFiles.ts` reserves a flat `PROMPT_OVERHEAD_TOKENS = 4_000` to
cover the preprompt *and* every tool schema, and never measures what actually
goes in. An unbounded memory block would eat that reserve and start silently
costing conversation history — a regression that presents as "the model
forgot what we said ten turns ago" and gets blamed on the model.

Newest wins when the budget binds, and the block **says how many were
dropped**. Saying so is load-bearing: a model told it can see everything
answers confidently about what it was never shown.

### Two ways to write, one service

A fact arrives either because somebody typed it on the Memory tab or because
the model called `remember` mid-turn. Both go through
`src/lib/server/memory/service.ts` — the same validation, the same
deduplication, the same ceiling. Two entry points that each grew their own
copy of those rules would not have stayed in step.

The routes never accept a provenance from the client: `POST /api/v2/memory`
stamps `source: "user"` because that route *is* the screen, and the tool
writes through the service directly. A client that could name its own
provenance could label a guess as something the person said.

### Deliberately not behind ADR 0075's approval gate

ADR 0075 gates calls with **external reach or cost**. A memory write has
neither: one document, in this application's own database, owned by the
person the turn belongs to. Three reasons it stays out, the second being the
real one:

1. **Nothing to protect against.** The gate exists to stop a model reaching
   somewhere or spending something without consent. This reaches nowhere.
2. **It would be the most frequent approval card in the product, and that
   degrades the gate everywhere else.** An approval prompt per remembered
   fact teaches people to dismiss approval prompts. The cost of that lands on
   `web_fetch` and MCP tools, where the card is doing real work. Gating a
   harmless high-frequency operation is how you make the gate decorative.
3. **A better safeguard exists for this specific operation.** The write is
   *shown* — its own card in the transcript, naming the fact — and can be
   undone from there in one click. Asking first costs an interruption on
   every correct write; showing afterwards costs nothing on a correct write
   and one click on a wrong one. For an operation that is reversible and
   local, "show and allow undo" strictly dominates "ask and interrupt".

This is a decision, restated here in the same spirit as ADR 0079's note about
`execute_code` and `load_skill`, so that the next person auditing
`toolInvocation.ts`'s gate resolver does not "fix" memory into being gated.

### The undo uses the ordinary routes, not a reversal endpoint

Undoing a `remembered` deletes that row; undoing a `forgot` re-creates the
fact from the text the update carried. Both go through the same two routes the
Memory screen uses. This is why `MessageMemoryUpdate` carries the fact's full
text rather than a reference — after a `forgot` there is no row left to read
it from.

The transcript card does **not** rewrite itself as undone in the persisted
record. The update is the historical account of what the model did on that
turn; the store is the thing the undo changes, and the Memory screen is the
view of the store. Editing history to match would make the transcript
disagree with itself.

### Forgetting matches on text, not on identifiers

Putting stable ids in the prompt block would mean carrying noise on every turn
to serve the small minority of turns that forget anything. So `forget` takes
the fact in words, and the service resolves it in three tiers: exact match
after normalising case, whitespace and a trailing full stop; then a unique
containment in either direction (the model paraphrasing, or quoting only the
clause it means); then refusal.

**The refusal is the important tier.** It lists what is actually stored, in
the shape `update_plan`'s validation errors use, so the model retries against
real wording rather than guessing again. Deleting the wrong fact silently is
far worse than one wasted round.

### Deduplication yes, contradiction reconciliation no

Re-remembering something already stored returns the existing row with its
timestamp moved — the cheap half of what mem0 does with an extraction model,
and the half that pays for itself immediately. The expensive half — noticing
that a new fact *contradicts* an old one and retiring it — is deliberately
not attempted. Getting it wrong deletes something true, silently, and the
model can call `forget` when it actually knows. An automated retirement that
is right 90% of the time is a machine for quietly losing the other 10%.

### Two switches, defaulting in opposite directions

- **`CHAT_MEMORY_ENABLED`, the operator's, defaults on** (`!== "false"`, the
  `knowledgeEnabled` shape). Off hides the tab, answers 404 on the routes, and
  withholds the tools. A feature that defaults off deployment-wide is a
  feature nobody discovers.
- **`Settings.memoryEnabled`, the person's, defaults off.** This is the same
  judgement `Project.indexPastChats` already makes and for the same stated
  reason: writing what somebody said into a store that outlives the
  conversation is a decision worth making rather than discovering.

So a fresh deployment ships the feature available and storing nothing. No
deployment flag can opt somebody in, and no personal setting can survive an
operator withdrawing the feature.

**The person's switch lives on the Memory tab, not on the settings page.**
Every other preference is under Settings and this one deliberately is not:
"is memory on" and "what does it currently hold" are one question. Split
across two screens you get people turning it on without seeing what that
means, or reading the list without knowing it is inert.

### Turning it off deletes nothing, and deleting works when it is off

Off means nothing is injected and no tool is offered. Stored facts remain,
because a switch that deleted them would make "let me try this off for a
week" an irreversible act.

The one asymmetry in the route set follows from this: `DELETE` does **not**
check the deployment flag, while every other verb does. An operator setting
`CHAT_MEMORY_ENABLED=false` must not strand what people have already stored
behind a 404 — that turns a feature switch into "your data exists and you
cannot reach it". Reading and writing stop; getting rid of it does not.

### Provenance is kept, and sharing is not built

Each fact records whether the model wrote it or the person typed it, and a
model-written fact records the conversation it came from. This is not
decoration: "I inferred this about you" and "you told me this" are different
claims, and they should not look identical on the screen where somebody
decides whether to delete one. The conversation reference means an odd entry
can be traced to the exchange that produced it instead of merely deleted in
puzzlement.

There is **no sharing and no administrator path** — unlike skills, which have
a deployment scope. A standing fact about a person is the most personal thing
this application stores, and "I administer this deployment" is not "I may read
what you told the assistant about yourself".

### The doctrine is the real control

Nothing mechanically prevents a model from remembering something useless. The
tool's `preprompt` is what actually governs behaviour, and it is deliberately
conservative: durable facts only; nothing transient; nothing about third
parties; nothing secret. A store that fills with "the user is currently
debugging a Postgres error" is worse than an empty one, because every later
turn pays to carry it.

The secret clause is not boilerplate. Memory is injected into every prompt, so
a credential remembered once is a credential transmitted on every subsequent
turn, to whichever upstream the gateway routes to. The tab's closing note says
so to the person as well.

## Consequences

- A new Mongo collection, `memories`, one compound index, no migration.
- `FeatureFlags` gains `memoryEnabled`; the installer gains a toggle, on in
  all three ADR 0076 profiles. It is not a *component* — it needs no
  container and no second database — but it is exposed because withdrawing
  it is a policy decision an enterprise operator may need to make, and the
  installer's job is to surface exactly those.
- The injection sits in `textGeneration/index.ts` after `resolvePreprompt`
  and **before** the project block: the conversation's own prompt keeps
  precedence over both, and a standing fact about a person is more general
  than passages retrieved for one question. Because all three turn entry
  points funnel through that file — the chat route and both sweepers —
  resumed turns are covered by the one insertion.
- It cannot fail a turn. `memoryContext` swallows and logs its own failures,
  the posture ADR 0062's retrieval and the ADR 0072 skills assembly already
  hold: a store that cannot be read is a reason for a worse answer, never for
  no answer.
- Anonymous sessions get no memory at all, in either direction. Every other
  per-person store here accepts a session through `authCondition`; this one
  requires a user, because a fact attached to a cookie that expires is a
  promise the store cannot keep.
- `prepareFiles.ts`'s 4,000-token overhead reserve now has a real named
  consumer for the first time. It is still unmeasured, and this ADR does not
  fix that — it only stops being the first thing to make it a problem.

## Deliberately not built

- **A background extraction pass** (mem0's shape, and ChatGPT's newer one).
  It spends a model call per turn and writes facts nobody watched it decide,
  which is the opposite of the visibility this design is built around. If it
  is ever wanted it should arrive as a deployment flag, off by default, and
  its writes should be as visible as the tool's are.
- **Vector retrieval over memories.** See the whole first decision. If
  somebody genuinely outgrows the budget, the answer is a knowledge base, not
  a second retrieval implementation over a different collection.
- **Per-project or per-agent isolation** (LibreChat's "keep memories separate
  for this agent"). A real need, but it is a second scoping dimension on top
  of projects and it should not be designed from speculation. Today one
  person has one memory.

## Verified

`npm run check` reports 0 errors over 2,770 files; `npx eslint .` is clean.
`prettier --check` fails only on `docs/*.md` and `README.md` in the Cerea
repository, which were already failing before this work.

**Unit, 47 tests across four files**, re-run independently of the agent that
wrote them:

- `src/lib/server/api/__tests__/memory.spec.ts` (13) — the routes end to end.
  The 401 with no user; a stranger's id answering 404 on both `PATCH` and
  `DELETE`, so one person cannot read or clear another's; and the deployment
  flag refusing `GET`, `POST` and `PATCH` while **`DELETE` still works**. That
  last one is the least obvious rule in this ADR and the most likely to be
  "corrected" later, so it is pinned by a test whose name says why: *still
  deletes when the deployment flag is off — off must not strand data*.
- `src/lib/server/memory/service.spec.ts` (22) — deduplication on the
  normalised form returning `created: false`, the `MEMORY_MAX_FACTS` refusal,
  all four branches of `forget`'s resolution (exact, unique containment,
  ambiguous, miss), and the block's truncation notice.
- `src/lib/utils/memoryBudget.spec.ts` (5) — newest-wins, oldest dropped
  first, one over-long fact surviving alone, chronological ordering of what
  survives.
- `src/lib/components/memory/MemoryManager.svelte.test.ts` (7), run in
  `mcr.microsoft.com/playwright:v1.61.1-noble` — the list, the switch
  reflecting the stored setting in both states, adding through the API, and a
  row past the budget carrying its "No longer sent" mark.

The full server+ssr suite reports 1,831 of 1,833 tests passing. The two
failures are the Pyodide wasm SIGILL (this box has no AVX) and one
`replayRoundTrip` assertion that passes in isolation and fails under
full-suite load — both pre-existing, and no implementation file outside this
work was touched.

**One thing the tests found, recorded because the direction matters:** the
first over-budget assertion failed against a correct implementation. The
fixture seeded 20 facts of 64 characters, about 1,340 in total — under the
1,500-character budget — so nothing was ever omitted and the truncation
notice correctly did not appear. The test was wrong, not the code. Worth
noting because a budget test that silently sits under the budget is a test
that would have gone on passing for the wrong reason if the assertion had
been written the other way round.

**Not verified:** the client suite as a whole. Something in that project
boots `mongodb-memory-server` inside the container, which SIGILLs without
AVX — the limitation `CLAUDE.md` already documents. The memory-adjacent
client files were each run individually and pass.
