# Brief: retry and rollback on agent messages in /code, and rename "Handoff" to "Fork"

Repo: Cerea. It contains the Go machine agent **galopin** in `agent/` (Go; gofmt, `go vet ./...`, `go test ./...`). Worktree: `/home/ubuntu/.paseo/worktrees/retry-cerea`, branch `feat/agent-retry-fork`, cut from `origin/main`, with node_modules symlinked. The wire protocol spec is `agent/PROTOCOL.md`, and its TypeScript half is `src/lib/types/machineProtocol.ts`.

## Background
In `/code` (the coding-agent panel that drives opencode on a user's machine through galopin), each agent message shows three icons: copy, retry and fork. The retry icon is chat's own retry, and it does nothing for a machine session. The fork icon is milestone M7's "Handoff" (it starts a new session from this point); it's to be renamed "Fork".

## 1. Retry and rollback via the machine protocol
- **opencode API.** opencode `serve` exposes `POST /session/:sessionID/revert` with body `{messageID, partID?}` ("Revert a specific message in a session, undoing its effects and restoring the previous state"), and `POST /session/:sessionID/unrevert` ("Restore all previously reverted messages"). Newer versions also have a v2 staged API (`/api/session/:id/revert/stage|clear|commit`, with `files: boolean`).
  - **Verify against the opencode version the e2e harness actually runs** (`tests/machineHarness.ts`; the agent log says 1.18.31) and against the one installed at `/home/ubuntu/.nvm/versions/node/v24.21.0/bin/opencode` (1.18.32). Hit them with curl against a local `opencode serve` to see the exact request and response and whether **files on disk are restored**.
  - Record the findings in the brief's report and in `agent/PROTOCOL.md`.
- **galopin:**
  - New ops `session.revert {sessionId, messageId, partId?}` and `session.unrevert {sessionId}` in the dispatch and the opencode backend (`agent/internal/backend/opencode/`).
  - A new backend capability `revert` (with `revertFiles: bool` saying whether files are restored), advertised in `hello` like the existing capabilities.
  - The ACP backend reports no capability.
  - Update the materializer so the reverted messages disappear from `session.sync`, or are marked the way opencode marks them (session `revert` info); follow what opencode returns.
- **Cerea:**
  - Forwarder routes in `src/routes/api/v2/code/[...path]/+server.ts` following the existing op routes.
  - UI on a `/code` agent message:
    - **"Retry"** (on the last assistant message): revert to the preceding user message, then re-send that user prompt.
    - **"Rollback to here"** (on any user message, or a menu item): revert to that message.
  - Gate both on the `revert` capability. Hide them when it's absent; never show a dead button.
  - The confirm text says whether files revert: "Also restores files changed after this point", or "Files on disk are NOT restored".
  - After a revert, the transcript re-syncs and truncates. The next prompt continues from there.
  - An "Undo rollback" affordance (unrevert) until the next prompt, if opencode supports it.
- **If this proves large** (more than about a day, or opencode's semantics are unreliable): hide the dead retry button on `/code` messages now, ship that, and write the full design into the report instead.

## 2. Rename Handoff to Fork (the M7 feature only)
- The button, the dialog, and their copy: "Fork from here", "Fork session", and so on.
- The docs: `docs/code-panel.md`, `docs/agent-machines.md`, and anything else that names the M7 feature.
- Keep the word "handoff" for the separate **agent-initiated handoff** feature, if present. Keep internal identifiers only if renaming them is risky; UI text and docs must say Fork.

## Tests (required)
- **Go:** unit tests for the new ops with a fake backend, the capability in hello, and the opencode request shape. Also a real-opencode IT if the IT harness supports it (see `agent/*_it_test.go` and `GALOPIN_OPENCODE_IT`).
- **vitest:** the gating (the capability shows or hides the buttons; the files-revert wording), and the forwarder route.
- **Real-machine Playwright**, in `tests/code-machine-parity.spec.ts` (it builds galopin from `agent/`): send two prompts, "Rollback to here" on the second user message, and check that the transcript truncates, that the next prompt continues from there, and the files state matches the capability wording. Also: Retry re-sends the last prompt. The Fork rename is visible. At root and under `/chat`.
- `npm run check` 0/0, and `npm run lint` clean.

**How to run Playwright:**
1. Build alone: `flock /tmp/heavy.lock npm run build`, or `APP_BASE=/chat flock /tmp/heavy.lock npm run build`.
2. Then: `E2E_SKIP_BUILD=1 E2E_APP_PORT=5341 E2E_MONGO_PORT=8798 MOCK_OPENAI_PORT=18841 MOCK_OIDC_PORT=18842 MOCK_MCP_PORT=18843 flock /tmp/heavy.lock npx playwright test <specs> --project=chromium --reporter=line`. Add `E2E_APP_BASE=/chat` for `/chat`.

WebKit is not installed: always `--project=chromium`, and never install browsers. vitest runs: `TEST_MONGODB_URL=mongodb://127.0.0.1:8798/ npx vitest run --no-file-parallelism <files>`.

## Box rules (mandatory)
- Wrap every heavy command (builds, check, Playwright, go test with ITs, a local `opencode serve`) in `flock /tmp/heavy.lock …`. The box OOMs otherwise.
- Use only the private ports above; for a local opencode serve, use port 18849. Never use 5199. Kill only what you started, by recorded PID; never `pkill -f` with a pattern.
- Never run `ruff format`. Use `npx prettier --write` on the files you touched, and gofmt for Go.
- Cite ADRs by number only, never by link. Don't add dependencies without asking (a non-OSI dependency needs approval).
- No "WIP:" commit subjects. Commit messages should be descriptive and end with `Co-Authored-By: Muse Spark <noreply@opencode.ai>`. Push the branch; don't merge to `main`.
- Never deploy, and never touch the `llm-platform-*` containers or `/home/ubuntu/test/`.
- Delete `build/` and `test-results/` when done.
- If a capability is missing, stop and report it.

## Report
Reply with: the commits, the opencode revert findings (the exact API, and whether files are restored, per version), what shipped (full or the hide-now fallback), test results with commands and pass counts at root and under `/chat`, and anything left undone.
