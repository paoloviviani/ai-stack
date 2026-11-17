# Image rendering brief: I1 (chat figure capture) + I3 (explorer image view)

Worktree: the MAIN checkout /home/ubuntu/workspace/Cerea (branch off main
into feat/image-rendering — create it, work there, push it; no merge, no
deploy). This is Cerea-side Svelte/TS work only; no Go, no galopin. You
implement; ambiguity → stop and report.

Plan of record: the advisor's image-rendering plan (OC has the full text in
oc-orchestrator/STATE.md, 2026-09-28 ~15:00 entry — read that entry first;
it is your spec). I2 (agent tool-output images) is NOT yours yet — it waits
for the slash-commands merge (same events.go + machineTimeline.ts). Do NOT
touch I2, machineTimeline.ts, the forwarder, or anything under agent/.

## I1: chat figure capture (~2d)

**Goal:** notebook-style inline display — a matplotlib figure produced by a
Pyodide run shows as an image under the code block / in the execute_code
card, not just as an unexpanded file card.

- **Hook, in `src/lib/utils/execution/pyodide.worker.ts`'s run path:** once
  `matplotlib` is imported, a Python prelude sets the non-interactive Agg
  backend and replaces `plt.show()` with "save every open figure to the
  working directory as `figure-<n>.png`, then close it". End-of-run sweep:
  any figure still open gets saved the same way. Cap ~20 figures per run
  (a loop must not exhaust the store).
- **No new persistence:** files land in the working directory; the existing
  `collectOutputFiles` → `uploadRunFiles` → deliverable store →
  `Outputs`/`Resolved` update path carries them; reload renders from
  `persistedFiles`. **The message update shape does not change.** If the
  shared output-file list from the file-card work is present, hook into it;
  it is on main — check first.
- **Presentation:** `FileCard` gains an auto-expand option for raster images
  ONLY (png/jpeg/gif/webp — never SVG, see Security); `RunOutput` and
  `CodeExecutionCard` use it. A figure shows as an image with the card
  header above it; every other file type is unchanged.
- **Naming:** `figure-<n>.png` is stable across re-runs → a re-run becomes a
  new VERSION of the same file artifact; opening a card must use the
  sha-matched version (the file-card correction — find it in the recent
  file-artifact work on main and follow it).
- **Tests:** worker-level specs (prelude behavior: Agg set, show() saves +
  closes, end-of-run sweep, 20-cap) in the existing execution spec style;
  component specs for the auto-expand option (raster expands, SVG/text do
  not); follow the repo's vitest idioms (server/ssr/client projects per
  CLAUDE.md — client needs Chromium/Playwright only if you touch .svelte
  behavior; prefer server/ssr-level specs where they suffice).

## I3: explorer image view (~0.75d)

- `src/lib/components/code/CodeFileViewer.svelte` (71 lines, text-only
  CodeMirror today) gains an image branch on `files.read`'s `kind: "image"`:
  render `<img>` from the EXISTING forwarder raw route (it already sends
  nosniff + sandboxed CSP — verify, don't rebuild). `too_large` → a message
  + download link. **SVG keeps its current CodeMirror text view, always.**
- Specs in the existing style.

## Security (binding, from the plan)

- **One rule everywhere: raster png/jpeg/gif/webp inline in `<img>` ONLY;
  SVG NEVER inline** (script-capable document; keep the rule simple and
  testable). SVG outputs stay a file card / text view. Assert this in specs
  (an SVG-named/typed output must not take the image branch).
- I1 bytes come from model-written code in the user's own browser sandbox.
  The download route already sends `attachment` + sandboxed CSP — **tighten
  it: add `X-Content-Type-Options: nosniff` to `output/[sha256]/+server.ts`
  where it is missing** (verify first; only add if absent). Store limits
  apply unchanged (MAX_DELIVERABLE_BYTES, 200 files, 5× per-file cap per
  conversation).

## Non-goals

Model-generated images (work already), video, inline SVG, editing/annotating
images, EXIF stripping, anything agent-side (I2 — not yours).

## Box + git rules (binding)

- Another worker (slash-commands close-out) is ACTIVE on this box. Heavy
  commands serialize through `timeout -s KILL <secs> flock
  /tmp/heavy.lock <cmd>` — always use it, never compete. Before each heavy
  step: `free -m` ≥1500 MB and `df` ≥20% free; if RAM is low, wait between
  steps. Foreground only. NO sub-agents.
- Client vitest needs TEST_MONGODB_URL=mongodb://127.0.0.1:8801 (container
  e2e-mongo-8801). `npm run check` baseline: 13 pre-existing errors — 0 new
  is the rule. No `npm install` (forbidden; the tree already builds).
- Git: the repo owner identity (already configured), NO AI
  trailers, coherent commits on feat/image-rendering, push it. No merge to
  main, no /opt/cerea, never touch ports near 5199.

## Report

Design as built (hook shape, FileCard option, viewer branch, the nosniff
check), files, commits, exact test commands + pass counts, deviations. Then
stop for review — I2 comes only after the slash merge, do not start it.
