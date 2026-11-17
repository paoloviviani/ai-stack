# 0103 — Office documents as typed tools on a server-side document service

- Date: 2026-10-26
- Status: **Accepted** 2026-10-26 by the owner, with the recommended answers to the open questions (below).
- Related:
  - 0055: `/v1/ocr`, the local extractor. Reading stays there.
  - The Office-preview work (backlog C10: Gotenberg, pptx-glimpse, `convert_document`).
  - Backlog C12 / Cerea #18: Euro-Office as a document backend.
- Evidence:
  - `reports/2026-10-26-office-editing.md`, the editing investigation.
  - `reports/2026-10-26-euro-office-spike.md`, the spike.
  - The helpers shipped in Cerea 0.29.0: `xlsx_patch.py`, `docx_edit.py`, `pptx_edit.py`.

## Context

Models create and edit Office files by writing Python in the browser sandbox (Pyodide), guided by skills. That fails in three ways:
- **Weak models write fragile file-surgery code.** A colleague's chat needed several attempts and produced one corrupt workbook before it delivered.
- **The general libraries lose formatting.** openpyxl's load and save drops other sheets' extensions; python-docx and python-pptx re-serialise what they parse.
- **The sandbox is clumsy for this:** time limits, mounts, and big wheels loaded per session.

0.29.0 added precise helpers to the skills as a stop-gap: they edit only the parts they touch. The owner's direction (2026-10-26):
- document work moves **server-side**, behind **typed tools**: creation as well as editing;
- the tools are **engine-agnostic**, so Euro-Office can be plugged in later;
- **images in documents** are supported throughout, and charts may be native or embedded images.

The Euro-Office spike showed that it works (panel editor, a server-side scripting engine, live co-editing through a plugin), but that every save rewrites every part of the file. For "change only this", our own helpers are the more faithful engine. Euro-Office's value is human editing in the browser, live co-editing and conversion.

## Decision

### 1. The model works on documents only through typed tools

These are built-in Cerea tools, so they are always present when the service is configured. The model never handles bytes or writes code for documents. Every tool takes and returns **file references**: an attachment, a stored file or an earlier tool result, as the chat's file store names them.

| Tool | Does | Result |
|---|---|---|
| `doc_outline(file)` | structure with stable ids: Word headings, paragraphs, tables, images, sections; Excel sheets, used ranges, tables, charts; PowerPoint slides, shapes, placeholders, images, notes | JSON tree with ids and short text previews |
| `doc_read(file, targets)` | exact content of ids or ranges: paragraph text with run formatting, table cells, a cell range with values and formulas, slide text | JSON |
| `doc_create(format, spec, images?)` | a new docx, xlsx, pptx or pdf from a **document spec** (§2) | a new file, with an outline summary |
| `doc_create_from_template(template, values, images?)` | fill a template the person uploaded in the chat: `{{placeholders}}`, named ranges, layout placeholders | a new file, with a diff |
| `doc_edit(file, operations[], track_changes?, author?)` | apply typed operations (§3), all or none | a **new version** of the file, with a diff and a verify report |
| `doc_convert(file, to)` | to `pdf`, `markdown` or `png` (page images); availability depends on the engine | a new file |

Rules:
- **Never in place.** An edit always produces a new version linked to its source. The person can download either one, and the original stays as it was.
- **All or none.** An operation that can't be applied (a missing id, a merged cell, or an operation this format doesn't support) fails the whole call with an actionable message listing what exists. No partial output is written.
- **Every result carries the diff:** a short human-readable list of changes, which the model shows the person, and the **verify** report (valid package; untouched parts byte-identical where the engine guarantees it).
- **Images are first-class input:** an image is a file reference (an attachment, a generated chart, a sandbox output in `/mnt/output`, or a URL already fetched by `web_fetch`). The service never fetches anything itself.

### 2. The document spec, for creation

One JSON schema for all formats, with format-specific blocks. Markdown with a small front-matter is accepted as a shorthand for prose documents, and converted to the same tree.

- **Document:** `title`, `page` (size, orientation, margins), `header` and `footer` (text with page-number fields), `theme` (the neutral built-in style set plus prompt-driven overrides: fonts, colours, heading styles, spacing; or `template`: a file the person uploaded in the chat, to take styles from), `language`.
- **Blocks:**
  - `heading` (level);
  - `paragraph` (runs: text, bold, italic, underline, link, code, colour);
  - `list` (ordered or bulleted, nested);
  - `table` (header row, rows, column widths, alignment, an optional style);
  - `image` (file reference, width or height, caption, alignment);
  - `chart` (§2.1);
  - `page_break`, `toc`, `quote`, `code`.
- **Workbooks:** `sheets[]` with `cells` (values, formulas, number formats, bold, fill), `column_widths`, `freeze`, `autofilter`, `tables`, `charts`, `images` (anchored at a cell).
- **Decks:** `slides[]` with `layout` (from the template or the built-in set), `title`, `body` (blocks), `notes`, `images` (position and size, or "fit placeholder"), `charts`.

#### 2.1 Charts: native or image, the model's choice

`chart { type, title, categories, series[{name, values}], axis titles, legend, render: "native" | "image" }`

| `render` | Word | Excel | PowerPoint | PDF |
|---|---|---|---|---|
| `native` | a native chart (editable in Word); falls back to image if the type isn't supported | a native chart (openpyxl) | a native chart (python-pptx) | image |
| `image` | PNG rendered by the service (matplotlib, deterministic style), embedded | image anchored at a cell | image | image |

v1 types: bar, column, stacked, line, area, pie and doughnut, scatter. The chart's data is kept with the native chart, so the person can edit it in Office.

### 3. Edit operations (v1)

Engine-agnostic names. The first engine implements all of them, with the code ported from the 0.29.0 helpers.

- **Word:**
  - `replace_text` (scope, all or first; spans runs, keeps formatting);
  - `fill_placeholders`;
  - `set_paragraph_text`;
  - `insert_paragraph_after` (style);
  - `delete_paragraph`;
  - `insert_image_after` (file, width, caption);
  - `replace_image`;
  - `set_table_cell`;
  - `add_table_row`;
  - `add_comment` (anchor, text).

  `track_changes` writes `w:ins`/`w:del` with the author and date.
- **Excel:**
  - `set_cells` (values, formulas, dates, style copied from a cell);
  - `clear_cells`;
  - `insert_rows` / `delete_rows` (v1.1: shifts formulas, merged ranges and tables; refused when it can't do so safely);
  - `add_sheet`;
  - `insert_image` (at a cell);
  - `insert_chart`.
- **PowerPoint:**
  - `replace_text`;
  - `set_placeholder_text`;
  - `replace_image`;
  - `insert_image` (position and size, or a placeholder);
  - `duplicate_slide`, `delete_slide`, `reorder_slides`;
  - `add_slide` (layout plus blocks);
  - `insert_chart`;
  - `set_notes`.

Anything not listed is refused with a clear message. Operations grow by need, each with tests.

### 4. Engines behind the tools

The tools call an **engine** interface (`outline`, `read`, `create`, `create_from_template`, `edit`, `convert`, plus `capabilities()`). The chat asks for `capabilities()` and offers the model only what the configured engines can do.

- **`cerea-documents` (default, §5):** precise edits that touch only the parts they change; creation; outline and read; charts; `convert` to markdown. To PDF only for documents it created (rendered through the same spec path), otherwise it delegates.
- **Converter (optional, one of):**
  - Gotenberg (today), or Euro-Office (later), for `convert` of arbitrary files to PDF or page images, and for previews.
  - Euro-Office replaces Gotenberg where it is deployed; a deployment runs one or the other, never both.
- **Euro-Office as an editing engine (later):**
  - **When the file is open in a person's editor:** it applies the same operations live through the Cerea plugin (co-editing).
  - **Otherwise, and for operations our engine doesn't cover:** through its server-side scripting.
  - Its saves rewrite every part, so it never replaces `cerea-documents` for precise edits, and the verify report says which engine wrote the version.

### 5. The `cerea-documents` service

- **Ownership:** a **Cerea-owned image** in the Cerea repo (`documents/`), built and released with Cerea, and pinned by the kit like the chat image. **Not** in Pystino: the extractor stays Pystino's, because it is the gateway's `/v1/ocr` interface for API clients and shares the redaction image. Reading uploads to text stays there; `doc_outline`/`doc_read` give *structure*, which is a different job.
- **Contents:**
  - Python 3, lxml, python-docx, python-pptx, openpyxl, matplotlib (Agg), Pillow;
  - our engine code, ported from the 0.29.0 helpers.

  No LibreOffice and no browser, so the image stays small: the target is under 300 MB.
- **API:**
  - internal HTTP on the stack network only, `POST /v1/{outline,read,create,create_from_template,edit,convert}`, plus `GET /healthz` and `GET /v1/capabilities`;
  - files go in and out as multipart bytes;
  - stateless, no storage, no per-user auth: Cerea is the only caller, and it authenticates with a shared secret header;
  - the kit generates the secret.
- **Flow:** the tool call goes to Cerea, which fetches the referenced files from its store (checking the person's access), posts them to the service, stores the result as a new version linked to the source, and returns the reference, diff and verify report to the model.
- **The kit:** on by default with the chat. Deployments without it fall back to the 0.29.0 in-sandbox helpers, and the skills say which path to take based on the tool's presence.

### 6. Hardening (every input is hostile)

- **XML:** lxml parsers with `resolve_entities=False`, `no_network=True`, `load_dtd=False`, `huge_tree=False`; DOCTYPE refused. This blocks XXE and billion-laughs.
- **Zip:**
  - before parsing: caps on entry count, single-part size, total uncompressed size, and compression ratio (blocks zip bombs);
  - refuse absolute paths, `..`, duplicate names and symlinks;
  - read only the parts the operation needs.
- **Active content:**
  - macros (`vbaProject.bin`), ActiveX and OLE objects are passed through untouched and never executed or parsed;
  - creation never emits them;
  - `.xlsm`/`.docm`/`.pptm` are accepted for editing only if the person's file already is one; the type is never changed silently.
- **Images:**
  - Pillow with `MAX_IMAGE_PIXELS` set;
  - only PNG, JPEG, GIF and SVG-rasterised-by-us (or refused) are allowed;
  - image headers are verified against content.
- **Execution:**
  - each request runs in a fresh subprocess with `RLIMIT_AS`, `RLIMIT_CPU` and a wall-clock timeout, killed on overrun;
  - only typed operations exist, so there is no `eval`, no templates that execute, and no formula evaluation;
  - the spec is validated against a JSON schema before any work starts.
- **Container:**
  - non-root, read-only root filesystem plus a tmpfs, `cap_drop: ALL`, `no-new-privileges`;
  - no outbound network (an internal-only network);
  - memory and CPU limits in compose, and a health check.
- **Tests:**
  - a hostile-fixture suite (zip bomb, XXE, path traversal, huge image, macro file, malformed parts, oversized spec) must be refused cleanly;
  - property and fuzz tests on the parsers;
  - CI runs them.

### 7. What stays in the browser sandbox

General computation:
- data analysis on uploaded data;
- ad-hoc calculations;
- quick charts *for the chat itself*;
- anything that isn't producing or changing an Office or PDF document.

A chart image made in the sandbox can be handed to `doc_create`/`doc_edit` as an image reference. The Office skills are rewritten to use the tools; their bundled helpers remain only as the fallback.

## Consequences

- **More reliable with weaker models:** a typed call either works or fails with a message naming what exists; no code to debug.
- **Faithful edits:** fidelity comes from our engine (byte-identical untouched parts), and creation is deterministic. Native charts stay editable.
- **One more small image for Cerea to build and release,** plus its security surface. It is mitigated by §6 and kept small (no LibreOffice).
- **The kit gains a default service.** Small deployments gain ~300 MB and a little RAM. The optional heavy converter becomes "Gotenberg or Euro-Office".
- **Euro-Office plugs in later** without changing the model's tools or the skills.

## Owner decisions (2026-10-26)

(1) **One neutral built-in style set, styled by the prompt**: the spec's `theme` carries overrides the model sets from what the person asks (fonts, colours, heading styles, spacing, page look). **No admin-uploaded deployment template.** Templates are used only when a person **uploads one in the chat explicitly** (`doc_create_from_template` with that file, or `theme.template` taking styles from it).
(2) PDF creation through the spec path by default, through the converter when one is deployed and asked for.
(3) No metering.

## Open questions (as asked)

1. **Built-in style sets for `doc_create`:** a neutral default only, or also a "deployment template" the admin uploads (company Word and PowerPoint templates)? Recommended: both. The admin template is what makes generated documents look like the organisation's.
2. **PDF creation:** through the spec path (reportlab, deterministic, no converter needed), or always via the converter from a generated docx (better typography, needs Gotenberg or Euro-Office)? Recommended: spec path by default, converter when available and asked for.
3. **Metering:** none, since this isn't model usage. Confirm.

## Plan (after acceptance)

1. **`cerea-documents`:**
   - the service skeleton, hardening and hostile-fixture suite;
   - outline, read, edit for docx, xlsx and pptx, ported from the helpers.
2. **The Cerea tools,** with file references and versioning, the kit service, and the fallback rule in the skills.
3. **`doc_create`:** spec, charts (native and image), images, and `create_from_template`.
4. **`doc_convert` delegation** to Gotenberg; the preview path unified.
5. **Later:** Euro-Office as converter and editor (milestones from the spike), then live co-editing.

## Amendment (2026-10-27, owner)
- **PowerPoint design exception:** the `doc_*` tools stay the only way by default. When the person explicitly asks for a custom visual design the tools can't express, the assistant may build the deck in the sandbox (python-pptx), says so in one line, and never mixes the two ways in one deck. Word, Excel and PDF keep the strict rule.
- **Design elements in `doc_create`, added gradually:**
  - step 1: slide backgrounds (colour, gradient, cover image) and positioned shapes, validated in bounds;
  - later: designed layouts (big number, timeline, comparison, full picture).
  - Each addition narrows the exception.
