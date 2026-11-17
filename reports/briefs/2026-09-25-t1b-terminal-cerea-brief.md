# Brief: T1b, terminals in Cerea (the browser half; SECURITY-CRITICAL)

Repo: Cerea. Worktree `/home/ubuntu/.paseo/worktrees/t1b-cerea`, branch `feat/code-terminal`, already cut from `origin/main` `4e93e8c0`, which includes T1a (galopin's terminal). Run `npm ci` first. Don't change `agent/` except to add a harness hook the real-machine spec needs; if galopin itself needs a change, stop and report it.

**Read these first, in full, and implement them exactly:**
1. `agent/PROTOCOL.md` §9: the terminal ops, the binary frames and credits, notices, the `Terminal` type. galopin implements it as merged.
2. ADR 0090 (`/home/ubuntu/workspace/ai-stack/docs/adr/0090-machine-file-explorer-and-terminal.md`).
3. The plan, `/home/ubuntu/workspace/reports/2026-09-24-code-files-and-terminal-plan.md`: §2.3 (the Terminal tab), §4.1 (machine↔Cerea: the binary branch, `maxPayload`), **§4.2 (browser↔Cerea: tickets, the WebSocket, reconnects)**, §6 (security, audit), and §8.2–§8.4 (tests). §2.4 mobile view mode and extra keys are **T2**, not this slice.

## Notes from T1a's review (as merged)
- Resize ownership is **one owner per terminal** (the last `terminal.resize` with `claim` wins), not per channel.
- galopin's local audit is `<state-dir>/audit.log`.
- galopin reports `hello.machine.capabilities.terminal: true` on Unix builds. The policy is `terminal: "allowed"|"denied"` (default denied) plus `maxTerminals`, both in hello's policy.
- Credits: a 256 KiB window per viewer channel, acked with binary `term.ack`. The ring holds 2 MiB with absolute offsets. An evicted `from` answers `reset` plus a `prelude`.

## Scope
- **Deployment switch** `CODE_TERMINAL_ENABLED`, **default off** (empty = off; "true" = on). Add it to `.env` with a comment, and thread it like `codeFilesEnabled()` in `src/lib/server/codeEnabled.ts`. It's live only when the switch, the machine's policy and the capability all allow it (§6.1). Cerea checks before forwarding: 403 naming `--allow-terminal` for the machine veto, 404 when the switch is off. galopin enforces again.
- **Forwarder** (`src/routes/api/v2/code/[...path]/+server.ts`): REST for `terminal.list`, `terminal.open`, `terminal.rename` and `terminal.close` under `v1/workspaces/:ws/terminals…` / `v1/terminals/:id…`, mirroring the files routes (RULES allowlist, `callOp` mapping, `getPairedDevice`).
- **Tickets** (`POST v1/terminals/:id/ticket?device=`):
  - 256 random bits, **single use, 30 s**, held in memory;
  - bound to `{userId, sessionId, deviceId, terminalId}`;
  - minted only after the whole chain (`locals.user` → a paired device row owned by that user → the live link).
- **Step-up (ADR 0090, D6):** mint a ticket only if the Cerea session's OIDC `auth_time` is within the last 12 h. Otherwise answer 401 with a `reauth` hint, and let the UI send the user through the existing login with a return URL.
  - Cerea doesn't store `auth_time` today. Capture it from the ID token at login into the session record (find where the OIDC callback creates the session).
  - A session without it counts as stale.
  - Keep this small and well tested.
- **Browser WebSocket** on the existing upgrade seam, `src/lib/server/code/machineServer.ts` (`noServer` + `handleUpgrade`). Route by path: `${base}/api/v2/code/terminal?ticket=…`.
  - **Require `Origin` to equal the public origin** (CSWSH), and refuse *before* upgrading on any mismatch, or on a bad or expired ticket. It must work under `APP_BASE=/chat`.
  - Browser → Cerea: binary `term.input` (Cerea fills in the channel), binary `term.ack`, and JSON `{t:"resize", cols, rows, claim?}`.
  - Cerea → browser: binary output, and JSON `{t:"reset", prelude}`, `{t:"exit", code}`, `{t:"machine-offline"}` / `{t:"machine-online"}`.
  - Cerea sends `terminal.attach` / `terminal.detach` to the machine.
  - Ping every 20 s. Every 60 s, re-check the session and the device row, and close with 4403 on logout, revoke or unpair.
  - Machine-link drops keep the browser socket ("reconnecting") and re-attach from the last relayed offset. Browser drops re-mint a ticket and reattach with `from` = the last offset xterm wrote, with no duplicate or missing output.
  - The machine link's `ws` `maxPayload` and the binary branch on the machine side must fit §9.2's 32 KiB stream frames.
- **Audit** into the existing `codeAudit` (`src/lib/server/code/audit.ts`): `terminal.open`, `attach`, `close`, the first-use acknowledgement, veto refusals, and ticket mint and redeem failures. **Never content or keystrokes.** No per-frame logging anywhere.
- **UI:**
  - A lazy `CodeTerminal.svelte` with xterm.js (`@xterm/xterm`, plus `@xterm/addon-fit`, `@xterm/addon-unicode11` and `@xterm/addon-web-links`, all MIT and approved by the plan), dynamically imported so the chat bundle doesn't grow. Use a system monospace font stack; a bundled font is T2.
  - A **Terminal** entry beside Files in `AgentView` / `sidePane.svelte.ts` (a `terminal` view) with a tab strip: + New, rename, close, the exited state with its exit code, and Restart.
  - Reattach on reload.
  - The veto state disabled, with the exact fix text ("This machine was enrolled without `--allow-terminal`. Re-enroll with it to use terminals here."). Hidden when the switch is off.
  - The **one-time acknowledgement per machine**: "A terminal is a full shell on ‹machine› as ‹user›", audited.
  - Theme: light and dark.
- **Test harness:** `tests/fake-machine.ts` gets a fake terminal (echoes input, scripted output, binary frames, credits), and `tests/machineHarness.ts` a way to enroll the real machine with `terminal: allowed` per test.

## Tests (required)
- **vitest** (`TEST_MONGODB_URL=mongodb://127.0.0.1:8798/`, `--no-file-parallelism`):
  - ticket single use, expiry, and a wrong user, session or device;
  - a revoked device;
  - a foreign `Origin` refused before the upgrade;
  - step-up: a stale or missing `auth_time` → 401 reauth;
  - the switch and veto gating with the exact 403 text;
  - relay binary routing, ack pass-through, and resume after a simulated machine reconnect;
  - socket close on logout or revoke;
  - `codeAudit` rows written, and no content or keystrokes in any row or log.
- **Hermetic Playwright** `tests/code-terminal.spec.ts` with the fake machine:
  - the vetoed state shows the exact flag;
  - open, type, echo, resize;
  - reload → reattach with the prior output present exactly once;
  - a forced reset path;
  - the exit state;
  - multiple tabs;
  - the acknowledgement.
- **Real-machine Playwright** `tests/code-machine-terminal.spec.ts`:
  - `echo $((6*7))` → `42`;
  - `tput cols` follows a resize;
  - `exit` shows the exit state;
  - reload reattaches with scrollback;
  - **coexistence:** `yes | head -c 50000000` in the terminal while a session prompt streams, and the transcript still completes;
  - a policy-denied machine shows the disabled entry.
- **Every Playwright spec at root AND under `E2E_APP_BASE=/chat`.** Then the whole suite once at each base, after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`. WebKit isn't installed.
- `npm run check` (0 errors); eslint and prettier on the changed files.
- **Environment for every Playwright run:**
  ```
  export E2E_APP_PORT=5381 E2E_MONGO_PORT=8798 MOCK_OPENAI_PORT=18881 MOCK_OIDC_PORT=18882 MOCK_MCP_PORT=18883
  unset OPENCODE_CONFIG_CONTENT OPENCODE_CONFIG
  ```
  The Mongo container `e2e-mongo-8798` is yours; the orchestrator starts it.

## Box rules (mandatory)
- Wrap EVERY heavy command (npm ci, build, check, playwright, vitest, go build) in `flock /tmp/heavy.lock …`. The box OOMs otherwise. Before each heavy command, if `free -m` shows under 1.5 GB available, wait.
- Kill only the processes you start, by recorded PID. Tests must reap every PTY, shell and server they start. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199.
- Write nothing to `/tmp`, which is tmpfs (RAM). The harness already keeps its files under `~/.cache/galopin-e2e`.
- Don't spawn sub-agents.
- Never deploy. Never touch the `llm-platform-*` containers, docker volumes or `/home/ubuntu/test/`.
- Dependencies: only the four xterm packages above without asking (a non-OSI dependency needs approval). Cite ADRs by number only. Never run `ruff format`.
- Commits: descriptive subjects, no "WIP:", with NO `Co-Authored-By: Claude` trailer (a commit-msg hook rejects it). Push the branch; DON'T merge to main.
- If a capability is missing, stop and report it.

## Report
Reply with:
- the commits;
- the ticket, step-up, Origin and re-check design as built, and where `auth_time` comes from;
- the relay and resume design;
- any deviation from §9 or the plan, and why;
- test commands and pass counts (vitest; each Playwright spec at both bases; the full suite at both bases);
- screenshots' paths (the tab, the veto, the acknowledgement);
- anything left undone.
