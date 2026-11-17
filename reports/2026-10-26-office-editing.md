# Editing existing Office files in the Cerea sandbox (2026-10-26)

Investigation only. No Cerea/Pystino changes, nothing committed.
Prototype: `/var/tmp/office-tmp/proto/` (`xlsx_patch.py` 344 lines, `make_fixture.py`, `test_patch.py`, `t2.py`, `rt.py`).
Run: `/var/tmp/office-tmp/v/bin/python -W ignore test_patch.py` (venv: openpyxl 3.1.5, lxml 6.1.3, python-docx 1.2.0, python-pptx 1.0.2 - the same versions Cerea vendors).

## Recommendation

1. Ship a tested `scripts/xlsx_patch.py` in the `excel` skill (same pattern as `pdf-tools/scripts/pdf_tools.py` and `powerpoint/scripts/*.py`: model loads it with `load_skill_file`, writes it to the working dir, imports it). Stdlib + lxml only; lxml is in the Pyodide lock (6.1.3), so no new vendored wheel and no auto-install change.
2. Skill rule: new file -> openpyxl; edit an existing .xlsx -> `xlsx_patch`; always `verify()`. Never openpyxl load+save on a workbook the person supplied (it silently drops x14 extensions; reproduced below).
3. No helper needed for .docx / .pptx now (see section 3). Only add a "verify untouched parts" snippet to their skills; the generic `verify()` can be shared.
4. Effort: ~1 day for a Sonnet worker including vitest-style integration test through the existing Pyodide harness (`pyodideOfficeSkills.integration.spec.ts` already exists as the pattern), SKILL.md rewrite, SOURCE.md note (own work, Apache-2.0). The prototype already covers the core.

## What the sandbox has (verified in repo)

- `src/lib/utils/execution/autoInstallImports.ts` VENDORED_PACKAGE_BY_IMPORT: docx, pptx, openpyxl, pypdf, reportlab, seaborn.
- `scripts/sync_pyodide_wheels.mjs` PYPI_WHEELS: python-docx 1.2.0, openpyxl 3.1.5, et-xmlfile 2.0.0, pypdf 6.19.0, python-pptx 1.0.2, XlsxWriter 3.2.9, reportlab 5.0.1, seaborn 0.13.2, all MIT/BSD.
- The full Pyodide lock (357 packages, `pyodide-lock.json` for 314.0.7) is vendored, including lxml 6.1.3, python-calamine 0.6.2 (read-only), xlrd 2.0.2, beautifulsoup4. So `import lxml` and `zipfile` work with no network.
- Current excel SKILL.md says "Preserve existing formatting exactly" and "re-open with openpyxl" but gives the model no safe way to edit; word/powerpoint skills are python-docx/pptx only (pptx has `edit.py`: inventory/replace text/reorder).

## 1. The xlsx helper (prototyped)

### API

```python
import xlsx_patch as xp
xp.sheet_names(src)                       # [(name, part, state)]
rep = xp.patch_cells(src, dst, "T2.4", {
    "B3": "text",                         # str -> inlineStr (no sharedStrings change)
    "C3": 12.5, "D3": True,               # n / b
    "E3": datetime.date(2026, 1, 31),     # -> serial (honours date1904); keeps cell's existing style
    "F3": xp.Formula("=B3*2"),            # <f>, no cached value
    "G3": None,                           # clear value, keep style
    "H3": xp.Cell("x", style_from="H2"),  # copy style index from another cell (or style=<int>)
}, recalc=None)                           # default: fullCalcOnLoad=1 iff formulas added/removed
xp.verify(src, dst, rep["changed_parts"]) # raises PatchError unless sound
```

Report: sheet, part, cells_set, cells_created, formulas_added, formula_cells_replaced, changed_parts.

### How it works

- Sheet by name: workbook.xml `<sheet name r:id>` -> workbook.xml.rels Target (relative or absolute, `..` resolved); refuses chartsheets/non-worksheet.
- Only the target sheet part is parsed (lxml) and re-serialised. Rows created in order, cells inserted in column order, `spans` dropped on touched rows, `<dimension>` recomputed.
- Rezip: same part order and names, a FRESH `zipfile.ZipInfo` per entry (date_time, compress_type, external_attr copied), data passed to `writestr` so CRC/sizes are computed by zipfile; written to temp file then `os.replace` (in-place `dst == src` works). This is exactly the bug the model hit (reused ZipInfo from the source).
- Touched parts besides the sheet: `xl/workbook.xml` (only a `fullCalcOnLoad="1"` attribute on `<calcPr>`, string-level edit, rest byte-identical) and `xl/calcChain.xml` (only when a formula cell is overwritten by a non-formula; that entry is removed and the `i=` sheet marker handed to the next sibling, else Excel reports a repair). Everything else is copied byte-for-byte (decompressed).
- `verify()`: `testzip()` CRC, same part list and order, every part outside `changed_parts` byte-identical, changed XML well-formed, openpyxl `read_only` load succeeds.

### Edge cases and decisions

| Case | Behaviour |
|---|---|
| Merged range, non-top-left cell | PatchError (names the range) |
| Overwriting a shared-formula or array-formula master | PatchError (would orphan dependants). Dependants can be overwritten safely |
| Formula cell replaced by value | calcChain entry removed (handled) |
| New formula | not in calcChain (Excel tolerates; rebuilt on load); fullCalcOnLoad set so values compute on open; cached values absent (say so to the person) |
| Dates | serial number only; number format is the cell's existing one. If the target cell has no date format the person sees a serial: use `Cell(..., style_from=)` from a date-formatted cell |
| Strings | inlineStr, `xml:space=preserve` when leading/trailing/double spaces or newline, illegal XML control chars stripped. Excel converts to shared strings on next save. `sharedStrings.xml` untouched (so no index shifting). Rich text not supported |
| Tables (`xl/tables`) | cells inside work; writing below the table ref does not extend it (not handled; documented) |
| Data validation / CF / x14 ext / defined names | untouched (not parsed). Writing a value that violates a validation is not checked |
| Row/column default style | new cell in a row with `customFormat` inherits the row `s`; column default style not looked up (use `style_from`) |
| 1904 date system | honoured |
| .xlsm / vbaProject | other parts copied through, works; output name must stay .xlsm |
| Encrypted/password files, strict OOXML (`http://purl.oclc.org/ooxml` namespaces) | not supported; fails with a clear error is a TODO (strict namespace check) |
| Not done | delete rows/insert rows shifting references, add sheets, styles creation (new styles need styles.xml edit - a possible `add_style()` later), hyperlinks, comments |

### Prototype results (evidence)

Fixture (`make_fixture.py`): 10 sheets (Cover, T1.1 ... T3.2, Lists, Summary), each with an openpyxl data validation plus an injected x14 `conditionalFormatting` (dataBar) ext and x14 `dataValidations` ext; target sheet T2.4 has a merged range, date formats, a shared formula (master C2, dependants C3:C10), a defined name, a table on Lists, and a calcChain part (21 parts).

- openpyxl read of fixture warns `Unknown extension is not supported and will be removed` (the colleague-template symptom, reproduced).
- openpyxl load+save: x14 gone from the other sheets (`b"x14:" in sheet2.xml` True -> False). `xlsx_patch`: stays True.
- Patch of 11 cells (string with `& <`, int, float, date, datetime, bool, formula, leading-space+newline string, new row 70, styled new cell, clear): 21 parts, 19 byte-identical, changed = `xl/workbook.xml` + `xl/worksheets/sheet6.xml` only. CRC ok. openpyxl read-only reopen ok; values, `dd/mm/yyyy` format on dates, and shared-formula dependants (`=B3*2`) read back correctly.
- Formula-removal case: changed = calcChain + workbook + sheet; calcChain 580 -> 579 entries; `i="7"` marker carried to the next entry.
- Guards fire: shared master C2 (value or formula), merged inner cell B1 ("A1:C1"), unknown sheet name lists the real names.
- In-place (`dst == src`) works, CRC ok.
- Timing (this box, CPython; Pyodide will be ~2-4x slower, still sub-second): 11 cells 0.010 s patch + 0.027 s verify; 500 cells 0.039 s on a ~60-row sheet.
- NOT verified: opening in real Excel/LibreOffice (neither is on this box; soffice not found). Evidence of validity is structural only (schema-ordered children, valid cell order, no orphaned calcChain/shared-formula refs). Recommend one manual open in Excel on the real colleague template before shipping, and say in the skill that Excel validity is checked structurally, not rendered.
- Not yet tested on a big real-world sheet (10^5 rows): lxml full-parse of the sheet; expect ~1 s per 100 k cells native; memory ~10x XML size. Add a size guard (>50 MB sheet XML: refuse) or move to iterparse splice later.

## 2. Existing libraries (verified via pip metadata / local experiment)

- openpyxl 3.1.5: `keep_vba`/`keep_links` do not help; reproduced x14 ext dropped on save (its reader warns "Unknown extension ... will be removed", `_reader.py` parses extLst only for known types). Also loses/rewrites charts, images partially, custom XML, slicers, etc. Right for new files only.
- XlsxWriter 3.3.0 (BSD-2): write-only, cannot open existing files. No.
- python-calamine 0.9.0 (MIT; Pyodide lock has 0.6.2): read-only. Useful for fast reads, not edits.
- pycel 1.0b30 and formulas 1.3.4: formula evaluators layered on openpyxl; they do not write back preserving parts; formulas pulls scipy/schedula. Not patchers. (Could be a later separate "compute cached values" feature, out of scope.)
- I did not find a maintained pure-Python OOXML "patch one sheet" library to adopt; did not exhaustively search PyPI. Writing our own ~350 lines is lower risk than a dependency, and we control tests.

## 3. docx / pptx (empirical round trip, `rt.py`)

python-docx 1.2.0 and python-pptx 1.0.2 load every part reachable from relationships into the package (known parts as lxml trees, unknown as raw blobs) and write them back; unknown elements/extLst inside parts survive in the tree.

- Test: default docx/pptx plus an unreferenced `customXml/orphan.foo` (and `word/unref.xml`) and an extra `Default Extension` in `[Content_Types].xml`, load+save:
  - Lost: parts not reachable from any relationship (orphans), and the custom content-type Default (`[Content_Types].xml` is regenerated).
  - Kept byte-identical: `word/document.xml`, all slide/layout/master parts, everything reachable.
- So no x14-style silent loss; the loss class is orphaned parts and package-level plumbing (rare in real files; Office never writes orphans). Zip order/compression may change. python-docx known gaps: content controls (SDT) fine to carry but not editable via API, tracked changes and comments are in the XML but not exposed (edits via API can break them: need raw XML), fields. python-pptx: SmartArt/charts kept but not editable.
- Conclusion: no helper now. Add to both skills the same "verify" step: compare namelist and per-part bytes of untouched parts with a short snippet (`xlsx_patch.verify` is generic: pass `changed_parts` = the parts you expect to differ; consider renaming to `ooxml_verify`). Revisit a docx/pptx raw-XML text-replace helper only if tracked-changes/SDT editing shows up in real conversations. pptx already has `edit.py`.

## 4. Skill text (draft for excel/SKILL.md "Editing an existing workbook")

> Decision rule. New workbook: openpyxl. A workbook the person supplied that you must change: do NOT `load_workbook(...).save(...)`; it silently removes extensions (conditional-formatting and data-validation ext, slicers, unknown parts) from sheets you never touched. Use `xlsx_patch`:
> 1. Inspect with `openpyxl.load_workbook(path, read_only=True)` or `xp.sheet_names`.
> 2. `rep = xp.patch_cells(src, "<new name>.xlsx", "<sheet>", {...})` - one call per sheet; never overwrite the original.
> 3. `xp.verify(src, dst, rep["changed_parts"])`, then reopen read-only and print the cells you set.
> 4. Say what you changed, that formulas have no cached values until opened in Excel, and that only structural validity was checked.
> If patch_cells refuses (merged cell, shared-formula master), tell the person and write to the permitted cell; do not hand-edit the zip. Never build a zip with `zipfile` by reusing ZipInfo objects from another archive.

Also add the wheel-free note: no new packages; script is loaded with `load_skill_file`.

## Risks

- Excel-validity unproven on a real client (mitigate: manual Excel check; add LibreOffice headless convert in CI if a docker image is acceptable).
- Model may ignore the rule: mitigate with the tool-visible refusal (could add to `executeCodeTool` a warning when code does `load_workbook` + `save` on a `/mnt/data` path; optional).
- Inline strings differ from Excel's shared strings: pandas/openpyxl read them fine; some third-party readers ignore them (rare). Option `shared=True` (append to sharedStrings.xml, bump count/uniqueCount) is a ~40-line follow-up if needed.
- Large sheets/memory in the browser worker.
- Strict-OOXML, protected-sheet and password files untested.

## Next steps (if approved)

1. Port `xlsx_patch.py` into `excel/scripts/`, add tests (fixture generator as a pytest-like node test through the Pyodide harness), add strict-namespace and size guards.
2. Rewrite excel SKILL.md editing section; add verify snippets to word/powerpoint.
3. One manual Excel/LibreOffice open on a real template; then ship with a Cerea patch release.
