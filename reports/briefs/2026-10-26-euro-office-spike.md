# Brief: Euro-Office spike (C12 / Cerea issue #18), research, no merge

The owner approved the plan (2026-10-26): Euro-Office as an optional document backend for Cerea. The integration has three parts:
- **the editor in the side panel:** Cerea serves files through signed links, and each save becomes a new version in GridFS;
- **one set of typed document-editing tools for the model, with two engines:** the sandbox helpers (`xlsx_patch.py`, and `docx_edit` / `pptx_edit` in progress) when Euro-Office is absent; Euro-Office's own engine (Document Builder) on the server when the document isn't open;
- **live co-editing:** a Cerea plugin in the open editor applying the same operations through `callCommand`.

This spike must answer, **with evidence and numbers**, whether the plan is feasible and what it costs. No changes to the Cerea or Pystino repos. The results go to `/home/ubuntu/workspace/ai-stack/reports/2026-10-2x-euro-office-spike.md`, with screenshots under `ai-stack/reports/screenshots/<date>-euro-office/`. Don't commit in ai-stack.

Background: `ai-stack/reports/backlog.md` row C12; `gh issue view 18 -R paoloviviani/Cerea`; `ai-stack/reports/2026-10-26-office-editing.md`. Euro-Office: https://github.com/Euro-Office (DocumentServer, sdkjs, web-apps, server, plugins, document-server-integration). Image `ghcr.io/euro-office/documentserver`; pin a release tag, not latest.

## Questions, in priority order

1. **Runs at all.**
   - Pull and run the pinned image with `JWT_SECRET`, without exposing it beyond localhost.
   - Measure: image size, RAM at idle and while editing one docx, xlsx and pptx, CPU, time to healthy. Use `docker stats` and a short script.
   - Note: the image's README calls Docker "for testing and integration purposes". Check the release notes for what's missing from the image compared with the deb/rpm packages.
2. **Integrator round trip, the essential piece.**
   - A minimal throwaway integrator: a tiny local Node or Python server, not Cerea, serving a test docx through a JWT-signed URL, an HTML page embedding `DocsAPI.DocEditor` with a signed config, and a `callbackUrl` endpoint.
   - Show: open, edit, and the callback delivering the saved file (status 2 / 6 as documented), with forcesave via the Command Service. Confirm the saved bytes are a valid docx with the edit.
   - Time to first paint of the editor. Screenshot desktop and phone (390) view mode.
3. **The server-side engine (key unknown).** Does Euro-Office ship Document Builder usable server-side? Look for a docbuilder binary in the image, a `/docbuilder` endpoint, the Conversion API with builder scripts, or anything equivalent.
   - If yes: run a script that opens a docx, replaces text in one paragraph keeping formatting, sets cells in an xlsx sheet, then saves. Measure time, and compare fidelity with the input (unzip and diff parts).
   - If no: say exactly what exists instead, and whether the Conversion API plus a headless editor could substitute.
4. **Plugins and live editing.**
   - Can a custom plugin be installed into the self-hosted server (mounted plugin folder or config) without rebuilding the image?
   - Build a minimal plugin with a button or postMessage hook that calls `callCommand` to insert a paragraph and set a cell, and show the edit appears live and in co-editing (a second browser session sees it).
   - Can the integrator page (Cerea) talk to the plugin (postMessage/connector)? Is `createConnector` absent, as previously found, and if so, which channel works?
5. **Isolation.** Can it run with no outbound internet (check it doesn't phone home or need fonts/CDN at runtime), as a non-root user, read-only filesystem where possible, with memory limits? What happens at the memory limit?
6. **Licence and attribution.** AGPL-3.0-only for an unmodified container run as a separate service: what notices does Cerea need to show? Does the plugin we'd write carry any licence obligation?
7. **Phone.** The view-only experience on a 390-wide screen: usable? Does a mobile editor exist?

## Constraints
- **The box** has 4 cores, 6 GB RAM, and limited disk: check `df -h` first and prune your own images afterwards. Run only when no other heavy job holds `/tmp/heavy.lock`, and hold `flock /tmp/heavy.lock` for container runs and browser automation. Stop and remove every container and image you started at the end. Never touch containers you didn't create, `~/.config/galopin` or the running galopin.
- `export TMPDIR=/var/tmp/eo-spike && mkdir -p $TMPDIR`; scratch code under `/var/tmp/eo-spike`.
- Never expose ports beyond 127.0.0.1.
- No nested sub-agents.
- Browser automation via Playwright is fine (the Cerea checkout's node_modules has it); screenshots should be readable (viewport-sized, deviceScaleFactor 2 for phone).

## Report format
Answer each question (yes/no/partly), with the evidence (commands, timings, file diffs, screenshots).

Then:
- a go/no-go recommendation for the three parts (panel editor, server engine, live co-editing);
- an effort estimate for each;
- the risks;
- the minimum hardware to recommend in the kit for deployments enabling it.
