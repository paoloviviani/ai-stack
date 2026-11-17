# Brief: admin tabs — finish, fix the red check, ship (2026-10-29)

## Task
Finish branch `feat/admin-tabs-consolidate` (the handoff's section 3): diagnose the red CI run, run the outstanding local gates, dispatch one green CI run, and report for review. Read the handoff first: /home/ubuntu/workspace/ai-stack/reports/2026-10-29-handoff-forms-artifacts-admin.md (section 3 is your task; the Rules section at its top applies to you verbatim).

## State (verified by the orchestrator)
- Branch pushed at `e1d425b5f`, 0 behind / 1 ahead of `origin/main` (up to date). Worktree `/home/ubuntu/workspace/wt-admin-tabs` is clean; `core.hooksPath` is `.husky/_` ✓.
- CI run **40851262002** on `e1d425b5` FAILED: the `check` job died at **`npm run lint`** (exit 1); everything else green (commit-messages green too). Pull the actual lint failure from the run's `check` log (`gh run view 40851262002 --job <check-job-id> --log`) and fix it at the cause — likely i18n:check or prettier on the new sections/messages, but verify, do not guess.
- The handoff says the worker saw the connectors spec fail under load and pass alone; treat it as a flake only if it passes alone again.

## Do
1. Install deps in the worktree (the handoff says `pnpm install`; the repo's AGENTS.md says `npm ci` — check which lockfile the repo actually has and use that one; say which you used).
2. Fix the lint failure. Then svelte-check, lint, and the affected tests the handoff lists (`src/routes/admin/**`, `SectionSwitcher.svelte.test.ts`, `admin-instructions-turn.spec.ts`, `InstructionsSection.svelte.test.ts`).
3. `mkdocs build --strict` for the docs changes.
4. Check the redirect `Location` really carries the hash; check by eye at desktop and phone widths that the six tabs fit on one line and the Console button sits at the end of the title row. Screenshots (if you take them) go under `reports/screenshots/2026-10-29-admin-tabs/` and you look at every one yourself.
5. Commit anything needed (no trailers; hooks run in this worktree), push, dispatch exactly one CI run (`gh workflow run ci.yml --ref feat/admin-tabs-consolidate`), watch it to completion.
6. Report: the lint failure's cause and fix, gates results, screenshots' paths, CI run id and conclusion.

## Constraints
Heavy steps under `flock /tmp/heavy.lock`; `TMPDIR=/var/tmp/admin-tabs-tmp`; mongod detached, never inside a flock; no stash, no force-push, no `--no-verify`. New UI text says "users", not "people" (owner preference). Do NOT merge — the orchestrator merges after review.

## Outcome (W1, 2026-10-29)

**Branch state:** `feat/admin-tabs-consolidate` at `52cbe8aa7` (lint fix) on top of `e1d425b5f`, pushed, tree clean, hooksPath `.husky/_`. One CI run dispatched, green. Not merged — ready for the Opus review.

**The lint failure, cause and fix.** CI run 40851262002's `check` job died at `npm run lint`, whose first leg is `prettier --check .`; the log names one file, `docs/configuration.md`. Cause: the branch's edits to the `CHAT_DICTATION` / `CHAT_DELEGATION` rows (the new "Settable from Administration → …" links) were hand-padded one space wider than Prettier's column alignment — the `→` glyph's width was counted by eye, and Prettier disagrees by one column. Nothing else in the repo failed; eslint and i18n:check never even ran (the `&&` chain stopped at prettier). Fix at the cause: `npx prettier --write docs/configuration.md` re-padded the two rows to Prettier's canonical alignment (2 lines changed, no content change), committed as `52cbe8aa7`.

**Installer:** `npm ci`. The repo has only `package-lock.json` (no `pnpm-lock.yaml` anywhere), and both AGENTS.md and the CI `check` job say npm ci — the handoff's `pnpm install` is stale on this point.

**Gates, all local on `52cbe8aa7`'s tree:**
- `npm run lint` (prettier + eslint + i18n:check, 2424 messages): **pass**.
- `npm run check` (svelte-check): **0 errors, 0 warnings**.
- vitest server: `src/routes/admin/redirects.spec.ts` 5/5; `src/lib/server/__tests__/admin-instructions-turn.spec.ts` 9/9.
- vitest client (real Chromium): `src/routes/admin/tabs.svelte.test.ts`, `admin.pseudo.svelte.test.ts`, `connectors/page.svelte.test.ts`, `knowledgeMemory.svelte.test.ts`, `src/lib/components/admin/InstructionsSection.svelte.test.ts`, `src/lib/components/nav/SectionSwitcher.svelte.test.ts` — 6 files, **37/37**. The connectors spec was in the list because it once flaked under load: it passed **inside the batch** (14 tests), which is stronger than alone, so no flake to adjudicate.
- `mkdocs build --strict`: **pass** (docs/).

**Redirect Location carries the hash** — verified twice: `redirects.spec.ts` asserts all five load functions throw `{status: 308, location: "/admin/web#web-search" | "/admin/web#fetch" | "/admin/assistant#instructions" | "/admin/assistant#sub-agents" | "/admin/assistant#voice"}`; and over real HTTP against the production build, `curl -i /admin/web-search` → `308` with `Location: …/admin/web#web-search`, `/admin` → `307 /admin/knowledge` (Knowledge on; the Knowledge-off landing on Web is covered by the root +page.server.ts logic and tabs tests).

**Screenshots** (all six eyeballed; measured, not just looked at): `reports/screenshots/2026-10-29-admin-tabs/` — `desktop-1440-admin-web.png`, `desktop-1440-admin-web-sections.png`, `desktop-1440-admin-assistant.png`, `desktop-1440-console-button.png` (element shot), `phone-390-admin-web.png`, `phone-390-admin-switcher-sheet.png`. Desktop 1440: all six tabs share one baseline (one y value) and the tab row does not overflow (scrollWidth 976 = clientWidth 976); the Console button's vertical centre is within 3 px of the title's and its right edge sits at the row's end. Phone 390: the tab nav is hidden, the SectionSwitcher stands in, the Console button shares the title row and fits, and **no element anywhere scrolls sideways** (measured across every element). The sheet lists all six sections in order with icons, current marked. UI text says "users" ("Show these instructions to users").

**CI:** run **40861398437** (`gh workflow run ci.yml --ref feat/admin-tabs-consolidate`, exactly one), on `52cbe8aa7` — **conclusion: success**. check 10m19s, client 9m33s, e2e-smoke 4m32s, go 51s, documents 2m22s, changes 6s; e2e-full skipped (nightly/dispatch-full only). The only annotations are the pre-existing Node 20 actions deprecations.

**Decisions I made myself:**
- The local `prettier --check .` flagged `project.inlang/cache/paraglide-js/*.json`, which CI never sees: the file is gitignored and generated by `i18n:compile`, which runs *after* prettier in the lint script. I deleted the generated cache before linting to mirror CI's order, rather than touching .prettierignore.
- The affected e2e item `admin-instructions-turn.spec.ts` turned out to be a vitest **server** spec (`src/lib/server/__tests__/`), not Playwright; run as such.
- The production build OOM'd twice on this 5 GB box at adapter-node (Vite itself finished): `--max-old-space-size=4096` with the 2 GB swap saw it through. The default heap fails here; worth knowing for the next small-box build.
- For the Console button screenshots I started the hermetic stack myself (playwright-config env, detached, outside the flock) with one addition, `CHAT_CONSOLE_ENABLED=true`, since the stock e2e env doesn't set it and the button is flag-gated. Playwright reused the running servers (`reuseExistingServer`); the throwaway `tests/_shots.spec.ts` was deleted after the run, never committed; the stack was torn down afterwards.

**Addendum — review fixes folded in (W1, 2026-10-29):** commit `f4a39d8e0` on the same branch, two one-liners from the "fix first" review.
1. `scripts/i18n-check.mjs`: `src/lib/components/admin` joins `CONVERTED` (placed in the components group's alphabetical order, not at the line number the review cited) — the five section components the branch moved out of `src/routes/admin` are scanned by the hard-coded-string gate again. `npm run i18n:check` passes: 2424 messages, **183** converted templates (178 before — the newly scanned components are clean, as the reviewer found).
2. `scripts/test_admin_panel_live.py`: the "Detect automatically" marker (removed from the app in `eb5e4e7f1`) is replaced by **"Fetching a URL"** (`admin.fetch.title`) in both the positive check (~line 171) and the negative flow's not-in clause (~line 120, which the review called vacuous) — the negative check again fails when a panel renders for a non-administrator, which was its intent. Chosen over "Web search" because it is page-specific (the tab bar renders "Web", never "Web search", on other tabs). Verified against the production build over HTTP with a seeded admin session: the server-rendered HTML of `/admin/web` contains "Fetching a URL", and no "Detect automatically" remains anywhere in the repo. The script isn't runnable against the hermetic stack (it signs in through a real identity provider); CI covers it nowhere (ruff is scoped to `documents/`), so the gates run were `python3 -m py_compile`, prettier + eslint on the `.mjs`, and the i18n:check above. The ruff SIM115 finding at line 41 is pre-existing code outside CI's scope — untouched.
Pushed, then one CI run dispatched: **40871171791** on `f4a39d8e0` — **success** (check 12m29s, client 7m0s, e2e-smoke 4m28s, go 50s, documents 2m14s). Not merged.
