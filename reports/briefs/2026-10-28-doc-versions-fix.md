# Brief: doc-versions re-review fixes (2026-10-28 evening)

## Task
On branch `feat/doc-versions` (worktree `/home/ubuntu/workspace/wt-doc-versions`, clean at `9129825`, pushed), apply the three approved fixes from the second Opus review, run the specs, push once, one CI run. Do not merge to main — the orchestrator merges after a focused review of the fix commit.

## Context
The branch adds document versions (`version` on doc_outline/doc_read/look_doc/convert_document/doc_edit source, `file_versions` list, restore, lazy back-fill, sandbox mount race fix). Review history: first review's 9 findings all fixed; the re-review addendum's verdict was "mergeable once one fix is in". The fixes below are owner-approved. Earlier the reviewer could not run tests (`node_modules/.vite` EACCES) — that is fixed now, the worktree runs specs fine.

## Fix 1 (must): the retention sweep scans the whole collection
`src/lib/server/execution/deliverables.ts` — `staleBefore(cutoff)` builds `{ $expr: { $lt: [ { $ifNull: ["$latestAt", "$createdAt"] }, cutoff ] } }` (const `LIVE_AT`), used by `sweepExpiredDeliverables` and `deliverableStorageSummary`. `$expr` cannot use the `createdAt` index, so every hourly sweep and the admin storage summary scan all of `codeExecutionOutputs`.
- Replace the filter with `{ $or: [ { latestAt: { $lt: cutoff } }, { latestAt: null, createdAt: { $lt: cutoff } } ] }` (in Mongo a missing field matches `null`).
- Add a sparse `{ latestAt: 1 }` index in `src/lib/server/database.ts` beside the other `codeExecutionOutputs` indexes.
- Behaviour must stay identical.

## Fix 2a (owner-approved): two versions can get the same number
`fileVersions.ts` `nextVersionNumber()` reads the highest number and the save path then inserts; concurrent saves can collide.
- Add a unique **partial** index on `{ conversationId: 1, name: 1, version: 1 }` (partial filter: `version` exists) in `database.ts`.
- On duplicate key (Mongo code 11000) in the deliverable save/insert path, recompute the number and retry.
- The back-fill loop in `numberedRows` must ignore duplicate-key errors on its update (a second replica booting concurrently can race it; the next pass renumbers the leftover).
- Add a spec that covers the retry where testable.

## Fix 2b (owner decision): number attachments
Today an attachment re-uploaded under an existing deliverable name collides (the review: model makes `report.docx` stored as v1; user later re-uploads `report.docx`; two v1s, and `version: 1` resolves to the attachment). Owner decision: **the attachment takes the next free number at upload time**, so everything stays numeric and `version: N` resolution stays simple.
- Find where attachment files become stored rows (follow `attachmentNamed` and the attachment save path) and assign the next free number for `(conversationId, name)` there.
- The `nextVersionNumber` fallback "2 after an attachment" should become unnecessary; remove it if the new rule covers it.
- Keep this minimal: if it turns out to reshape the attachment pipeline (resolution semantics beyond numbering), implement the minimal correct version and flag it in your report.

## Out of scope (deferred, do not touch)
`downloadDeliverable` name handling, `deleteRows` preview release, image-mount f-string/glob cases, the `dropIndex` code-27 wrap, the release-notes downgrade note.

## Verify
- Run the server specs covering fileVersions, deliverables, documentVersions (`npx vitest run --project=server` with the relevant files; find them). The box has 4 cores/6 GB — heavy steps under `flock /tmp/heavy.lock`.
- Push once (no force). Exactly one CI run; watch it to completion (`gh run watch <id>` or poll `gh run view`).
- Commit style: one descriptive line like the branch's existing ones, no AI trailers (Cerea hooks reject them). New user-facing text says "users", not "people".

## Report back
Files changed with a one-line why for each; spec results; CI run id and conclusion; anything you had to decide yourself.

## Outcome (2026-10-28 evening, W1)

Fix commit `3dcf6fb08` (rewritten to `63435387` in the owner-approved trailer rewrite of 2026-10-28 night) on `feat/doc-versions`, pushed once (no force), not merged.

**Files changed**
- `src/lib/server/execution/deliverables.ts` — Fix 1: `staleBefore()` is now `{ $or: [{ latestAt < cutoff }, { latestAt: null, createdAt < cutoff }] }` (the `LIVE_AT` `$expr/$ifNull` is gone), so the sweep and the storage summary can use indexes. Fix 2a: the insert in `storeDeliverable` retries on duplicate key (`isDuplicateKeyError`, code 11000, max 3 recomputes): a twin row with the same bytes returns `existing: true` (the racer won; the orphan sweep frees the loser's GridFS entry), otherwise the number is recomputed.
- `src/lib/server/database.ts` — Fix 1: sparse `{ latestAt: 1 }` index beside the other `codeExecutionOutputs` indexes. Fix 2a: unique partial `{ conversationId: 1, name: 1, version: 1 }` (partial filter `version: { $exists: true }`).
- `src/lib/server/execution/fileVersions.ts` — Fix 2a: exported `isDuplicateKeyError`; the `numberedRows` back-fill swallows duplicate-key errors on its version writes (a racing numbering pass leaves the row for the next pass); `nextVersionNumber` returns one past the highest number taken by a row **or** the attachment's stored number — the "2 after an attachment" fallback is gone (the attachment's number covers it).
- `src/lib/server/files/uploadFile.ts` — Fix 2b: `uploadFile` (the chat conversation path only) assigns the next free number for `(conversationId, name)` at upload and records it on the `MessageFile` when it is > 1; version 1 stays implicit, so ordinary uploads are unchanged.
- `src/lib/server/textGeneration/builtinTools/conversationFiles.ts` — `listFileVersions` honours the attachment's stored number (was hardcoded 1), and the version list is now ordered by number (an attachment numbered 3 sits between rows 2 and 4, not first); `findConversationFile`'s attachment-first pick and bytes-gone fallback find the attachment entry by origin instead of by array position.
- `src/lib/types/Message.ts`, `src/lib/utils/execution/attachmentNames.ts` — optional `version?: number` on `MessageFile` / `AttachmentSource`.
- `src/lib/types/CodeExecutionOutput.ts` — `latestAt` typed `Date | null` (optional): the sweep's filter matches a missing field with `null`, and Mongo's `Filter` type requires the schema to admit it.
- Specs: `deliverables.spec.ts` (retry: recomputed number wins; twin-bytes race returns `existing`; sparse/unique index assertions; expiry by an old `latestAt` on a young row), `documentVersions.spec.ts` (back-fill loses a number to a concurrent pass, still lists, next pass renumbers), `uploadFile.spec.ts` (re-upload under a produced name takes 3 and the next produced file takes 4; first version carries no number).

**Verification**
- New tests fail without the fix: reverted the eight source files and ran the three spec files — exactly the 5 new tests fail, all 46 pre-existing pass; fix restored, all green.
- Focused: `deliverables.spec.ts` + `documentVersions.spec.ts` + `uploadFile.spec.ts` — 51/51 pass.
- Full `npx vitest run --project=server` — 4101 passed, 1 failed: `src/styles/tokens.drift.test.ts` (vendored `tokens.css` vs the sibling Pystino console checkout, 280 lines). Pre-existing and environmental: the vendored file is byte-identical to main's, I touched no styles, and the test skips in CI where the sibling checkout is absent.
- `npm run check` 0 errors; `eslint` clean; `i18n:check` passed. (`npm run lint`'s prettier step flagged two files under `project.inlang/cache/` — gitignored paraglide compile artifacts created by the local check run, not in the commit; CI's lint is unaffected.)

**CI**: run `40775521011` (workflow_dispatch on `feat/doc-versions`), **success** — check 8m59s, e2e-smoke 4m34s, go 43s, client 6m47s, documents 2m13s all green.

**Decisions I made myself**
- No PR: the branch had none, and the orchestrator merges the commit itself, so I dispatched `ci.yml` on the branch ref (`gh workflow run ci.yml --ref feat/doc-versions`) — exactly one run, watched to completion.
- The attachment's number is recorded on the `MessageFile` (the row `attachmentNamed` already returns), not in GridFS metadata or a deliverable row — no second lookup at listing time, no byte duplication; number 1 is left implicit so attachments under fresh names store nothing new.
- Version-list order is now by number (needed once an attachment can be numbered 3), which also makes `version: "previous"` numerically previous; in every pre-existing flow the order is unchanged. The pre-existing resolution rules are untouched: a plain name still prefers the attachment, document tools still prefer the newest produced file — so after a re-upload the list may mark an older-numbered row "(latest)" while a plain name resolves to the attachment. That tension predates this change; flagging, not changing.
- Known race left open (small, harmless): two same-named files uploaded in one turn (`Promise.all`) both compute the same next number before either message exists; only the first is addressable by name, so no single version list shows a collision. A row inserted between an upload and its message save can likewise claim the attachment's number; the list then shows a duplicate number for that pair. Both need concurrent writers in one conversation within seconds; the unique index does not span attachments (they are not rows). Flagged rather than reshaping the upload pipeline.

## Outcome (follow-up, C53 — attachment is the newest content, incl. the review round)

Branch `fix/attachment-current` off the rewritten `origin/main` `1ef68e339`, three commits, pushed, not merged (orchestrator merges): `93ed33975` (the prescription), `530d987a1` (the review round: S1+S2), `6f380ebc7` (the two specs pinning the mount-notice wording, which the review round's wording change broke in CI).

**Files changed**
- `src/lib/server/execution/fileVersions.ts` — `attachmentNamed()` returns the NEWEST attachment of the name (last match over the plan, ES2018-safe loop) and its own message's `createdAt` (reference-matched file; conversation fallback for timestamp-less messages). With the newest attachment returned, the existing taken-set line honours its stamped number in `numberedRows`/`nextVersionNumber`, so the next row continues past it instead of taking it.
- `src/lib/server/textGeneration/builtinTools/conversationFiles.ts` — `listFileVersions` computes "current" over every entry (rows by `latestAt ?? createdAt`, the attachment by its message's moment; ties to the later-built entry); `prefer: "output"` is `pick = current` outright (the old ternary's `versions[0]` else-branch was already wrong post-sort).
- `src/lib/utils/execution/attachmentMounter.ts` — S1: `syncProduced` no longer mounts a row over an attachment that is the current version of its name (comparison by the stamped `version` the output list already carries; a row without a number counts as newer; a failed/absent attachment mount never blocks the row); `ProducedFile`/`Entry` carry the number; header and doc comments say "current", not "latest".
- `src/lib/utils/execution/attachmentNames.ts` — the prompt notice now says "(its current version, if it has been edited)".
- `src/lib/server/textGeneration/builtinTools/documentVersions.spec.ts` — two regression specs: produced-first re-upload (C53 proper) and re-upload of an attached name (S2: list `[2,3,4(attachment,current)]`, `at` = message moment, edit starts from v4 and saves v5 — numbering continues past the stamp).
- `src/lib/utils/execution/attachmentMounter.spec.ts` — S1 spec: rows mounted, re-uploaded attachment (v3) over them, further syncs of the older rows do not take the path back, a row numbered 4 does. Uses per-fetch response factories — a shared `Response` body is single-read, which first made the test pass for the wrong reason.
- `prepareFiles.spec.ts` + `attachmentNames.spec.ts` — the pinned notice text updated to "current version" (found by CI, not locally — lesson: full suite before push).
- `AGENTS.md` — document-tools sentences: the tools edit the current version (produced or attachment); the current-version rule; the sandbox mounts the current version, a row over the attachment unless the attachment is current.

**B1 resolution**: kept `.some((file) => file === planned.file)` over the prescribed `includes(planned.file as MessageFile)` — the same by-reference match without a cast, and it typechecks because comparability (not element identity) is all `===` needs.

**Verification**
- Revert check (source files restored to the base of each round): exactly the new tests fail — round 1: 1 of 14; round 2: 2 of 32 (S1+S2), all pre-existing pass; fixed files restored, everything green.
- Focused: documentVersions 15, uploadFile 12, attachmentMounter 17, deliverables 26 — all green; `attachmentMounts.svelte.spec.ts` run locally too (16/16, client project).
- Full `npx vitest run --project=server --project=ssr`: 4115 passed, 1 failed — the pre-existing `tokens.drift` environmental failure (skips in CI; vendored file byte-identical to main's).
- `npm run check` 0 errors (after B1's shape), `npm run lint` clean (gitignored paraglide cache noise removed before linting).

**CI** — three dispatched runs on the branch, one per pushed commit: `40785423340` success (first commit; client green on job rerun after one infra-noise timeout), `40830931323` failure (check job: the mount-notice wording is pinned by two specs I had not run locally), `40833669989` **success** on `6f380ebc7` — check 12m53s, client 10m42s, e2e-smoke 4m27s, go, documents all green. The review arrived after the first push, so the fold-in is commits 2–3 with their own runs; no force anywhere.

**Judgement calls**
- The mounter's "is the attachment current?" test compares version numbers (the review's suggested mechanism), not live moments: a stamped attachment outranks every row that existed when it was numbered. Residue (flagged, exotic): a restore of an older row AFTER a re-upload makes the row current server-side while the mounter keeps the attachment mounted until the next numbering event.
- With `findLast`, the superseded first upload no longer appears in the bare name's version list (its implicit 1 stays taken; its bytes stay mounted under the bare name, while the re-upload mounts at `name (2)` — tool resolution of the bare name follows the newest attachment, so for the attached-first-then-re-uploaded flow the sandbox's bare-name bytes can differ from the tool's resolution; the re-upload's own mount path always holds exactly its bytes). A second re-upload similarly supersedes the first from the list; both remain reachable under their own mount names. Deeper reshaping (reallocating mount names, listing every attachment) was out of the review's prescription.
- `listFileVersions` still echoes the attachment's planned mount name as the listing's `name` — for a re-upload matched by raw name that is the ` (2)` name, which is also where those bytes are mounted.
- The wording change ("latest" → "current" in the mount notice) was user-facing model text; kept "user" spelling per the C51 amendment.
