# Brief: W6 — CI backstop against AI-attribution trailers (2026-10-28 evening)

## Task
On branch `ci/reject-ai-trailers` (worktree `/home/ubuntu/workspace/wt-trailer-ci`, fresh from `origin/main`): make CI reject AI-attribution trailers in commit messages, factoring the regex into one shared script used by both the husky hook and CI. Implement, test locally, push once, exactly one CI run (dispatched), watch it. Do NOT merge — the orchestrator merges after the 0.32.4 release.

## Context
Three commits on today's main carried trailers (`Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, `Claude-Session: https://claude.ai/code/session_…`). The husky `commit-msg` hook (added 2026-10-08) exists in every tree, but the hook only runs where the generated `.husky/_` shims exist — husky's `_` is created per-checkout by its install and is not committed, so worktrees that never ran the install have `core.hooksPath = .husky/_` pointing at an empty directory and git silently runs no hook. On this box the shim was missing in `wt-doc-versions` (where the three commits were made), `Cerea-wt-merge` and `wt-maps-skill2`. The owner wants CI as the backstop (it sees every commit, whatever the local hook state).

## Build
1. Extract the regex from `.husky/commit-msg` into ONE shared script (e.g. `scripts/check_no_ai_trailers.sh`, executable, taking the path of a file with the message(s)): the exact current pattern, case-insensitive —
   `Co-Authored-By:.*(claude|anthropic|openai|gpt|gemini|copilot)|Claude-Session:|claude\.ai/code|noreply@anthropic\.com|Generated with \[?(Claude|opencode`.
   The hook calls the script with `$1` and keeps its current error text and exit behaviour byte-for-byte.
2. In `.github/workflows/ci.yml` add a step, on push and pull_request, that checks the commits NEW to the event:
   - push: the range `<before>..<sha>` (guard the create-branch case where `github.event.before` is all zeros: use the merge-base with the default branch, or the whole pushed range);
   - pull_request: `<github.event.pull_request.base.sha>..<github.sha>`.
   Feed each commit's full message separately (`git log <range> --format=%B` per commit, or concatenate with unmistakable separators such as a line of `=` so a trailer cannot hide across a message boundary) into the shared script; the step fails on a match.
3. Local verification (no CI needed for this part): run the script against (a) a clean message; (b) each of the three old offender messages — fetchable by SHA from GitHub if the objects are still served (`git fetch origin 016ed418600cac11384e0db4cf59b9a20d872415` etc.; if not, reconstruct the two trailer lines by hand in temp files — they are quoted in the brief above); (c) the hook behaviour unchanged (a dry-run of the hook with a temp message).

## Verify and ship
- `npx prettier --check` on touched files; the workflow YAML parses (`gh workflow view ci.yml` or a YAML lint).
- Commit: one descriptive line, NO trailers (the hooks run in this worktree). Push once — normal push, the branch is new on origin. Dispatch exactly one CI run: `gh workflow run ci.yml --ref ci/reject-ai-trailers`, watch it to completion.
- Heavy steps under `flock /tmp/heavy.lock`.

## Report back
Files changed; the local test matrix results (fetched-by-SHA vs reconstructed for each offender); CI run id and conclusion; the shim status you observed in the three worktrees named above.

## Constraints
Do not merge; do not touch other branches. The merge happens after the release.

## Outcome
Done. Branch `ci/reject-ai-trailers` at `5428cfab9` on origin, one commit, one push, not merged (waits for after 0.32.4).

**Files changed (worktree wt-trailer-ci, fresh from origin/main 9f57efc49):**
- `scripts/check_no_ai_trailers.sh` (new, executable): the exact regex from the hook, `grep -qiE`, same stderr line (`commit-msg: AI attribution …remove it.`), exit 1 on match, exit 0 otherwise.
- `.husky/commit-msg`: now calls `"$(dirname "$0")/../scripts/check_no_ai_trailers.sh" "$1" || exit 1`; the `commit-msg.local` block is untouched.
- `.github/workflows/ci.yml`: new step "Commit messages carry no AI attribution" in the `changes` job (the one job with a full-history checkout; runs on every push, PR and dispatch, so the check costs no extra job minutes). It feeds `git log --format='--- commit %H ---%n%B' <range>` into the shared script; on a match the script's line prints, the whole dump is catted and the job fails.

**Ranges:** push → `github.event.before..<sha>`; pull_request → `github.event.pull_request.base.sha..<github.sha>`; created ref (before all zeros) or dispatch → merge-base with the default branch; if even that names nothing → nothing is checked, with a log note.

**One deliberate deviation from the brief, discovered locally:** the "whole pushed range" fallback would have failed for ever. The fork kept upstream chat-ui's history, and **134 commits of that pre-fork ancestry match the regex** (upstream's own AI-attribution trailers, latest 2026-09-02; none in Cerea's own post-fork history). The step therefore never scans whole ancestry: when the merge-base yields no distinct range (created ref, dispatch on main), it checks nothing and says so. Every path by which commits actually reach main (push to main, PR) is fully covered; a stale branch carrying the old offender commits would also be caught at merge time via the merge-base range.

**Local test matrix** (all in /tmp/trailer-test/):
- (a) clean message → exit 0, silent. ✓
- (b) all three offenders **fetched by SHA from GitHub** (`git fetch origin 016ed418…`, `f244cff1…`, `9129825…` all served; no reconstruction needed) → each exits 1 with the exact hook wording. ✓
- (b2) CI-format concatenation (same `--format` string) of the three offender messages → fails; of a clean message → passes. ✓
- (c) hook behaviour unchanged: old hook (Cerea checkout) vs new hook (worktree), both run as `sh -e .husky/commit-msg <file>` from the repo root — identical exit codes and byte-identical stdout/stderr on a clean message and an offender. ✓
- Step logic rehearsed locally under `bash -e` with mock env for push-normal (2 commits, pass), push-with-zero-before, pull_request (10 commits, pass), dispatch-on-main (nothing checked, note), dispatch-on-branch (1 commit, pass), and a negative range containing the fetched offenders (exit 1 with dump). ✓
- `npx prettier --check` on `.github/workflows/ci.yml` → passes; the two shell files have no Prettier parser (same as the pre-existing hook). YAML parses (`python3 -c yaml.safe_load` and `gh workflow view ci.yml`). ✓

**CI run 40785582680** (`workflow_dispatch` on the branch, 10m49s): `changes` (my step ran and passed), `go`, `e2e-smoke`, `client`, `documents` all **success**; `check` **failure — pre-existing on main, not this change**: `prettier --check docs/chat-admin.md` fails on main itself (9f57efc49), introduced by today's `4a4ba8da5` (docs-only, so main's push runs never saw it — paths-ignore `**/*.md`; a dispatch has no paths-ignore). Verified locally on the main checkout. The orchestrator may want a one-line `prettier --write docs/chat-admin.md` on main before or with the 0.32.4 release; left untouched here (not this branch's scope, and the brief allows one push only).

**Shim status observed** (2026-10-29 00:2x CET, after the orchestrator's out-of-band fix was said to have happened): `.husky/_` is still **absent** in all three worktrees — `wt-doc-versions`, `Cerea-wt-merge`, `wt-maps-skill2` (each has `core.hooksPath=.husky/_`, `_` dir ABSENT, so git silently runs no hook there). The `.husky/commit-msg` files in wt-doc-versions (mtime Oct 28 19:41) and wt-maps-skill2 (21:04) are fresh, but no install ran in those checkouts. The hook-less window in those worktrees is therefore still open — worth re-running husky install there (or noting that CI now catches whatever slips).

Worktree hygiene: wt-trailer-ci has `.husky/_` + full node_modules (npm ci) so hooks really ran for the commit; branch tracks origin/main, HEAD one commit ahead.
