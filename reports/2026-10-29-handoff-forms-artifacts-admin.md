# Handoff: PDF form follow-ups, live artifact preview, admin tabs — 2026-10-29

From the Opus orchestration session. Nothing in here is started except the admin tabs (section 3), which are pushed and waiting for checks and review. Cerea main is at `8f72e33cd` (v0.32.4 released; trailer CI check merged).

## Rules for whoever picks this up
- Workers are Sonnet, reviews Opus. One worktree per branch off `origin/main`; `git config core.hooksPath` must be `.husky/_` before the first commit.
- No Co-Authored-By / Claude-Session / "Generated with" lines (hook + CI reject them). Never `--no-verify`, never `git stash`, never force-push.
- `export TMPDIR=/var/tmp/<task>-tmp` before tests. Heavy steps (build, Playwright, docker) under `flock /tmp/heavy.lock`; never wrap a self-locking script in it. Start mongod detached, never inside a flock.
- Run affected tests + lint locally; a bare push triggers no CI: `gh workflow run ci.yml --ref <branch>`, one run per branch, up to date with main.
- Merge `--no-ff` with a real message; delete branch/worktree only after `git merge-base --is-ancestor <head> origin/main`, chained with `&&`, never `;`.
- New UI text says "users", not "people". The repo is public: no private hostnames, no internal doc references in issues or commits.
- Releases need the owner's "go".

## 1. PDF form filling — findings from the owner's ISEE test

Inputs (in `~/.claude/uploads/ab09613d-…/`):
- `5224c677-…rev_2_08022016.pdf`: the original.
- `ed02385a-…-2.pdf`: the filled version 2.
- `06ad19bd-…-flattened.pdf`: the flattened copy.
- `90fa4ca8-form-dummy-data-testing-9eb0da.md`: the chat transcript.

**What the files actually contain** (checked with pypdf + PyMuPDF):
- **The fill is vector.** In the filled version, each of the 26 widgets has an `/AP /N` stream: `BT /Helv 10 Tf … (value) Tj ET` with a Type1 Helvetica resource.
  - No appearance stream draws an image.
  - The only image on the page is the 112×175 logo, the same one the original carries.
  - `NeedAppearances` is unset, so viewers use our appearance streams.
- **The "pixelated numbers" are a macOS Preview quirk.** The owner confirmed it: Preview shows filled field values blurry until the field is clicked, then sharp. The file itself is fine.
- **The flattened copy is correct.** It has no AcroForm. The values are in `CrFlat0…25` Form XObjects, and PyMuPDF extracts them at the right positions (for example `47.000,00` at 484,627 in top-left coordinates).

**Fixes to make (one worker, documents service + skill text):**

1. **Bug: doc_outline misplaces text in flattened PDFs.**
   - On the flattened file, our extractor reports every value as one block at x≈3, y≈2–6 (page bottom-left). The model passed that on to the owner as a "caveat", and it was false.
   - Cause to confirm: the extractor in `documents/src/cerea_documents/` (pdflayout.py / the outline text extraction) doesn't apply the `cm` before `Do`, or the XObject's `/Matrix`, for Form XObjects.
   - Fix it, and add a regression test that flattens a small form and checks the reported value positions against the field rects.
2. **Bug, confirmed by the owner and still happening: the sandbox doesn't see the conversation's files.** Do this one first.
   - In that chat, `execute_code` listed `/mnt/data` several times and found neither the attached PDF nor the produced version 2. The owner confirms it still doesn't find the file. That's why the model couldn't inspect the PDF and spent about 600 lines of reasoning guessing.
   - **A simpler second case from the owner** (`d8c18568-form-contents-check-9eb3fd.md` in the same uploads folder) shows it isn't about produced files:
     - Setup: a new chat with one attached PDF and one `doc_outline` call, then "list /mnt/data". No doc_edit and no produced version.
     - Result: `/mnt/data` and `/mnt/output` exist but are empty, and `*.pdf` across `/mnt` finds nothing.
     - So a plain attachment isn't mounted at all.
     - The model also told the owner that "re-attaching usually restores it". That's invented; the fix should make that sentence unnecessary, and the guidance shouldn't suggest it.
   - Reproduce on current main and on the owner's live version: attach a PDF, run `doc_edit` fill_form, then `execute_code` with `os.listdir('/mnt/data')`. Try both a fresh page load and a conversation reopened later.
   - Leads:
     - Mounting is driven from the chat page into the in-browser sandbox (`src/lib/utils/execution/attachmentMounter.ts`). `sync()` mounts attachments and `syncProduced()` mounts produced files.
     - Each refusal goes through `hooks.skipped({name, reason})`. Check whether a skipped note was shown (MountedChips) or logged, and why.
     - Check the doc-versions changes: the conversation registration with `$effect.pre` and `trackAttachmentSource`, the 5 s list and 30 s download timeouts, and the per-conversation byte cap.
     - Check whether a doc-tool turn, which runs server-side, ever triggers a sync before the next `execute_code`.
   - Fix it with a regression test (attachment plus a doc_edit-produced version, both visible to the next `execute_code`). A live check in the browser is required, since unit tests passed before and this still broke.
3. **Model guidance.** Add these facts to the PDF skill and the `doc_edit` fill_form description, so the next "it looks pixelated" gets a two-line answer:
   - fill_form writes vector text appearances (Helvetica).
   - macOS Preview shows filled fields soft until clicked; that's a viewer quirk, not the file.
   - If the file will be sent or printed and must look the same everywhere, offer the flattened copy.

   Keep it short and keep "never flatten unasked".
4. **Low priority, only if cheap:** field values use Helvetica 10 pt while the form is set in Times/Arial. Not worth a change unless the worker finds a clean way to honour a field's own DA font.

The transcript's other choices were fine. It filled one coherent branch, explained the printed ■ boxes, and flattening created `<name>-flattened.pdf` while keeping the fillable version.

## 2. Artifact preview only appears at the end of the turn

The owner's report: during a turn the artifact panel shows no preview, only at the end. They want to see it while the turn runs.

What the code does today:
- **The panel forces the code tab while the version is incomplete.** `src/lib/components/chat/ArtifactPanel.svelte` (~line 157) has `effectiveTab = !previewable || isStreamingVersion ? "code" : sidePane.tab`.
- **Inline `<artifact>` artifacts complete at their closing tag.** `src/lib/utils/artifacts.ts` (~382): `isLive = !op.closed && message.id === liveMessageId`, so an inline artifact could already preview mid-turn once its tag closes.
- **Tool-mode artifacts start as drafts.** `drafts`, `pendingDraft`, `editingDraft` and `writingDraft` in ArtifactPanel are likely what the owner's model uses, and they appear to become versions only when the call's result lands or the message is finalised. **Confirm this first:** reproduce with both modes and note when `version.complete` flips.

Proposed change (worker, then Opus review):
1. **Preview on completion:** an artifact gets its preview as soon as its content is complete (closing tag, or the tool call's arguments complete), not at the end of the turn. If the user hasn't picked the code tab themselves, the panel switches to preview then.
2. **Live preview while streaming,** for previewable kinds:
   - markdown, SVG and mermaid: re-render throttled (about once a second);
   - HTML: debounced, in the same sandboxed iframe, re-rendered only when the stream pauses or the document parses, so it doesn't flicker or run half-written scripts.

   Keep the code view's existing streaming throttle.
3. **Tests:** component tests for both modes (tab switches when complete; live preview throttled) and a check that an interrupted artifact still shows as interrupted.

Ask the owner before building step 2 for HTML if it turns out costly; steps 1 and 2 for markdown/SVG are the default.

## 3. Admin tabs: nine to six, plus the console button (in progress, stopped on purpose)

- **Branch:** `feat/admin-tabs-consolidate`, head `e1d425b5f`, pushed. Worktree `/home/ubuntu/workspace/wt-admin-tabs`, no uncommitted changes. The worker was stopped by the owner's request to avoid interference.
- **Done in the commit:**
  - **Tabs:** Knowledge · Web (web search + fetching) · Connectors · Skills (its own icon) · Assistant (instructions + sub-agents + voice) · Storage.
  - **Code layout:** the section bodies moved into `src/lib/components/admin/*Section.svelte`, each with an anchor.
  - **Redirects:** the five old URLs 308-redirect to `/admin/web#…` or `/admin/assistant#…`, and `/admin` lands on Web when Knowledge is off.
  - **Console button:** an outlined "Console" button at the end of the title row, with the full sentence as tooltip and accessible name.
  - **Docs, messages and tests:** docs, the en and en-XA messages and `scripts/test_admin_panel_live.py` are updated; new `redirects.spec.ts` and `tabs.svelte.test.ts`.
- **Left to do:**
  1. `pnpm install`; then svelte-check, lint, and the affected tests:
     - `src/routes/admin/**`
     - `SectionSwitcher.svelte.test.ts`
     - `admin-instructions-turn.spec.ts`
     - `InstructionsSection.svelte.test.ts`

     The worker saw the connectors spec fail under load and pass alone; treat it as a flake only if it passes alone again.
  2. `mkdocs build --strict` for the docs changes.
  3. Check the redirect `Location` really carries the hash. Check by eye at desktop and phone widths that the tabs fit on one line and the console button sits at the end of the title row. If a screenshot is taken, store it under `reports/screenshots/2026-10-29-admin-tabs/`.
  4. Dispatch CI once, then an Opus review, then merge `--no-ff` and do the gated cleanup.

## Open items carried over
- Box Node is still v24.21.0 (unpatched for CVE-2026-111497): `nvm install 24.22.1 && nvm alias default 24.22.1` once no worker is running.
- The Playwright image was pruned today; the next e2e run pulls it again.
- Many stale local branches in Cerea; sweep only those already merged (`merge-base --is-ancestor`), if the owner wants it.
- Machine permission asks: the plan is in the private notes and the public issue #48 (not started).
