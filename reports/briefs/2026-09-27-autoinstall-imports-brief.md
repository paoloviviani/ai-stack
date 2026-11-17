# Brief: install a run's imports before it runs, so `from docx import Document` just works

Repo: Cerea. The orchestrator gives you the worktree, branch (off main), ports and Mongo in the launch message. Run `npm ci` first. **A fix for the user's own test case** ("create a hello world docx" from a code block). Nothing beyond this.

## The bug
Twice live, the model wrote a code block that does `from docx import Document` with no `micropip.install`, and it failed with `ModuleNotFoundError`. Today:
- **No auto-install.** The browser runtime (`src/lib/utils/execution/pyodide.worker.ts`) loads micropip and points it at the same-origin vendored wheels (`pinMicropipIndex`: the vendored index, plus the public PyPI index only if the person opted in). It never installs anything from a run's imports: no `loadPackagesFromImports`, and no import-to-package map. So even Pyodide-shipped packages (numpy, pandas, lxml, Pillow) and the vendored document packages need an explicit install first.
- **The prompt only describes the tiers.** The execution prompt (`src/lib/server/textGeneration/executionPrompt.ts`) never says "install before importing", and the import names differ from the package names (`docx` vs `python-docx`, `pptx` vs `python-pptx`).
- **Only execute_code self-heals:** its traceback returns to the model. A chat code block's error is terminal.

## Fix
1. **Before a run, install from the code's imports,** in the worker, the one place every browser run path goes through. Confirm that the chat block (auto-run and Run), the artifact cell and `execute_code` all share it; if one doesn't, cover it too.
   - **Pyodide's own packages:** `pyodide.loadPackagesFromImports(code)` for packages in the lock file (same-origin, from the vendored dist).
   - **The vendored document packages:** a tiny import→package map (`docx`→`python-docx`, `pptx`→`python-pptx`, `openpyxl`→`openpyxl`, `pypdf`→`pypdf`), installed through micropip against the **same-origin index only**. Use the existing pinned index; the public PyPI index stays reachable only when the person has already opted in, exactly as today. No new trust, no new origins, no new dependencies.
   - **Find the imports** robustly: `pyodide.code.find_imports(code)` (or the Pyodide equivalent) rather than a regex. Skip what's already importable. Don't fail the run if an auto-install fails: let the user's code run and raise its normal error.
   - **Surface it** in the run's output or status if an install happens (a line like "Installing python-docx…"), if the existing output channel makes that easy. Otherwise keep it silent.
   - **Cost:** one extra find-imports pass per run is fine; don't re-install per run once loaded.
2. **The prompt belt:** one line in the execution prompt telling the model to install before importing. For example: "Install before importing: `import micropip; await micropip.install("python-docx")`, then `import docx` (the package name differs from the import name)." **Keep the system prompt under the 32k ceiling tests:** `src/lib/server/mlAssistantPrompt.spec.ts`, `src/lib/server/textGeneration/utils/toolPrompt.spec.ts` and `executionPrompt.spec.ts` must still pass. Trim elsewhere in the same prompt if needed, keeping the facts.

## Tests
- **Playwright** (the real Pyodide runtime in the browser, as `tests/chat-artifact-files.spec.ts` already uses), at root AND under `E2E_APP_BASE=/chat`:
  - a chat code block that ONLY does `from docx import Document` (no install), builds a document and saves it, succeeds and produces the file (the file card or artifact appears);
  - a block importing an unknown module (e.g. `import not_a_real_module_xyz`) still fails with the normal `ModuleNotFoundError`, with no hang and no crash.
- **vitest** where it fits: the import→package map, "an already-loaded package isn't reinstalled", "an auto-install failure doesn't block the run". A worker integration spec already exists (`pyodide.worker.integration.spec.ts`); extend it if practical.
- The prompt ceiling specs above, plus `executionPrompt.spec.ts`.
- `npm run check` (0 errors); eslint and prettier on the changed files. Then the touched specs, plus the artifact specs (`chat-artifact-files`, `chat-artifact-math`, `chat-artifact-table`, `chat-artifact-tool`), `chat-autorun-final-answer`, and the terminal specs (`code-terminal`, `code-terminal-mobile`), at root AND under `/chat`, after an explicit build per base, with `E2E_SKIP_BUILD=1 … --project=chromium`.

## Box rules (mandatory)
- EVERY heavy command runs as `timeout -s KILL <secs> flock /tmp/heavy.lock …` **in the foreground** (never background mode), with a timeout longer than the job: 1500 for a build, 1800 for Playwright. Put the `E2E_*` and `TEST_MONGODB_URL` exports on the same command line. Never nest flock (no self-locking scripts under an outer flock).
- If a run is cut off, kill your own leftover Playwright and Chromium processes by PID.
- If `free -m` shows under 1.5 GB available, wait.
- Kill only your own processes. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199. Nothing in `/tmp`.
- No sub-agents, no deploy, no live checks.
- Don't touch sign-in, OIDC or user identity.
- No new dependencies.
- **Commits:** as Paolo Viviani from git config (never override it), with no `Co-Authored-By` trailer. Before pushing, `git fetch` and check that `git log origin/main..HEAD` lists only your commits. Push the branch; don't merge. Never commit probe specs.
- **The disk is tight:** when done, delete the worktree's `build/`, `test-results/` and `playwright-report/`.

## Report
Reply with:
- the design (where it hooks in, and which run paths it covers);
- the prompt line and the ceiling results;
- the commits;
- the test commands and pass counts at both bases.
