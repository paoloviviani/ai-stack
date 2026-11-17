# Brief: the context-ring popup shows quotas only

Repo: Cerea. The orchestrator creates the worktree and gives you its path, branch, base SHA, ports and Mongo container. Run `npm ci` first.

## The change
In the `/code` composer's context-ring popup (`src/lib/components/code/ContextMeter.svelte`; the data plumbing is in `AgentComposer.svelte` and its server source), the Pystino section currently lists every consumption entry.
- **Show only the quotas:** each quota the user is subject to, with its used amount against the limit and its reset or period, as a compact bar or a fraction. `src/lib/components/settings/UsageBar.svelte` may already fit; reuse it if it does.
- **Drop the per-entry consumption list.**
- **No quotas:** show a single muted line, "No quotas".
- **Keep the context-window part** of the popup as it is.
- **Chat:** check whether chat's ring or usage popup has the same per-entry list, and apply the same rule there if so. Report either way.
- If the server response carries the per-entry list only for this popup, stop fetching or sending it. Keep any other consumer working.

## Tests
- A component or vitest test for the quota rendering: several quotas (used/limit and period shown), none ("No quotas"), and no per-entry rows.
- A Playwright check on the popup (the existing `tests/code-context-meter.spec.ts` is the place) at root and under `E2E_APP_BASE=/chat`.
- `npm run check` (0 errors); eslint and prettier on the changed files. Then the touched specs at both bases, after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`.

## Box rules (mandatory)
- Wrap EVERY heavy command (npm ci, build, check, playwright, vitest) in `flock /tmp/heavy.lock …`. If `free -m` shows under 1.5 GB available, wait. Pause heavy jobs whenever the orchestrator says so.
- Kill only the processes you start, by recorded PID. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199.
- Write nothing to `/tmp`.
- No sub-agents.
- Never deploy. **No live checks or enrollments against cerea.example.org.** Don't touch docker volumes or `/home/ubuntu/test/`.
- No new dependencies without asking. Cite ADRs by number only.
- **Commits:** descriptive subjects, no "WIP:" on main.
  - **No `Co-Authored-By: Claude` trailer, ever.** A commit-msg hook rejects it; don't bypass it.
  - Before pushing, run `git fetch origin` and check that `git log origin/<branch>..<branch>` lists only your commits.
  - Push the branch; DON'T merge to main.

## Report
Reply with:
- the commits;
- what changed, including the chat finding;
- the test commands and pass counts at both bases;
- a screenshot path of the popup with quotas and with none.
