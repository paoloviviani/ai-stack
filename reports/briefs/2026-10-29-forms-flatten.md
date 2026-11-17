# Brief: flattened-PDF text positions and model guidance (2026-10-29)

## Task
Two fixes from the owner's ISEE form test (handoff section 1). Read the handoff first: /home/ubuntu/workspace/ai-stack/reports/2026-10-29-handoff-forms-artifacts-admin.md — section 1 items 1, 3 and 4 are yours (item 2, the sandbox mount, is another worker's and takes priority).

## Fix 1 — `doc_outline` misplaces text in flattened PDFs (bug)
On the owner's flattened file, our extractor reports every value as one block at x≈3, y≈2–6 (page bottom-left). The model passed that on as a false "caveat". Cause to confirm in `documents/src/cerea_documents/` (pdflayout.py / the outline text extraction): the extraction likely does not apply the `cm` before `Do`, or the Form XObject's `/Matrix`, for Form XObjects (the flattened file draws its values from `CrFlat0…25` Form XObjects — PyMuPDF extracts `47.000,00` at 484,627 top-left, so the data is there).
- Fix it, and add a regression test that flattens a small form and checks the reported value positions against the field rects (fixtures per `documents/tests/pdf_fixtures.py`; the documents tests run in CI's `documents` job).

## Fix 2 — model guidance (skill + description)
Add these facts, short, to the PDF skill and the `doc_edit` `fill_form` description, so the next "it looks pixelated" gets a two-line answer:
- fill_form writes vector text appearances (Helvetica);
- macOS Preview shows filled fields soft until the field is clicked — a viewer quirk, not the file;
- if the file will be sent or printed and must look the same everywhere, offer the flattened copy.
Keep "never flatten unasked" standing. Watch the description budget specs (documentTools specs pin tool-description lengths).

## Optional, only if cheap
Field values use Helvetica 10 pt while the form is set in Times/Arial — only if you find a clean way to honour a field's own DA font; otherwise leave it and say so.

## Verify
The owner's four files are in `~/.claude/uploads/ab09613d-fd72-4594-baa7-87d71d2ead82/` (original `5224c677-…pdf`, filled `ed02385a-…-2.pdf`, flattened `06ad19bd-…-flattened.pdf`, transcript `90fa4ca8-…md`). Run the documents tests (`documents/tests/`), the affected Python + tool specs, lint, and push once, dispatch exactly one CI run (`gh workflow run ci.yml --ref <branch>`), watch it.

## Constraints
New worktree off `origin/main`; `core.hooksPath` must be `.husky/_` before the first commit; `TMPDIR=/var/tmp/forms-fix-tmp`; heavy under `flock /tmp/heavy.lock`; mongod detached; no stash/force-push/--no-verify; new text says "users" not "people" and the repo is public (no private hostnames in commits). Do NOT merge — the orchestrator merges after review.

## Report back
The confirmed cause of the misplaced text, the fix, the regression test, the guidance wording (and where it landed), whether you took the optional font fix, gates results, CI run id and conclusion.

## Outcome

Done on branch `fix/forms-flatten-outline` (head `2f5591d9f`, worktree `/home/ubuntu/workspace/wt-forms-flatten`, off `origin/main` `8f72e33cd`; `core.hooksPath` set to `.husky/_` before the first commit). Not merged — for review.

**Cause, confirmed.** pypdf's text extraction recurses into a Form XObject with a fresh graphics state (`PageObject._extract_text__xform` → `extract_xform_text` → `_extract_text` on the form): the `cm` in effect on the page at the `Do` and the form's own `/Matrix` are applied to neither the visitor nor the returned text. On the owner's flattened file each value is drawn as `q 1 0 0 1 <x> <y> cm /CrFlatN Do Q` with `3.00 5.67 Td` inside the form, so all 26 values were reported near the page origin (one block at x≈3, y≈2–6) exactly as the handoff described. The data was indeed all there.

**Fix** (`documents/src/cerea_documents/pdflayout.py`, `_fragments`): when a page's `/Resources` hold a Form XObject, the extraction also installs `visitor_operand_before`/`visitor_operand_after`. The operand visitors follow the forms in the exact order pypdf recurses (a form counts as entered only from its first drawn operation, so the surrounding-text pieces pypdf flushes at the `Do` itself keep the outer placement), building for each level the mapping form-space → page space as `outer ∘ (cm at the Do) ∘ /Matrix` (nested forms included, resources inherited). `visit` folds that mapping into the `cm` it is given, which also corrects the font-size scale for scaled forms. Pages without a Form XObject are extracted exactly as before (the visitors are not installed). Verified on the owner's flattened file three ways: all 26 values sit exactly where the raw operators put them (`cm.tx + Td.x`, `cm.ty + Td.y` — e.g. `47.000,00` at 484.5/203.8); a full multiset diff against the old extractor shows the page-level fragments are byte-identical (88 fragments before and after; only the 26 form values moved); and spot positions agree with PyMuPDF where a span corresponds (the two table-header occurrences included).

**Regression tests** (`documents/tests/test_pdf_forms_round2.py`, fixture `make_flatten_check_pdf` in `pdf_fixtures.py`): a one-page form with three text fields whose labels sit well above (no baseline sharing), one field with `/MK /R 90` so its appearance stream carries a `/Matrix`; fill + flatten through `edit`, then the outline's lines (and, for `make_form_pdf`, the fragments) must fall inside the field rects. Both fail without the fix (they report the old `(3.0, 6.6)` positions) and pass with it.

**Guidance, where it landed.**
- `src/lib/server/skills/builtin/pdf-tools/SKILL.md` ("One rule for forms", item 3, new last bullet): the values are drawn as **vector text** (Helvetica), not an image — the file itself is sharp; macOS **Preview** shows filled fields soft until the field is clicked — a viewer quirk, not the file; if the filled file will be sent or printed and must look the same everywhere, offer the flattened copy, and flatten only when the user takes the offer. "Never flatten unless the user asks" stands untouched (pinned wording preserved).
- `doc_edit` description (`pdfNote` in `documentTools.ts`): "Values are vector text (Helvetica): sharp in the file; macOS Preview shows them soft until a field is clicked (a viewer quirk). If it will be sent or printed and must look the same everywhere, offer the flattened copy."
- Both wordings are pinned (`officeSkills.spec.ts`, `documentTools.spec.ts`), and "users" wording rules hold.

**Description budget:** the doc_edit description was already at 2,997 of the pinned 3,000 (`documentsContract.spec.ts`), so `pdfNote` was tightened to make room (final 2,993): the value-type list is shorter, the "bad values are refused" sentence went (the service refuses with what the field takes; the skill says it), the flatten sentence lost "and the fillable file stays" (the skill and the `flatten` schema carry it), and place_text's "(points from the page's bottom left; doc_outline lists the text lines)" parenthetical went (doc_outline's pinned description carries the origin, the skill the workflow). All pinned fragments kept verbatim; budget test green.

**Optional DA-font item: not taken.** The owner's form (and the repo's ISEE fixture) declare `/DA "/Helv 10 Tf 0 g"` on the fields themselves — the form asks for Helvetica; the Times/Arial look belongs to the page's static text. Honouring a field's own DA font would only matter for forms whose DA names a non-Helv font, and doing that cleanly means DR lookups, per-font widths (the fitting/wrapping maths is Helvetica-based), encoding safety and a re-synced `pdf_tools.py` copy — not cheap. Left as is.

**Gates.** documents: `pytest` 531 passed, 2 skipped (full suite, twice); `ruff check`, `ruff format --check`, `mypy --strict` clean. Chat: `documentsContract.spec.ts`, `documentTools.spec.ts`, `officeSkills.spec.ts` 80/80 (after the wording change), `npm run check` 0 errors, prettier/eslint clean on the changed files. Pushed once; one CI dispatch on the branch ref: run **40864271411** — **success** (check, client, go, e2e-smoke, documents green; e2e-full skipped by design).

**Decided myself:** the guidance went into the `pdf-tools` skill (the form-filling one) rather than the `pdf` create-skill, since the facts answer form-filling questions; the description trims listed above; the one-op (no place_text) wording variant kept consistent. No re-sync of `pdf_tools.py` needed — `pdfform.py` itself is untouched.
