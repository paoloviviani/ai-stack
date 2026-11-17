# Brief: PDF forms, round 2: see filled forms, positions and labels, text on flat forms, safe flatten (Cerea 0.32.4)

## What went wrong (a real session, the CGIL/CAAF "Prospetto di bilancio ISEE" form, 41 fields named `Testo104`…)
The originals are in `/home/ubuntu/.claude/uploads/ab09613d-fd72-4594-baa7-87d71d2ead82/`: `7cda2d1e-…rev_2_08022016.pdf` is the blank form (use it as a test fixture: copy it into the tests; it's a public form), and `7764ef0d-…_1.pdf` is the mis-filled flattened result.
1. **`look_doc` doesn't draw form fields.** `documents/src/cerea_documents/render.py:~119` renders without PDFium's form layer, so a correctly filled form looked empty, and the model flattened it just to see the values.
2. **`doc_outline` gives field names but not positions,** so with generic names the model guessed the mapping in reading order and got it wrong. Each widget's `/Rect` is in the file: table 1 is columns at x≈59/264/389 and rows at y≈404/387/371.
3. **Flatten was used as a diagnostic** and destroyed the form.
4. **Narrow amount boxes clipped "45.000,0":** our appearance generator ignores an auto font size (`0 Tf` in /DA).
5. **The model's last resort** was to rebuild the official form as a lookalike with `doc_create`.

## What to build (branch `feat/pdf-forms-round2` from origin/main)
1. **`look_doc` renders form fields:** `pdf.init_forms()` before loading pages, and `render(..., may_draw_forms=True)`. Test: render the filled fixture, and a field's value region isn't blank (pixel check).
2. **Auto font size:** when a field's /DA font size is 0, fit the text to the widget width and height (shrink from about 12 pt down to a floor of 6 pt; comb fields per cell). Test: "145.000,00" in a 52 pt-wide box is fully drawn (measure the glyph run width ≤ the box width).
3. **Field positions and labels in `doc_outline`.** For every form field add:
   - `rect` (page, x, y, w, h in PDF points, origin bottom-left; say so in the tool description);
   - `label`: the nearest page text that describes it. Use the text to the left on the same line, or else the column header above in a table, or the text just above. Extract with pypdf's text visitor (positions); keep it deterministic and cap its length;
   - for grid-like groups (fields aligned in rows and columns), add `table: {id, row, col}` with the column header text as the label.

   Test on the ISEE fixture: Testo119/120/121 are table 1, column 1 ("Cognome e Nome"), rows 1–3; Testo126/127/128 are column 3 ("Patrimonio Netto di Competenza"); Testo103 is labelled "Codice Azienda"; Testo102 is "CF o Partita Iva Società"; Testo125 is "31 dicembre".
4. **Step 3 of #39: writing onto PDFs without form fields.**
   - `doc_outline` on any PDF also returns the page's text lines with positions (capped, e.g. the first 200 lines per page, plus the page size), so the model can place values next to labels;
   - a new `doc_edit` PDF operation, `place_text({items: [{page, x, y, text, size?, font?}]})`, draws text onto the page content (an overlay merged into the page, in-place style: only the page content changes, and the file is saved as a new version). It uses the same Helvetica/WinAnsi rules and refusal of unsupported characters as fill_form, bounds-checks against the page box, and can't be combined with fill_form in one call. On a PDF that has form fields, refuse it and point to fill_form, unless an `allow_on_form: true` flag is given;
   - the verification report re-extracts the text and confirms each item is present near its position;
   - tests: the "Fax cover sheet" style flat form (build a fixture with labels and drawn lines), values placed next to labels, re-extracted, rendered and checked.
5. **Safe flatten:** `fill_form` with `flatten: true` saves the flattened result **as a new file** (`<name>-flattened.pdf`), leaving the fillable file as it was, unless `flatten_in_place: true` is passed. Update the tool description.
6. **Skill rules** (`builtin/pdf-tools/SKILL.md`, `builtin/pdf/SKILL.md`; wording "the user"):
   - use `doc_outline` first; map fields by **label and position**, never by name order;
   - after filling, check with `look_doc` (it shows the values now);
   - **never flatten unless the user asks** (and then it's a separate file);
   - for a form without fields, use `place_text` next to the labels from `doc_outline`'s text lines, check with `look_doc`, and adjust. The sandbox route (reportlab and pypdf) is now only the fallback when the doc tools are absent;
   - **never rebuild an official or third-party form as a substitute.** If the original is damaged or lost, restore the earlier version (the `version` support another worker is adding to the doc tools: if it isn't on main yet, write the rule as "ask the user to attach the original again") or ask for the original.
7. Regenerate `src/lib/server/documents/capabilities.fixture.json` and keep the `doc_edit` and `doc_outline` descriptions within their budget tests. Docs: `docs/office.md`.

## Coordination
- Another worker is on `feat/doc-versions` (the chat side: addressing earlier versions in the doc tools, and the sandbox attachment mount bug). It doesn't touch `documents/` or the PDF skills; you own those.
- Another is on `fix/brotli-hardening` (`fetching/playwright.ts`, Dockerfiles); stay out of those files.
- If you both need `documentTools.ts`, keep your edits to the PDF parts of the descriptions.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-pdf2 -b feat/pdf-forms-round2 origin/main`. `export TMPDIR=/var/tmp/pdf2-tmp && mkdir -p $TMPDIR`. Read AGENTS.md first.
- The documents service's memory cap (150 MiB per worker) and lazy imports: keep pypdf and pypdfium2 loaded only for PDF jobs; the existing import-guard tests must stay green.
- Heavy steps (npm ci, builds, Docker, Gotenberg) under `flock /tmp/heavy.lock`; never wrap a self-locking script in another flock. Bind to 127.0.0.1, and kill what you start.
- Never git stash, never --no-verify, never force-push, no AI attribution in commits, no generated files.
- Checks:
  - the documents pytest, ruff and mypy;
  - `npm run check`, eslint and prettier on the changed files;
  - the server specs for documents, builtinTools/document* and skills;
  - the fixture regenerated.
- **End-to-end on the real ISEE form:** with the service, fill it with dummy data mapped via your labels, render it with look_doc, and look at the PNG yourself. Every value must be in its right box and fully visible. Do the same for the flat fixture with place_text. Put the PNGs in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-28-pdf-forms-round2/`.
- Merge origin/main (merge commit) before CI. Push, run CI once (`gh workflow run ci.yml --ref feat/pdf-forms-round2`), and wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report: per item, the fails-without-fix evidence, the PNGs, the CI result and changelog lines. No sub-agents.
