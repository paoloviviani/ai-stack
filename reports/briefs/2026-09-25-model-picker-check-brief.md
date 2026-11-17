# Brief: the model picker checks the active model on first open (/code and chat)

Repo: Cerea. The orchestrator creates the worktree and gives you its path, branch, base SHA, ports and Mongo container. Run `npm ci` first.

## The bug
In the `/code` composer's model picker (`src/lib/components/code/AgentComposer.svelte`), the currently selected model (e.g. glm-5.3-flash) shows no checkmark when the dropdown first opens; its row has an empty space where the check should be. This happens at least when the model came from the default rather than an explicit choice.
- Show the check on the active model on first open, including when it's the default: the agent snapshot's model, or the machine's or deployment's default when the session has none. Match by the same id the pill's label uses; beware provider-prefixed vs bare ids, e.g. `pystino/glm-5.3-flash` vs `glm-5.3-flash`.
- Exactly one row checked; no row checked only when the active model truly isn't in the list, and then the pill still names it.
- **Chat:** check chat's picker (`src/lib/components/chat/ModelPicker.svelte` / `ModelEffortPicker.svelte`) for the same bug, including a new conversation that uses the default model, and fix it there too if so. Report either way.

## Tests
- A component or vitest test for the matching (default model, explicit choice, prefixed and bare ids).
- Playwright: open the `/code` picker on a fresh agent (the default model) and on one with an explicit choice, and assert the check is on the right row. Do the same for chat's picker. The existing `tests/code-composer.spec.ts` / `tests/chat-model-picker.spec.ts` are the places.
- `npm run check` (0 errors); eslint and prettier on the changed files. Run the touched specs at root and under `E2E_APP_BASE=/chat`, after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`.

## Box rules (mandatory)
- Wrap EVERY heavy command in `timeout -s KILL <secs> flock /tmp/heavy.lock …` (e.g. 1500 for a build or a Playwright run, 300 for a vitest file). Always pass `TEST_MONGODB_URL` to vitest, and the `E2E_*` exports to Playwright, on the same command line. Without them the harness falls back to mongodb-memory-server, which can't run on this box.
- If `free -m` shows under 1.5 GB available, wait. Pause heavy jobs whenever the orchestrator says so.
- Kill only the processes you start, by recorded PID. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199.
- Write nothing to `/tmp`.
- No sub-agents.
- Never deploy; no live-stack changes.
- Don't touch sign-in, OIDC or user identity; that work is on hold by user decision.
- No new dependencies without asking.
- **Commits:** descriptive subjects, no "WIP:" on main, and **no `Co-Authored-By: Claude` trailer** (a commit-msg hook rejects it). Before pushing, run `git fetch origin` and check that `git log origin/main..HEAD` lists only your commits. Push the branch; DON'T merge to main.

## Report
Reply with:
- the commits;
- the cause, plus the chat finding;
- the test commands and pass counts at both bases;
- a screenshot path of each picker with the check.
