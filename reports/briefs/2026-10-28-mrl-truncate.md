# Brief: finish the MRL embedding fix (2026-10-28 evening)

## Task
The worker on branch `fix/mrl-truncate` (worktree `/home/ubuntu/workspace/wt-mrl`, based on `origin/main` `5ff84be0`) was stopped mid-task; its work is **uncommitted**. Finish it: verify correctness, run the specs, commit, push once, one CI run. Do not merge — the orchestrator arranges the review and the merge.

## Context
Cortecs ignores `dimensions` for `qwen3-embedding-8b` and answers at the native 4096; the store indexes at most 3072, so every reindex fails ("4 documents, 4 failed" on the Padova project's chat memory). The fix: for a known Matryoshka (MRL) model, truncate each vector to the store's width and L2-renormalise — documents and queries alike; non-MRL too-wide models keep failing with a message naming the allowlist. Owner approved this for 0.32.4.

## Uncommitted state (verified by the orchestrator)
- `src/lib/server/knowledge/mrl.ts` (new, 68 lines): `MRL_FAMILIES` allowlist (Qwen3 Embedding, OpenAI text-embedding-3 small/large, Nomic v1.5/v2, Jina v3/v4, mxbai-embed-large, Snowflake Arctic L v2), `isMrlModel`, `truncateRenormalise`, `tooWideMessage`.
- `src/lib/server/knowledge/service.ts`: `embedChunks` truncates and renormalises when `native > target && isMrlModel(model)`, logs once per base (`truncationLogged`), `upsertChunks` gained a `model` parameter, two inline too-wide errors replaced by `tooWideMessage`, one log line reworded to `knowledge_embedding_too_wide`.
- `docs/knowledge.md`: new "Wide embedding models" section.
- `src/lib/server/knowledge/mrlUnit.spec.ts` (24 lines): passes 2/2 (verified locally).
- `src/lib/server/knowledge/mrl.spec.ts` (191 lines): integration spec on the TEST_DATABASE_URL + TEST_MONGODB_URL harness (same as `ingestBackground.spec.ts`); the `resolveExtractorModel` mock (the stopped worker's last step) is present at line 34.

## Verify (in order)
1. **The query path really goes through `embedChunks`.** The comment in `service.ts` claims documents and queries share it — confirm by tracing the chat-memory search path. If queries have a separate embed path, the truncation must cover it too; add it if missing. This is the key correctness check.
2. Read the whole diff (`git diff` plus the new files) as a reviewer would: the embed mock's contract vs the real `embed()` signature; every `upsertChunks` call site updated; `truncationLogged` unbounded growth acceptable (per-base keys); no behaviour change when the provider honours `dimensions`; the too-wide error names the model and the allowlist.
3. Run `mrlUnit.spec.ts` (passes) and `mrl.spec.ts`. CI sets only `TEST_MONGODB_URL: mongodb://127.0.0.1:27017/` (`.github/workflows/ci.yml:87`); find how `TEST_DATABASE_URL` is provided (spec fallback, another workflow file, or `.env`) by searching the repo. Run the integration spec locally if practical (ephemeral mongod binary in `~/.cache/mongodb-binaries`; `pgvector/pgvector:pg18` image is present). Heavy steps under `flock /tmp/heavy.lock`. If a local integration run is impractical, say so and rely on CI.
4. Commit everything including the docs: one descriptive line, no AI trailers (Cerea hooks reject them). Push once. Exactly one CI run; watch it to completion.

## Report back
What you verified or changed beyond the found state; local spec results; CI run id and conclusion; anything questionable — especially the query-path check.

## Constraints
Only this branch/worktree. No merge to main. New user-facing text says "users", not "people".

## Outcome (W2, 2026-10-28 evening)

**State found = state shipped, plus one PR.** The stopped worker's uncommitted work was correct; nothing needed fixing beyond it. Committed as `31a33bc03` on `fix/mrl-truncate` (5 files, 329 insertions), pushed once, PR #46 (https://github.com/paoloviviani/Cerea/pull/46) — not merged.

**Verifications, beyond the found state:**

1. **Query path (the key check): confirmed, not assumed.** `embed` (`knowledge/embed.ts`) is imported by exactly one module, `service.ts`. Its only three call sites are `embedChunks` from `ingestDocument` (twice) and from `search` (service.ts:1396, the query). Both retrieval surfaces — `projects.ts:422` (`searchBase`, the chat-memory/project-context path) and the gateway forwarder's `vector_stores/<id>/search` route (`gateway/[...path]/+server.ts:204`) — call `service.search`. There is no second embed path anywhere (the only `gateway.post(..., "embeddings", ...)` is in `embed.ts`); `GatewaySearchHit` in projects.ts is a type only. The comment's claim holds: truncation covers queries by construction.
2. **Embed mock contract**: real signature `embed(token, model, texts, dimensions?)`; the spec's mock `(_t, _m, texts, dims?)` matches, returns one vector per text in input order.
3. **`upsertChunks` call sites**: exactly two (service.ts:811, 866), both pass the model.
4. **Too-wide error text**: `tooWideMessage` names the returned width, the indexed widths, the allowlist, and the offending model — the integration spec asserts all three substrings land on the document row.
5. `truncationLogged` grows one key per (base, model) — bounded in practice, acceptable as the brief judged.
6. No behaviour change when the provider honours `dimensions` (truncation fires only when `native > target`); the spec pins this (provider-sliced vectors stay untouched, norm ≫ 1).

**Local spec results** (real `pgvector/pgvector:pg18` on port 55461 — container `mrl-pg` left running by the stopped worker, reused — plus ephemeral mongod 4.4.30 on 8801, under `flock /tmp/heavy.lock`):

- `mrlUnit.spec.ts` **2/2 pass**.
- `mrl.spec.ts` **3/3 pass** (integration: 4096→3072 unit-length rows in Postgres, `dimensions` still asked first, query embedded at the base's width, non-MRL refusal text, honours-dimensions provider untouched).
- Neighbour specs on the same harness (`ingestBackground.spec.ts`, `deleteDerived.spec.ts`): **6 failures — identical on a main-state checkout run immediately before** (3 background timeouts, a `documentMime`-not-in-mock error, 2 deleteDerived assertions traced to a `knowledgeConfig` wipe by an earlier test in the same file). Pre-existing in this environment, not caused by the change; those files skip in CI (no `TEST_DATABASE_URL`). Not chased further — out of scope.

**Gates**: `npm run lint` ✓ (after deleting a gitignored `project.inlang/cache` artifact my vitest runs had generated — CI never sees it), `npm run check` 0 errors/0 warnings ✓, `mkdocs build --strict` ✓ (docs.yml runs only on main pushes, so the docs change would not have been validated by CI on the PR).

**CI**: exactly one run, `40769697229` (pull_request, PR #46): **completed, success** — `check` 8m1s, `e2e-smoke` 4m36s, `go` 45s, `changes` pass; `e2e-full`/`client`/`documents` skipped by design. Watched to completion.

**Questionable / noted, not acted on:**
- `TEST_DATABASE_URL` is provided by no CI or repo file at all — it is a runner-supplied variable documented in each spec's header; CI never sets it, so `mrl.spec.ts` and its neighbours **skip in CI entirely**. Local validation was therefore load-bearing for this change (done, above).
- Pre-existing rough edge, unchanged by this fix: on a base whose *non-MRL* model's provider ignores `dimensions`, a failed first ingest still records `dimensions: 3072` on the base row; a later `search` on such a base builds a 4096-wide literal against a `halfvec(3072)` cast and fails at the pg level (raw 500, not a KnowledgeError). Same on main; a `vector.length !== dims` guard in `search` would make it a clean 400 if anyone picks it up.
- origin/main advanced 4 commits (kit + docs nav only, no overlap) while the work was uncommitted; the branch was left based on `5ff84be0` as briefed.
- Housekeeping: the ephemeral mongod was stopped and `/tmp/mrl-mongo` removed; the `mrl-pg` container was already running before this task and was left as found. A trap for the next person: `mongod --fork` started inside a `flock` wrapper inherits the lock fd and blocks every later `flock` on the box — start it detached, outside the flock.
