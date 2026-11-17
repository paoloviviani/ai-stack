# Brief: auto-run a code block that first appears in the current live turn, even if it arrives all at once in the final answer

Repo: Cerea. The orchestrator gives you the worktree, branch (off main), ports and Mongo in the launch message. Run `npm ci` first. **A fix, wave scope: nothing beyond this.**

## The bug (live, Cerea 17c4af9f)
Auto-run failed in 5 of 7 live attempts. The cause, from a captured stream:
- with the live model (glm-5.3-flash via the gateway), only the *thinking* streams token by token;
- the visible answer, **code fence included, arrives in the single final update**;
- so the block is never rendered while `loading`, never gets the "seen streaming" mark, and never auto-runs.

Today's mechanism: `CodeBlock.svelte` marks `runsStore.markSeenStreaming(conversationId|runKey)` while `loading`, and auto-runs when `autorun && !loading && hasSeenStreaming(...)`. The mark lives in the tab-wide runs store (`src/lib/utils/execution/runs.svelte.ts`), because `MarkdownRenderer.svelte` re-keys a fence at settle (`stream-${index}` → `block.id`), remounting CodeBlock.

## Goal
Auto-run fires for a code block that **first appears in the current live turn this tab is generating**, whether it streamed in or arrived whole in the final answer.

Keep every guarantee, each tested:
- it runs **once**;
- it **never runs twice** after a remount;
- it **never runs for history blocks** on reopen or reload;
- it **never crosses conversations** (the mark stays scoped by conversation);
- Run, the manual path, is unchanged.

**One design to consider:** mark the blocks of the message *the tab itself was generating* when that turn settles. For example, the conversation page knows which assistant message it's writing (`messageToWriteTo`, the `loading` state), so the settled message's fences get marked by conversation + runKey (or the message id at that point) before or when CodeBlock checks. Choose the design; make it robust to:
- the message id swapping from client-minted to the server's at the post-stream sync (see the run-files review: the claim and record use the id, but the auto-run mark shouldn't depend on the swap);
- a retry or a continue of an older message (a regenerated message counts as live);
- the fence re-keying at settle.

**Not live** (must not auto-run): a message loaded from history, one arriving via another tab or device, or a shared view.

## Tests
- A test that **fails on the current code:** a turn whose content (the code fence) arrives only in the final update, with no streamed tokens of the answer → the block auto-runs exactly once. Component or unit level (CodeBlock/ChatMessage with the runs store), and ideally a Playwright case where the mock OpenAI server sends the answer in one chunk. `tests/mock-openai.ts` can script chunking; check its options.
- The existing auto-run tests still pass: it streamed in and runs once; a history block stays inert; a remount doesn't run twice; no crossing conversations.
- A reload of the conversation afterwards doesn't re-run.
- `npm run check` (0 errors); eslint and prettier on the changed files.
- Playwright: the touched specs plus the artifact specs (`chat-artifact-files`, `chat-artifact-math`, `chat-artifact-table`, `chat-artifact-tool`) and the terminal specs (`code-terminal`, `code-terminal-mobile`), at root AND under `E2E_APP_BASE=/chat`, after an explicit build per base, with `E2E_SKIP_BUILD=1 … --project=chromium`.

## Box rules (mandatory)
- EVERY heavy command runs as `timeout -s KILL <secs> flock /tmp/heavy.lock …`, **in the foreground** (never background mode), with a timeout longer than the job: 1500 for a build, 1800 for Playwright. Put the `E2E_*` and `TEST_MONGODB_URL` exports on the same command line.
- If a run is cut off, kill your own leftover Playwright and Chromium processes by PID.
- If `free -m` shows under 1.5 GB available, wait.
- Kill only your own processes. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199. Nothing in `/tmp`.
- No sub-agents, no deploy, no live checks.
- Don't touch sign-in, OIDC or user identity.
- No new dependencies.
- **Commits:** as Paolo Viviani from git config (never override it), with no `Co-Authored-By` trailer. Before pushing, `git fetch` and check that `git log origin/main..HEAD` lists only your commits. Push the branch; don't merge.
- **The disk is tight:** when done, delete the worktree's `build/`, `test-results/` and `playwright-report/`, and any probe specs you added (never commit a probe).

## Report
Reply with:
- the design and why it's robust to the id swap, retry and continue, and re-keying;
- the commits;
- the failing-then-passing test;
- the test commands and pass counts at both bases.
