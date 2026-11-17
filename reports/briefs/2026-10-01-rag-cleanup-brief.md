# RAG lifecycle fixes — M1+M2+invariant first, then the Ls

Branch feat/rag-cleanup off main (/home/ubuntu/workspace/Cerea, on main).
You own src/lib/server/knowledge/**, src/lib/server/projects.ts, the
chat conversation delete routes, and the gateway identity erasure path
(Pystino: apps/gateway/src/gateway/identity/ + userKeyedCollections) —
plus specs for all of it. You implement; ambiguity → stop and report.

Plan of record: the advisor's RAG soundness verdict, logged in
/home/ubuntu/workspace/oc-orchestrator/STATE.md (2026-10-01 ~02:00 entry —
read it FIRST; M1/M2 with file:line + fixes, L1–L9, the invariant). The
invariant is the design; the file:lines are starting points, verify each
against the tree.

## Batch 1 — M1+M2 + the invariant core (~1d, ordered)

1. **M1 (privacy): conversation delete removes its index.** BOTH
   single-delete routes (api/v2/conversations/[id] DELETE ~:117-132,
   conversation/[id] DELETE ~:899-913) flow through deleteConversationStorage
   (conversationStorage.ts) — extend IT (not a second call site): find
   knowledgeDocuments with sourceRef "chat:conversation:<id>" in ANY store,
   `DELETE FROM knowledge_chunks WHERE document_id = ANY($1)`, then delete
   the rows. Bulk delete excludes project conversations and loose
   conversations are never indexed — verify both claims in code, don't trust
   the report. Spec: delete a project conversation → its chunks + doc rows
   gone; other conversations' rows untouched.
2. **M2 (erasure promise): account erasure deletes passage text+vectors.**
   userKeyedCollections erases Mongo docs/stores; add the Postgres step to
   the erasure run: `DELETE FROM knowledge_chunks WHERE store_id = ANY(<the
   person's store uuids>)`, run BEFORE the vectorStores step (its ids are
   needed). Spec: erased person's chunks gone (assert zero rows for their
   store uuids, not just unretrievability).
3. **The invariant, part 1 — one cleanup function** `deleteDerived({conversationId? |
   documentIds? | storeIds?})`: deletes Postgres chunks, then GridFS files,
   then Mongo rows, in that order, safe to repeat (idempotent — deleting
   twice is a no-op, never an error). REWIRE M1 and M2 through it (M1 calls
   it with conversationId; M2's Postgres step becomes a call with storeIds),
   and rewire document-delete + store-delete through it too (replacing
   their inline Mongo-first sequences — same behavior, one path).
4. **Postgres-second ordering** (from the verdict §3): write rows first,
   delete chunks first, so a halfway failure leaves nothing retrievable.

## Batch 2 — the sweep + the remaining Ls (~1d)

5. **The orphan sweep** (the backstop): a daily job (follow the erasure
   retry loop's scheduling idiom) deleting: knowledge_chunks whose
   document_id/store_id no longer exists in Mongo; GridFS knowledge files
   with no document; chat:conversation:<id> docs whose conversation is
   gone. Log counts, never fail loudly. Spec with seeded orphans.
6. **L6**: addText must not pre-delete outside the upsert txn — move the
   delete INSIDE (the txn already prevents version mixing). Spec: embedding
   failure mid-reindex keeps the old chunks.
7. **L7**: unique index on (storeId, sourceRef) — find-then-insert becomes
   safe under concurrent turns. Check the existing indexes first (database.ts);
   spec: two concurrent indexings, one transcript.
8. **L2**: shared-project memory — minimum: SURFACE the degraded state
   (the owner's base, members silently unindexed today). If the project-owned
   base is a small diff, do it (members gain editor through membership);
   else surface + report as follow-up. Do NOT silently change ownership
   semantics without flagging it in the report.
9. **L9**: project-memory index failures surface to the person (not just a
   log line) — follow whatever surface file documents use for their
   "failed" status; minimum: the same status, same place.
10. **L1**: project-delete confirmation gains "also delete ‹project› — past
    chats" checkbox (wired to deleteDerived with storeIds).
11. **L5**: document/store delete removes the GridFS bytes (deleteDerived
    covers it — verify, don't assume).
12. **L8**: same-file re-upload dedups by content sha within a store (or
    replaces by filename — pick the smaller diff that matches the codebase
    idiom; report which). **L3**: no move-out-of-project route exists —
    nothing to do; note the constraint in a code comment where a future
    route would live.

## Rules (binding)
- NO sub-agents; foreground; every heavy command `timeout -s KILL <secs>
  flock /tmp/heavy.lock`; free -m ≥1500 / df ≥20% before heavy steps, WAIT
  rather than compete. Never kill processes you did not start. Postgres
  specs: reuse the throwaway-container idiom (pgvector/pgvector:pg18 on
  127.0.0.1:55442, TEST_DATABASE_URL/TEST_POSTGRES_URL envs — read how the
  existing live legs do it; do NOT start a second Postgres if one's
  running). Client vitest needs TEST_MONGODB_URL=mongodb://127.0.0.1:8801.
  npm run check baseline: 0 — 0 new. Prettier/eslint (and ruff for any
  Pystino touch — Pystino work happens in /home/ubuntu/workspace/Pystino
  on a sibling branch feat/rag-cleanup there if needed; keep the two
  repos' work clearly separated in the report). NO npm install. Never
  ports near 5199, never /opt/cerea.
- GIT: Paolo Viviani (configured); NO AI trailers; coherent commits
  (M1, M2, invariant+sweep, L-batch); push feat/rag-cleanup (both repos
  if touched); NO merge to main.
- Report: design as built, files, commits, exact test commands + pass
  counts, deviations — ESPECIALLY any verdict claim that proved wrong
  against the code (the report is claims-to-verify, not gospel). Then
  STOP for review.
