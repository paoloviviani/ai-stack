# Brief: artifact preview during the turn (2026-10-29)

## Task
Handoff section 2: the owner sees no artifact preview while a turn runs — only at the end — and wants it during. Read the handoff first: /home/ubuntu/workspace/ai-stack/reports/2026-10-29-handoff-forms-artifacts-admin.md (section 2 is yours; the Rules at its top apply verbatim).

## Step 0 — confirm the mechanics first (the handoff demands this)
Reproduce with BOTH artifact modes and note exactly when `version.complete` flips:
- inline `<artifact>` artifacts: `src/lib/utils/artifacts.ts` (~382) — `isLive = !op.closed && message.id === liveMessageId` says an inline artifact could already preview mid-turn once its closing tag arrives;
- tool-mode artifacts (drafts/`pendingDraft`/`editingDraft`/`writingDraft` in `src/lib/components/chat/ArtifactPanel.svelte`) — these likely become versions only when the call's result lands or the message finalises;
- the panel forces the code tab while the version is incomplete: `ArtifactPanel.svelte` ~157 `effectiveTab = !previewable || isStreamingVersion ? "code" : sidePane.tab`.
Write down which mode the owner's report matches before building.

## Build (after the confirmation)
1. **Preview on completion** (the default): an artifact previews as soon as its content is complete — the closing tag for inline, the complete tool-call arguments for tool mode — even mid-turn. If the user has not picked the code tab themselves, the panel switches to preview then.
2. **Live preview while streaming** for previewable kinds: markdown, SVG and mermaid re-render throttled (~once a second); HTML debounced in the same sandboxed iframe, re-rendered only when the stream pauses or the document parses, so it does not flicker or run half-written scripts. Keep the code view's existing streaming throttle.
   - **HTML caveat:** if the HTML live preview turns out costly or fragile, STOP and say so in your report instead of building it — the owner asked to be consulted before that piece. Markdown/SVG live preview + completion-preview are the default scope.
3. **Tests:** component tests for both modes — the tab switches when complete (and only then, unless the user chose code); live preview is throttled; an interrupted artifact still shows as interrupted.

## Constraints
New worktree off `origin/main`; `core.hooksPath` must be `.husky/_` before the first commit; `TMPDIR=/var/tmp/artifact-preview-tmp`; heavy steps under `flock /tmp/heavy.lock`; no stash/force-push/--no-verify; run the affected client tests + lint + `npm run check`; push once, dispatch exactly one CI run (`gh workflow run ci.yml --ref <branch>`), watch it. Do NOT merge — the orchestrator merges after review.

## Report back
The Step-0 findings (when `version.complete` flips in each mode, and which matches the owner's report), what you built (step 1 always; step 2 scope — including whether you took HTML or stopped to ask), the tests, gate results, CI run id and conclusion.

## Outcome (2026-10-29, worker W4)

**Branch `feat/artifact-preview-during-turn`, head `ef40a118b`** (two commits on `origin/main` @ `34d5dc961` — rebased once after the admin-tabs merge landed mid-task; no file overlap). Worktree `/home/ubuntu/workspace/wt-artifact-preview`. Not merged — ready for the Opus review; the orchestrator merges.

### Step 0 — when `version.complete` flips (verified by reading the streaming path, then pinned by tests)

- **Inline `<artifact>`** (`collectArtifacts`, `artifacts.ts:382`): `isLive = !op.closed && message.id === liveMessageId` (the live message is `messages.at(-1)` while `loading`), `complete = !isLive` — so **`complete` flips the moment the closing tag arrives in the streamed content, mid-turn**. The panel already followed it: `effectiveTab = !previewable || isStreamingVersion ? "code" : sidePane.tab` fell back to `sidePane.tab`, which the auto-open leaves at "preview". An aborted generation finalises instead with `interrupted: true` (no spinner, card says "Interrupted").
- **Tool mode**: while the `artifact` call's arguments stream there is **no version at all** — only the throttled `ArtifactDraft` updates (250 ms), which the panel showed as a plain code block. `version.complete` flips only when the **executed call appends its canonical block** (one Stream `extraUpdate` at call execution, after the round ends) — mid-turn if the model runs another round, at the end if the call was the turn's last act.
- **Which matches the owner's report**: both, in practice — in each mode the panel shows no preview during the whole content-writing phase (inline: forced code tab until the closing tag; tool: draft-as-code until execution), and an artifact is typically the last thing a turn writes, so the preview appeared "only at the end". The tool-mode gap is the longer one; the handoff's guess ("become versions when the call's result lands or the message finalises") was close: the version lands at call execution, not at finalisation.

### What was built

1. **Preview on completion** (both modes now): for inline this already worked and is pinned by tests; for tool mode the draft update now carries `contentComplete` (server emits it as soon as the content string's closing quote lands, plus a **throttle-exempt final draft after the round's stream ends**, since the throttled loop could otherwise skip the tail with no further chunk to re-trigger a parse). A complete previewable draft previews before the call executes, and the preview carries over seamlessly to the canonical block (byte-identical content → same srcdoc string → no iframe reload).
2. **Live preview while streaming**, on by default (the panel shows the preview during the turn unless the user picked the code tab, `sidePane.userPinnedTab`): **markdown, SVG and mermaid re-render throttled to ~1/s** (shared snapshot effect, first paint of each new version immediate); **HTML built, debounced** in the same sandboxed iframe — re-rendered only after the stream pauses 1 s and never while a `<script>` element is unterminated (`htmlScriptsBalanced`, new helper in `previewSrcdoc.ts`), so the iframe is not reloaded per token and a half-written script never runs. The code view keeps its existing 150 ms throttle. Preview errors are captured only once the previewed content is complete (half-written code throws by design; the problems pill must not flicker mid-stream, and a stale mid-stream error could otherwise survive into the completed view). Screenshot-to-chat stays completion-only (version-gated).
3. **HTML decision (mine to make, flagged for the owner)**: the handoff said stop if the HTML piece turned out costly. I judged it **not costly**: the mechanism is identical to SVG/mermaid (same builder, same sandboxed iframe, same CSP) with a different timing policy (debounce instead of throttle) plus the script-balance gate and error suppression. Residual risks, for the owner to veto if unwanted: a partial `<script>` mentioned in unescaped text holds the render (safe direction — only lag), a model that streams HTML without 1 s pauses gets no mid-stream refresh until completion (per the handoff's own "stream pauses" wording), and any script side-effects re-run at each debounced re-render (bounded by the existing sandbox: no network, no modals, no storage). Nothing else in the sandbox surface changed.

### Tests (all written to fail without the fix — verified by restoring the pre-fix files and re-running)

- `ArtifactPanel.svelte.test.ts` (new, 10 tests, real Chromium): inline react — code while streaming, preview on completion, and only-then unless the user pinned code; inline markdown — live preview visible mid-stream; SVG — throttle asserts the iframe srcdoc repaints on the trailing edge at ~1/s (fake timers); HTML — debounce on pauses, hold while a script is unterminated, completion always paints; tool-mode table draft — code while arguments stream, preview at `contentComplete`; markdown draft — live preview during streaming and seamless handover to the executed call's version; code-type draft never previews; interrupted version — not live (no "Generating"), previews its partial content; `ArtifactCard` — interrupted version still reports "Interrupted · Document".
- `runMcpFlow.spec.ts` (+3): the final complete draft is emitted when the arguments finish inside the throttle window (mid-escape split), no duplicate when the loop already caught it, and none for non-artifact calls.
- `previewSrcdoc.svelte.test.ts` (+3): `htmlScriptsBalanced` cases.
- Evidence: with the four fixed files restored to HEAD, the 5 new-behavior panel tests and 2 of 3 server tests fail; the 5 regression guards pass.
- Also updated 3 assertions in `tests/chat-artifact-tool.spec.ts` / `chat-artifact-math.spec.ts` that would now hit Playwright strict-mode collisions: the live preview renders the artifact's own `# Title` heading beside the panel header of the same name, so the panel-header assertions are pinned to level 2.

### Gates

- Affected client tests: ArtifactPanel (10) + previewSrcdoc (17) + ChatWindow, PreviewPane, SidePane, DeliverablesPanel ×2, FileArtifactCard, FileArtifactView, MarkdownRenderer (74) — all green, run serially after a wide-open parallel run hit memory contention on this 5.8 GB box (one OOM kill at 13:48 UTC interrupted the session; work was committed first, then resumed per the orchestrator's adjustments).
- Server: `runMcpFlow.spec.ts` full file + `applyUpdate.spec.ts` + `artifactDraft.spec.ts` — 145 green.
- `npm run lint` (Prettier + ESLint + i18n:check) and `npm run check` — 0 errors, 0 warnings. (A Prettier warning on the git-ignored paraglide cache appears locally only after `check` regenerates it; CI lints before anything compiles paraglide, and the clean-tree lint run passed.)

### CI

`gh workflow run ci.yml --ref feat/artifact-preview-during-turn` — exactly one dispatch, **run 40882646869: success** (check 13m04s, client 8m25s, e2e-smoke 3m17s, go 48s, documents 2m26s). The artifact e2e specs are not @smoke, so they run in the nightly, not on this dispatch; their edits are reasoned from the component tests but have not executed against the built app yet.
