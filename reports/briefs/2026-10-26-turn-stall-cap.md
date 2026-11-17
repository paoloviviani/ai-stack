# Brief: a turn can never run forever (Cerea, fix for 0.30.1)

## The bug
A chat turn on the owner's deployment stayed `status: "running"` for over an hour with a **live heartbeat**, so the sidebar's blue dot never cleared and the reaper (which only reaps stale heartbeats, `src/lib/server/generation/reaper.ts`) never touched it. It happened at a moment of peak load: another chat was answering and an Office preview was being made.

The diagnosis, from reading the code:
- every other wait in a turn already has a deadline: MCP tools (`MCP_TOOL_TIMEOUT_MS`), `execute_code` (`CODE_EXECUTION_DEADLINE_MS`), the document client, Gotenberg (`CONVERT_TIMEOUT_MS`), and nested agents (`NESTED_CALL_TIMEOUT_MS` 120 s, 8 min overall);
- **the main turn's model calls have none.** The `new OpenAI({...})` in `src/lib/server/textGeneration/mcp/runMcpFlow.ts` (about line 639) and the one in `src/lib/server/endpoints/openai/endpointOai.ts` (about line 105) set no `timeout`. The SDK's timeout only covers the wait for response headers. Once a stream has started, a stream that stops sending without closing is awaited forever;
- the heartbeat (`writer.ts` setInterval) keeps beating while the turn hangs, and nothing caps a turn's total time.

## What to build (branch `fix/turn-stall-cap` from `origin/main`)
1. **Stream idle watchdog.** Wherever the main turn iterates a streamed completion: the tool loop in `runMcpFlow` (including the no-tools rescue call) and `endpointOai`'s streaming paths (completions and chat completions).
   - Bound the gap between chunks: `CHAT_STREAM_IDLE_TIMEOUT_MS`, default 300000 (5 min).
   - The gap before the first chunk counts too: slow reasoning models are silent at first, which is why the default is generous.
   - On expiry, abort the underlying request (its own AbortController, chained to the turn's signal with `AbortSignal.any` or similar) and throw an error the person reads: "The model stopped responding, so this answer was stopped. Try again."
   - Write it as one small reusable helper, for example `src/lib/server/textGeneration/utils/idleTimeout.ts`, wrapping an `AsyncIterable` plus the abort. The same helper should be usable by `nestedAgent.ts` later; don't change nestedAgent now.
   - Also set the OpenAI client's `timeout` (wait for headers) to the same value, so a request that never answers doesn't sit for the SDK default of 10 min × 3 attempts.
2. **A hard cap per turn.**
   - In `src/routes/conversation/[id]/+server.ts`, where `ctrl` is created (about line 481): a timer of `CHAT_TURN_MAX_MINUTES` (default 30) that calls `ctrl.abort(new TurnTimeoutError())`. Clear it everywhere the turn ends (next to `clearInterval(abortMarkerWatcher)`), with `unref`.
   - The catch block must tell this abort apart from the person's Stop: check `ctrl.signal.reason instanceof TurnTimeoutError`. A timeout is an **error** status: the message "This answer took longer than N minutes and was stopped.", the generation finished as `error`, and `turnEnded` failed. A Stop stays `interrupted`, as now.
   - Whatever was streamed so far stays in the message.
   - A parked turn (an approval or a question) ends the stream, and the resume is a new run with its own cap. Confirm in the code that this holds, and say so in a comment.
3. **Configuration.** Read both variables through `config` like the neighbouring ones, with sane minimums (idle at least 30 s, cap at least 1 min; invalid or empty means the default). Document them in `.env` near `MCP_TOOL_TIMEOUT_MS`, in the kit's env reference if one lists chat variables (grep `kit/` for `CHAT_CODE_RUN_TIMEOUT_SECONDS` and follow the same pattern), and a short paragraph in `docs/` where turn limits or operator variables are described (grep for `CHAT_CODE_RUN_TIMEOUT_SECONDS`).
4. **Tests** (server project). Each must fail without its fix: check with `git restore --source=HEAD -- <file>` on a temporary copy, as AGENTS.md describes. **Never `git stash`.**
   - the idle helper: an iterator that yields, then hangs; expect the error and the abort fired. Use fake timers or tiny timeouts;
   - the helper passes chunks through untouched and does nothing when chunks keep coming;
   - the turn cap: test the decision ("timeout abort means an error status with the message; a user abort means interrupted") through whatever seam is cleanest. Extract a small function if the route is too big to test directly.
5. Changelog: add lines under an `## Unreleased` or the pending `v0.30.1` section of `kit/CHANGELOG.md` **only if** one exists on main; otherwise put the wording in your report and the orchestrator adds it.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-turn-cap -b fix/turn-stall-cap origin/main`. `export TMPDIR=/var/tmp/turn-cap-tmp && mkdir -p $TMPDIR`.
- Never `git stash`, never `--no-verify`, never force-push. No AI attribution in commits. No private hostnames or paths in the repo (it is public).
- Checks: `npm run check`, eslint and prettier on **every** changed file (tests included), and the server tests for the files you touched plus the existing route/generation specs (`src/lib/server/generation`, `src/lib/server/textGeneration`). No Playwright, no full suites: CI runs them. Builds or docker only under `flock /tmp/heavy.lock`.
- Push the branch and run CI once: `gh workflow run ci.yml --ref fix/turn-stall-cap`. Wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done` and report the result. Don't merge.
- Report: what changed (files), the test-fails-without-fix evidence, the CI run id and result, and the changelog wording.
- The box has 4 cores and 6 GB: don't leave dev servers running, and don't touch galopin, `~/.config/galopin` or `cerea-test-mongo`.
