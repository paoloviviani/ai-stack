# Brief: precise editing toolkit for Word and PowerPoint (Cerea built-in skills)

Repo /home/ubuntu/workspace/Cerea (public). Owner decision (2026-10-26): the model must edit existing Office files precisely on every deployment, whether or not an office suite is installed. The Excel helper (`excel/scripts/xlsx_patch.py`, branch `feat/xlsx-patch-helper`) is the first piece. This brief is the second: Word and PowerPoint. Read `/home/ubuntu/workspace/ai-stack/reports/2026-10-26-office-editing.md` first (findings: python-docx and python-pptx preserve every part reachable from relationships; the problems are the model improvising and losing formatting at run level).

## Want
Tested helpers bundled with the built-in skills, loaded the same way as `pdf_tools.py` and `xlsx_patch.py`. Pure Python plus what the Pyodide sandbox already has (python-docx, python-pptx and lxml: confirm against the vendored list).

**`word/scripts/docx_edit.py`** (on python-docx plus lxml where needed):
- `outline(path)` returns headings, paragraphs and tables with stable ids and styles.
- `replace_text(path, out, find, replace, scope=…)` keeps run formatting even when the match spans several runs. This is the classic python-docx pitfall; handle it properly.
- `fill_placeholders(path, out, mapping)` covers `{{name}}` style templates, including in headers, footers and tables.
- `set_table_cell` / `add_table_row` copy the previous row's formatting.
- `insert_paragraph_after(anchor_id, text, style)`.
- Optional, if it is clean to do: `track_changes=True`, which writes the edits as tracked insertions and deletions (w:ins / w:del, with author and date) so a reviewer can accept or reject them in Word. Say whether you did it.

**`powerpoint/scripts/pptx_edit.py`** (on python-pptx):
- `outline(path)` returns slides, shapes, placeholders and text with ids.
- `replace_text` keeps run formatting.
- `set_placeholder_text`, `replace_image(shape_id, image)` preserving size and position, `duplicate_slide` within the same deck, `delete_slide`, `reorder`.

**Shared:** a `verify(src, dst)` that checks:
- the zip is valid and the CRCs are good;
- the parts that should be untouched are byte-identical;
- the file reopens with the library;
- a text diff of what changed, so the model can show the person what it did.

**SKILL.md updates** (word, powerpoint) mirror the Excel rule:
- a new document uses the library directly;
- an existing document someone supplied uses the helper and then `verify`;
- tell the person what changed, using the diff.

Keep within the 500-line SKILL.md body limit.

## Tests
Run in the existing Pyodide integration harness (`src/lib/server/skills/pyodideOfficeSkills.integration.spec.ts` pattern), with generated fixtures:
- a docx with styled runs split mid-word, header and footer placeholders, a table with formatted rows, and a comment;
- a pptx with a layout placeholder, a picture and notes.

Assert that formatting survives, untouched parts are byte-identical, and the diff is accurate. The builtinSeeds spec must still pass (bundled-file validation).

## Rules
- Coordinate with `feat/xlsx-patch-helper`: if it is merged by the time you start, branch from main; if not, branch from it. It adds a short verify step to word/powerpoint SKILL.md, so keep it consistent.
- `git fetch origin && git worktree add -b feat/office-edit-toolkit /home/ubuntu/workspace/Cerea-wt-officekit <base>`; `npm ci` there (no lock); `export TMPDIR=/var/tmp/officekit-tmp && mkdir -p $TMPDIR`.
- NEVER git stash, NEVER --no-verify, no AI attribution, no literal think tags.
- eslint and prettier on changed TS files, `npm run check`, the specs you touched.
- Merge origin/main before handing back. Push the branch only, no PR. Then full CI (`gh workflow run ci.yml --ref feat/office-edit-toolkit -f full=true`) and an until-completed wait.
- Report: API, what was hard (run-spanning replace, tracked changes), tests, CI result.
