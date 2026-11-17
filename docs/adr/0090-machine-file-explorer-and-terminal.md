# 0090 — Files and a terminal on the owned machine agent, each behind a double veto

- Date: 2026-09-24
- Status: **accepted**. The decisions were taken by the user on 2026-09-24. They are recorded as D1–D14 in the plan, all as recommended. F1 (the read-only explorer) is implemented and merged (Cerea `980a5fe1`, 2026-09-25). T1 (the terminal) is next. T1 does not ship before this ADR is merged.
- Amends: 0089, its consequence "What C4 becomes", for machines enrolled with terminal or file-write powers.
- Related: 0089 (galopin, the machine agent, and its wire protocol), 0084 (the bundled IdPs whose `auth_time` the step-up rule reads).
- Wire spec: Cerea `agent/PROTOCOL.md`, sections "Machine powers: files and terminals" and "Binary frames".

## Context

`/code` drives coding agents on a user's own machine through galopin, the Go agent 0089 introduced, over one outbound WSS link. People asked for the two things every hosted coding tool has next to the chat: a **file explorer** for the workspace, and a **terminal**.

Both are machine powers, not agent powers. They answer the owner's own actions and never go through the model or opencode. So they need their own authorization story.

0089's residual risk was stated as: "while a paired machine is connected, a compromised Cerea process can prompt it within the machine's policy."
- **That already reaches code execution.** Cerea sends `session.prompt` and then answers its own `permission.asked` with `permission.reply once`, over the same link. Only the model and opencode's permission rules mediate it.
- **A read-only explorer adds no new class of power.** A compromised Cerea could already ask the agent to read a file. It does remove the model from the loop.
- **A terminal adds no new class either, but it removes every friction:**
  - there is no model in the way;
  - no opencode `permission` rules apply (for example, `bash: deny` patterns);
  - no `workspaceRoots` confinement applies to what the shell does.

  It also widens the surface without any compromise of Cerea: an XSS on the chat origin, or a stolen session cookie, becomes an interactive shell.

## Decision

1. **Machine ops, not backend ops.**
   - `files.*` and `terminal.*` are handled by galopin before the backend switch, and never call opencode or an ACP agent. They behave the same under every backend.
   - They are advertised in a new `hello.machine.capabilities` (`files`, `fileSearch`, `fileWatch`, `fileWrite`, `terminal`), where a capability means "this build implements it on this OS". The backend's own `files` capability (attachments) is unchanged.
   - opencode's `/file*`, `/find*` and `/pty` are deliberately not used: ACP backends lack them, they would bypass galopin's policy, and a PTY inside `opencode serve` dies with opencode.
2. **A double veto for each power.** A power is live only when the machine's policy allows it, the deployment allows it, and the capability says it is implemented. Cerea checks the policy and the switch before forwarding, answering 403 with the exact enroll flag. galopin enforces again. It is the same double enforcement as `allowFreeModels`. The policy is set by `enroll` and is never writable over the link.

   | Power | Machine policy (enroll) | Default | Deployment switch | Default |
   | --- | --- | --- | --- | --- |
   | Read files in workspaces | `files: read\|off` (`--no-files`) | **read**, confined and redacted | `CODE_FILES_ENABLED` | on when the code panel is on |
   | Write files | `fileWrite` (`--allow-file-write`) | **denied** | `CODE_FILE_WRITE_ENABLED` | off |
   | Terminal | `terminal` (`--allow-terminal`), `maxTerminals` (8) | **denied** | `CODE_TERMINAL_ENABLED` | off |

   A local `galopin policy set` may only **tighten** the policy; loosening it needs `enroll`.
3. **Confinement and redaction for files.**
   - Every file access goes through Go's `os.Root` for the workspace, which is openat-based and defeats `..`, absolute paths and symlink escapes. A symlink whose target escapes the root is listed but never followed.
   - A default secret deny list (`.env*` except examples, keys and certificates, `.netrc`, `.npmrc`, `.pypirc`, `.git-credentials`, cloud credentials, `*.tfstate`, and so on) is listed as `redacted` and refused on read. The owner may extend it, or drop it with `--no-default-file-deny`.
   - The deny list prevents **accidental** exposure (screen sharing, and content flowing through Cerea's logs and caches). It is **not** a boundary against a terminal or the agent, and the UI says so.
   - Raw bytes are served on the chat origin only as raster images with `nosniff` and `CSP: sandbox`. HTML and SVG from a repository never become script on Cerea's origin.
4. **Terminals.**
   - A PTY (`creack/pty`) runs a login shell whose `cwd` must resolve inside the workspace root. Its environment is scrubbed of everything galopin injected for itself: the opencode server password, the shim secret, and any token.
   - A 2 MiB byte ring with absolute offsets lets a viewer reattach.
   - Terminals die with galopin, are reaped after 24 h with no viewer, and are closed on a 4403 revoke. tmux-backed persistence is an opt-in follow-up.
   - Unix only. There is no Windows build today.
5. **Transport.**
   - **Binary frames on the machine link, for terminal streams only.** A 1-byte kind (output, input, ack), a channel id, a u64 offset, then raw bytes. They are sent only on a channel Cerea opened with `terminal.attach`, so an old Cerea never receives one. File content stays JSON: request and response, capped at 1 MiB per range.
   - **Flow control.** galopin's writer becomes a two-lane scheduler, with control (res, event, notice) always drained before stream frames of at most 32 KiB. Each viewer has a credit window of 256 KiB, acked from the browser after xterm has processed the data. Out of credit, galopin stops reading that PTY. With no live viewer, it keeps reading into the ring, so a background build never hangs on a sleeping tab.
   - **A browser WebSocket for terminals, with a ticket.** The browser first POSTs for a ticket. That request goes through the normal hooks (session, CSRF rules, `getPairedDevice`), and the ticket is 256 random bits, single use, 30 s, held in memory, and bound to user, session, device and terminal. It is redeemed at the upgrade, which also requires `Origin` to equal the public origin (against CSWSH). The open socket re-checks the session and the device row every 60 s and closes on logout, revoke or unpair.
6. **Step-up authentication for terminals.**
   - Minting a terminal ticket requires an OIDC `auth_time` within the last 12 h; otherwise the browser is sent through a fresh login.
   - The first terminal on each machine needs a one-time acknowledgement in the UI.
   - `enroll` spells out what `--allow-terminal` means ("anyone who controls your Cerea session can run commands as ‹user› on this machine"). It warns, but does not refuse, when a terminal is allowed while auto-accept is denied.
7. **Audit on both sides, never content.**
   - **Cerea:** a `codeAudit` collection with a 90-day TTL. It holds who, which device and which action, plus the workspace, terminal or path, and bytes, IP, user agent and time. Actions: terminal open, attach and close; file writes; veto refusals; ticket failures.
   - **galopin:** a local, rotated `audit.log` with terminal open and close, file writes (path, bytes and revisions) and policy refusals. Under C4, this is the record Cerea cannot rewrite.
   - Neither ever records keystrokes, terminal output or file content, and the forwarder never logs them.
8. **Additive protocol.** `protocol` stays `1`. Unknown ops answer `unsupported`, and a new `notice` frame (machine-level, lossy, unsequenced) carries `files.changed` and the terminal state. An old Cerea paired with a new galopin, or the reverse, works unchanged.

## Consequences

- **What C4 becomes. This amends 0089.**
  - **Default machines:** read-only files, no terminal, no writes. 0089's statement stands, plus the owner's own read access to workspace files through the same confined, redacted path the agent already had.
  - **A machine enrolled with `--allow-terminal`:** *a compromised Cerea, or a hijacked owner browser session, has an interactive shell as the owner's OS user on that machine, for as long as it is connected.* The step-up rule, the ticket binding, the Origin check, the per-machine acknowledgement and the machine-side audit narrow and record this. They do not remove it.
  - **A machine enrolled with `--allow-file-write`:** the same statement, for writing files inside its workspaces.

  These powers are the owner's explicit, per-machine choice at enroll time, and the deployment can switch them off wholesale.
- **Auto-accept is orthogonal.** It governs agent permission requests only. Explorer reads, file writes and terminal input are the owner's own actions: they never create permission requests, and auto-accept never applies to them. A terminal is strictly more power than auto-accept.
- **What we now own:** a binary codec with a fuzzed header parser, a writer scheduler, a PTY supervisor with a ring and a mode tracker, a second WebSocket path in Cerea with its own authentication, and a new audit collection.
- **Weight:** xterm.js and CodeMirror 6 are lazy-loaded, so the chat bundle does not grow.
- **The real fix for C4, noted and not planned:** browser-signed operations. A key registered with the machine at confirm time would let galopin verify that terminal input and permission replies came from the owner's browser rather than from Cerea. It becomes more valuable now that terminals exist.

## Verification (filled in as F1 and T1 land)

- **F1 (done, 2026-09-25):**
  - Go tests for `os.Root` confinement (`..`, absolute paths, escaping and dangling symlinks, a directory swapped for a symlink), the deny list and git decorations: done.
  - Forwarder tests for the veto checks and the safe raw route: done. They run as a fake-machine forwarder spec covering the list, the raw headers and audit, 415 for HTML, and the refusal with its audit row.
  - Real-machine Playwright for the Files pane: done, at root and under `/chat`. It covers the badges, redaction, an escaping symlink, and a file an agent turn writes.
  - Not written: a hermetic, fake-machine Playwright case for the pane itself. It's a follow-up; the real-machine case covers the same UI.
- **T1:**
  - Go tests for the environment scrub (asserted by running `env` in the PTY), ring offsets and reattach, credit flow control, and the two-lane scheduler (a session event is never stuck behind terminal output), plus a fuzz test on the binary header;
  - vitest for ticket single use, expiry and binding, the Origin refusal, the step-up redirect, and `codeAudit` holding no content;
  - real-machine Playwright for open, type, reattach after reload, the veto state and coexistence with a running agent turn, at root and under `/chat`.
