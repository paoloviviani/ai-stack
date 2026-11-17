# Brief: exited terminals must not come back as live tabs (/code terminal, live bug)

Repo: Cerea (the Cerea UI and relay, plus galopin in `agent/` if the fix needs it). The orchestrator gives you the worktree, branch, base SHA, ports and Mongo in the launch message. Run `npm ci` first.

## The bug (live, reported by the user)
Exit a terminal with `exit` or Ctrl+D, close the terminal side pane, then re-open it: the exited terminals reappear in the tab list, and they don't work.

**Expected:** a terminal whose shell has exited is either gone from the list, or shown clearly as **exited** (with its exit code), where only Close/Remove is offered. It's never presented as a live, attachable tab.

## What the design already says (read before changing anything)
- `agent/PROTOCOL.md` §9: `Terminal.state` is `"running" | "exited"`, with `exitCode?`/`signal?`; a `terminal.exit` notice fires.
- galopin keeps an exited terminal for `ExitRetention` (10 min, `agent/internal/terminal/terminal.go`) so a viewer can still see how it ended, then the reaper drops it (`manager.go`). **Retention is intended; showing it as live is the bug.**
- Check whether an exited terminal still counts against `maxTerminals` in galopin. It must not: a user who exits 8 shells must be able to open a 9th right away. If it does count, fix that in galopin (with a Go test) and say so. That's a galopin change, and PROTOCOL.md must stay true.

## Where to look
- **Cerea UI:**
  - `src/lib/components/code/CodeTerminals.svelte` / `CodeTerminal.svelte`: how the tab list is rebuilt when the pane re-opens (from `terminal.list`, from memory, or from `sessionStorage`), and whether it honours `state: "exited"`.
  - The reattach-on-reload path added in commit "Fix the ticket-mint reauth path and reload reattach" (in `AgentView.svelte`).
  - What happens when the client attaches to an exited terminal.
- **The relay** (`src/lib/server/code/terminalServer.ts`): the `terminal.exit` notice → `{t:"exit"}` to the browser; attaching to an exited terminal.
- **The UI's close button** vs `exit`: both paths must end with the right list.

## Fix
Choose from what you find, keeping the protocol's retention:
- Exited terminals show as "exited (code N)" with only Close/Remove, and never auto-attach or restore as a live tab.
- Close/Remove on an exited terminal removes it for good (`terminal.close` is fine on an exited one).
- A fresh pane open lists only running terminals as tabs.

State your choice and why.

## Tests (required)
- **Real-machine Playwright** (`tests/code-machine-terminal.spec.ts`), at root AND under `E2E_APP_BASE=/chat`:
  - open a terminal, type `exit` + Enter, close the pane, re-open it, and assert the exited terminal isn't offered as a live tab;
  - the same with Ctrl+D;
  - the UI close-button path;
  - exiting doesn't use up a slot: with `maxTerminals` at 2 via the harness policy, open 2, exit both, then open a new one successfully.
- Hermetic spec / vitest wherever they fit (the fake machine in `tests/fake-machine.ts` can emit `terminal.exit` and list exited terminals).
- If galopin changes: `cd agent && gofmt -l . && go vet ./... && go test ./...`, plus `GOOS=darwin GOARCH=arm64 go build -o /dev/null .`.
- `npm run check` (0 errors); eslint and prettier on the changed files. Run the terminal specs at both bases after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`.

## Box rules (mandatory)
- Wrap EVERY heavy command in `timeout -s KILL <secs> flock /tmp/heavy.lock …` (e.g. 1500 for a build or a Playwright run, 300–600 for vitest).
- Always pass `TEST_MONGODB_URL` to vitest and the `E2E_*` exports to Playwright, on the same command line. Without them the harness falls back to mongodb-memory-server, which can't run on this box.
- If `free -m` shows under 1.5 GB available, wait. Pause heavy jobs whenever the orchestrator says so.
- Kill only the processes you start, by recorded PID. Tests must reap every PTY and shell they spawn. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199.
- Write nothing to `/tmp`.
- No sub-agents.
- Never deploy. **No live-stack checks.**
- Don't touch sign-in, OIDC or user identity; that's on hold by user decision. The terminal's own ticket and step-up path may be read, but not changed unless the bug needs it; if it does, stop and report first.
- **Commits:** descriptive subjects, **no `Co-Authored-By: Claude` trailer** (a hook rejects it). Before pushing, run `git fetch origin` and check that `git log origin/main..HEAD` lists only your commits. Push the branch; DON'T merge to main.

## Report
Reply with:
- the root cause (Cerea, galopin, or both);
- the fix chosen and why;
- the commits;
- the test commands and pass counts at both bases;
- whether exited terminals counted against `maxTerminals`.
