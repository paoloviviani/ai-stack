# Brief: three live follow-ups on "every produced file is a file artifact" (Cerea 702ec822, live)

Repo: Cerea. The orchestrator gives you the worktree, branch (off main), ports and Mongo in the launch message. Run `npm ci` first. **Nothing beyond these three items.**

Background: `702ec822` made every file a run produces a persisted file artifact.
- **Shared upload path:** `src/lib/utils/execution/runFiles.ts` (`uploadRunFiles`, `recordRunFiles`).
- **Storage:** records in `codeRunFiles`, via `src/routes/conversation/[id]/code-execution/run-files/+server.ts`, which refuses an unsaved message id with a 409. They're served by `withRunFiles` (`src/lib/server/execution/runFiles.ts`) as `CodeExecution/Outputs` updates.
- **Client:** the persist effects in `CodeBlock.svelte` and `ArtifactPanel.svelte` (claim `messageId|runKey@startedAt`, released on failure); ChatMessage's `canPersist` (skips `isLast && loading`); `collectFileArtifacts`/`withLiveRunFiles` in `src/lib/utils/fileArtifacts.ts`; `CodeExecutionCard.svelte` now uses `uploadRunFiles`.

Observed on the live stack:

## 1. After a reload, the inline file card shows the size but no filename (a real bug: fix and test)
The file came from an auto-running code block (a docx), so after the reload it was most likely served back through the `codeRunFiles` → `CodeExecution/Outputs` path, and CodeBlock's `storedState` builds the `persistedFiles` RunOutput/FileCard renders.
- Find where the name is lost: the record the route stores (`files: {name,size,sha256}`, rebuilt from `codeExecutionOutputs` rows), `withRunFiles`, `storedState`'s mapping, or the field FileCard/RunOutput actually reads for the name (e.g. `path` vs `name`).
- Fix it, and add a test that fails on the old code: a component test of the replayed block, and/or a Playwright assertion that the card shows the filename after a reload (extend `tests/chat-artifact-files.spec.ts`'s reload case).

## 2. The execute_code resume posted `/code-execution` twice; the second answered 409 (a console error only)
- Find out whether it's ours:
  - the new 409 path (the run-files route);
  - CodeExecutionCard's changed upload/persist code double-firing (a remount, an effect re-run, a missing guard);
  - or pre-existing behaviour of the execute_code resume route (`src/routes/conversation/[id]/code-execution/+server.ts`) answering 409 to an already-resolved call.
- Check which URL got the 409 (the resume POST vs run-files) and trace it. Compare with main before `702ec822` (`git log`, `git show 7a691d78:<file>`) to see whether the double-post predates this wave.
- If it's ours, fix it (one post per resume) and add a test. If it's pre-existing or benign, explain precisely, and change nothing.

## 3. A code block didn't auto-run within 2 minutes (Run worked)
- Check whether this wave's changes could affect auto-run: CodeBlock's new persist effect, the claim, `canPersist`, or ChatMessage's `!(isLast && loading)` gate. Note that auto-run is triggered separately in CodeBlock (`if (!autorun || !sawStreaming || loading || !runsStore || !runKey) return; runsStore.run(...)`).
- If the wave caused it, fix it with a test. If it's unrelated (e.g. `sawStreaming` or `loading` semantics, cold Pyodide, a model that didn't mark the block to auto-run), or intended, **say so and don't change auto-run behaviour.**

## Tests and verification
- `npm run check` (0 errors); eslint and prettier on the changed files; the touched vitest files.
- Playwright: the touched specs plus the artifact specs (`chat-artifact-files`, `chat-artifact-math`, `chat-artifact-table`, `chat-artifact-tool`) and the terminal specs (`code-terminal`, `code-terminal-mobile`), at root AND under `E2E_APP_BASE=/chat`, after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`.

## Box rules (mandatory)
- EVERY heavy command runs as `timeout -s KILL <secs> flock /tmp/heavy.lock …`, **in the foreground** (never background mode), with a timeout longer than the job: 1500 for a build, 1800 for these Playwright runs. Put the `E2E_*` and `TEST_MONGODB_URL` exports on the same command line.
- If a run is cut off, kill your own leftover Playwright and Chromium processes by PID.
- If `free -m` shows under 1.5 GB available, wait.
- Kill only your own processes. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199. Nothing in `/tmp`.
- No sub-agents, no deploy, no live checks.
- Don't touch sign-in, OIDC or user identity.
- No new dependencies.
- **Commits:** as Paolo Viviani from git config (never override it), with no `Co-Authored-By` trailer. Before pushing, `git fetch` and check that `git log origin/main..HEAD` lists only your commits. Push the branch; don't merge.
- **The disk is tight:** when done, delete the worktree's `build/`, `test-results/` and `playwright-report/`.

## Report
Reply with, per item:
- the finding (root cause, with file and line);
- the fix, or why there's none;
- the commits;
- the test commands and pass counts at both bases.
