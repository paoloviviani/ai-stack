# Session sharing: Cerea Agents panel vs. goose Desktop / opencode editor (2026-11-06)

Read-only investigation. Sources: goose main @4facf56 (clone in /var/tmp/sharing-inv/goose), opencode master clone (/var/tmp/sharing-inv/opencode; note its core server code is not in the clone, CLI/client/VS Code SDK only), installed opencode 1.18.34, goose 1.57.0 spike binaries, galopin code. Marks: [V] verified in source or by a local run, [I] inferred, not tested live.
No model calls were made.

## A. goose

### A1. Where sessions live, shared store?
- [V] One SQLite DB, `<data_dir>/sessions/sessions.db` (`~/.local/share/goose/sessions/sessions.db` on Linux), WAL mode. Code: goose/crates/goose/src/session/session_manager.rs (`DB_NAME`, `create_pool`, `journal_mode(Wal)`). The spike's DB at /var/tmp/acpspike/goose-home/.local/share/goose/sessions/sessions.db confirms (journal_mode=wal, table `sessions` with `session_type`, `working_dir`).
- [V] Desktop and `goose acp`/`goose serve` use the same SessionManager and the same data dir, so one store as long as galopin runs goose as the same user with the same HOME/XDG (do not isolate HOME).
- [V] Visibility catch: sessions created over ACP without `_meta.client` get `session_type = acp` (new_session.rs `session_type_from_meta`; the spike's DB rows are all `acp`). Desktop lists only `user`+`scheduled` by default (ui/desktop/src/acp/sessions.ts `SESSION_LIST_TYPES`); `acp` sessions show only behind the "include ACP sessions" toggle (SessionListView.tsx). Fix is trivial: galopin sends `_meta: {client: "cerea"}` on session/new, which makes them type `user`. Conversely Desktop-created sessions (type `user`) are returned by `session/list` (default types user, scheduled, acp) and can be `session/load`ed by galopin.
- [V] History replay on `session/load` is supported (load_session.rs replays messages and tool calls, with `replayTail`).

### A2. How Desktop talks to its backend; second client?
- [V] Since the 2.0 line Desktop spawns `goose serve` (ACP over HTTP + WebSocket, `127.0.0.1`, random free port), ui/desktop/src/gooseServe.ts, no longer goosed. `goose serve` defaults: host 127.0.0.1, port 3284 (cli.rs `Serve`).
- [V] Auth: shared secret `GOOSE_SERVER__SECRET_KEY`, sent as `X-Secret-Key` header or `?token=` query (transport/auth.rs); `--dangerously-unauthenticated` exists; WebSocket Origin is checked against loopback by default (transport/mod.rs). Desktop generates the secret per launch and keeps it in memory (main.ts `GENERATED_SECRET`), so galopin cannot discover it.
- [V] Desktop supports an external backend: env `GOOSE_EXTERNAL_BACKEND` + `GOOSE_EXTERNAL_BACKEND_URL` + `GOOSE_SERVER__SECRET_KEY`, or settings `externalGoosed` (main.ts ~l.860-1110). So the clean topology is reversed: galopin (or the user) starts ONE `goose serve` with a secret galopin knows, and Desktop is pointed at it.
- [V] The server is multi-connection by design: `AcpConnection` per client, shared `SessionRuntime`; a session can be attached by several connections (agents/session_runtime.rs: `attachments: HashMap<session, IndexMap<conn, Attachment>>`, comment "the last one is who the session currently talks to").
- [V/I] But it is NOT a broadcast model. Turn output (`session/update`) and `session/request_permission` are sent on the connection `cx` that drives the turn (server.rs handle_tool_permission_request / prompt stream), and name updates / extension starts go to the last-attached connection only. A second connection that `session/load`s gets replayed history, and a concurrent `session/prompt` is rejected ("session already has active run; use steer", server.rs:1873). I found no subscription/follow mechanism that mirrors a live run into another client [I: absence found by grep, not by a live two-client test]. Practical result: both UIs see the same session and history, and can alternate turns, but a turn started in Desktop does not stream live into Cerea (Cerea would see it after reload/refresh), and vice versa.

### A3. Permissions
- [V] Permission requests go to the connection that owns the running turn. Desktop-driven turns on a shared backend therefore ask Desktop, not galopin; galopin would not see them, and Cerea's review log / diffs would not record Desktop turns (galopin-side only sees what arrives on its own connection; a re-`session/load` replays tool calls, so a post-hoc import is possible [I]).
- [V] On `session/load` with a pending confirmation, goose re-sends pending permission requests to the loading connection (load_session.rs `resend_pending_tool_permissions`), which is a handover mechanism, not mirroring.
- Consequence: with a shared live backend, galopin is "in the loop" only for turns it drives. Policy enforcement would need to live in goose itself (goose_mode approve + the ACP client answering), i.e. not under Cerea's control for Desktop turns.

### A4. Two separate goose processes on one store
- [V] The store is built for it: WAL, `busy_timeout` 30 s, every write transaction `BEGIN IMMEDIATE` (session_manager.rs; there is even a test `run_lock_upgrade_race`). So cross-process DB corruption/locking errors are unlikely. Desktop itself runs `goose serve` and users also run the CLI against the same DB.
- [I] Residual risk is semantic: each process holds its own in-memory agent/extensions/provider for a session; if both drive the same session at once, messages interleave in the DB with no cross-process run lock (the active-run registry is per process, `ActiveRunRegistry`). Alternating turns (not concurrent) is fine.
- [V] A third-party adapter notes goose exposes no running/waiting marker per session and no process tied to a session; nothing to coordinate on.

### A5. Our side, options
1. Shared store only (separate processes; galopin keeps its own `goose acp`): XS, ~0.5 day. Send `_meta.client` on `session/new` in agent/internal/backend/acp so sessions are type `user`; make sure galopin does not isolate HOME/XDG for goose; make the ACP backend's session list/load handle sessions created elsewhere (list default types include user). Gives: sessions appear in Desktop history and vice versa, turn-alternating continuity, galopin keeps permission control for its own turns. No live mirroring. Lowest risk. Desktop shows Cerea turns after reopening/refreshing the session.
2. One shared `goose serve` that galopin owns (HTTP/WS transport instead of stdio child) with Desktop attached via `GOOSE_EXTERNAL_BACKEND`: M, ~3-5 days (new ACP HTTP/WS transport in backend/acp conn.go, secret handling, lifecycle, a Desktop launch helper/doc, tests). Still not live-mirrored and Desktop turns bypass galopin permissions, so the gain over option 1 is small. Not recommended now.
3. True live co-presence: needs upstream work (broadcast to all attached connections, permission fan-out). Out of scope; could be proposed upstream.

Recommendation A: option 1. Be explicit in the UI: "shared history, one driver at a time". Desktop-driven turns are outside Cerea's permission/review model by construction; say so.

## B. opencode

### B1. VS Code / TUI attach
- [V] The official VS Code extension (sdks/vscode/src/extension.ts) is only a terminal launcher: opens a terminal with env `OPENCODE_CALLER=vscode` and runs `opencode` (the TUI), plus keybindings to insert `@file#L-L` references. It starts its own opencode process, does not attach to a server.
- [V] `opencode attach <url>` exists (1.18.34 --help): attaches the TUI to a running `opencode serve`; flags `--dir`, `-s/--session`, `-c`, `--fork`, `-p/--password`, `-u/--username` (default `opencode`), env `OPENCODE_SERVER_PASSWORD`.

### B2. Editor/TUI attaching to galopin's `opencode serve`
- [V] Galopin starts `opencode serve --hostname 127.0.0.1 --port <random free port> [--pure]` with `OPENCODE_SERVER_PASSWORD=<random 16-byte hex>` (agent/internal/backend/opencode/opencode.go: pickFreePort, randomHex, runOnce; Basic auth user `opencode`), environment inherited. Both are in galopin's memory/process args only; a TUI can attach if given port+password (e.g. via a galopin-printed command or env on `ps`; note the password is in the child's environment, readable by the same user only).
- [V] Galopin's "everything asks" floor is injected through `OPENCODE_CONFIG_CONTENT` into that server process (floor.go), so it applies to ANY client attached to that server, including a TUI.
- [I] permission.asked is an event on the server bus (`GET /global/event` SSE, which galopin subscribes to); an attached TUI subscribes too and shows its own permission dialog. Both can reply; first reply wins, the second gets an error or no-op. It does not break the model (floor still forces asks) but the human may answer in the TUI instead of Cerea, and galopin must tolerate a `permission.replied` it did not send (it already handles that event, events.go l.314) and a failed reply. Not tested live; needs a model call to trigger.
- [I] Live mirroring: events are server-wide, so a session driven from Cerea streams live in the attached TUI and vice versa. This is the real "both UIs live" path for opencode.

### B3. Sharing via the store (separate processes)
- [V] Store: `~/.local/share/opencode/opencode.db` (SQLite, WAL; `opencode db path`). Local experiment in /var/tmp/sharing-inv/oc-home: a session created by process A (`opencode serve`) appeared in `opencode session list` (a separate process) and in a second `opencode serve` on the same data dir. Galopin inherits the environment, so it uses the user's normal store unless HOME/XDG are overridden (galopin does not override).
- [V] So sessions created in Cerea show up in a user's own opencode/VS Code TUI and vice versa (same project directory/project id).
- Caveats: [V] the floor and gateway-pinned model/provider config are only in galopin's process; a TUI in its own process runs with the user's config (default permissive, other providers), so its turns bypass Cerea's policy and review log. [I] No cross-process live updates: a running TUI will not live-follow a Cerea turn; it sees changes on reopen. Concurrent drives of one session from two processes would interleave.

### B4. Our side, options
1. Store sharing: already works, XS. Nothing to build except guard-rails/docs (and mark sessions as "also edited outside Cerea", optional).
2. Attach: S-M, ~1-2 days. A `galopin opencode-attach` / Cerea "Open in terminal/VS Code" action that prints or runs `opencode attach http://127.0.0.1:<port> -s <session> -p <pw>` (the server stays under galopin's policy and floor); handle double replies gracefully; optionally a stable per-user port/secret file (0600) instead of random per-start, with a UI prompt about the weakened trust (any local process with the secret can answer permissions). VS Code integration = run that command in the integrated terminal; no extension changes needed (the official extension just runs `opencode`, so a small wrapper script or user alias would be needed for it to attach).
Recommendation B: ship option 2 on top of option 1. It is the only path that keeps one policy engine, gives live two-way viewing, and uses first-party features. Warn that raw `opencode` in VS Code (own process) is the policy-bypassing path.

## Open checks (needs a live model call, not done)
- goose: two real ACP clients on one `goose serve`, confirm no cross-connection streaming and who gets request_permission.
- opencode: two SSE subscribers, permission.asked delivered to both, reply race behaviour.
