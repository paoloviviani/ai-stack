# STATE: new chat artifact types (math, table, Pyodide files) — 2026-09-25 brief

Branch: `feat/artifact-types` (from origin/main a52ce2f1). Worktree:
`/home/ubuntu/.paseo/worktrees/artifacts-cerea`. Work ONLY here; never
commit to / push main, never merge. THIS FILE stays uncommitted.

Env: Mongo e2e-mongo-8796 (port 8796). Playwright env (same command line):
`export E2E_APP_PORT=5391 E2E_MONGO_PORT=8796 MOCK_OPENAI_PORT=18891
MOCK_OIDC_PORT=18892 MOCK_MCP_PORT=18893 ; unset OPENCODE_CONFIG_CONTENT
OPENCODE_CONFIG`. Vitest: `TEST_MONGODB_URL=mongodb://127.0.0.1:8796/ ... --no-file-parallelism`.
Heavy commands wrapped: `timeout -s KILL <secs> flock /tmp/heavy.lock …`
(+ `free -m` first; wait if available < 1500 MB). RESTRICTION LIFTED by
orchestrator: builds + Playwright allowed (per-base builds, E2E_SKIP_BUILD=1,
--project=chromium). No docker needed. `git add <specific files>` only,
never `-A`/`.`. This STATE file lives OUTSIDE the repo (absolute path
above) and must never be committed.

## Done

- `npm ci` (clean).
- ITEM 1 (math) — commit 0de8fe91. FINDING: markdown artifacts ALREADY
  render LaTeX: the panel's markdown preview is `MarkdownRenderer` on
  `version.content`, i.e. the same worker-pool `marked.ts` pipeline (KaTeX
  block + inline extensions) as chat messages. No renderer change; the
  model-facing promise was missing, so added to both surfaces in
  `src/lib/server/textGeneration/artifacts.ts` (`ARTIFACTS_SYSTEM_PROMPT`
  tags mode + `ARTIFACT_TOOL_GUIDANCE` tool mode): "markdown supports
  $inline$ and $$display$$ LaTeX". Copy/download/export carry raw source
  and are unaffected. Tests: `marked.spec.ts` (inline `$x^2$` → katex,
  `$$…$$` → katex-display via the MarkdownRenderer block path),
  `artifacts.spec.ts` (both prompt strings mention LaTeX),
  `exportConversationMarkdown.spec.ts` (math passes through export
  verbatim). Vitest 3 files: 81 passed.
- ITEM 2 (table) — commit 33f5e77a. Decision: CSV (not TSV; documented
  in tool description + system prompt). New `src/lib/utils/csv.ts`:
  RFC-4180 parser (quoted fields, embedded commas/newlines, `""`, CRLF,
  BOM, tolerant unterminated quote), `MAX_TABLE_RENDER_ROWS = 5000`,
  numeric-aware `compareTableCells`, `rowMatchesQuery` — no new dependency.
  Wiring: `ArtifactKind` += table (+ csv/text/csv aliases), ARTIFACT_TYPES
  enum, guidance + prompt bullets, export fence ```csv, `.csv` downloads,
  card label "Table" + carbon/table icon, panel branches (srcdoc skip,
  code-view plaintext, no fullscreen; streaming stays raw text in code tab).
  New `TableGrid.svelte`: sortable 3-state headers, filter input, row
  counts, cap note "download for the rest", raw-text fallback when
  unparseable; header copy/download carry the full CSV. Tests: `csv.spec.ts`
  (18), tool schema + create/reject, registry aliases + filename + collect,
  export fence, guidance wording. Vitest 5 files: 133 passed.
  `npm run check`: 0 errors (fixed tuple-rest typing + unused var; hook
  eslint also clean on commit).
- Next: ITEM 3 (file artifacts) — DONE, commit 3afbc155. Design: file
  artifacts derived client-side from persisted `execute_code` resolved
  updates (`collectFileArtifacts`: filename = identifier, re-run = new
  version, byte-identical re-run adds nothing, bytes stay in
  GridFS/codeExecutionOutputs). Shared `$lib/utils/filePreview`
  (kind/mime/caps) reused by refactored `FileCard` (behavior unchanged,
  client tests pass) and new `FileArtifactView` (PDF unsandboxed frame +
  type/size checks + mobile fallback, DOCX offscreen + DOMPurify, text /
  image inline, download card otherwise). Panel: file artifacts on the
  shared nav axis (view="artifact"), version nav, header download.
  SIDEBAR DECISION: MERGE — library rows open the file artifact in-panel
  (same view, no duplicate listing); download stays per row; orphans keep
  legacy links; export section unchanged. Export lists executed files as
  generated files (deduped). Share: shared conversations render the same
  ChatWindow, so file artifacts appear automatically (download auth for
  anonymous viewers is pre-existing route behavior). Chat-fence /
  artifact-cell scratch files stay session-only per the deliberate
  deliverables rule. Tests: fileArtifacts/filePreview/paneItems specs +
  export merge + FileCard client suite (16 pass). `npm run check`: 0 errors.
- Next: Playwright specs + per-base builds + runs. Specs WRITTEN, commit
  b627bdaf (not yet run): `chat-artifact-table` (grid/sort/filter/download/
  reload), `chat-artifact-math` (inline + display KaTeX, reload),
  `chat-artifact-files` (seeded GridFS PDF + DOCX: registry, unsandboxed
  PDF frame, DOCX render, v1/v2 nav, export listing, reload). Screenshots
  to `reports/` (uncommitted) inside the specs.
- E2E run 1 (root base): 4 existing tool tests pass; 3 new specs failed on
  spec bugs, not app bugs: sort button named by content ("amount"), panel
  not auto-opening after reload (reopen via chat card), library showing two
  rows for two versions of one file. Fixes: d200aa59 (library collapses by
  filename, newest wins — versions live in-panel; this IS the brief's
  no-duplicate rule) + 4058f4e8 (locators, reload reopen).
- E2E run 2 (root base): table + math pass. Files failed only on the export
  step: seeded turns lacked terminal updates so the page read "generating"
  and disabled export. Fix 4b87d99c (finalAnswer in seed). Rerun: files
  spec passes (4.9s).
- Next: APP_BASE=/chat build + touched specs with E2E_APP_BASE=/chat, then
  the whole suite at each base.
- /chat base: APP_BASE=/chat build ok; touched 7 (3 new + 4 existing
  tool tests) ALL PASS with E2E_APP_BASE=/chat (50.5s). Screenshots:
  reports/artifact-table.png, artifact-math.png, artifact-file-pdf.png
  (uncommitted). Note: headless chromium does not paint the native PDF
  viewer (blank page in shot) — the data:application/pdf src + unsandboxed
  frame assertions prove the wiring; panel chrome (title, v2, v2/2) renders.
- Full suite, root base: 149 passed, 1 failed (scroll-anchoring read-mode
  wheel test — untouched by this work; passes alone on rerun: flaky).
- FULL suite with E2E_APP_BASE=/chat: 149 passed, same 1 flaky failure
  (passes alone at /chat too).
- Final: `npm run check` 0 errors; eslint + prettier clean on all 28 branch
  files (`npm run lint` equivalent; note lint-staged skips .svelte so ran
  prettier --write manually → commit cb2f303a). Touched vitest: 9 files,
  191 passed (server) + FileCard client suite 16 passed.
- Pushed feat/artifact-types (8 commits, only mine; reports/ + STATE file
  uncommitted). DONE.

## In progress

- Item 3 design: file artifacts derived client-side from
  persisted `execute_code` resolved updates (`files: PersistedDeliverableRef[]`)
  via a `collectFileArtifacts` walk (filename = identifier, re-run = new
  version, bytes stay in GridFS/codeExecutionOutputs). Shared
  renderer-selection util extracted from `FileCard` (`previewKindFor` etc.),
  reused by panel file view; PDF keeps unsandboxed-frame exception +
  type/size checks, DOCX keeps docx-preview + DOMPurify. Sidebar decision
  PENDING (leaning MERGE: library rows open the file artifact in-panel;
  export section stays). Chat-fence / artifact-cell scratch files stay
  session-only (deliverables rule is deliberate; only persisted tool-run
  outputs have the persistence item 3 requires).

## Left

- Item 3 implementation + commit(s).
- Playwright specs (root + E2E_APP_BASE=/chat): table sort/filter/download;
  markdown inline+display math; Pyodide PDF + DOCX as artifacts w/ preview,
  surviving reload. Screenshots under `reports/` (uncommitted).
- Per-base builds + full Playwright runs; final `npm run check`,
  eslint/prettier, touched vitest specs.
- Final reply per brief Report section.

## Test log

- `npm ci` — ok.
- vitest `marked.spec.ts` + `exportConversationMarkdown.spec.ts` +
  `textGeneration/artifacts.spec.ts` — 3 files, 81 tests passed.
- vitest `csv.spec.ts` + `artifacts.spec.ts` (utils) +
  `exportConversationMarkdown.spec.ts` + `artifactTool.spec.ts` +
  `textGeneration/artifacts.spec.ts` — 5 files, 133 tests passed.
- `npm run check` — 0 errors, 0 warnings.
