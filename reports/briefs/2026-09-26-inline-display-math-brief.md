# Brief: `$$…$$` mid-sentence renders with stray dollars in chat messages (small fix)

Repo: Cerea. The orchestrator gives you the worktree, branch, base SHA, ports and Mongo in the launch message. Run `npm ci` first.

## The bug (seen live)
In a chat message (not the artifact panel), `$$…$$` written mid-sentence renders as inline math with a stray `$` on each side. Example from the model: "…the integral $$\int_0^1 x^2\,dx$$ equals…".

## Where
`src/lib/utils/marked.ts`, the KaTeX extensions: `katexBlockExtension` (a block tokenizer; `$$…$$` and the bracket forms at the start of a block) and the inline extension (`katexInline`, single `$`). Most likely a `$$` that doesn't start a block reaches the inline tokenizer, which matches `$…$` inside it and leaves the outer `$` as text. Confirm the cause before fixing.

## Fix
- `$$…$$` anywhere in inline text is math, with no stray dollars. Follow the existing convention for `$$`: if block `$$` renders `displayMode: true`, an inline `$$…$$` renders display-mode (KaTeX display inside the line is acceptable, as other renderers do), or as the existing block if that's cleaner. State your choice.
- **Unchanged:** single-`$` inline math, escaped `\$`, currency ("$5 and $10" stays text), and code spans and fenced code blocks (nothing inside them is math).

## Tests
- vitest on the tokenizer or the rendered output:
  - a mid-sentence `$$…$$` (**this test must fail on the old code**; show it failing, then passing);
  - `$$` on its own lines;
  - inline `$…$`;
  - currency;
  - `\$`;
  - `$$` inside an inline code span and inside a fenced block.
- Check that the artifact panel's markdown preview, which uses the same pipeline, is unaffected: its existing math spec (`tests/chat-artifact-math.spec.ts`) still passes, at root and under `/chat`.
- `npm run check` (0 errors); eslint and prettier on the changed files.

## Box rules (mandatory)
The same as your previous brief:
- `timeout -s KILL <secs> flock /tmp/heavy.lock …` in the foreground, with the `E2E_*` and `TEST_MONGODB_URL` exports on the same line;
- kill only your own processes, by PID; nothing in `/tmp`;
- no sub-agents, no deploy, no live checks, no new dependencies;
- commit as Paolo Viviani from git config, with no `Co-Authored-By` trailer; before pushing, `git fetch` and check that `git log origin/main..HEAD` lists only your commits; push the branch, don't merge;
- when done, delete the worktree's `build/`, `test-results/` and `playwright-report/`.

## Report
Reply with:
- the cause and the fix;
- the commits;
- the failing-then-passing test;
- the test commands and pass counts.
