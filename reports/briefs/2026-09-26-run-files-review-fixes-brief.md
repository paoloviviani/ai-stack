# Brief: review fixes for "every produced file is a file artifact" (fix/all-run-files-are-artifacts)

Repo: Cerea. You work on `fix/run-files-review`, cut from the head of `fix/all-run-files-are-artifacts` (`ecc5af85`), in `/home/ubuntu/.paseo/worktrees/runfiles-cerea`. The orchestrator gives you ports and Mongo in the launch message. Run `npm ci` first.

Read the branch's own design first: `src/lib/utils/execution/runFiles.ts`, `src/lib/server/execution/runFiles.ts` (`withRunFiles`), `src/routes/conversation/[id]/code-execution/run-files/+server.ts`, `src/lib/stores/runFiles.svelte.ts`, `src/lib/utils/execution/messageContext.ts`, and the changes in `CodeBlock.svelte`, `ChatMessage.svelte`, `ArtifactPanel.svelte`, `ChatWindow.svelte` and `fileArtifacts.ts`.

## Findings to fix
1. **Files recorded under a message id the server never saves (the real bug).**
   - While a turn streams, the assistant message in the client carries a **client-minted id** (`addChildren` → `v4()` in `src/routes/conversation/[id]/+page.svelte`). The server saves the message under **its own** `v4()` id (`src/routes/conversation/[id]/+server.ts`), and the client only switches to the server's id when the page re-syncs `data.messages` after the stream ends (the `finally` invalidate).
   - CodeBlock's effect reads `ctx.messageId` when a run settles. An auto-run that settles after `loading` flips false but before that sync (a quick run with Pyodide already warm) records the files under the **client id**: `withRunFiles` then never matches it, and the file is gone after a reload.
   - Worse, `runFiles.claim(\`${runKey}@${startedAt}\`)` is tab-wide, so once the id swaps to the server's, no second attempt happens. ArtifactPanel's cell path has the same race (`version.messageId`).
   - **Fix, both sides:**
     - **Server:** the run-files route **refuses a messageId that isn't on the conversation** (409, "message not saved yet"), instead of accepting it, so no orphan records can exist. Keep the refusal of a non-assistant message.
     - **Client:** include the message id in the claim key (`${messageId}|${runKey}@${startedAt}`). On a 409 or any failure, **release the claim** (add a `release` to the store) so the effect retries once the message carries the server's id. The effect must re-run when `ctx.messageId` changes (the getter must be reactive) and when `canPersist` flips.
     - Also consider gating `canPersist` off for the message currently being generated (`isLast && loading`, or whatever the page exposes until the post-stream sync lands). Choose what's robust, and state it.
     - Uploading the **bytes** early is fine: they're content-addressed per conversation, and a repeat upload returns the existing ref. Only the **record** must wait for the real id.
   - **Required by the branch owner:** the run must get **recorded under the server id once the message syncs**. The effect re-runs on the `messageRun.messageId` change, uploads again (a dedupe hit) and records under the new id. **Test the sequence:** a run settles under client id A → the record gets a 409 → the context's messageId becomes the server id B → exactly one successful record under B, no duplicate. Also assert, through `collectFileArtifacts(withLiveRunFiles(...))`, that an orphan client-id entry in the live `runFiles` store doesn't add a second artifact version.
2. **ArtifactPanel records a partial file list.** CodeBlock waits for `state.outputsCollected` before uploading ("the file listing lands after the outcome"); ArtifactPanel's cell effect doesn't, so it can claim, and upload, a partial list, and the claim then blocks the rest. Wait for `outputsCollected`, as CodeBlock does.
3. **ArtifactPanel's gating.** `canPersistFiles={!shared && !isReadOnly}` lacks the author check ChatMessage applies (`isAuthor`). The server refuses a non-owner anyway (`authCondition`), but make the client gate match: the owner's own `/conversation/[id]` page only, as ChatMessage's `canPersist`.
4. **Bound the records.** `codeRunFiles` has no per-conversation cap. Refuse new records past a sensible cap per conversation (e.g. 1,000, answering 429 or 400 with a clear message); an idempotent re-record of an existing record still succeeds.

## Tests
- **Route spec** (`run-files.spec.ts`): an unknown messageId → 409, with no record written; the cap is enforced; an idempotent re-record still succeeds at the cap.
- **Component or unit tests:**
  - CodeBlock records under the message id it has once the id changes (simulate the swap: a settled run under id A with the record refused, then the context id becomes B → one record under B);
  - the claim is released on failure;
  - ArtifactPanel waits for `outputsCollected`.
- **Playwright:** the existing "a code block's file is a file artifact too, and comes back after a reload" keeps passing. If you can make the race deterministic (e.g. delay the post-stream sync in the test, or a warm runtime with a fast run), add a case where the run settles before the sync and the file still survives a reload.
- `npm run check` (0 errors); eslint and prettier on the changed files. Run the touched specs at both bases, then **the full suite once at root and once under `/chat`** (the /chat full run hasn't been done for this branch), after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`.

## Box rules (mandatory)
- `timeout -s KILL <secs> flock /tmp/heavy.lock …` in the foreground, with the `E2E_*` and `TEST_MONGODB_URL` exports on the same line.
- If `free -m` shows under 1.5 GB available, wait; pause when told.
- Kill only your own processes, by PID. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199. Nothing in `/tmp`.
- No sub-agents, no deploy, no live checks.
- Don't touch sign-in, OIDC or user identity.
- No new dependencies.
- **Commits:** as Paolo Viviani from git config (never override it), with no `Co-Authored-By` trailer. Before pushing, `git fetch` and check that `git log origin/fix/all-run-files-are-artifacts..HEAD` lists only your commits. Push `fix/run-files-review`; don't merge, and don't push to `fix/all-run-files-are-artifacts` or main.
- **The disk is tight:** when done, delete the worktree's `build/`, `test-results/` and `playwright-report/`.

## Report
Reply with:
- per finding, what you changed and why (including your `canPersist` gating choice);
- the commits;
- the test commands and pass counts, with the full suite at both bases.
