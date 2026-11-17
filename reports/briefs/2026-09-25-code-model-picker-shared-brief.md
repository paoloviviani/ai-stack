# Brief: the /code composer uses the chat's model and effort picker

Repo: Cerea. The orchestrator gives you the worktree, branch, base SHA, ports and Mongo in the launch message. Run `npm ci` first.

## The change
The user likes the chat's model selector and wants the same in the `/code` agent composer.
- **Replace the /code pickers.** `src/lib/components/code/AgentComposer.svelte`'s own model dropdown and its separate Effort pill give way to the chat's components: `src/lib/components/chat/ModelEffortPicker.svelte` for the pill, plus `ModelPicker.svelte` if the chat opens it for the full list. Same look, same interaction, same checkmark behaviour (`src/lib/utils/activeModel.ts`, `resolveActiveModel`).
- **The data stays the agent's:**
  - the model list is the machine's session models (what AgentComposer loads today);
  - the per-session model and effort are set through the existing agent APIs (`src/lib/codeApi.ts`: the model and effort calls AgentComposer already uses);
  - models without effort levels behave as they do in chat.
- **Shared layer, not a fork.** If the chat components are coupled to chat-only types or stores (conversation settings, the chat model list), extract a thin shared layer: props for `models`, `activeId`, `efforts`, `activeEffort`, and `onselect`/`oneffort` callbacks. Chat and /code each adapt their data to it. Chat's behaviour must not change.
- **Keep the layouts:** the mobile composer's compact behaviour (below `sm`: one row, compact pills, truncation) and the one-row desktop layout, both merged earlier.
- **Keep the /code-only bits** (the machine-policy veto on free models, "N non-gateway models hidden…", the loading and failure notes), inside or beside the shared picker.

## Tests
- Update `tests/code-composer.spec.ts` and the /code model and effort tests at root and under `E2E_APP_BASE=/chat`. Keep `tests/chat-model-picker.spec.ts`, `tests/composer-mobile.spec.ts` and `tests/code-context-meter.spec.ts` passing.
- vitest for any extracted shared logic.
- `npm run check` (0 errors); eslint and prettier on the changed files. Then the touched specs at both bases, and the whole suite once at each base, after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`.
- **Screenshots:** the chat picker and the /code picker, open, side by side at desktop, plus the /code one at 390×844.

## Box rules (mandatory)
- Wrap EVERY heavy command in `timeout -s KILL <secs> flock /tmp/heavy.lock …`.
- Always pass `TEST_MONGODB_URL` to vitest and the `E2E_*` exports to Playwright, on the same command line. Without them the harness falls back to mongodb-memory-server, which can't run on this box.
- If `free -m` shows under 1.5 GB available, wait. Pause heavy jobs whenever the orchestrator says so.
- Kill only the processes you start, by recorded PID. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199.
- Write nothing to `/tmp`.
- No sub-agents.
- Never deploy. No live checks.
- Don't touch sign-in, OIDC or user identity.
- No new dependencies without asking.
- **Commits:** descriptive, **no `Co-Authored-By: Claude` trailer** (a hook rejects it). Before pushing, run `git fetch origin` and check that `git log origin/main..HEAD` lists only your commits. Push the branch; DON'T merge to main.

## Report
Reply with:
- the commits;
- what you shared vs adapted, and why;
- the test commands and pass counts at both bases;
- the screenshot paths.
