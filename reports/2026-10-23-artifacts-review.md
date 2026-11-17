# Produced-file cards and previews: review and proposal (2026-10-23)

Status: phases 1 and 2 done (code reading, bundle inspection, real-build Playwright reproduction and a CSS-injection prototype of the card family). Nothing of the redesign is implemented. One small fix is on branch `fix/plain-file-card` (section 5).

## 1. What was ruled out

- Build-time deletion of `setArtifactsContext`: NOT the cause. The call `uu({get registry(){...},get fileRegistry(){...},panel:q,get requestFix(){...}})` is present in the v0.22.2 image bundle (`client/chat/_app/immutable/chunks/BQflelN2.js`) and in a fresh build of main. A build deletion would make every card plain, including the artifact cards the owner also sees.
- Regression in what a turn stores between v0.21.1 and v0.22.2: not found. `git log v0.21.1..v0.22.2` over execution, generation, builtinTools, MessageUpdate/ParkedCall types, conversation routes, fileArtifacts and utils/execution touches only the ML-assistant removal, plan tool and sub-agents (SubAgent updates are a new update type, replaced by uuid; no CodeExecution handling changed). `CodeExecutionCard`, `FileArtifactCard`, `RunOutput`, `fileArtifacts.ts` have no commits since v0.21.0. The sharing removal and hard-fork cleanup do not feed the registry (it is derived in `ChatWindow` from `messages` + `runFiles.all`).

## 2. Cause of the plain card on a fresh turn (reproduced)

The plain card is the LIVE-SESSION card. In the tab that ran the code, `CodeExecutionCard` and `RunOutput` render the run's own `outputFiles` (sandbox path + size, no sha256) and pass no `sha256` to `FileArtifactCard`; with no sha it cannot join the registry and falls back to `FileCard`. `CodeExecutionCard.displayState` deliberately keeps preferring the live RunsStore entry for as long as the tab holds it (comment: avoid swapping a working card for one that depends on the upload). The registry does get the file (the resolved update / `codeRunFiles` record arrives), but the live card never looks it up. A reload drops the RunsStore, the replay path (`persistedFiles` with sha) is used, and the same file becomes the artifact card.

This explains the owner's pattern exactly: yesterday's turns are seen after a reload (artifact cards), today's turns are seen in the tab that is still holding the run, typically a phone tab left open (plain cards). It dates from bcad0da7 (2026-09-27) and affects every release since, including v0.21.x; it is not new in 0.22.x.

Reproduction in a production build (`E2E_SKIP_BUILD=1`, Chromium, real Pyodide, fence run producing `hello_world.docx`): before the fix the card shows icon, monospace name, size, "Preview", download and never gains the "Open ... in panel" button (`tests/chat-live-file-card.spec.ts` fails). Screenshot: `screenshots/2026-10-23-file-card/before.png`. After: `after.png`.

Not reproducible from code, still possible: a file that never gets a card after reload because its upload did not complete (see 4.2).

## 3. Preview inconsistency (pptx-glimpse in the plain card vs PDF in the panel)

Both read `filePreviewKindFor(name, {fromBytes, officePreview})` in `src/lib/utils/filePreview.ts`:

| Surface | `officePreview` option | pptx result |
|---|---|---|
| live plain `FileCard` (no `downloadUrl`) | `officePreviewEnabledIn(page.data) && downloadUrl !== undefined` = false | `pptx`: drawn in the browser by pptx-glimpse as images (works on phone) |
| artifact card, panel `FileArtifactView`, replayed `FileCard` with `downloadUrl` | deployment flag only (`officePreviewEnabled`, true when Gotenberg is configured) | `office`: server converts to PDF, shown via the PDF path |

The PDF path is `<iframe src=data:application/pdf>`; `browserRendersPdfInFrame()` (`previewSrcdoc.ts`) is false on any mobile UA or iPadOS, and the panel then shows "X opens in the browser's PDF viewer / Open in a new tab". So on a phone, with a converter configured, every stored Office file previews via a path that is a dead end, while the unstored live card uses the working one. Same file, two renderers, chosen by whether a store URL exists, not by what the device can show.

Per-type matrix (code reading; device column = what the code does, not measured on a phone):

| Type | Renderer | Desktop | Phone |
|---|---|---|---|
| png/jpg/gif/webp | image / `InlineRasterImage` | ok | ok |
| svg, html, md, text, code | srcdoc iframe / text | ok | ok |
| pdf | data-URL iframe | ok | "Open in a new tab" only |
| pptx, no converter | pptx-glimpse images | ok | ok |
| pptx, converter | server PDF via PDF path | ok | new-tab only (the owner's screenshot b) |
| docx, no converter | docx-preview | ok | ok |
| docx/xlsx, converter | server PDF | ok | new-tab only |
| xlsx, no converter | none | download only | download only |

Limits of my verification: the box has no WebKit system libraries, so only Chromium desktop ran; the phone behaviour is read from `browserRendersPdfInFrame` and the panel template, not measured. No 390 px screenshots were produced.

## 4. Fragilities found

1. Two card families chosen by data availability (sha present or not), not by intent; plain `FileCard` is a permanent second design.
2. The durable record exists only if the browser's upload succeeded before the one-shot outcome POST: `resolved.files` is built from `outcome.fileRefs` (`executeCodeTool.ts`, ~L349). If the upload fails, the tab is backgrounded, or the response is lost, the recorded outcome has no `files`: after reload there is no card at all (sandbox bytes gone), and the model never learns the file is gone. The POST wins the server CAS once; a later upload cannot amend it.
3. Registry membership depends on message state: tool runs through the `Resolved` update, fences/cells through a separate `codeRunFiles` record that needs the message saved (409 retries about 10 s), so the same file can be an artifact in one place and not another.
4. `findFileVersionBySha` returns the first match; identical bytes under two names resolve to the first name.
5. Same-name rewrites are versions (v2...), identical bytes append nothing; the card's "Open" follows latest when it points at the last version, which is correct but invisible.
6. Sub-directory files: names are reduced to the basename on cards (`file.path.split("/").pop()`), so `a/report.pdf` and `b/report.pdf` collide into one artifact.
7. The panel's `filePreviewKindFor` ignores the device, so converter-on means PDF on phones.

## 5. Small fix on the branch (separate from the redesign)

`fix/plain-file-card`: a live run's file card now resolves to the artifact card once the run's upload has answered. `RunState.uploaded` (name, size, sha256) is set by `RunsStore.noteUploaded` from `CodeExecutionCard` and `CodeBlock` after `uploadRunFiles`; `RunOutput` and `CodeExecutionCard` pass `uploadedSha(...)` (match on basename and size) to `FileArtifactCard`. Until the upload and the registry record land, and if the upload fails, the card stays plain exactly as before. The artifact panel's cell runs (a separate ArtifactRunsStore) are not changed. Also added: `scripts/check-bundle.mjs` (fails if the built client has no artifacts-context call) run in the Dockerfile right after `npm run build`, with `src/lib/utils/bundleCheck.spec.ts` for its logic. Tests: RunOutput and CodeExecutionCard client tests (live cases), Playwright `tests/chat-live-file-card.spec.ts`.

## 6. Proposal (not implemented)

Goal: one card for every produced file, always resolvable, one preview pipeline per type that behaves the same on desktop and phone.

1. Identity at production time. A run's files get their identity (sha256 + name + size) the moment the sandbox lists them, computed in the browser (SubtleCrypto over the bytes already read for upload). `RunState.outputFiles` gains `sha256`. The card always has a sha; no live/replay split. Files: `runs.svelte.ts` (collectOutputFiles hashes), `runFiles.ts`. Removes the `uploaded` bridge of section 5.
2. Registry feeds from runs, not only from stored updates. `collectFileArtifacts` additionally folds live `outputFiles` (keyed by message id via the existing `withLiveRunFiles` pattern) so a file is in the registry from the instant it exists, and after reload from the persisted record. Deterministic order: message order, then listing order. Data shape: none stored; `FileArtifactVersion` unchanged.
3. Durable upload that cannot be lost silently. Send `files` (name, size, sha256 from step 1) in the outcome POST regardless of upload success, and add `uploaded: boolean` per file; the server records them, and the card shows "not saved - download only while this tab is open" when false instead of vanishing. A late upload can then amend the stored update (`$set` on the matching file entry). Migration: none needed for old rows (`files` optional, entries without `uploaded` read as true).
4. Delete the plain `FileCard` from produced-file surfaces. `FileCard` remains only as the internal body of the artifact card for unresolved-bytes edge cases (upload pending), rendered with the artifact card's layout. `ProducedFilesCard`, `RunOutput`, `CodeExecutionCard` all render `FileArtifactCard` only.
5. Preview pipeline per type, device-independent. Decision function `previewPlan(name, {converter, canFramePdf})` in `filePreview.ts`, used by card, panel and replay alike:
   - pptx: pptx-glimpse always (from bytes: live sandbox, or the store's `/output/<sha>` route). The converter's PDF is not used for pptx.
   - docx: docx-preview always; xlsx: keep download-only until a client renderer exists (or converter PDF on desktop only).
   - pdf: render with pdf.js to canvases inside the panel on every device (no pdf.js dependency exists today: `package.json` has none, so this is a new dependency, decision for the owner), or rasterised page images from Gotenberg's PDF if a converter exists. Keep "Open in a new tab" as a secondary action only.
   - images, text, md, code, html: unchanged.
   Files: `filePreview.ts`, `officePreview.ts`, `FileArtifactView.svelte`, `FileCard.svelte` preview handlers collapse into one `PreviewHost`.
6. Sub-directories: key artifacts by full relative path, show the basename with the directory as a subtitle; `findFileVersionBySha` returns all matches and the card prefers its own name.
7. Existing conversations: no data migration is required for 3 (optional fields). Rows lacking `files` stay as they are (no bytes exist to recover).

Tests that would have caught each bug:
- plain card on a live run: Playwright `chat-live-file-card.spec.ts` (added) plus a client test that a settled live run's card has `Open ... in panel`;
- build deletion class: `check-bundle.mjs` in the image build (added); the src-only `bundlerAnnotations.spec.ts` cannot see dependencies;
- phone PDF dead end: a Playwright project with a mobile UA (Chromium `devices["Pixel 7"]`, plus WebKit once its libraries are installed) opening a stored pptx/pdf and asserting slides or canvases render, not the "Open in a new tab" chip;
- lost upload: a server test that a POST with failed upload still records `files` with `uploaded: false`, and a client test of the "not saved" card;
- subdirectory collisions: `fileArtifacts.spec.ts` case with `a/x.pdf` and `b/x.pdf`.

## 7. Card family design: execution card and file rows (proposal, prototyped by CSS injection)

Prototype method (AGENTS.md "Validating UI with screenshots"): throwaway Playwright spec on the real production build, seeded conversation with six states (running, done with 1 file, done with 9 files, error, expanded code, and a model-written fence with 4 files incl. two images with inline preview), CSS injected per variant with `addStyleTag`, no source changes. Chromium only, desktop 1440 and phone 390, light and dark. Contact sheets (rows = states, columns = current | tinted | flat | outlined), in `screenshots/2026-10-23-file-card/`:
- `sheet-light-desk.png`, `sheet-light-phone.png`, `sheet-dark-desk.png`, `sheet-dark-phone.png`
- `before.png` / `after.png`: the live-run card fix (section 5).

What the sheets show (I viewed light-phone and dark-desktop in full; the other two are the same states in the other theme/width):
- Current: thin blue 1px outline, card-in-card (each file in its own bordered tile inside the card), "Called tool execute_code" plus "Assistant-run code" as two stacked lines, no air before the following text. At 390 px the file name is cut to "Cer..." / "pre..." because the Open and Download text buttons take the width. The 9-file case is a stack of nine bordered tiles.
- Tinted (neutral 1px border at 30% grey, soft grey fill, radius 14, 16px padding, files as divided rows, no inner tiles): reads as one surface; the 9-file list is scannable; names wrap onto two lines instead of "pre...".
- Flat (no border, slightly stronger fill, radius 16): cleanest in dark, but in light the card edge relies on the fill alone; weakest contrast of the three on a white page.
- Outlined (1.5px neutral border, transparent): closest to today's look, clear edge in both themes, more "boxed" than tinted.
- Icon-only actions below 520 px (font-size 0 on the buttons, icons kept) plus wrapping names are included in all three variants: on the phone the full name is visible in the 1-file and 4-file states, and the inline image keeps its width.

Recommendation: tinted. Spec for the family:
1. One header row per run: "Ran Python" + status (spinner while running, check and duration when done, cross on error) + chevron. The separate "Called tool execute_code" line is dropped for this tool (the summary already is the tool call); it needs the tool block to be absorbed into the code-execution block in `ChatMessage.svelte` the way plan and delegate blocks already absorb theirs.
2. Surface: `rounded-2xl`, 1px `border-gray-300/60` (dark `gray-600/50`), `bg-gray-500/[0.06]`, `my-3`, header `px-4 py-3`, body `px-4 pb-3`. No blue.
3. Produced files are rows inside the same surface under a divider, never cards inside the card: `FileArtifactCard` gets a `variant="row"` (no border, no tile background, divider between rows); the standalone card form is kept only where a file appears outside a run (a tool's files in the message, the panel library).
4. After a run the code and output stay collapsed; the files are visible directly under the header. An error keeps its message visible under the header (the prototype's collapsed error state hides it, which is a current-design flaw; the sheets show the error state clipped by the sticky composer, so it is not judged there).
5. A fence run (`CodeBlock` + `RunOutput`, the owner's phone screenshot with 4 files): `RunOutput` should not draw its own frame and "FILES" section inside the message column; the fence's status line and its files form the same single surface as above, so the nesting is message column > one surface > file rows (today: column > code block > run output frame > FILES > card > tile).
6. File row at narrow widths: name may wrap to two lines or middle-truncate keeping the extension (`report_…final.pptx`); kind line short ("Slides · 41.8 KB", not "File ..."); Open and Download become icon-only below 520 px with `aria-label` kept (already present), Open first; the left gutter inside the run output is removed with the nesting. At 1440 px keep the text labels.
7. Inline raster previews stay under the row, full width of the surface.

Files to change: `CodeExecutionCard.svelte`, `RunOutput.svelte`, `FileArtifactCard.svelte` (row variant, responsive actions), `FileCard.svelte` (retired or reduced per section 6.4), `BlockWrapper.svelte` (margins), `ChatMessage.svelte` (absorb the tool block), `CodeBlock.svelte`. Tests: client tests for the row variant and icon-only actions via `page.viewport`, Playwright contact-sheet spec kept out of the repo, one narrow-viewport spec asserting the visible name is the full file name for a 25-character name at 390 px.
