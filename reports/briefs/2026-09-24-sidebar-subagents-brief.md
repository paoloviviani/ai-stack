# Brief: identify subagents in the /code sidebar (no tree)

Repo: Cerea. It contains the Go machine agent **galopin** in `agent/`. Worktree: `/home/ubuntu/.paseo/worktrees/sidebar-cerea`, branch `feat/sidebar-subagents`, cut from `origin/main` **after `fix/subagent-approvals` merged**, with node_modules symlinked. That fix added `rootSessionId` on envelopes and parent tracking in galopin's materializer; read its merge commit and `agent/PROTOCOL.md` first, and reuse them.

**The design is approved.** It's in `/home/ubuntu/workspace/reports/2026-09-24-thin-agent-progress.md`, bullet "Subagents in the `/code` sidebar" (search for it). Implement it as written:
- **No tree.** Parent and child can sit in different workspaces or worktrees, so each session stays under its own workspace. This reverses milestone M4's hiding of children from `session.list`: children are listed now, but marked.
- **Subagent rows:** a "sub" badge, plus a line "↳ from ‹parent title›", adding "· ‹workspace/worktree name›" when the parent lives in a different workspace. Clicking that line opens the parent.
- **Parent rows:** an "N subagents" count whose popover links to each child, wherever it lives.
- **Status on subagent rows:** running, **waiting for approval** (prominent), done or failed. A parent row flags it when any descendant is waiting for approval.
- **In a subagent's own view:** a header "Subagent of ‹parent›" with a link back.
- **Filter:** a sidebar toggle to show or hide subagents, on by default and persisted per user (follow how other sidebar/UI preferences are stored).
- **Protocol:** `session.list`/`session.get` carry `parentId`, `rootId`, and a child-status summary (`{children: n, running: n, waiting: n}`) for parents. Backend-generic: ACP reports none. Update `agent/PROTOCOL.md` and `src/lib/types/machineProtocol.ts`. The waiting state comes from the materializer's pending permissions and questions per session.
- The sidebar is in `src/lib/components/code/` (find the device/workspace/session list components) and the data comes through the forwarder `src/routes/api/v2/code/[...path]/+server.ts`. Keep the sidebar's live-refresh behaviour, and have the waiting marker update without a manual reload (reuse the existing roster poll or event path).

## Tests (required)
- **Go:** `session.list` carrying `parentId`/`rootId` and the child-status summary from a fake backend, including the waiting count while a child's permission is pending.
- **vitest:** the derivation (badge, from-line with and without the cross-workspace suffix, the parent count, status precedence with waiting > running > failed > done, the parent's waiting flag) and the filter toggle's persistence. Run with `TEST_MONGODB_URL=mongodb://127.0.0.1:8795/ npx vitest run --no-file-parallelism <files>`; 8795 is private to you.
- **Real-machine Playwright** (`tests/code-machine-parity.spec.ts`; the harness builds galopin from `agent/`): the parent calls opencode's `task` tool through the mock LLM (the subagent-approvals spec shows how). Check: the child row shows the badge and the from-link, and clicking it opens the parent; the parent shows "1 subagent" and the popover links to the child; while the child's bash approval is pending, the child row and the parent both show waiting; the filter toggle hides and shows the row; the subagent view shows "Subagent of …". Run at root and under `/chat`.
- `npm run check` 0/0, `npm run lint` clean, and `cd agent && gofmt -l . && go vet ./... && go test ./...` clean.

**How to run Playwright:**
1. Build alone: `flock /tmp/heavy.lock npm run build`, or `APP_BASE=/chat flock /tmp/heavy.lock npm run build`.
2. Then: `E2E_SKIP_BUILD=1 E2E_APP_PORT=5381 E2E_MONGO_PORT=8795 MOCK_OPENAI_PORT=18881 MOCK_OIDC_PORT=18882 MOCK_MCP_PORT=18883 flock /tmp/heavy.lock npx playwright test tests/code-*.spec.ts --project=chromium --reporter=line`. Add `E2E_APP_BASE=/chat` for `/chat`.

WebKit is not installed: always `--project=chromium`.

## Box rules (mandatory)
- Wrap every heavy command in `flock /tmp/heavy.lock …`. The box OOMs otherwise.
- Use only the private ports above. Never use 5199. Kill only what you started, by recorded PID; never `pkill -f` with a pattern.
- Never run `ruff format`. Use `npx prettier --write` on the files you touched, and gofmt for Go.
- Cite ADRs by number only, never by link. Don't add dependencies without asking (a non-OSI dependency needs approval).
- No "WIP:" commit subjects. Commit messages should be descriptive and end with `Co-Authored-By: Muse Spark <noreply@opencode.ai>`. Push the branch; don't merge to `main`.
- Never deploy, and never touch the `llm-platform-*` containers or `/home/ubuntu/test/`.
- Delete `build/` and `test-results/` when done.
- If a capability is missing, stop and report it.

## Report
Reply with: the commits, the protocol additions, where the UI lives, test results with commands and pass counts at root and under `/chat`, and anything left undone.
