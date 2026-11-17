# Brief: the /code sidebar tree loads fast after a refresh and collapses per device and workspace, and the desktop composer is one row

Repo: Cerea. The orchestrator creates the worktree and tells you its path, branch and base SHA. Run `npm ci` first. There are three items (1, 1b, 2); do them in order, with a commit each.

## 1. The device tree is slow after a page refresh (investigate, then fix)
After a page refresh, the list of workspaces and agents under a device takes several seconds to show.

**Measure first**, and report the numbers:
- the server timing of `GET /api/v2/code/devices`, `…/v1/workspaces?device=` and `…/v1/agents?device=`, per device, from the forwarder `src/routes/api/v2/code/[...path]/+server.ts`;
- galopin's op latency for `workspace.list` and `session.list` (`agent/dispatch.go`, `case "session.list"`), including any per-session git status or diff work, and the subagent counts added last night;
- the client's request waterfall in `src/lib/components/code/CodeNavTree.svelte` (+ `src/lib/codeApi.ts`): does it fetch devices, then workspaces, then agents serially? Does it wait on every machine before rendering any?

Use the real-machine harness (`tests/machineHarness.ts`) with a workspace holding several sessions, and Playwright's timing or `performance` marks. Temporary instrumentation is fine; remove it before committing.

**Then fix it**, choosing from what the numbers show:
- render the device list at once and stream each device's subtree as it arrives;
- parallelise across devices and between workspaces and agents;
- make `session.list` cheap (no per-session git work in a list op; move that to where it's shown);
- a short server-side per-device cache (stale-while-revalidate, invalidated by the machine's session events);
- or a client cache (e.g. `sessionStorage`) rendered instantly on reload, then refreshed.

Keep correctness: a revoked or offline device, a deleted session, and a new session from another tab must still show right.

If you change galopin's `session.list` result shape, it's the protocol: update `agent/PROTOCOL.md` and keep older machines working.

**A regression timing assertion** in a Playwright spec: after reload, the first device's workspace and agent rows are visible within a bound you justify from the measurements (e.g. under 1.5 s on the real-machine harness), plus whatever unit tests fit the fix.

## 1b. Collapsible devices and workspace groups (do it with item 1)
In the `/code` agent sidebar (`CodeNavTree.svelte`):
- Let users collapse and expand each device and each workspace group.
- Remember the collapsed state per device id, and per device id + workspace id, across reloads in `localStorage`. Guard the parse, and drop entries for devices that no longer exist.
- A collapsed row keeps a compact count badge (the device's workspaces, or the group's sessions).
- The active session's device and workspace are expanded by default, even if stored as collapsed.
- **Lazy loading:** don't fetch a collapsed device's subtree (workspaces, agents) until it's expanded. Always show the device row and its online status.
- Keyboard and screen reader: a real button with `aria-expanded` and an accessible name.
- Tests: a Playwright spec that collapses a device and a workspace, reloads, and finds them still collapsed with their badges. It asserts that no `v1/workspaces` or `v1/agents` request is made for the collapsed device (`page.on("request")`), and that the active session's device and workspace open expanded. Run it at root and under `/chat`.

## 2. Desktop composer: `[+]` on the same row as the pills
On desktop, the `/code` composer still puts the `+` attach button on its own line above the row of `build`, the model, `Effort: Default`, `Auto-accept` … the ring and send. The mobile fix (merged, `fix/mobile-composer`) kept desktop as it was.
- Make desktop one row too: `[+] [pills…] … [ring] [send]`, in `src/lib/components/chat/ChatInput.svelte` and `src/lib/components/code/AgentComposer.svelte`.
- Chat's composer too, if its `+` is stacked the same way.
- On a narrower desktop the pills may wrap to a second row, but the `+` stays at the start of the first. Mobile (below `sm`) stays exactly as merged.
- The machine-veto banner under the pills on desktop stays.
- Update the specs that pinned the old desktop shape (`tests/composer-mobile.spec.ts`'s desktop cases, `tests/code-composer.spec.ts`, `tests/chat-model-picker.spec.ts`, or whichever assert it).
- Add a desktop (1280×800) assertion that the `+`, the pills, the ring and send share one row, for `/code` and chat.

## Tests and verification
- `npm run check` (0 errors); eslint and prettier on the changed files.
- vitest: the affected specs (`TEST_MONGODB_URL=mongodb://127.0.0.1:<your mongo>/`, `--no-file-parallelism`).
- Playwright: the new and touched specs at root and under `E2E_APP_BASE=/chat`, then the whole suite once at each base, after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`. WebKit isn't installed.
- If galopin changes: `cd agent && gofmt -l . && go vet ./... && go test ./...`, plus `GOOS=darwin GOARCH=arm64 go build -o /dev/null .`.
- The orchestrator gives your ports and Mongo container in the launch message.

## Box rules (mandatory)
- Wrap EVERY heavy command (npm ci, build, check, playwright, vitest, go build/test) in `flock /tmp/heavy.lock …`. Before each heavy command, if `free -m` shows under 1.5 GB available, wait. If the orchestrator tells you to pause heavy jobs (a deploy is building images), do so until told to resume.
- Kill only the processes you start, by recorded PID. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199.
- Write nothing to `/tmp`, which is tmpfs (RAM).
- Don't spawn sub-agents.
- Never deploy. Never touch the `llm-platform-*` containers, docker volumes or `/home/ubuntu/test/`.
- No new dependencies without asking (OSI-approved licences only). Cite ADRs by number only. Never run `ruff format`.
- Commits: descriptive subjects, no "WIP:", with NO `Co-Authored-By: Claude` trailer (a commit-msg hook rejects it). Push the branch; DON'T merge to main.

## Report
Reply with:
- the measurements (before and after, per endpoint and op, and the waterfall);
- the fix chosen and why;
- the commits;
- the test commands and pass counts at both bases;
- the screenshots' paths (desktop /code and chat composers);
- anything left undone.
