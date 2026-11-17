# Brief: three bug fixes and a default change. The provider "Test" for the local extractor (Pystino), and the document reader choice across Pystino, Cerea and cerea-deploy

Three repos, one task, a branch per repo. The orchestrator gives you both worktrees, the branches, the base SHAs, ports and Mongo in the launch message. Run `npm ci` in the Cerea worktree; use the Pystino repo's own test setup (read its README or CONTRIBUTING for how its tests run, and never run `ruff format`).

## 1. Pystino: the provider "Test" is wrong for the local extractor
`test_provider` (`apps/gateway/src/gateway/routers/admin.py`, around line 769) calls `upstream.list_models()` (`GET /models`) for every provider type.
- **Why that's wrong for the extractor:** the `extractor` provider (`plugins/extractor.py`, base URL `http://extractor:8080`) only serves `/healthz`, `/extract` and `/detect`. Test reports "the provider answered 404 — check the base URL includes the version path, e.g. /v1", a false failure; `POST /extract` with a PDF works and returns text through markitdown.
- **Fix:** probe per provider type through a **plugin-level probe method** (each provider plugin knows how to test itself), not a type switch in the router.
  - **OpenAI-compatible providers:** keep `list_models()`, and the `/v1` hint for them only.
  - **The extractor:** `GET /healthz`, then a tiny built-in PDF (a minimal valid one-page PDF, generated or embedded as bytes) sent to `/extract`. Report "reachable; extracted a sample page (markitdown)", or the real failure.
  - **The search provider type** (duckduckgo): check it for the same false negative, and give it an appropriate probe.
  - The response shape the console expects stays the same.
- **Tests:** per plugin (httpx mocking in the style the repo already uses): extractor healthy, extractor `/extract` failing, an OpenAI-compatible 404 still showing the `/v1` hint, and search.

## 2. The document reader choice: the real root cause spans two repos
- **The gateway hides the local extractor on purpose.** Since Pystino `a940516` ("Seed the local extractor by default, and take it out of the model lists"), `GET /v1/models` hides every model whose provider kind is INTERNAL (`_NOT_CALLER_FACING`, `apps/gateway/src/gateway/routers/models.py` around lines 44–51). So `markitdown` never appears in the list, though `/v1/ocr` still accepts it by name.
- **Cerea only offers what that list returns.** Both the Knowledge screen (`src/lib/server/knowledge/service.ts`, `extractorModels`) and `resolveExtractorModel` (`src/lib/server/files/extractDocument.ts`) build their choices from `/v1/models` `kind==='ocr'`. So markitdown is never offered, and the old fallback could only land on `mistral-ocr-4.1` (Cortecs), which failed an upload on a 429.

### 2a. Pystino: an explicit OCR listing includes the local extractor
- `GET /v1/models?include=ocr` also returns internal-provider OCR models, flagged so a caller can tell them apart: e.g. `"local": true`, and/or `owned_by`/`provider_kind: "internal"`. Pick one clear flag and document it.
- **The default listing is unchanged,** so chat pickers never see plumbing.
- Tests: the default listing still hides it; `include=ocr` shows it, flagged; non-OCR internal models stay hidden even with `include=ocr`.

### 2b. Cerea: every reader listed, no "Automatic"
- The Knowledge screen and `resolveExtractorModel` call `/v1/models?include=ocr`.
- The dialog lists every reader, with the local one labelled **"Local extractor (markitdown): on this server, text-layer PDFs and Office files"**. **No "Automatic" entry anywhere**, for the document reader or, for consistency, the embedding model.
- **With nothing chosen,** pre-select the local extractor (by the flag from 2a) and show it as an explicit selection. If there's no local extractor, take the first available.
- **An env value** (`CHAT_OCR_MODEL`, or a direct `CHAT_OCR_BASE_URL` preset; the embedding equivalent if one exists) is shown fixed and read-only, labelled "set in the environment".
- **The server resolves exactly the same way:** one function shared by the screen's loader and `extractDocument.ts`, so what the screen shows is what runs. It must keep working against a Pystino without `include=ocr` (an older gateway): then the local extractor simply isn't offered.
- **The chat's upload error:** an upstream reader failure (429, 5xx) surfaces its real reason, e.g. "the document reader mistral-ocr-4.1 is rate-limited by its provider", not a generic "not available".
- **Tests:**
  - vitest for the resolution order: env-fixed, stored choice, local extractor pre-selected, first available, none, an old gateway;
  - vitest for the error mapping (429 and 5xx);
  - a Playwright check of the Knowledge screen (every reader listed; no "Automatic"; the local extractor pre-selected and labelled) at root and under `E2E_APP_BASE=/chat`. The mock OpenAI server in `tests/mock-openai.ts` may need an `include=ocr` response.
- `npm run check` (0 errors); eslint and prettier on the changed files. Then the touched specs at both bases, after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`.

### 2c. cerea-deploy: pass the reader settings through
- Today `compose.yaml` doesn't pass `CHAT_OCR_MODEL` to the chat at all. Pass through `CHAT_OCR_MODEL`, plus `CHAT_OCR_BASE_URL` and `CHAT_OCR_API_KEY` for the generic preset, and document them in `.env.example`, commented and empty by default.
- Check `docker compose config` renders. The orchestrator gives c308f8d0 a heads-up before merging there.

## 3. Pystino: the local extractor can be deactivated, never deleted
The seeded local extractor provider (plugin `extractor`, kind INTERNAL) must not be deletable; it can only be deactivated and re-activated.
- **Gateway:** `DELETE /admin/providers/{id}` for it answers **409** with "the local extractor can be deactivated, not deleted". Deleting its `markitdown` model row answers the same.
- **Other seeded internal providers** (e.g. the duckduckgo search provider): check whether they deserve the same protection and **report it; don't change them** without the orchestrator's go.
- **Console:** Delete is hidden or disabled for that provider, with a tooltip saying why; Deactivate stays.
- **Re-seeding:** check that the startup seed doesn't silently re-create or re-activate the provider or its model once an admin deactivates it. Deactivation must persist across restarts. Fix the seed if it doesn't.
- **Tests:**
  - the 409 on the provider and on the model row;
  - deactivate → restart (re-run the seed) → still deactivated;
  - re-activate works;
  - the console hides Delete, with a component or e2e test in the style the repo uses.

## 4. Cerea: artifacts on by default for tool-capable models (do this LAST; items 1–3 have priority)
- **Today:** `supportsArtifacts` defaults to false (`src/lib/server/models.ts`, around line 90), and `artifactsEnabledForTurn` (`src/lib/server/textGeneration/artifacts.ts`, around lines 69–75) keeps artifacts off for gateway-discovered models such as `glm-5.3-flash` unless the user flips the per-model toggle in `ModelsManager.svelte`.
- **Change:** the effective default becomes `supportsArtifacts ?? (the model supports tools)`. Any tool-capable model has artifacts on, in tool mode, with inline tags as the fallback, as today.
- **Keep:**
  - an explicit `supportsArtifacts: false` on a model entry, which stays off;
  - the per-user `artifactsOverrides`, winning in both directions;
  - `ModelsManager`'s toggle, which must show the new effective default.
- **Tests:**
  - vitest: a tool-capable model with no flag → on; a non-tool model → off; an explicit false → off; the user override wins both ways;
  - a quick Playwright check that the toggle shows "on" by default for a tool-capable model, at root and under `/chat`.
- Its own commit on the Cerea branch.

## Box rules (mandatory)
- Wrap EVERY heavy command in `timeout -s KILL <secs> flock /tmp/heavy.lock …`.
- Always pass `TEST_MONGODB_URL` to vitest and the `E2E_*` exports to Playwright, on the same command line. Without them the harness falls back to mongodb-memory-server, which can't run on this box.
- If `free -m` shows under 1.5 GB available, wait. Pause heavy jobs whenever the orchestrator says so.
- Kill only the processes you start, by recorded PID. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199.
- Write nothing to `/tmp`.
- No sub-agents.
- Never deploy. No live checks.
- Don't touch sign-in, OIDC or user identity.
- No new dependencies without asking.
- **Commits:** as the repo owner identity, set in git config (never override it), with **no `Co-Authored-By: Claude` trailer**. Before pushing, run `git fetch origin` and check that `git log origin/main..HEAD` lists only your commits. Push the branches; DON'T merge to main.
- Write notes and screenshots under `reports/` if useful, but don't commit there.

## Report
Reply with, per repo (Pystino, Cerea, cerea-deploy):
- the root cause;
- the fix;
- the commits;
- the test commands and pass counts (Pystino's tests; Cerea's vitest, plus Playwright at both bases);
- anything left undone.
