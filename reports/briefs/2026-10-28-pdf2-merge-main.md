# Brief: pdf-forms-round2 — merge main and resolve the three hunks (2026-10-28 evening)

## Task
On branch `feat/pdf-forms-round2` (worktree `/home/ubuntu/workspace/wt-pdf2`, clean at `9274abb13`, 3 commits): merge `origin/main` (which just gained kit skills, mkdocs tabs, the mrl truncate fix, C44's delete menu and the whole of feat/doc-versions — the document-versions work), resolve the conflicts in `documentTools.ts` exactly as prescribed below, run the description budget specs and the focused document specs, push once, dispatch exactly one CI run on the branch, watch it to completion. Do NOT merge to main — the orchestrator does that after review.

## The three prescribed hunks (from the branch's plan — these resolutions were decided when the branch was parked, waiting for doc-versions to land)
Conflicts are expected in `src/lib/server/textGeneration/builtinTools/documentTools.ts` (doc-versions changed it heavily). Resolve:

1. **`sharedPreprompt(caps)` is now a function** (doc-versions turned the preprompt string into a function): keep BOTH the versions sentence (doc-versions') and the place_text sentence (this branch's).
2. **The save name**: keep doc-versions' early `const name = savedName(source)` and pass `withSuffix(name, savedSuffix(edited))` to `storeDeliverable` — this branch's flatten-suffix logic composed with doc-versions' saved-name shape.
3. **`derived_from` / the note**: keep doc-versions' `(version N)` marker plus this branch's flattened-copy note.

Anything else that conflicts: resolve minimally and mechanically, and FLAG it in your report (the expected overlap is documentTools.ts and possibly its specs and `lookDocTool`; doc-versions also touched `conversationFiles.ts`, `deliverables.ts`, `uploadFile.ts`, `attachmentMounter.ts` — this branch should not have touched those, but check).

## Verify
- The **description budget specs** (find them — the documentTools specs pin tool-description lengths; the doc: `documentTools.spec.ts`, `documentCreateTools.spec.ts`, `lookDocTool.spec.ts`, `convertDocumentTool.spec.ts`), plus `executionPrompt.spec.ts`. Full focused run: `npx vitest run` on those files (`--project=server`).
- Gates: `npm run check`, eslint, prettier on touched files.
- **Wording**: the resolved hunks' user-facing sentences follow `docs/writing.md` — "person"/"people", never "users" (the only kept term is "power user"). This audit is C51 in the backlog.
- Heavy steps under `flock /tmp/heavy.lock` — the box has 4 cores/6 GB.
- Push once (no force). A bare branch push triggers no workflow (learned earlier today): dispatch CI yourself — `gh workflow run ci.yml --ref feat/pdf-forms-round2` — exactly ONE run, then watch it to completion (`gh run watch` / `gh run view`).
- Commits: no AI trailers (hooks reject them).

## Report back
The conflicts found and how each was resolved (hunk by hunk); any conflict outside the three prescribed ones and what you did; spec results; the CI run id and conclusion; the wording audit result.

## Outcome (2026-10-28 evening, W5)

**Merged.** `origin/main` (doc-versions: `1ef68e339` after the history rewrite; content identical to the pre-rewrite `5cf72bd17` line) merged into `feat/pdf-forms-round2`. Final merge commit `1c44014e4cb67d7c3b86e371f4c59d491d9c23c3`, pushed to origin by the orchestrator, CI green.

**Conflicts:** exactly one file — `src/lib/server/textGeneration/builtinTools/documentTools.ts`, three hunks, resolved as prescribed:

1. **Preprompt** (`~166`): the conflict was inverted from the brief's description — it was *this branch* that turned the constant into `function sharedPreprompt(caps)` (to make the place_text sentence conditional), while doc-versions had added its versions sentence to the old `SHARED_PREPROMPT` constant. Resolution keeps the function (its three call sites at doc_outline/doc_read/doc_edit survived auto-merge) with **both** sentences: doc-versions' "doc_outline lists a file's versions; \`version\` works from an earlier one." between the original-untouched sentence and the PDF sentences, then the branch's `(place ? "to write on a PDF without fields, doc_edit place_text; " : "")`.
2. **Save name** (`~830`): main's early `const name = savedName(source)` (line 784, also used by the restore path unsuffixed) kept; the branch's line dropped; `storeDeliverable` takes `name: withSuffix(name, savedSuffix(edited))`. Semantics identical to the branch's composed form; restore still saves under the plain name.
3. **derived_from / note** (`~876`): doc-versions' `${source.name} (version ${source.version})` marker + the branch's conditional note (flattened-copy sentence when `savedSuffix(edited)` is set, doc-versions' new-version sentence otherwise).

**Outside the three hunks:** nothing else conflicted. AGENTS.md, docs/office.md, `documentTools.spec.ts` and `executionPrompt.ts` auto-merged; verified by double diff (vs HEAD = main's machinery only; vs origin/main = exactly the branch's PDF delta). The branch did **not** touch `conversationFiles.ts`/`deliverables.ts`/`uploadFile.ts`/`attachmentMounter.ts` (checked, as briefed). `documentTools.spec.ts` took main's version numbering (attachment = 1, first edit = 2) alongside the branch's flatten expectations; the two fixtures (with/without place_text) compose.

**Freeze interlude:** the orchestrator froze mid-task for an owner-approved history rewrite while the merge was resolved-but-uncommitted; it was committed locally on request, then the freeze brought a C51 correction (below) and the commit was amended, then rewritten by the orchestrator to `1c44014e4` (same tree, same message, ancestry re-pointed) and pushed for me.

**Wording audit (C51) — superseded by owner correction:** the original instruction ("person/people, never users") was applied to the resolved hunks ("user's original" → "person's original" in hunk 1) plus the branch's own `pdfNote` ("unless the user asks" → "person asks", spec pin moved). The orchestrator then relayed the owner's actual 2026-10-28 decision: **"users" stays; audits must not rewrite "users" to "people"** (conflict with `docs/writing.md` is the owner's to settle). The amend restored both sentences and the spec pin to the original "user" wording; the merge message's writing.md sentence was dropped. Current text: `documentTools.ts:156` "Never `flatten` unless the user asks", `:174` "the user's original stays as it was". Flagged for the owner: `executionPrompt.ts:23` still carries base text "a PowerPoint deck whose custom visual design the user explicitly asked for" (untouched by this merge, out of audit scope).

**Verification:** the five focused spec files (`documentTools`, `documentCreateTools`, `lookDocTool`, `convertDocumentTool`, `executionPrompt`) — 5 files, **118/118 pass** under `--project=server`; plus neighbour insurance `deliverables.spec.ts` + `fileArtifacts.spec.ts` 48/48; `documentTools.spec.ts` re-run 36/36 after the wording amend. Gates: `npx prettier --check` clean on every text file of the merge; `npx eslint` clean on documentTools.ts/.spec and executionPrompt.ts; `npm run check` 0 errors / 0 warnings. Heavy steps under `flock /tmp/heavy.lock`.

**CI:** push skipped (orchestrator pushed the rewritten commit). Dispatched exactly one run: `gh workflow run ci.yml --ref feat/pdf-forms-round2` → run **40783026748** (workflow_dispatch, head `1c44014e4`), watched to completion: **completed / success** — changes ✓ 5s, go ✓ 44s, e2e-smoke ✓ 4m47s, check ✓ 12m21s, client ✓ 10m48s, documents ✓ 2m33s (e2e-full skipped as designed). Not merged to main — left for the orchestrator.
