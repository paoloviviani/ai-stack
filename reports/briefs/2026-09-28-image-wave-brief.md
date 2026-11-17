# Image rendering brief — I1+I3 (chat) and I2 (agents), two workers

User order 2026-09-28: implement the parked image-rendering plan, split across two
Sonnet 5.5 workers. I2 is UNBLOCKED (the slash wave merged to main as 96f21b18 and
deployed); the advisor's "after the slash merge" condition is met.

Plan of record: the advisor's image plan, logged verbatim in
/home/ubuntu/workspace/oc-orchestrator/STATE.md (2026-09-28 ~15:00 entry) — it is the
spec. Read it FIRST. Branch discipline below splits the work so the two workers
never touch the same files.

## SPLIT

- **Worker A (chat, feat/image-chat)**: I1 (matplotlib figure capture) + I3 (explorer
  image view) + the nosniff tightening + Cerea-side specs. The prior image worker's
  unreviewed work-in-progress is RECOVERED into git stashes on main
  (stash@{0} specs, stash@{1} 11 files, 441 insertions) — `git stash show -p` to read
  them, salvage anything sound, re-verify everything you keep (it was never
  reviewed; do not trust it blindly, and do not ship it as-is).
- **Worker B (agents, feat/image-agents)**: I2 — galopin tool-output images (opencode
  + ACP), the session.attachment op + capability, PROTOCOL §6/§7, the Cerea
  forwarder raw route + machineTimeline mapping + ToolUpdate url branch, live ITs.

File-ownership boundary (hard): A owns src/lib/utils/execution/**,
src/lib/components/chat/{FileCard,FileArtifactCard,CodeExecutionCard,RunOutput}*,
src/lib/components/code/CodeFileViewer.svelte, the output/[sha256] route. B owns
agent/**, src/lib/server/code/**, src/lib/server/code/machineTimeline.ts,
src/lib/components/chat/ToolUpdate.svelte, the code forwarder
(+server.ts), src/lib/machineProtocol.ts. ToolUpdate.svelte is B's alone this wave
(A's FileCard auto-expand must NOT touch it). If a change seems to need the other's
files: STOP and report.

## I1 (chat figure capture, ~2d)

- Hook in src/lib/utils/execution/pyodide.worker.ts's run path: once matplotlib is
  imported, a prelude sets the Agg backend and replaces plt.show() with "save every
  open figure to the working directory as figure-<n>.png, then close it"; end-of-run
  sweep saves still-open figures the same way; cap ~20 figures per run.
- NO new persistence: existing collectOutputFiles → uploadRunFiles → deliverable
  store → Outputs/Resolved path; reload renders from persistedFiles; the message
  update shape does not change.
- FileCard gains an auto-expand option for raster images ONLY; RunOutput and
  CodeExecutionCard use it. Stable figure-<n>.png naming → new versions of the same
  file artifact; opening a card must use the sha-matched version.
- Specs: worker-level (Agg set, show saves+closes, sweep, 20-cap) + component specs
  (raster expands; SVG/text do not) in the repo's vitest idioms.

## I3 (explorer image view, ~0.75d)

- CodeFileViewer.svelte branches on files.read's kind:"image" → <img> from the
  EXISTING forwarder raw route (verify its nosniff+sandboxed CSP; don't rebuild).
  too_large → message + download link. SVG KEEPS the CodeMirror text view, always.
- Specs in the existing style.

## I1/I3 security (binding)

- Raster png/jpeg/gif/webp inline in <img> ONLY; SVG NEVER inline (script-capable;
  keep the rule simple and testable). Assert in specs.
- Verify output/[sha256]/+server.ts carries X-Content-Type-Options: nosniff (the
  prior worker's stash added it — verify, don't assume); add if missing. Store
  limits unchanged (MAX_DELIVERABLE_BYTES, 200 files, 5× per-file cap/conversation).

## I2 (agent tool-output images, ~3.5d)

- galopin maps opencode tool-part state.attachments (image/* data: URLs — where
  Playwright-MCP screenshots land) and ACP tool_call image items into the wire TOOL
  part as attachments: [{sha256, mime, size, filename?}] (extend the part, NOT a new
  part type). Compute sha256 server-side in galopin.
- Bytes stay OFF the stream: galopin keeps a bounded content-addressed LRU (~64MiB);
  cache miss → opencode re-reads its own transcript by callId; ACP images memory-only
  → "no longer on the machine" after a galopin restart. New op session.attachment
  {sessionId, sha256} → {mime, data}, behind a NEW capability toolImages; PROTOCOL
  §6 (op + field) and §7 (the attachments field on the tool part) updated.
- Cerea: machineProtocol.ts field; machineTimeline maps attachments to
  {type:"image", mimeType, url}; NEW forwarder raw route GET v1/agents/:id/
  attachments/:sha256 calling the op (getPairedDevice + session-ownership checks —
  the sha in the URL is NOT a capability); ToolUpdate renders url images next to
  data: ones (it renders data:-only today, ToolUpdate.svelte ~line 208).
- Route security (binding, from the plan): the route checks the BYTES' magic
  numbers itself against the raster allowlist (ignore the claimed mime); reads w×h
  from PNG/JPEG headers and refuses >~50 megapixels (decompression-bomb guard); 8MiB
  cap per image like files.read; N-per-tool-call cap on the wire attachments;
  Cache-Control: private, immutable keyed by sha; NOTHING persisted in Cerea (no
  capability at rest); dedup by sha keeps snapshots/stream small.
- A bash-saved screenshot FILE is I3's viewer's case, not I2's.
- Live ITs (GALOPIN_OPENCODE_IT=1 / GALOPIN_ACP_IT=1): an image-bearing tool part
  lists with the attachment sha; the fetch op returns bytes; a reload renders; a
  galopin restart shows the ACP "no longer" state; the magic-number refusal; the
  >50MP refusal. Follow the existing IT harness idioms (mockllm /__control routes
  are the precedent for additive test helpers).

## Non-goals (both)

Model-generated images (work), video, inline SVG, editing/annotating, EXIF
stripping, persisting agent images in Cerea, cross-machine anything.

## Box + git rules (binding, two workers share the box)

- NO sub-agents each. Foreground only. EVERY heavy command under `timeout -s KILL
  <secs> flock /tmp/heavy.lock <cmd>` — you share /tmp/heavy.lock with the other
  worker; check `free -m` ≥1500 MB and `df` ≥20% free before each heavy step, and
  WAIT between steps rather than compete.
- Client vitest: TEST_MONGODB_URL=mongodb://127.0.0.1:8801. npm run check baseline
  is now 0 errors on main (96f21b18) — 0 new is the rule. NO npm install.
- Never touch ports near 5199, never /opt/cerea, never kill processes you did not
  start. The live stack is PRODUCTION.
- Git: the repo owner identity (configured); NO AI trailers; coherent
  commits; push your branch; NO merge to main (that's the user's, after review).
- vitest client project runs need Chromium; prefer server/ssr-level specs where
  they suffice.

## Report

Design as built, files, commits, exact test commands + pass counts, deviations.
Then STOP for review. If a brief item proves wrong against the real code, report
with evidence rather than guessing.
