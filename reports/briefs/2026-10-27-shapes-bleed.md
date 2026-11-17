# Brief: shapes may bleed off the slide; clearer doc_create errors (Cerea fix for 0.31.1)

## What the owner hit (0.31.0)
`doc_create` with format `pptx` failed with:

```
slides[0]: shapes.1.y_cm: -2 is less than the minimum of 0 Details: {"properties":["background","body","body_right","charts","images","layout","notes","shapes","subtitle","title"],"required":[]} No file was made.
```

The model placed a decorative shape partly above the top edge. A design "bleed" like this is common and legitimate (a circle or band half off the slide). PowerPoint and LibreOffice clip it at the slide edge when presenting.

On the chat's tool card, "Input" showed only `{"format":"pptx","file_name":"Cerea-Pystino.pptx"}`, with no `spec`. That makes a failed call impossible to debug from the chat.

## What to change (branch `fix/shapes-bleed` from origin/main)
1. **Bleed for decorative shapes** (`documents/src/cerea_documents/spec.py` `_SHAPE_CM` and the bounds check in `make_pptx.py`, `_check_shape_bounds`):
   - Shapes **without text or runs** (any kind except `text`, and lines and arrows included) may extend past the slide edges: `x_cm` and `y_cm` from -50, sizes as now. They must still **overlap the slide** by at least 0.5 cm in both directions; a shape entirely off the slide is a 422 naming it.
   - Shapes **with text or runs, and every `text` kind**, must stay fully inside the slide, as now: text cut off at the edge is a defect.
   - The error for a text shape out of bounds keeps today's clear wording (shape index, the numbers, the slide size).
2. **One clear error, not two.** Find where the "Details: {properties…}" part comes from:
   - probably the JSON-schema error formatting in the service (`errors.py`, the validation path) or the chat's error mapping (`src/lib/server/documents/client.ts`);
   - the details list the parent object's allowed keys, which is noise for a range error.

   For a range error, the message should say the field, the value and the allowed range, and for a shape position, the slide size. Keep the details only where they help (an unknown property: list the allowed ones). Add a test.
3. **The tool card must show the spec.** Find why the `doc_create` call's input shown in the chat lacks `spec`. Candidates:
   - the tool card's argument rendering in `src/lib/components/chat/ToolUpdate.svelte`, or what the server stores as the call's parameters;
   - a deliberate size cap that drops large values;
   - the tool rewriting its arguments before the update is emitted (e.g. moving `spec` out).

   Fix it so a large spec is shown: pretty-printed JSON is fine, behind the existing expandable "Input" section. If there is a size cap, truncate with a visible "… (N more characters)" instead of dropping the key. Add or extend a component or server test.
4. **The model gets to retry.** Confirm a 422 from `doc_create` reaches the model as a tool error it can act on: the text must include the corrected range, so the next call can fix it. Say how you checked.
5. Regenerate `src/lib/server/documents/capabilities.fixture.json` if the schema changes (command in `documentsContract.spec.ts`), and keep the generated tool description within its budget. Mention bleed in one short clause of the PowerPoint SKILL.md "Creating a deck" shapes bullet: decorative shapes may bleed off the edge; text never.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-bleed -b fix/shapes-bleed origin/main`. `export TMPDIR=/var/tmp/bleed-tmp && mkdir -p $TMPDIR`. The main checkout's node_modules lacks paraglide: run `npm ci` in the worktree under `flock /tmp/heavy.lock`.
- Never `git stash`, never `--no-verify`, never force-push. No AI attribution in commits. The repo is public: no private hostnames or paths.
- Checks:
  - the documents tests (`uv run pytest` in `documents/`), plus ruff and mypy as CI runs them;
  - `npm run check`, eslint and prettier on every changed file;
  - the server tests for `src/lib/server/documents` and `src/lib/server/textGeneration/builtinTools`;
  - for a component change, that component's client test only, in the Playwright container as AGENTS.md shows, under the heavy lock.

  Each new test must fail without its fix.
- One render check: a slide with a circle bleeding off the top-right corner, through Gotenberg 8.38.1 under the heavy lock on 127.0.0.1, container removed afterwards. Put the PNG in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-27-shapes-bleed/` and look at it yourself.
- Push and run CI once: `gh workflow run ci.yml --ref fix/shapes-bleed`. Wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report: the cause of each of the three problems, the changed files, the fails-without-fix evidence, the screenshot path, the CI run and result, and a changelog line.
- No sub-agents.
