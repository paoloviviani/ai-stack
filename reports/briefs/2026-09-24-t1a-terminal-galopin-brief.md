# Brief: T1a, terminals in galopin (the Go half; SECURITY-CRITICAL)

Repo: Cerea, **only `agent/`** (the Go machine agent galopin; Go 1.24; gofmt/vet/test). Worktree: `/home/ubuntu/.paseo/worktrees/t1a-cerea`, branch `feat/galopin-terminal`, already cut from `origin/main` (`c8adc8e1`). Do not touch Cerea's TypeScript; T1b does the Cerea side later.

**The contract is fixed. Read these first, in full, and implement them exactly:**
1. `agent/PROTOCOL.md` §9: the policy fields `terminal`/`maxTerminals`, §9.2 binary frames and flow control, the `terminal.*` rows of §9.3, the `Terminal` and `Notice` types, the terminal process rules, and §9.5 notices.
2. ADR 0090 (`/home/ubuntu/workspace/ai-stack/docs/adr/0090-machine-file-explorer-and-terminal.md`).
3. The plan, `/home/ubuntu/workspace/reports/2026-09-24-code-files-and-terminal-plan.md`: §4.1 (the two-lane writer, credits, the slow-viewer rules, the coalescer), §5.2 (`internal/terminal`), §5.3 (link, dispatch, enroll, the local audit), §6, and the Go rows of §8.1.

## Precedents already on main (F1a): follow them
- `internal/policy`: `Files`, `FileDeny`, `FilesAllowed()` and `EffectiveFileDeny()`. Add `Terminal`/`MaxTerminals` the same way.
- `enroll.go`: `--no-files`, `--file-deny` and the `filesPolicySummary` epilogue. Add `--allow-terminal` beside them.
- `run.go` `buildHello`: `hello.machine.capabilities` already sends `terminal:false`. Make it true on Unix builds when the build supports it.
- `dispatch.go`: `opFiles`/`filesErr` handle `files.*` before the backend switch. Put `terminal.*` beside it.
- `internal/files` uses `os.Root` for confinement. Reuse its `CleanRel` for `cwd`.
- **Temp files:** never leave anything in `/tmp`, which is tmpfs (RAM) on this box. Tests use `t.TempDir()` only when it points at disk; otherwise use the IT helper `itTmpDir(t)` in `opencode_it_test.go` (under `~/.cache/galopin-it`). Any shell a test spawns runs with `TMPDIR` set to such a dir.

## Scope
- **Policy** (`agent/internal/policy`):
  - `terminal: "allowed"|"denied"` (default denied) and `maxTerminals` (default 8), reported in hello.
  - Enroll flag `--allow-terminal`, with the plain-words epilogue: "Terminals: ALLOWED — anyone who controls your Cerea session can run commands as ‹user› on this machine". A warning, not a refusal, when `--allow-terminal` is given without `--allow-auto-accept`.
  - A local `galopin policy show|set` that can only **tighten** (turning terminal or files off, lowering `maxTerminals`, adding `fileDeny`); loosening prints "re-run enroll with …" and exits non-zero.
- **`hello.machine.capabilities.terminal`:** true on Unix builds (a build tag), false otherwise.
- **`agent/internal/terminal`:**
  - Spawn: `creack/pty` (MIT; approved by the plan), `StartWithSize`, `Setsid`/`Setctty`, and `Pdeathsig=SIGHUP` on Linux, using the existing `procattrs_*` pattern. Shell: `$SHELL -l`, falling back to `/bin/sh`. The `cwd` is resolved **inside the workspace root** via `os.Root` (refuse otherwise). Set `TERM=xterm-256color`, `COLORTERM=truecolor`, `GALOPIN_TERMINAL=1`.
  - **Environment scrub:** remove everything galopin injected for itself: `OPENCODE_SERVER_PASSWORD`, the shim secret, and any variable carrying a token, refresh token or credential that galopin set. Build the child env from an explicit denylist of galopin's own keys plus a pattern for token-like names, and document the list.
  - A 2 MiB ring of raw bytes with absolute offsets. The ring start advances to just after a `\n` within its first 4 KiB.
  - A mode tracker for alternate screen (`?1049`/`?47`), bracketed paste, cursor visibility and application-cursor mode, which produces the `prelude` on reset.
  - Redraw nudge after a reset attach: resize to rows−1 and back.
  - Coalescer: a 5 ms leading edge, then a trailing flush at 5 ms or 32 KiB.
  - Multi-viewer size ownership (`terminal.resize` with `claim`).
  - Lifecycle: exited terminals are kept 10 min with their exit code; a terminal with no viewer for 24 h gets SIGHUP; all terminals close on `run` shutdown and on a **4403 revoke** (SIGHUP to the process group, then SIGKILL after 5 s).
- **Link** (`agent/internal/link`):
  - The binary codec (§9.2), with a **fuzz test** on the header parser.
  - The **two-lane writer scheduler** replacing `writeMu`: control is always drained before stream frames, and stream frames are at most 32 KiB.
  - A per-channel **credit window** (256 KiB, acks from Cerea).
  - Slow-viewer rules: stop reading the PTY when every attached viewer is out of credit, except with zero viewers, or when all have been out of credit for 10 s, in which case keep reading into the ring.
  - Inbound binary `term.input`/`term.ack` routed to `terminal`. Unknown kinds are ignored.
  - Binary frames are only ever sent on channels opened with `terminal.attach`.
- **Dispatch:** `terminal.*` ops before the backend switch (`agent/dispatch.go`), never touching the backend, with policy enforcement (forbidden when denied) and `maxTerminals`.
- **Notices:** `terminal.exit`, `terminal.title` (from OSC 0/2) and `terminal.state` as `notice` frames.
- **Local audit:** `<state-dir>/galopin/audit.log`, JSON lines with rotation, recording `terminal.open`/`close` (id, cwd, shell, when) and policy refusals. **It never records keystrokes, output or content.**
- **Docs:** `agent/README.md` and `docs/agent-machines.md` for `--allow-terminal`, `galopin policy`, and the warning.

## Tests (required; Go)
- **The env scrub:** spawn a real PTY running `env` and assert that none of galopin's secrets are present.
- `cwd` escapes refused (`..`, and a symlink out of the root).
- Ring eviction and the newline-aligned start; reattach offsets (a `from` inside the ring streams exactly from there; an evicted `from` gives `reset` plus prelude).
- The mode-tracker prelude.
- **The two-lane scheduler:** with a flood of terminal output, a control frame is written within one stream frame.
- **Credits:** no output beyond 256 KiB unacked; reading resumes on ack; with zero viewers the ring keeps filling and the process doesn't block.
- **The binary header fuzz test** (`go test -fuzz` seed corpus committed; run it for 30 s).
- Policy: denied → forbidden; `maxTerminals`; `policy set` tightens and refuses loosening.
- 4403 revoke closes all terminals, and their process groups are gone.
- Audit lines contain no output or input bytes.
- `echo $((6*7))` over a real PTY produces `42` through the codec.
- **Run:** `cd agent && gofmt -l . && go vet ./... && flock /tmp/heavy.lock go test ./... && flock /tmp/heavy.lock go test -run=NONE -fuzz=FuzzBinaryHeader -fuzztime=30s ./internal/link`.

## Box rules (mandatory)
- Wrap every heavy command in `flock /tmp/heavy.lock …`. The box OOMs otherwise.
- Kill only processes you started, by recorded PID. Tests must reap every PTY and child they spawn; no stray shells after the run. Never `pkill -f` with a pattern. Never use port 5199.
- gofmt for Go. Never run `ruff format`.
- Cite ADRs by number only, never by link. `creack/pty` (MIT) is approved; any other new dependency needs asking (a non-OSI dependency needs approval).
- No "WIP:" commit subjects. Commit messages should be descriptive and have NO `Co-Authored-By: Claude` trailer (a commit-msg hook rejects it). Push the branch; don't merge to `main`.
- Never deploy, and never touch the `llm-platform-*` containers or `/home/ubuntu/test/`.
- If a capability is missing, stop and report it.
- Do not spawn sub-agents of your own.
- Available memory: if `free -m` shows under 1.5 GB available, wait before the next heavy command.

## Report
Reply with: the commits, the env-scrub list, the scheduler and credit design as built, any deviation from §9 and why, test results (commands and pass counts, the fuzz run), and anything left undone.
