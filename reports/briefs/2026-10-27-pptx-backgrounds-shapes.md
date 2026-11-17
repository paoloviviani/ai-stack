# Brief: slide backgrounds and shapes in doc_create (Cerea documents service)

## Owner decision (2026-10-27)
`doc_create` decks can't be visually designed: there are no backgrounds and no free shapes. Add both to the service, validated and laid out by the service so they can't overlap or run off the slide. They form step 1 of a gradual set; designed layouts (big number, timeline, comparison, full picture) come later, not now.

## Context
- ADR 0103 (cite by number only; the repo is public). Service code: `documents/src/cerea_documents/`.
  - `make_pptx.py` builds new decks;
  - `spec.py` and `schemas.py` hold the spec models;
  - `theme.py`;
  - `verify.py`, which runs after every create;
  - `powerpoint.py` (editing).
- Tests: `documents/tests/test_create*.py`.
- The chat generates `doc_create`'s description from `create_schemas` (`src/lib/server/textGeneration/builtinTools/documentTools.ts`, `describeSchema`). `src/lib/server/documents/capabilities.fixture.json` must equal the live service: `documents/tests/test_api.py` checks this, and the command to regenerate it is in `src/lib/server/documents/documentsContract.spec.ts`. `documentsContract.spec.ts` checks the generated text, and the description has a length budget, so keep the new schema compact. Look at how the theme and text runs are printed once as aliases, and reuse the existing `runs` and colour definitions.
- The 0.30.1 fix just reworked the layout code in `make_pptx.py`: 16:9 layouts, content below the title, text shrinking no further than 14 pt. Don't regress it. The CI `documents` job renders decks through Gotenberg; keep that check passing and add a case using the new features.

## What to build (branch `feat/pptx-backgrounds-shapes` from origin/main)
1. **`background` on a slide, and as a default in `theme.slide_background`:** one of
   - `{color}`;
   - `{gradient: [c1, c2], angle?}`, a native two-stop gradient fill;
   - `{image: "<file name in the conversation>", fit: "cover"}`, full-bleed with the picture cropped to cover the slide, not stretched.

   It is set as the slide's own background (`p:bg`), not as a shape. Text colour isn't changed automatically, but `verify.py` (or the create step) warns when the theme text colour has under 4.5:1 contrast with a solid background colour. A warning goes in the result, not an error.
2. **`shapes` on a slide:** a list of at most 30.
   - Each has a `kind`: `rect`, `rounded_rect`, `ellipse`, `line`, `arrow`, `chevron`, or `text` (a text box with no fill).
   - Position: `x_cm`, `y_cm`, `w_cm`, `h_cm`.
   - Style: `fill` (hex or `none`), `line: {color, width_pt}`, `radius` for `rounded_rect`.
   - Text: optional `text` or `runs`, with `size_pt` (minimum 10), `align` and `valign`, and `bold`/`color` through runs.
   - Shapes are drawn in list order, above the background and **below** the layout's placeholders, unless `layer: "front"` is given.
   - Validation: every shape must lie within the slide (in cm, for 16:9 and 4:3). An out-of-bounds shape is a 422 error naming the shape index and the slide size, so the model can fix it.
   - Text that can't fit a shape at its size is a warning (reuse the existing estimate used for placeholders).
   - `blank` and `title_only` are the intended layouts for shape-built slides. Shapes are allowed on any layout.
3. **Placeholders over shapes.** When a slide has a shape placed where the body placeholder would be, keep things predictable. A shape-heavy slide should use `blank`/`title_only`; on other layouts, warn when a shape overlaps a non-empty placeholder.
4. **Template path.** With `theme.template`, backgrounds and shapes work the same way (they're slide-level). Test one case.
5. **Word and PDF:** out of scope. The schema for those formats must not change.
6. **Tests.** Unit tests in `documents/tests` for:
   - each background kind: assert the XML (`p:bg` with `a:solidFill` / `a:gradFill` / `a:blipFill`, the stretch and crop for cover);
   - each shape kind, the z-order (behind placeholders, and `layer: "front"`);
   - the bounds 422, and the contrast and overflow warnings.

   Also:
   - a reopen check with python-pptx;
   - add a background-plus-shapes deck to the CI Gotenberg render check;
   - regenerate the capabilities fixture and update `documentsContract.spec.ts` expectations if the generated text changes;
   - add a short bullet on backgrounds and shapes to the "Creating a deck" part of `src/lib/server/skills/builtin/powerpoint/SKILL.md`. Edit **only** that part: another worker is changing that file's "One rule" and fallback sections. Mention not to use shapes for ordinary text slides.
7. **Screenshots.** Render 3 sample decks (a gradient title slide, a "three cards" slide made from rounded rects, an image-cover section slide) through Gotenberg. Use the image `gotenberg/gotenberg:8.38.1`, only under `flock /tmp/heavy.lock`, on 127.0.0.1, removed afterwards. Put the PNGs in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-27-pptx-shapes/` and look at each one yourself before reporting.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-pptx-shapes -b feat/pptx-backgrounds-shapes origin/main`. `export TMPDIR=/var/tmp/pptx-shapes-tmp && mkdir -p $TMPDIR`.
- Never `git stash`, never `--no-verify`, never force-push. No AI attribution in commits. No private hostnames or paths.
- Checks:
  - the documents service tests (see the README or CI job for how: `uv run pytest` in `documents/`);
  - ruff, if CI runs it;
  - for the chat side: `npm run check`, eslint and prettier on changed TS/MD files, and `src/lib/server/documents` plus `src/lib/server/textGeneration/builtinTools` server tests.
  - No Playwright, no full suites. Docker only under the heavy lock.
- Push and run CI once: `gh workflow run ci.yml --ref feat/pptx-backgrounds-shapes`. Wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report: the schema added (compact), the changed files, the test-fails-without-fix evidence for the bounds check, the screenshot paths, the CI run id and result, and the changelog wording.
- No sub-agents. The box has 4 cores and 6 GB; another worker runs alongside you.
