# Brief: subagent approvals and questions surface in the parent view (HIGH priority)

Repo: Cerea. It now contains the Go machine agent **galopin** in `agent/` (Go module; `gofmt`, `go vet ./...`, `go test ./...`). Worktree: `/home/ubuntu/.paseo/worktrees/subperm-cerea`, branch `fix/subagent-approvals`, cut from `origin/main` after the galopin merge, with node_modules symlinked.

## The live bug
In `/code`, when the agent (opencode) spawns a subagent via its `task` tool and that child session needs a permission (e.g. bash) or asks a question, nothing appears in the parent's view. The turn just hangs. Pressing Stop makes everything appear at once.

**Root cause (verified):**
1. The machine forwards every event under the session id it belongs to, so a child's `permission.asked` / `question.asked` / `part` / `delta` envelopes carry the **child's** sessionId.
2. Cerea's SSE bridge (`src/routes/api/v2/code/agents/[id]/stream/+server.ts`) subscribes via `subscribeSessionEvents` (`src/lib/server/code/machines.ts` ~274), keyed by the **parent's** session id only. The child's events are dropped.
3. Auto-accept is a per-session flag in galopin (`agent/internal/sessions/sessions.go`: `st.autoAccept`, checked ~391 on `permission.asked`). A child never has it set, so even with auto-accept on in the parent, its subagents block.
4. Stop "fixes" it because the roster re-polls and the child syncs at the turn boundary.

## What to build
**galopin (`agent/`):**
- The materializer tracks each session's parent. The opencode backend already maps `parentID` into `Session.ParentID` (`agent/internal/backend/opencode/mapping.go` ~127/140; see also `agent/dispatch.go` ~271).
- On `permission.asked` for a session without its own auto-accept, walk up to the root. Auto-reply if any ancestor has auto-accept on AND the policy allows it (`m.policy.AutoAcceptAllowed()`). **Never** auto-accept handoff approvals; they're excluded today, so keep that exclusion.
- Every envelope gains `rootSessionId`: the top-level ancestor, or itself for a top-level session.
- Document the new field in `agent/PROTOCOL.md`, and in `src/lib/types/machineProtocol.ts` (the `Envelope` type).

**Cerea:**
- `machines.ts`: listeners can subscribe by root. The bridge for a top-level session also receives its descendants' envelopes (match `rootSessionId`; fall back to the sessionId for machines that don't send it).
- `machineTimeline.ts` / the stream route:
  - A child's `permission.asked`/`permission.replied` and `question.asked`/`question.resolved` become the same approval and question frames the parent already renders. Label them with the subagent (e.g. prefix the title "Subagent ‹title›: …"; the child's title comes from the session list or event) and carry the child's session id, so the reply goes to the **child's** request.
  - The permission/question reply routes in `src/routes/api/v2/code/[...path]/+server.ts` must accept and forward to the child session id. Validate that the child belongs to the same machine and user.
  - The child's `part`/`delta` events must NOT be folded into the parent's transcript. Emit a side-channel frame `{type: "childActivity", childId}` instead. An expanded subagent card in the UI re-syncs that child's transcript on it, throttled to ~1/s, so its output streams live.

## Tests (required)
- **Go:** unit tests with a fake backend: a child's `permission.asked` is forwarded with `rootSessionId`; it's auto-accepted when the parent (or grandparent) has auto-accept on and the policy allows it; it's NOT auto-accepted when the policy vetoes; handoff approvals are never auto-accepted. Also a real-opencode IT if the existing IT harness supports it (see `agent/*_it_test.go` and the `GALOPIN_OPENCODE_IT` env): the parent spawns a task whose child needs bash permission.
- **vitest:** the fold/labelling in `machineTimeline`, the root-keyed subscription in `machines.ts`, and the reply route targeting the child. Run with `TEST_MONGODB_URL=mongodb://127.0.0.1:8795/ npx vitest run --no-file-parallelism <files>`.
- **Real-machine Playwright** (`tests/code-machine-parity.spec.ts`, which builds galopin from `agent/` via `tests/machineHarness.ts`): the mock LLM (`tests/mock-openai.ts`, with `toolCallsOnce` etc.) makes the parent call opencode's `task` tool, and the child calls bash. Cases:
  - the approval card appears mid-turn, labelled as the subagent;
  - approving it lets the child finish and its output show in the subagent card;
  - with auto-accept on, there's no card and the child completes.

  Run at root and under `/chat`.
- Also: `npm run check` 0/0, and `npm run lint` clean.

**How to run Playwright on this box:**
1. Build alone first: `flock /tmp/heavy.lock npm run build` (and for `/chat`: `APP_BASE=/chat flock /tmp/heavy.lock npm run build`).
2. Then: `E2E_SKIP_BUILD=1 E2E_APP_PORT=5321 E2E_MONGO_PORT=8795 MOCK_OPENAI_PORT=18821 MOCK_OIDC_PORT=18822 MOCK_MCP_PORT=18823 flock /tmp/heavy.lock npx playwright test <specs> --project=chromium --reporter=line`. Add `E2E_APP_BASE=/chat` for the `/chat` build.

WebKit is not installed: always pass `--project=chromium`, and don't install browsers.

## Box rules (mandatory)
- Wrap every heavy command (build, check, Playwright, `go test` with ITs) in `flock /tmp/heavy.lock …`. The box OOMs otherwise.
- Use only the private ports listed above. Never use 5199. Kill only the servers you started, by recorded PID; never `pkill -f` with a pattern.
- Never run `ruff format`. Format TS/Svelte with `npx prettier --write <files you touched>`, and Go with gofmt.
- Cite ADRs by number only, never by link. Don't add dependencies without asking; a non-OSI dependency needs approval.
- No commit subjects starting "WIP:". Commit messages should be descriptive and end with `Co-Authored-By: Muse Spark <noreply@opencode.ai>`. Push the branch; don't merge to `main` (the orchestrator reviews and merges).
- Never deploy, and never touch the `llm-platform-*` containers or `/home/ubuntu/test/`.
- Delete `build/` and `test-results/` when done.
- If a capability is missing, stop and report it rather than working around it.

## Report
Reply with: the commits, the design as built (protocol field, subscription change, labelling, the reply path), test results with commands and pass counts at root and under `/chat`, and anything left undone.
