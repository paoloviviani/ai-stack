# Brief: agent panel keeps its machines and sessions between visits; no sidebar flash (Cerea 0.32.1)

## What the owner sees
Every time they go to the agent panel (`/code`), the machines and sessions list is reloaded from scratch. The sidebar visibly refreshes and "flashes": it empties or shows a loading state, then fills again. The owner asks to keep the list for a while and refresh only as needed.

## What to do (branch `fix/agent-panel-cache` from origin/main)
1. **Find what reloads.** Start in `src/routes/code/`, `src/lib/components/code/` and the stores `codeDeviceList.svelte.ts`, `codeNav.svelte.ts`, `codeLegacyMachines.svelte.ts` and `agentTranscriptCache.ts`. Find out what drops and refetches the list on each visit:
   - a store created per mount;
   - a `load` function with no reuse;
   - `{#key}` or `{#if loading}` blocks that empty the sidebar;
   - an SSE or WebSocket subscription that resets state on reconnect.

   Measure it: the requests per visit, and what the sidebar renders in between.
2. **Keep the list across visits, and refresh in the background** (stale-while-revalidate):
   - a module-level store holds the last machines and sessions list for the browser session;
   - returning to `/code` renders it at once, with no loading state and no empty frame;
   - a refresh runs in the background only when the cached list is older than a short interval (e.g. 30-60 s; pick and justify it), or when something says it changed;
   - the refresh **reconciles in place**: rows are keyed by id, so unchanged rows don't re-render or reorder, and nothing flashes.
3. **"As needed" means:**
   - events the panel already receives (a machine going online or offline, a session starting, finishing or being renamed, a schedule firing) update the cached list directly;
   - the focus or visibility change, and a manual refresh if one exists, trigger a revalidation;
   - creating, deleting or renaming a session, or enrolling or removing a machine, from this browser updates the cache immediately.
4. **Correctness:**
   - the cache is per user: clear it on sign-out, as the composer drafts are cleared (see how `drafts cleared on sign-out` was done), and on a user switch;
   - never show another account's machines;
   - a failed refresh keeps the cached list and shows the existing error affordance, not an empty list;
   - the existing re-auth flow (`codeReauth`) still works.

## Tests (each fails without its fix)
- Visiting `/code`, leaving, and returning within the interval: no second list request, and the sidebar never renders empty or loading in between.
- Returning after the interval: the cached list renders at once, and the background refresh updates one changed row without re-rendering the others (check by DOM node identity or a render counter).
- Sign-out clears the cache.
- A failed refresh keeps the list.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-agent-cache -b fix/agent-panel-cache origin/main`. `export TMPDIR=/var/tmp/agent-cache-tmp && mkdir -p $TMPDIR`. Read AGENTS.md first.
- Other workers are on fix/connectors-admin-edit and fix/composer-draft-sticks. Don't touch their files: the connector UI, ChatInput and the drafts. If you need the sign-out hook the drafts use, reuse it without changing it.
- `npm ci`, builds and Playwright run under `flock /tmp/heavy.lock`; never wrap a self-locking script in another flock. The Playwright container runs as root: chown back `node_modules`, `src` and `.svelte-kit` with a throwaway container before `npm run check`. Bind to 127.0.0.1, and kill what you start.
- Never git stash, never --no-verify, never force-push, no AI attribution in commits.
- Checks: `npm run check`, eslint and prettier on the changed files, and the `src/lib/components/code` and `src/lib/stores/code*` client tests in the container.
- A short screen recording or a before/after frame sequence of returning to `/code`, in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-27-agent-cache/`. Look at it yourself.
- Push and run CI once (`gh workflow run ci.yml --ref fix/agent-panel-cache`). Wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report: the cause, the design (the interval, what triggers a refresh), the fails-without-fix proof, the frames, and the CI result. No sub-agents.
