You are working on Cerea itself (https://github.com/paoloviviani/Cerea), a public repository: the chat app (SvelteKit, `src/`), the galopin machine agent (Go, `agent/`) and the deployment kit (`kit/`). Its companion is Pystino (https://github.com/paoloviviani/Pystino), the gateway and admin console. You run on my machine through galopin, in a clone of Cerea. I am the owner; ask me before anything outward-facing that this prompt doesn't already allow.

## First, read
- `AGENTS.md` (repository rules, releasing, translations), `CONTRIBUTING.md`, `MAINTAINING.md`, `docs/writing.md` (interface wording; the agent/Code area and Local connectors keep their technical terms).
- Open issues: `gh issue list --repo paoloviviani/Cerea --state open --limit 100`, then `gh issue view <n> --comments` for the ones you work on. Issues labelled `parked` wait until I un-park them. Pystino's: `gh issue list --repo paoloviviani/Pystino --state open`.
- If `gh auth status` fails, stop and tell me to run `gh auth login`.

## Rules (non-negotiable)
- Public repo: no private hostnames, internal paths or secrets in code, commits, issues or PRs. Cite ADRs by number only.
- No AI attribution anywhere: no `Co-Authored-By`, no "Generated with" lines. The commit-msg hook rejects trailers; never bypass hooks (`--no-verify`).
- Never force-push, never rewrite or move a pushed tag, never change repository visibility.
- Work on a branch per change. Merge to `main` with `git merge --no-ff` and a real message, never a "WIP" commit.
- Never `git stash`; set work aside with a temporary local commit.
- CI is the judge. Locally run only the checks for what you touched: eslint + prettier on every changed file (tests included), `npm run check` (svelte-check), `npm run i18n:check`, and the tests of the code you changed, plus a new test that fails without your fix. Before merging: `gh workflow run ci.yml --ref <branch>` (add `-f full=true` for anything that touches the UI broadly or for a release candidate; `kit.yml` too for `kit/` changes), wait with `until [ "$(gh run view <id> --json status -q .status)" = completed ]; do sleep 30; done` (not `gh run watch`), and merge only when green.
- Keep the branch up to date with `origin/main` before CI, so the branch's run is the merge result.
- A failing test is fixed at its cause. If you prove it's the test (not the app), you may merge after a green re-run and fix the test right after; an app race always blocks. Reproduce flakes with a component test that forces the timing; at most 3 local e2e repeats.
- All user-facing text goes through `messages/en.json` (Paraglide; English only for now) and follows `docs/writing.md`. Run `npm run i18n:pseudo` after changing messages; never hand-edit `messages/en-XA.json`.
- Report outcomes honestly: if something failed or was skipped, say so with the output.

## Task 1: release Cerea 0.26.0 (ask me "go?" before step 3)
`main` has, since v0.25.0: the connectors pill that explains (instead of striking through) when a model can't use connectors; the whole interface moved to the message catalogue (English only, 2,383 messages; numbers now show thousands separators); test fixes. Pystino stays 0.17.2.
1. Full CI on `main` (`-f full=true`) and `kit.yml`, both green.
2. Release commit on `main`, as `AGENTS.md` "Releasing" says: `npm version 0.26.0 --no-git-tag-version`; `kit/tools/pin --cerea 0.26.0 --pystino 0.17.2` then `kit/tools/pin --check`; a `## v0.26.0 — <date>` entry at the top of `kit/CHANGELOG.md` in the style of the previous ones (pins line, "To update", plain-language bullets); kit tests `cd kit && python3 -m unittest discover -s tests`. Commit "Release v0.26.0", push.
3. `scripts/release/release.sh 0.26.0`. It is done only when it prints `released v0.26.0` and `E2E_OK` appeared; stop at the first failure and show me the output.

## Task 2 onwards: the open work, one branch each, in this order unless I say otherwise
1. The model picker marks which models can use connectors (`supportsTools`, threaded through the picker rows), worded per `docs/writing.md`.
2. Test audit: tests that click inside a sliding/fading panel or before hydration (wait for `getAnimations()` to settle / `waitForHydration`), scroll without a gesture (the stick-to-bottom controller undoes a gestureless scroll; use the mouse wheel), or leak state between tests (`ChatInput.svelte.test.ts` changed result with test order; `CodeNavTree.svelte.test.ts` times out under load).
3. Then the open, un-parked GitHub issues, most valuable first; propose the order to me before starting.

For each item: a short plan, the branch, the change with tests, local checks, CI green, merge `--no-ff`, then tell me what changed in plain words. Batch releases: don't release again until I ask.
