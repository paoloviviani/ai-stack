# Brief: new chat artifact types (math, table, Pyodide files)

Repo: Cerea. This is a feature-freeze exception approved by the user. The orchestrator gives you the worktree, branch, base SHA, ports and Mongo in the launch message. Run `npm ci` first.

Today's types (`src/lib/server/textGeneration/builtinTools/artifactTool.ts`, around line 12): `html`, `react`, `svg`, `mermaid`, `markdown`, `code`. Read how the artifact tool, the canonical inline blocks, `ArtifactDraft` streaming, the inline-tag fallback parser and the artifact panel fit together before changing anything.

## How to work (read first: you're an opencode agent, and these rules are not optional)
- **Heavy commands:** every one (npm ci, `npm run build`, `npm run check`, vitest, Playwright) runs as `timeout -s KILL <secs> flock /tmp/heavy.lock <command>`, e.g. 1500 for a build or a Playwright run, 600 for vitest. The box has ~10 GB RAM shared with other agents and has run out of memory before. Before each heavy command, run `free -m`; if under 1500 MB is available, wait and retry.
- **Private ports only:** for every Playwright run, on the same command line, `export E2E_APP_PORT=… E2E_MONGO_PORT=… MOCK_OPENAI_PORT=… MOCK_OIDC_PORT=… MOCK_MCP_PORT=…` (values in your launch message), then `unset OPENCODE_CONFIG_CONTENT OPENCODE_CONFIG`. For vitest, `TEST_MONGODB_URL=mongodb://127.0.0.1:<your mongo port>/`. Without these the harness falls back to mongodb-memory-server, which crashes on this box. Never use port 5199.
- **Processes:** kill every server or process you start, by the PID you recorded when starting it. Never `pkill -f` or `killall` with a pattern. Never touch an `opencode serve` whose parent is "Paseo Daemon". Nothing in `/tmp` (it's RAM).
- **Git:**
  - commit as the repo owner identity, which is already in git config; never pass `--author` or set `GIT_AUTHOR_*`/`GIT_COMMITTER_*`;
  - no `Co-Authored-By` trailer of any kind (a hook rejects Claude ones; don't add others either);
  - WIP commits are fine on YOUR branch only: never commit or push to `main`, and never merge;
  - push only your branch, after `git fetch origin`, and check that `git log origin/main..HEAD` lists only your commits;
  - never make any repo, gist or artifact public.
- **Writing:** cite ADRs by number only ("ADR 0090"), never by link.
- **Licences:** Cerea is Apache-2.0. Ask the orchestrator before adding ANY dependency, stating its name, version and licence. GPL, AGPL, LGPL or an unknown licence is a no. KaTeX (MIT) and anything already in `package.json` are fine.
- **Reuse, don't duplicate:** the chat already renders PDF and DOCX files produced by the Python sandbox (`FileCard.svelte`, `PreviewPane.svelte`, `docx-preview`; see item 3). Build on those.
- **Never:** deploy, touch live containers or `/opt/*`, run checks against cerea.example.org, touch sign-in, OIDC or user identity, run `ruff format`, or spawn sub-agents.
- **Handoff state:** keep `reports/briefs/2026-09-25-artifact-types-STATE.md` up to date after every commit. It records what's done, what's in progress (files and next step), what's left, and the test commands you ran with their results. Another agent may continue your work from this file and your branch alone. Don't commit files under `reports/`.

## 1. Math in markdown artifacts
- **Check first** whether `markdown` artifacts already render LaTeX with KaTeX, as chat messages do.
- **If they do:** say so to the model in the tool description and the artifact prompt: "markdown supports $inline$ and $$display$$ LaTeX".
- **If not:** make the artifact panel's markdown renderer use the same KaTeX pipeline as messages. Reuse, don't duplicate.
- **Tests:** inline and display math render in the panel, and the export and copy views don't break.

## 2. `table`, a new artifact type
- **Content:** CSV or TSV with a header row. Decide which, document it in the tool description, and parse robustly: quoted fields, embedded commas and newlines.
- **The panel:** a sortable, filterable grid, with CSV download and copy.
- **Streaming:** while it's still arriving, render rows progressively, or show the raw text until it's complete, matching how the other types behave.
- **Limits:** a render cap (e.g. 5,000 rows), with a "download for the rest" note.
- **Wiring:** the tool enum, the zod schema, the model-facing description ("table — tabular data as CSV with a header row; the user can sort, filter and download it"), and the inline-tag fallback parser.
- **Libraries:** prefer what's already in the tree. **Ask the orchestrator before adding ANY dependency**, stating its name, version and licence. It must be OSI and Apache-2.0-compatible (Cerea is Apache-2.0).

## 3. Files produced by Pyodide become artifacts (a `file` kind): build on what exists
**DOCX and PDF are already rendered today. Don't add renderers, and don't add mammoth or pdf.js.**
- **`FileCard.svelte`**, used by `RunOutput`, shows files produced by Python in the sandbox. `previewKindFor` returns `text` | `image` | `pdf` | `docx` | `none`.
- **PDF** opens in `PreviewPane.svelte` in the browser's native viewer, **deliberately not sandboxed**, because Chrome and Safari refuse sandboxed PDF frames. It's guarded by an 8 MB cap, an app-set `application/pdf` type, and a mobile fallback (`browserRendersPdfInFrame`).
- **DOCX** renders through `docx-preview` (already a dependency, Apache-2.0): `renderAsync` offscreen, the output sanitised with DOMPurify, from fetched bytes, so it survives reloads.
- **What's missing:** `PreviewPane`'s own header says these previews carry "no registry entry, no versions and no persistence", unlike artifacts.

So item 3 is: **register these outputs as `file` artifacts**, with:
- a registry entry, versions and persistence;
- a listing in the artifact panel;
- inclusion in export and share.

Constraints:
- **Reuse** `FileCard`'s preview logic and `PreviewPane`'s renderers, keeping their exact security posture: the PDF unsandboxed-frame exception with its type and size checks, and docx-preview sanitised with DOMPurify.
- **Put the renderer selection in one place,** so the artifact panel and the side-panel preview can't drift, as `FileCard` already does for its two modes.
- **Other file types:** a download card, as today.
- **Versioning:** a re-run that rewrites the same filename is a new version of the same artifact, as `update`/`rewrite` does for text artifacts.
- **Storage:** keep today's (GridFS / `codeExecutionOutputs`). Never duplicate the bytes.
- **The sidebar outputs list:** keep it or merge it, whichever avoids showing the same file twice. Describe your choice.

**Out of scope:** charts (Vega-Lite) and any server-side execution.

## Tests
- **vitest:** the tool schema and parsing for `table` and `file`, CSV edge cases, and the versioning of a rewritten filename.
- **Playwright** at root AND under `E2E_APP_BASE=/chat`:
  - a table artifact (sort, filter, download);
  - a markdown artifact with inline and display math;
  - a Pyodide-generated PDF appearing as an artifact with its preview, and a DOCX one, both surviving a reload.
- `npm run check` (0 errors); eslint and prettier on the changed files. Then the touched specs at both bases, and the whole suite once at each base, after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`.
- Screenshots under `reports/` (don't commit there): the table, math, and the PDF preview.

## Box rules (mandatory)
- Wrap EVERY heavy command in `timeout -s KILL <secs> flock /tmp/heavy.lock …`.
- Always pass `TEST_MONGODB_URL` to vitest and the `E2E_*` exports to Playwright, on the same command line. Without them the harness falls back to mongodb-memory-server, which can't run on this box.
- If `free -m` shows under 1.5 GB available, wait. Pause heavy jobs whenever the orchestrator says so.
- Kill only the processes you start, by recorded PID. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199.
- Write nothing to `/tmp`.
- No sub-agents.
- Never deploy. No live checks.
- Don't touch sign-in, OIDC or user identity.
- **Commits:** as the repo owner identity, set in git config (never override it), with **no `Co-Authored-By: Claude` trailer**. Before pushing, run `git fetch origin` and check that `git log origin/main..HEAD` lists only your commits. Push the branch; DON'T merge to main.

## Report
Reply with:
- the commits;
- per item, what you did and why (including the KaTeX finding, the CSV/TSV decision, and the sidebar decision);
- any dependency requested;
- the test commands and pass counts at both bases;
- the screenshot paths.
