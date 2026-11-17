# Brief: F1, a read-only file explorer in /code (galopin + Cerea)

Repo: Cerea. It contains the Go machine agent **galopin** in `agent/` (Go 1.24, gofmt/vet/test). Worktree: `/home/ubuntu/.paseo/worktrees/f1-cerea`, branch `feat/code-files`, cut from `origin/main`, with node_modules symlinked.

**The design is decided and specified. Read these first, in full:**
1. `agent/PROTOCOL.md` §9, "Machine powers: files and terminals", plus the §4 policy fields and the §5 `Machine`/`Policy` shapes. This is the contract.
2. ADR 0090, at `/home/ubuntu/workspace/ai-stack/docs/adr/0090-machine-file-explorer-and-terminal.md`.
3. The plan, `/home/ubuntu/workspace/reports/2026-09-24-code-files-and-terminal-plan.md`: §2.1–2.2 (UX), §5.1 (`internal/files`), §6 (security), §8 (tests), and "F1" in §10. The decisions D1–D14 are accepted as recommended.

## F1 scope (only this; no search, watch, write or terminal)
**galopin:**
- `internal/files` with `files.list`, `files.stat`, `files.read` and `files.status`, exactly per §9.3. Use `os.OpenRoot(workspace.path)` for every access. Symlinks are listed with `target`/`escapes`/`dangling`; escaping ones are never followed. Skip `.git/`; set `hidden`. Ignore flags come from one `git check-ignore -z --stdin` per list; status from `git status --porcelain=v2 -z --untracked-files=all`, cached 1 s and capped. Type detection is by extension plus an 8 KiB sniff; `revision = dev:ino:size:mtimeNs`. Follow `agent/internal/checkout`'s git helper style.
- Policy (`agent/internal/policy`): `files: "read"|"off"` (default `"read"`) and `fileDeny` (default: the §9.4 list). Enroll flags: `--no-files`, `--file-deny GLOB` (repeatable) and `--no-default-file-deny`. Matching entries are redacted, reading them is `forbidden`, and `files: off` makes every `files.*` op `forbidden`. The enroll epilogue states the files policy in plain words.
- `hello.machine.capabilities` with `files: true` (the others false for now), plus the new policy fields in `hello.policy`.
- Dispatch `files.*` before the backend switch (`agent/dispatch.go`, like `workspace.*`). These ops never call the backend.
- Update `agent/README.md`, and `docs/agent-machines.md` for the flags.

**Cerea:**
- Types in `src/lib/types/machineProtocol.ts` (`Entry`, `Machine`, the policy fields) and `src/lib/types/CodeAgent.ts` as needed.
- Forwarder routes in `src/routes/api/v2/code/[...path]/+server.ts`, per §9.6 and plan §4.2: `GET …/workspaces/:ws/files?path=`, `…/files/content?path=&offset=&length=`, `…/files/raw?path=` (raster images only, with `nosniff` and `CSP: sandbox; default-src 'none'`; everything else as text/plain or an attachment, never HTML/SVG inline), and `…/files/status`. Same `getPairedDevice` rule as the others. Map `forbidden` to 403 with the policy message, and `too_large` to 413.
- The deployment switch `CODE_FILES_ENABLED`, default on when the code panel is on. Add it to `.env` with a comment, like the other `CODE_*` switches.
- Audit (D14): a new `codeAudit` Mongo collection with a 90-day TTL index on `at`, holding `{userId, deviceId, action, workspaceId?, path?, bytes?, ip, userAgent, at}`. For F1, record veto refusals and raw image reads. **Never content.** Add a vitest asserting that neither the logger nor the audit ever receives file content.
- **UI:**
  - The agent view's side pane (`src/lib/stores/sidePane.svelte.ts`, `AgentView.svelte`) gets one "workspace" pane with tabs **Changes | Files**. Changes is today's diff view. The header button opens the pane on its last tab.
  - **Our own Svelte tree** (D10): virtualized, lazy per-directory expand, directories first, git badges rolled up to folders, ignored entries dimmed and never auto-expanded, redacted entries with a lock and "hidden by this machine's policy", no `.git/`.
  - A **CodeMirror 6 read-only viewer**: lazy-loaded chunk, syntax highlighting by extension, the first 1 MiB with "Load more", images via `<img>` on a blob URL (SVG only through `<img>`), "Binary file · <size>" for binaries.
  - A refresh button, plus an automatic refresh of status and the open file at each turn boundary (`status idle`) of a session in the workspace.
  - "Open in Files" from a Changes file header. The sidebar workspace kebab gains "Browse files", which opens `/code?device=&ws=&view=files` full-width.
  - All links use `${base}`.
  - Mobile below 768 px: see plan §2.4 for the files part.
- **Dependencies:** CodeMirror 6 packages (`@codemirror/*`, MIT) are approved by the plan. Use only the modules you need, and list them in the report. No other new dependency without asking; the project is OSI-licensed, and a non-OSI dependency needs approval. Icons come from the existing `unplugin-icons` Carbon/Lucide sets (D13), never Codicons.

## Tests (required)
- **Go:**
  - `os.Root` confinement: `..`, absolute paths, escaping and dangling symlinks, and a directory swapped for a symlink mid-operation;
  - the deny list (defaults, `--file-deny`, `--no-default-file-deny`);
  - `files: off`;
  - UTF-8 range trimming, binary/image detection and the 8 MiB image cap;
  - git status and ignore decorations on a temp repo;
  - enroll flag parsing and the hello capability.
- **vitest:** the forwarder routes (the veto maps to 403 with the flag message, `too_large` to 413), the raw route's headers and refusals (SVG and HTML never inline), the `CODE_FILES_ENABLED` switch, `codeAudit` shape and TTL with no content, and the tree's badge roll-up and sort. Run with `TEST_MONGODB_URL=mongodb://127.0.0.1:8796/ npx vitest run --no-file-parallelism <files>`. Mongo 8796 is a private container for you; if it doesn't exist, report it rather than using another port.
- **Hermetic Playwright:** extend `tests/fake-machine.ts` with `files.*` and add a spec: browse the tree, open a file, check the badges, the lock on `.env`, the image preview and "Load more".
- **Real-machine Playwright** (`tests/code-machine-parity.spec.ts` or a new `tests/code-machine-files.spec.ts`; the harness builds galopin from `agent/`): a real workspace with a git repo, a modified file (badge), a `.env` (lock) and a symlink escaping the root (listed, not followed); the file opens in the viewer; after an agent turn edits a file, the turn-boundary refresh shows it.
- Run Playwright at root and under `/chat`. `npm run check` 0/0, `npm run lint` clean.

**How to run Playwright:**
1. Build alone: `flock /tmp/heavy.lock npm run build`, or `APP_BASE=/chat flock /tmp/heavy.lock npm run build`.
2. Then: `E2E_SKIP_BUILD=1 E2E_APP_PORT=5371 E2E_MONGO_PORT=8796 MOCK_OPENAI_PORT=18871 MOCK_OIDC_PORT=18872 MOCK_MCP_PORT=18873 flock /tmp/heavy.lock npx playwright test tests/code-*.spec.ts --project=chromium --reporter=line`. Add `E2E_APP_BASE=/chat` for `/chat`.

WebKit is not installed: always `--project=chromium`.

## Box rules (mandatory)
- Wrap every heavy command (builds, check, Playwright, `go test` with ITs) in `flock /tmp/heavy.lock …`. The box OOMs otherwise.
- Use only the private ports above. Never use 5199. Kill only what you started, by recorded PID; never `pkill -f` with a pattern.
- Never run `ruff format`. Use `npx prettier --write` on the files you touched, and gofmt for Go.
- Cite ADRs by number only, never by link, in code and docs.
- No "WIP:" commit subjects. Commit messages should be descriptive and end with `Co-Authored-By: Muse Spark <noreply@opencode.ai>`. Push the branch; don't merge to `main`.
- Never deploy, and never touch the `llm-platform-*` containers or `/home/ubuntu/test/`.
- Delete `build/` and `test-results/` when done.
- If a capability is missing, stop and report it.

## Report
Reply with: the commits, the dependency list, any deviation from §9 and why, test results with commands and pass counts (Go, vitest, hermetic and real-machine at root and under `/chat`), and anything left undone.
