# Brief: PowerPoint slide editing, honest fit warnings, clearer limits (Cerea, folded into 0.32.0)

## What happened (0.31.0, a real session building a 14-slide designed deck)
The model built a dark, shape-based deck with `doc_create` and then fixed it. Four problems with our tools made this expensive and fragile:
- **No slide-level edit.** `doc_edit` for pptx (`documents/src/cerea_documents/powerpoint.py`) has only text, image, notes and slide duplicate/delete/reorder operations. To fix one slide, it re-sent the full ~90-shape spec about 7 times.
- **The fit warning cried wolf.** About 96 "the text will not fit" notes, almost all false: `_text_height` in `make_pptx.py` assumes 14 pt of frame insets (PowerPoint's default is 0.127 cm top and bottom, about 7.2 pt) and adds paragraph spacing even for a single line. So any 10 pt label in a 0.6 cm box is flagged. The model then reasoned its way into ignoring every warning, including any real one.
- **The shape limit error was unreadable.** `shapes` has `maxItems: 30` (`spec.py`). `_friendly()` doesn't handle `maxItems` or `minItems`, so the message is jsonschema's "[...whole array...] is too long". The chat cut it off, and the model had to guess the cause.
- **Slide titles ignore the theme.** With no template, layout titles get the master's fixed bold `TITLE_PT` 36. `theme.heading_sizes_pt` is ignored for pptx, so the one slide built on `title_content` looked different from the shape-built slides (the person noticed). The deck also had no slide numbers on that slide, because numbers exist only as hand-placed shapes.

## What to change (branch `feat/pptx-editing-fit` from origin/main)
1. **`replace_slide` op in `doc_edit` for pptx.** It takes `{slide: n, spec: <one slide spec exactly as doc_create takes it>}`. It rebuilds that slide in place with the deck's theme (background, fonts, colours) and keeps position, notes (unless the spec gives notes) and sections. It runs the same validation and bounds and fit checks as `doc_create`, with the same error wording (prefixed with the slide). Also add **`add_slide`** (`{after: n, spec}`) if it falls out of the same code. Templated decks resolve layouts against the file's own layouts, as `doc_create` does. The decks carry their theme only in the file, so derive what you need (slide size, fonts, colours) from the file. Where a theme value can't be recovered, use the defaults and say so in the result. A design note in the report on how you did this is welcome.
   - Optional, only if it stays small: an `update_shape` op (`{slide, shape, x_cm?, y_cm?, w_cm?, h_cm?}`) for moving or resizing one shape by its index from `doc_outline`.
2. **Honest fit estimate for shapes** (`_shape_text`, `_text_height`):
   - use PowerPoint's real default insets (0.25 cm left and right, 0.127 cm top and bottom), the same as the frame the builder actually writes. Check what `_shape_text` sets and make the estimate match it;
   - no paragraph gap for the first paragraph, and none in shapes unless we write `spcBef`/`spcAft`;
   - **warn only when it matters**: the text's estimated bottom spills over another shape that has text, or out of a filled shape that contains it, or off the slide. A short label in a slightly short, empty-around box is not a warning. Keep one warning per shape, worded with the estimated height needed.
   - Tests: a 10 pt one-line label in a 0.6 cm box gives no warning. A 4-line paragraph overflowing into the shape below it does. Text overflowing its filled card does.
3. **Readable array limits.** `_friendly()` handles `maxItems` and `minItems` with a short sentence, never echoing the instance, e.g. "slides[9].shapes: 34 shapes; 30 at most per slide". Check every other branch for instance echoes of large values too (`const`, `type`, `oneOf` on a list or object): print a type and length, not the value. Raise `shapes` `maxItems` to **40**. Tests for each.
4. **Slide titles follow the theme** (no template): the master title style uses `heading_sizes_pt.h1` when given, with `TITLE_PT` (36) as the default. Bold stays the default, and add `theme.heading_bold` (bool, default true) only if it's trivial. Make sure the schema description of `heading_sizes_pt` says what applies to pptx. Test: h1=28 gives a 28 pt master title.
5. **Slide numbers:** `theme.slide_numbers: true` (default false) puts the number on every slide except the first, bottom right, in the theme's muted colour at 10 pt. Use the layout's slide-number placeholder where there is one, otherwise a text box with a `<a:fld type="slidenum">` field so reordering keeps it right. Templated decks use the template's own slide-number placeholder. `replace_slide`/`add_slide` respect it.
6. **Smaller spec conveniences:**
   - `color` on a shape: the default colour for its text;
   - `size_pt` on a run, overriding the shape's size;
   - lower the shape `size_pt` minimum from 10 to **8**, and update the "(10 at least)" wording in the fit note;
   - the unknown-layout error already lists the names. Also accept `title_and_content` as an alias of `title_content`, since that's the PowerPoint name models reach for.
7. **Skill and tool description:** in the PowerPoint SKILL.md, add one short bullet on fixing one slide with `doc_edit` `replace_slide` rather than re-creating the deck, and mention `slide_numbers`. Regenerate `src/lib/server/documents/capabilities.fixture.json` (command in `documentsContract.spec.ts`) and keep the generated tool description within its budget. Docs: update the PowerPoint section in `docs/` that the 0.31.1 docs pass wrote (find it by grepping for "designed slides").

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-pptx-edit -b feat/pptx-editing-fit origin/main`. `export TMPDIR=/var/tmp/pptx-edit-tmp && mkdir -p $TMPDIR`. Run `npm ci` in the worktree under `flock /tmp/heavy.lock` only if you need the node side (the fixture regeneration and `npm run check`).
- Another worker is on `feat/deployment-connector-modes` (`wt-conn-modes`) for the same 0.32.0 release. Don't touch connectors, `runMcpFlow` or tool assembly. Both branches merge separately.
- Never `git stash`, never `--no-verify`, never force-push. No AI attribution in commits (the repo's hook rejects it). The repo is public: no private hostnames or paths, and cite no private reports.
- Checks:
  - the documents tests (`uv run pytest` in `documents/`), plus ruff and mypy as CI runs them;
  - `npm run check`, eslint and prettier on every changed file;
  - the server tests for `src/lib/server/documents`.

  Each new test must fail without its fix (say how you verified).
- One render check through Gotenberg 8.38.1 under the heavy lock on 127.0.0.1, container removed afterwards: build a 3-slide shape deck with `slide_numbers: true`, then `replace_slide` slide 2 with a different design. Render before and after. Put the PNGs in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-27-pptx-editing-fit/` and look at them yourself: numbers present and right, theme kept on the replaced slide, no warnings for well-placed small labels.
- Push and run CI once: `gh workflow run ci.yml --ref feat/pptx-editing-fit`. Wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report: what you changed per item (or why you skipped it), the changed files, the fails-without-fix evidence, the warning count for the sample deck before and after the fit change, the screenshot paths, the CI run and result, and changelog lines for 0.32.0.
- No sub-agents.
