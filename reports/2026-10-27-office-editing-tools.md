# Accurate editing of Office files: tools survey (2026-10-27)

Research only. No repo changes. Clones were in /var/tmp/office-research/ and are deleted.
Builds on `2026-10-26-euro-office-spike.md` and `2026-10-26-office-editing.md` (not redone here).
Facts about stars, dates and licences come from the GitHub and PyPI APIs on 2026-10-27. Things I did not verify are marked "unverified".

## Verdict

> **Correction (orchestrator review, 2026-10-27):** rank 1 is already how `doc_edit` works. `cerea_documents/pkg.py` rewrites only the edited parts and copies every other part through byte for byte. That covers docx (`word.py`), pptx (`powerpoint.py`) and xlsx (`excel.py`). So what's missing is the set of operations, not the editing model: tracked changes and comments in Word, and slide- and shape-level edits in pptx (the `feat/pptx-editing-fit` branch). Read rank 1 as "copy the skill scripts' ideas for the operations we lack".

The owner's priority is exact edits that leave everything else untouched. That points to one rule: **patch the XML in place, do not load and save through an engine**. Engines (LibreOffice, Euro-Office, openpyxl, python-pptx save) rewrite the whole file. Use an engine only to look at the result.

Ranked:

1. **Own in-place XML patchers for docx and pptx, same model as `xlsx_patch.py`** (Apache-2.0, our code, lxml only). Copy the *pattern* of Anthropic's docx/pptx skill scripts (merge fragmented runs, duplicate slide with all bookkeeping, clean orphans, validate against the original). Gives byte-identical untouched parts. Effort: about 5 to 7 days for docx + pptx patch helpers and a shared `verify()`; xlsx is already prototyped (about 1 day to land).
2. **Render-and-measure loop with LibreOffice (we already run Gotenberg) plus `pypdfium2` for text boxes.** Not for editing: for checking overflow, page count and "did the text land there". Effort: 3 to 5 days for a `doc_check` tool (render, extract text bboxes, compare with shape boxes). Details in the measurement section.
3. **`docx-editor` (PyPI, MIT, pure Python) for tracked changes and comments in Word**, as a dependency if its save is confirmed to be in place, otherwise as a pattern. Hash-anchored paragraph IDs, batch edit that is atomic, word-level diffs into `w:ins`/`w:del`. Effort: 2 to 3 days to evaluate against our fixtures and wrap as `doc_edit` operations. Risk: young, 41 stars, no tagged releases, "does it keep other parts byte-identical" is unverified.
4. **Docxodus / Python-Redlines (MIT, .NET binary in a Python wheel) for "compare two versions and produce a redline".** Only worth it if users ask for "show me what changed against the original". Effort: 2 days; adds a .NET binary to the image. Not needed for the model's own edits.

Not worth adopting: libre-office-mcp (pattern only), GongRzhe servers (archived), Excel MCP (openpyxl round trip), Collabora/CODE (same engine as Euro-Office, heavier), docx4j and POI (JVM, no gain over our patchers).

## Comparison table

| Candidate | Fidelity model | Operations | Model-friendly | Licence | Footprint | Maintenance (2026-10-27) | Headless, self-hosted |
|---|---|---|---|---|---|---|---|
| libre-office-mcp | Round trip through LibreOffice UNO (open copy, edit, store, replace) | 156 tools (Writer 55, Calc 51, Impress 42, core 8) incl. tracked changes, comments | Good: typed tools, index addressing, batch | MIT | Ubuntu image + LibreOffice + fonts, GBs | Rewritten 2.0 on 2026-10-23/24; 16 stars; 23 commits; 9 test files | Yes |
| LibreOffice UNO via unoserver | Round trip (re-exports OOXML) | Anything UNO exposes | Needs our own tool layer | MIT (unoserver), MPL-2.0 (LibreOffice) | LO install, 1 to 2 GB RAM per busy instance | unoserver 3.7 (2026-06-10) | Yes |
| Collabora Online / CODE | Round trip (same core) | Same plus live co-editing | Not an API for models | MPL-2.0 (GitHub shows NOASSERTION) | Large, server + LO | Very active (pushed today) | Yes |
| GongRzhe Word / PowerPoint MCP | python-docx / python-pptx load and save | Create, format, tables, images | Fair | MIT | Small | **Archived** (last push 2025-12-31) | Yes |
| haris-musa excel-mcp-server | openpyxl load and save (drops x14 extensions, see earlier report) | Charts, pivots, formulas, 260-function calc engine | Good | MIT | Small | Active, 4,267 stars | Yes |
| Open XML SDK (.NET) | In-place, typed XML; save keeps other parts | Everything in OOXML, low level; has a validator | Needs a wrapper | MIT | .NET runtime | Very active (4,616 stars, pushed 2026-10-26) | Yes |
| Open-Xml-PowerTools | In-place + comparer (WmlComparer) | Compare, accept/reject, markup simplify | Needs a wrapper | MIT | .NET | **Archived/stale** (last push 2024-11-12) | Yes |
| Docxodus / Python-Redlines | In-place; produces redline docx | Compare, accept/reject, move detection, docx to HTML | CLI + Python | MIT | Self-contained .NET binary per platform | Active (pushed 2026-10-24, 1,824 commits) | Yes |
| docx4j | In-place JAXB tree | Wide, incl. tracked changes | Needs a wrapper | Apache-2.0 per project (API returned none; unverified) | JVM | Active (pushed 2026-10-25) | Yes |
| Apache POI | In-place-ish object model (XWPF/XSLF/XSSF) | Wide, weak tracked changes | Needs a wrapper | Apache-2.0 | JVM | Very active | Yes |
| docx-editor (PyPI) | Pure XML, tracked changes (in-place unverified) | Replace/insert/delete as revisions, comments, accept/reject | Very good: hash paragraph IDs, atomic batch | MIT | Tiny (defusedxml only) | 0.8.2 (2026-08-31), 41 stars | Yes |
| docx-revisions (PyPI) | python-docx extension | Read/write `w:ins`/`w:del` | Low level | MIT | Tiny | 0.1.5 (2026-04-14) | Yes |
| python-pptx | In-place on parts it touches; `save()` rewrites all parts | Shapes, text, notes; no slide duplicate | Medium | MIT | Tiny | **Last release 1.0.2 on 2024-08-07** | Yes |
| SuperDoc | Browser editor with its own model | Tracked changes, comments, co-editing | UI first | **AGPL-3.0** | Node | Very active (1,111 stars) | Yes |
| Anthropic docx/pptx skills | Unzip, edit XML, validate, re-zip, render | Whatever the model writes, plus helper scripts | Medium (model writes XML) | **Proprietary: excluded**, quality benchmark | LO + poppler + node | Active | Yes |
| OpenAI `doc` skill | python-docx edit, render to PNG to check | python-docx level | Medium | Not checked (mirrors only) | LO + poppler | Active | Yes |
| MS Word / Aspose / Spire / ONLYOFFICE commercial | Native or proprietary | Everything | n/a | **Proprietary: excluded** | n/a | n/a | n/a |
| Euro-Office Document Builder | Engine round trip, rewrites all parts | JS API | Needs a wrapper | AGPL-3.0 | 7.2 GB, 2 GB RAM | Young fork | Yes |

## 1. libre-office-mcp (read in full)

Repo: https://github.com/harshithb3304/libre-office-mcp. Cloned and read; nothing run.

**Maturity.** Created 2025-04-03 as a small v1 (last v1 commit 2025-05-27). The current server is a **rewrite ("2.0") landed on 2026-10-23 and 2026-10-24**, so it is days old. 23 commits total, 16 stars, 10 forks, 0 open issues, last push 2026-10-23. Tests: 9 files, about 4,000 lines (writer, calc, impress, http, lifecycle, unit), run inside Docker. No releases. The README says the tests run on Linux inside Docker; I did not run them.

**Licence.** MIT (`LICENSE`). Fine for us.

**How it edits** (`docs/ARCHITECTURE.md`, `src/libreoffice_mcp/worker/session.py`, `client.py`):
- MCP server (Python `mcp` SDK, stdio or streamable HTTP) talks line-JSON to a **worker** on the system Python that has `uno`. The worker drives one `soffice --headless` over a private named pipe.
- Each call copies the file to a scratch dir, opens the copy, runs "ops" (UNO code), stores it, then `os.replace` over the original. Batch tool = one load, one save, all or nothing.
- So this is a **full LibreOffice round trip**. Every save re-exports the whole OOXML file from LibreOffice's model. That is the opposite of what the owner wants for untouched parts. LibreOffice drops or rewrites things it does not model (x14 extensions, some SmartArt, theme details, custom XML, field codes), and changes styles IDs and relationships. The README says nothing on fidelity of untouched parts; I found no test that compares untouched parts byte for byte.
- It is not python-docx and not the soffice CLI for edits. UNO only. (`office_convert`/PDF export uses LibreOffice.)

**Tool list** (`docs/TOOLS.md`, generated, 156 entries incl. headings). Writer: read text, structure with paragraph index, find, styles, tables, images, comments, footnotes, headers/footers, tracked changes (get, set on/off, accept all, reject all), add comment. Calc: ranges, formulas, formats, column/row fit, comments, cell info. Impress: 42 tools incl. get/set shape text, geometry, notes, replace text, duplicate slide, move slide, layouts, masters. Core: create, copy, convert, info, batch edit.
- Useful for us as a *surface list*. Note: tracked changes are "switch recording on, then edit"; there is **no tool that says "replace this exact run as a tracked change author X"** beyond that, and no overflow or fit check tool for Impress (only Calc column/row auto-fit).
- Addressing by 0-based block index is a good idea we already have in `doc_outline`.

**Security posture.**
- Paths: resolved, `..`, `~`, symlinks checked against `--root` (`paths.py`); Docker sets root to `/data`. Good pattern.
- Macros: `MacroExecutionMode = NEVER_EXECUTE` on load (`session.py`). Good.
- Network: **no authentication on the HTTP transport** by design; binds 127.0.0.1; Host-header check against DNS rebinding (`http_server.py`). Insert-image tools take local paths; I found no URL fetching in the source (grep for http/urlopen/requests found none outside comments). LibreOffice itself can fetch linked images/OLE/external links on open unless disabled; `UpdateDocMode = NO_UPDATE` is set, which helps.
- Per-request timeout, whole-process-group kill, private profile dir, tini as PID 1. Careful and sensible.

**Verdict.**
- As a dependency: **no**. Round-trip fidelity is the wrong model, it is 4 days old, one maintainer, and a second service in the image.
- As a pattern: **yes, partly.** Copy: scratch copy + atomic replace; `NEVER_EXECUTE`; root-confined paths; timeout kills the whole process group; batch = one load/save, all-or-nothing; generated tool docs. Cerea already has several of these.
- As a tool-surface checklist: the Impress tools `set_shape_geometry`, `align_shapes`, `set_slide_layout`, `set_footer`, `set_slide_hidden`, `modify_table` are things `doc_edit` does not have yet.

## 2. Other candidates

### LibreOffice UNO headless (unoserver, unoconv, python UNO)
- unoserver 3.7 (PyPI 2026-06-10, MIT, 943 stars). Keeps a warm `soffice` and gives you convert over XML-RPC. unoconv is the older one and superseded by it.
- Editing through UNO works (libre-office-mcp proves it) but it is a round trip. Good for: layout truth, PDF/PNG render, page counts, accepting tracked changes (Anthropic's `accept_changes.py` uses LibreOffice for this), converting `.doc` to `.docx`. Bad for: byte-exact preservation.
- Footprint: LibreOffice is already in Gotenberg. A warm unoserver gives faster calls than Gotenberg's per-request spawn and exposes real UNO measurements (see below). Needs a PID/lock discipline and a profile dir per worker.
- Verdict: use as **read-only measurer and renderer**, not as editor.

### Collabora Online / CODE
- https://github.com/CollaboraOnline/online. Very active, MPL-2.0 (GitHub says NOASSERTION; it is a mix). Same LibreOffice core as above plus a browser UI and co-editing over WOPI. It competes with Euro-Office for the later co-editing slot, and is lighter in some setups. No model-friendly edit API: you automate through the browser protocol or UNO. Not for accurate model edits.

### Other Office MCP servers
- **GongRzhe/Office-Word-MCP-Server** (2,110 stars) and **Office-PowerPoint-MCP-Server** (1,859 stars): MIT, both **archived**, last push 2025-12-31. python-docx / python-pptx load and save. No tracked changes. Not a base.
- **haris-musa/excel-mcp-server** (4,267 stars, MIT, active 2026-10-26): built on openpyxl, with its own formula engine (260 functions checked against recorded Excel results), pivots, charts, sparklines, trace precedents. Rich and well kept. But it is openpyxl load/save, so it hits the x14-loss issue we reproduced. Useful as a **feature checklist** and for its formula-evaluation and "why is this number wrong" tools, which our service lacks. Check the formula engine licence before copying anything (it is in the same MIT repo).
- None of these is better than our own typed ops on fidelity.

### Microsoft Open XML SDK and PowerTools
- **dotnet/Open-XML-SDK**: MIT, 4,616 stars, pushed 2026-10-26. Strongly typed in-place editing, and `OpenXmlValidator` checks against the schemas. This is the gold standard for "valid OOXML". It is .NET, so it would be a sidecar or a CLI in the image. The cheapest way to get its benefit: use its **validator** as an optional check (the Anthropic skill ships XSDs for the same purpose and validates with Python).
- **OpenXmlDev/Open-Xml-PowerTools**: MIT, 642 stars, last push 2024-11-12; Python-Redlines' README says Microsoft archived it. WmlComparer, accept/reject revisions, markup simplifier, SmartTag/runs coalescing live here. Do not depend on it directly; its maintained descendant is Docxodus.
- **Docxodus** (https://github.com/JSv4/Docxodus): MIT, 103 stars, pushed 2026-10-26, 1,824 commits. Compare/redline to native tracked changes with move detection, accept/reject (`RevisionProcessor`), docx to HTML, a "markdown projection with stable block anchors for LLM agents", CLI, npm WASM build and Python client. **Python-Redlines 2.0.0** (2026-10-24, MIT) wraps it with per-platform wheels that embed a self-contained .NET binary (size not stated, unverified). Use case: "redline my edited file against the original". That is a diff tool, not an editor, so it ranks 4th.

### docx4j and Apache POI
- docx4j: Apache-2.0 (the project is Apache-licensed; the API licence endpoint returned nothing, so confirm before use), pushed 2026-10-25. Rich in-place JAXB model, tracked changes supported, MailMerge, PDF via XSL-FO. JVM sidecar, big dependency set. No reason to choose it over our Python patchers unless we add a JVM for another reason.
- Apache POI: Apache-2.0, very active. XWPF/XSLF/XSSF are object models; known weak on tracked changes and on keeping unknown parts. Same "needs a JVM" cost. Skip.

### Python libraries for tracked changes
- **docx-editor** (https://github.com/pablospe/docx-editor, PyPI 0.8.2, 2026-08-31, MIT, 41 stars, 185 commits, tests + Codecov). Dependency: `defusedxml` only. Replace/delete/insert as revisions across run and element boundaries; `rewrite_paragraph()` makes word-level revisions; comments (add, reply, resolve, delete); accept/reject; paragraph IDs like `P2#f3c1` and an atomic `batch_edit()`; saves via temp file + rename, turns on Track Changes in settings.xml, refuses Restrict-Editing documents. I only read the README: whether the save leaves unrelated parts byte-identical is **unverified**; test it first on our fixtures.
- **docx-revisions** (PyPI 0.1.5, 2026-04-14, MIT): adds `w:ins`/`w:del` read/write to python-docx. Low level; python-docx's save rewrites more than needed.
- **python-docx** itself: 5,751 stars, MIT, pushed 2026-08-01. No tracked changes, no comments writer for older versions (1.2 added comments, unverified for revisions). `save()` re-serialises the parts it loaded.
- **python-pptx**: MIT but last release is 1.0.2 (2024-08-07). Cannot duplicate slides; `text_frame.text=` flattens run formatting (Anthropic's pptx skill warns of both). Stale; we already depend on it, so we need to own the gaps.

### Pandoc
- GPL-2.0 (a separate binary is fine as a tool, but not something to link). Good for reading docx to markdown with `--track-changes=all` and for a text view. Anthropic's skill notes `--track-changes=accept` does not join paragraphs whose runs were all deleted. Not an editor for fidelity: any pandoc write rebuilds the file. Use only to read, if at all (our `doc_read` already does).

### How Anthropic and OpenAI skills edit (public material)
- **Anthropic docx skill** (`skills/docx/SKILL.md`, scripts: `merge_runs.py`, `comment.py`, `accept_changes.py`, `office/validate.py`, `office/soffice.py`, XSD schemas). Edit flow: `unzip`; strip symlink entries (input is untrusted); `merge_runs.py` to coalesce fragmented runs so text is findable; edit `word/document.xml` in place, no pretty-printing; `zip -Xr`; `validate.py out.docx --original doc.docx` (XSD checks, `--auto-repair`); with `--author` it reports any changed text **not wrapped in `w:ins`/`w:del`**. Comments: `comment.py` writes the six cross-linked parts (comments, commentsExtended, commentsIds, commentsExtensible, rels, content types). Render check: `soffice` to PDF, `pdftoppm` to JPEG, model looks at the images. Licence: **proprietary**, so excluded as a dependency; we copy ideas only, not code. It is the quality benchmark.
- **Anthropic pptx skill** (`skills/pptx/SKILL.md`, scripts: `add_slide.py`, `clean.py`, `thumbnail.py`, `office/validate.py`): same unzip-edit-zip. `add_slide.py` duplicates a slide with all registration. `clean.py` removes orphans after `sldIdLst` is final. Rule: do structural changes (add, delete, reorder) before touching slide text. Use `defusedxml.minidom`, never ElementTree (namespace prefixes). Validate with `--original`. Visual QA by rendering. Notes: a duplicated slide still references the source's chart parts.
- **OpenAI `doc` skill** (mirrors of openai/skills curated `doc`; I could not open the repo page, so this is from mirrors): python-docx for edits, render docx to PDF to PNG (`soffice` + `pdftoppm`, or a bundled `render_docx.py`), re-render after each change, fall back to text extraction and say layout risk if rendering is not possible. A lighter model than Anthropic's: higher level, less fidelity.
- Lesson: both give the model a **render-and-look loop**, and Anthropic adds **a validator that compares against the original**. Our typed ops can do better than "the model writes XML": the op applies a precise patch, and `verify()` proves what changed.

### Proprietary (excluded, benchmarks)
- Microsoft Word/PowerPoint/Excel (and Graph/Office add-ins), Aspose, Spire.Office, GroupDocs, ONLYOFFICE commercial builds. Quality benchmark for layout and for tracked changes. Excluded by the licence rule.
- SuperDoc is AGPL-3.0 (OSI-approved, so not excluded) but AGPL is the same problem and benefit as Euro-Office: keep separate, unmodified. It is a browser editor, not a headless edit API.

## 3. Layout measurement: what is realistic

Today we estimate fit with a heuristic. Options, from cheapest to strongest:

1. **Real font metrics in Python (Pillow `ImageFont` / `fontTools`, optionally HarfBuzz via `uharfbuzz`).** Measure each run's width with the actual font (Carlito/Caladea/Liberation are the metric-compatible stand-ins for Calibri, Cambria, Arial/Times). Wrap to the box width minus insets, apply line spacing (`a:lnSpc`, `a:spcBef`), paragraph spacing, bullet indents, `normAutofit` font scale. Good for single shapes, runs in the Pyodide sandbox if fonts are provided, milliseconds. Accuracy: close for Latin text with metric-compatible fonts; off for kerning/complex scripts and for fonts we do not have. Effort 3 to 4 days. This is the right upgrade for the "does it overflow" estimate.
2. **Render with LibreOffice and measure the PDF** (strongest realistic option). Gotenberg already converts pptx/docx to PDF. Then use `pypdfium2` (BSD-3/Apache-2.0) or `pdfminer.six`/`pdfplumber` (MIT) to get text char boxes per page, and compare to shape boxes from the pptx (EMU to points). For docx: page count, where a heading falls, whether a table splits. Caveats: LibreOffice is not PowerPoint/Word. It is close with the right metric-compatible fonts but line breaks and autofit differ at the edges, and a missing font (no Calibri) shifts everything. Say "approximate, LibreOffice layout" in tool output. `PyMuPDF` is AGPL: avoid; poppler `pdftotext -bbox` is GPL as a separate binary and fine only as a subprocess.
   - To compare per shape, you need to know which PDF text belongs to which shape. Practical trick: for each text shape, match its words in reading order to the PDF chars within the shape's page region, then see whether any chars fall outside the shape's rectangle (or beyond the slide). Effort 3 to 5 days for pptx, 2 days more for docx page-level checks.
3. **UNO-based measurement** (via unoserver or the soffice already in the image): for Impress, a shape with auto-grow turned on reports its grown height after layout, and Writer exposes page/line cursors. This gives the engine's own numbers without PDF parsing. I did not verify these API calls here (unverified); libre-office-mcp's `impress_get_shape` and `calc_set_row_height(fit)` show the same idea works. Needs a warm LibreOffice with a lock; effort about 1 week; more fragile than option 2.
4. **A pptx layout engine** in the sense of a pure-library one: I found none that is maintained and OSI-licensed. (Not exhaustive.)

Suggested path: do (1) first to replace the heuristic inside `doc_edit` results, and (2) as an explicit `doc_check` tool the model calls after edits, which returns per-slide overflow flags plus a rendered PNG. That mirrors what the Anthropic and OpenAI skills do (render and look) but returns numbers, not only pictures.

## 4. What this changes for Euro-Office

- Euro-Office (earlier spike): Document Builder works but rewrites every part, 7.2 GB image, about 2 GB RAM. Judged against the owner's priority, it is **not an accurate-editing engine**. It is the same class as LibreOffice here: an engine round trip.
- So: **demote it to "live co-editing and human editing UI", later.** Keep Part A (side panel editor) and Part C (co-editing) on the roadmap but do not build Part B (server-side Document Builder as the editing engine). Its 4 to 5 days are better spent on the docx/pptx patchers above.
- Boundary to keep: model edits go through the typed in-place ops; a human opening a file in the Euro-Office editor and saving is a user action that rewrites the file. Say so in the UI and keep versions.
- One synergy: after a human saves in the editor, our patchers still work on the result. And a patcher edit can be pushed to the live session through the plugin channel, later.
- If the owner ever needs layout truth from a Microsoft-compatible engine, Euro-Office's renderer might be closer to Word than LibreOffice is. That is a hypothesis, not tested.

## Open items to verify before building

1. Does `docx-editor` leave untouched parts byte-identical on save? Test with the fixtures used in the 2026-10-26 report.
2. Run one real Excel/PowerPoint/Word open of the patched fixtures (the earlier report only checked structure).
3. Confirm the docx4j licence text in a release artifact if the JVM option is ever considered.
4. Check the licence of the Excel MCP formula engine before borrowing any code (MIT repo, but confirm per directory).

## Sources

- https://github.com/harshithb3304/libre-office-mcp (files read: README.md, docs/ARCHITECTURE.md, docs/TOOLS.md, src/libreoffice_mcp/worker/session.py, src/libreoffice_mcp/http_server.py, Dockerfile, LICENSE)
- https://github.com/anthropics/skills (skills/docx/SKILL.md, skills/pptx/SKILL.md, script listings)
- https://github.com/pablospe/docx-editor , https://pypi.org/project/docx-editor/
- https://github.com/JSv4/Python-Redlines , https://github.com/JSv4/Docxodus
- https://github.com/dotnet/Open-XML-SDK , https://github.com/OpenXmlDev/Open-Xml-PowerTools
- https://github.com/GongRzhe/Office-Word-MCP-Server , https://github.com/GongRzhe/Office-PowerPoint-MCP-Server
- https://github.com/haris-musa/excel-mcp-server
- https://github.com/unoconv/unoserver , https://github.com/CollaboraOnline/online
- https://github.com/plutext/docx4j , https://github.com/apache/poi
- https://github.com/python-openxml/python-docx , https://github.com/scanny/python-pptx , https://pypi.org/project/docx-revisions/
- https://github.com/superdoc-dev/superdoc
- OpenAI doc skill via mirrors: https://skills.sh/openai/skills/doc , https://mcpservers.org/agent-skills/firecrawl/openai-skills/doc
