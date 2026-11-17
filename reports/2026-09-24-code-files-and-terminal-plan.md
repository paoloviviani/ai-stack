# `/code`: a file explorer and a terminal, backed by galopin — plan

Date: 2026-09-24. Status: **plan only**. Nothing here is built.
Inputs: `reports/2026-09-24-thin-agent-protocol.md`, `reports/2026-09-24-thin-agent-progress.md`, Cerea `feat/galopin` (`agent/PROTOCOL.md`, `agent/internal/*`, `src/lib/server/code/*`, `src/lib/components/code/*`), ADR 0089, and the prior-art survey below.

Decisions the user must make are marked **⚑ D*n*** and collected in §9.

## TL;DR

- **Files:** an explorer in a new **Files** tab of the agent's side pane, next to **Changes**. It is per workspace, so each worktree gets its own. It is read-only first. galopin serves it from the workspace root through Go's `os.Root`, which blocks traversal and symlink escapes, adds git decorations, and redacts a secret deny list. Cerea relays it over ordinary JSON ops. The UI is our own small virtualized Svelte tree plus a read-only **CodeMirror 6** viewer, and the same viewer becomes the editor later.
- **Terminal:** **xterm.js 6**, lazy-loaded, with the fit, search, unicode11 and web-links addons, and webgl optional. galopin runs a PTY through `creack/pty` and keeps a 2 MiB byte ring with absolute offsets, so a viewer can reattach after reconnecting. Output travels as **binary frames** with **credit-based flow control**, and galopin's writer gains a priority lane so session events never queue behind terminal output. The browser reaches it through a new cookie-and-ticket-authenticated **browser WebSocket** on Cerea.
- **Policy:** a terminal is a remote shell. It stays off unless the machine was enrolled with **`--allow-terminal`**. Writing files needs **`--allow-file-write`**, also off by default. Reading files is on by default but confined to the workspace and redacted (⚑ D2). A deployment kill switch sits on top of both.
- **Trust:** a compromised Cerea can already reach code execution today, by prompting and then answering its own permission request. The terminal makes that direct, deterministic and free of any model or permission-rule friction. It also turns a stolen browser session into a shell. That changes ADR 0089's consequences, so it gets **its own ADR** (⚑ D5).
- **Backend-generic:** these are machine ops (`files.*`, `terminal.*`) advertised under a new `hello.machine.capabilities`, not per backend. They work the same under opencode and ACP. opencode's own `/file` and `/pty` APIs are deliberately not used.
- **First slices:** F1, the read-only explorer (M), then T1, the terminal behind its veto (L).

---

## 0. Where we start (facts from the code)

| Fact | Where | Why it matters |
| --- | --- | --- |
| One WSS per machine. Frames are **JSON text only**. | `agent/internal/link/link.go` `writeFrame` → `websocket.MessageText` | There is no binary path yet. Terminal bytes as JSON escape badly: each ESC becomes the 6-byte `\u001b`. |
| All writes serialize on **one `writeMu`**, and a frame can be up to 160 MiB (inbound read limit). | `link.go` | **Head-of-line blocking.** A multi-MB `session.sync` snapshot or diff stalls everything behind it, terminal output included. |
| Cerea parses every message as `JSON.parse(raw.toString())` and ignores `isBinary`. `WebSocketServer` has no explicit `maxPayload` (the `ws` default is 100 MiB). | `src/lib/server/code/machines.ts`, `machineServer.ts` | Cerea needs a binary branch. An old Cerea never sends `terminal.attach`, so it never receives binary frames, which keeps this safe across versions. |
| Every op has a deadline: 15 s, or 20 s for sync. Events are fanned out by `sessionId` and carry an `(epoch, seq)` cursor. | `machines.ts`, PROTOCOL §3, §7 | File ops fit the request/response model. Terminal output needs its own per-stream cursor. Workspace-level notifications need a frame that isn't tied to a session. |
| Browser ↔ Cerea is **REST + SSE only**. The WebSocket upgrade seam lives in `server.js` (global symbol) and `vite.config.ts`, and it compares against `${base}${MACHINE_PATH}`. | `machineServer.ts` | A browser terminal WebSocket needs a second path on the same seam. It must carry the base path and do its own authentication, because upgrades bypass the SvelteKit hooks. |
| Browser authorization: `locals.user` → `getPairedDevice` (owned + `paired`). | `src/lib/server/codeDevices.ts` | We reuse it unchanged for REST, and for minting terminal tickets. |
| Policy is `autoAccept`, `workspaceRoots`, `allowFreeModels`, set by `enroll` flags and never writable over the link. | `agent/internal/policy/policy.go`, `enroll.go` | The new vetoes go in the same place. |
| The side pane has one slot: `SidePaneView = artifact\|trackio\|library\|preview\|diff`. | `src/lib/stores/sidePane.svelte.ts`, `AgentView.svelte` | Files and Terminal become tabs of one "workspace" pane, together with Changes. |
| The UI already ships highlight.js (lazy chunk) and `artifactDiff` (`diffLines` / `renderDiffHtml`). It has **no editor**, no Shiki and no xterm. | `package.json`, `ArtifactPanel.svelte`, `AgentDiff.svelte` | Anything we add is new weight, and it should be lazy-loaded. |
| `checkout.Diff` already runs the git CLI and caps output (200 files, 256 KiB each). | `agent/internal/checkout` | Git status for decorations reuses the same helper style. |
| galopin builds `linux/{amd64,arm64}` and `darwin/{amd64,arm64}` with `CGO_ENABLED=0`, and has **no Windows build**. `go 1.24`. Its only non-stdlib dependency is `coder/websocket`. | `packaging/build-dist.sh`, `go.mod`, ADR 0089 | Windows is out of scope. `os.Root` is available now (Go 1.24); `Root.Rename`/`WriteFile` need Go 1.25. |
| A fake machine exists for hermetic specs, and there is a real-machine harness. The `/code` suite runs at root and under `E2E_APP_BASE=/chat`. | `tests/fake-machine.ts`, `tests/machineHarness.ts`, `playwright.config.ts` | We extend both rather than invent new ones. |

---

## 1. Survey: prior art and reusable components

### 1.1 How the others do it

| Product (licence) | File tree | Viewer / editor | Terminal renderer | PTY, transport, reattach |
| --- | --- | --- | --- | --- |
| **paseo** (Apache-2.0, "portions" third-party). Read from the installed `@getpaseo/server` 0.9.1 and the repo tree. | Lazy per-directory listing. Paths are confined by `realpath` against the root, and reads use `O_NOFOLLOW`. Revision = `dev:ino:size:mtimeNs`. A write compares revisions and returns `conflict` on mismatch, then does temp + rename. `git mv` on rename. Dangling or escaping symlinks are skipped. Editable cap 1 MiB, stream chunks 256 KiB. The observer is `fs.watch` on the file's directory with a polling fallback. | CodeMirror 6, plus `@getpaseo/highlight` (Lezer grammars) | xterm.js 6.1 beta in a WebView, with webgl, fit, search, unicode11, web-links, image and clipboard | `node-pty` in a worker process. An **`@xterm/headless` mirror** (1000 lines of scrollback) renders **restore snapshots** as ANSI. **Binary frames**: opcode + slot. A **5 ms leading-edge coalescer**, 256 KiB max output frame. When the socket's `bufferedAmount` exceeds **4 MiB**, the client is switched to a snapshot instead of a backlog. Resize has **size ownership**, with claim or update intents. |
| **opencode web** (`packages/app`, MIT) | `@pierre/trees` with `@tanstack/solid-virtual` | Shiki | **ghostty-web, its own fork pinned to a commit** | `bun-pty` or `node-pty` inside `opencode serve`. `/pty/:id/connect` is a WebSocket behind a **connect ticket** plus an Origin check. A **2 MiB raw-output ring with an absolute cursor**: `cursor` replays from an offset, `-1` tails. |
| **OpenChamber** (MIT) | Its own, in React, with TanStack virtual and git status decorations | CodeMirror 6, plus `@pierre/diffs` and Shiki | ghostty-web | `node-pty`/`bun-pty`, chunk replay (`terminalChunkReplay.ts`), a session keepalive hook |
| **CodeNomad** (MIT) | none found in its UI package | Monaco + Shiki | none found | none |
| **OpenHands** (MIT) | its own `file-tree-view` | Monaco (`@monaco-editor/react`) | xterm.js 6 + fit | its sandbox runtime's API (not reviewed in depth) |
| **opencode serve** (MIT) | `GET /file`, `/file/content`, `/file/status`, `/find`, `/find/file`, `/find/symbol` | none | none | `/pty` (see opencode web) |
| code-server / VS Code web (MIT); Theia (EPL-2.0) | A whole IDE | Monaco | xterm.js | Their own server, with its own authentication |
| Zed collab (GPL-3.0 / AGPL-3.0 server, Apache-2.0 GPUI) | none | none | none | A CRDT-based protocol, not reusable |
| **ttyd** (MIT, C) | none | none | xterm.js | Binary WebSocket with a **1-byte command prefix**: `0` = I/O, `1` = resize, **`2` = PAUSE, `3` = RESUME**. **Client-side flow control**: it counts pending `term.write` callbacks against `limit`/`highWater`/`lowWater`. |
| gotty (MIT, Go); wetty (MIT) | none | none | xterm.js | gotty: a prefix protocol (originally base64). wetty: socket.io over ssh. |
| upterm (Apache-2.0); tmate (ISC, from tmux) | none | none | a native terminal | SSH over a reverse tunnel. Read-only versus read-write share links. Host-side ACLs. |

**What we take from each:**
- **paseo:**
  - explorer semantics: revision-based conflicts, `O_NOFOLLOW`, skipping escaping symlinks, 1 MiB edit cap, 256 KiB chunks;
  - terminal ideas: the coalescer, binary slot frames, size ownership, and "when a client is far behind, send a fresh state rather than a backlog".
- **opencode:** the connect ticket, and the raw ring with an absolute cursor. It is simpler than a headless mirror and good enough for v1.
- **ttyd:** browser-driven flow control from xterm's write callbacks.
- **Not reused:** no IDE-in-a-box (code-server, Theia). Each would be a second remote-control plane with its own authentication, which is exactly what ADR 0089 removed.

### 1.2 Terminal renderer

Sizes were measured with esbuild (minify, ESM) and gzip -9 on 2026-09-24.

| Option | Licence | Maintenance | Size (min / gz) | Svelte fit | Mobile / touch | a11y | `/chat` base path |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **xterm.js 6.0** `@xterm/xterm` | MIT ✅ | Very active (VS Code's terminal); 6.0.0 released 2026-08 | core 336K / **86K**. With fit, search, serialize, unicode11 and web-links: 423K / **114K**. webgl adds 123K / 35K. | Imperative. A Svelte 5 action or component wraps it cleanly, and no wrapper package is needed. | Usable but weak. Touch scroll works, but there is no native selection and the soft keyboard has no Esc, Ctrl or arrows. **We need an extra-keys bar.** | **`screenReaderMode`**: a live region plus an accessible buffer | No workers, no WASM. The CSS is bundled by Vite, so it is base-safe. |
| ghostty-web 0.4 | MIT ✅ | Last push 2026-07-02. opencode pins its **own fork**. Open issues: no screen-reader support, Korean and CJK IME, paste, and a paste CVE fix (CVE-2026-26982). | 623K / **180K** (includes about 413 KiB of WASM) | The xterm-compatible API ports over | IME and paste bugs are open | **None** (open issue) | The WASM must load base-aware; it is inlined in the ESM build |
| wterm (`@wterm/*`, vercel-labs) | Apache-2.0 ✅ | New: created 2026-04, at 0.5 | core 33K / 13K, plus an optional libghostty core (about 400 KB of WASM) | Has an `@wterm/svelte` package | unknown | unknown | Uses WASM |
| libghostty (native) | MIT ✅ | Active | none | none | none | none | Only via WASM (that is ghostty-web). It doesn't apply to the browser directly, and it needs cgo in galopin. |

**Recommendation: xterm.js 6**, lazy-loaded only when a terminal opens, with:
- `fit`, `search`, `unicode11` and `web-links`;
- `webgl`, loaded if WebGL2 is available, falling back to the DOM renderer. That also keeps things simpler for screen readers.
- `serialize`, client-side only, for "copy all output" and for keeping a terminal's contents across in-app navigation.

Revisit ghostty-web once it has accessibility and stable IME, since its API is xterm-compatible and swapping would be cheap. `@xterm/headless` is not needed on the machine (see §5.2).

### 1.3 File tree, viewer and editor

| Option | Licence | Maintenance | Size (min / gz) | Svelte fit | Mobile / touch | a11y | `/chat` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Own Svelte tree**: flattened visible rows plus `@tanstack/svelte-virtual` | ours (first-party), plus MIT | ours; TanStack is active | the virtualizer is 27K / **8K** | Native. It reuses `CodeNavTree`'s patterns and the Tailwind tokens. | Native. The rows are ordinary elements. | We implement the ARIA `tree` pattern (roving tabindex, arrows, type-ahead) | Trivial |
| `@pierre/trees` 1.0.0-beta.6 (used by opencode web) | Apache-2.0 ✅ | Active, **beta** | 252K / 74K | Vanilla mount API in a **shadow DOM**, so Tailwind theming has to go through CSS variables | Probably fine | Has keyboard navigation; not audited | OK |
| Existing highlight.js 11.12 (already shipped) | BSD-3 ✅ | Active | **0 added** | In use already | Static HTML | Static text | In use already |
| **CodeMirror 6** (`@codemirror/view` 6.43, `state`, language packages) | MIT ✅ | Active. It **moved from GitHub to its own Forgejo** (`code.haverbeke.berlin`) in 2026, and npm releases continue. | read-only view + state: 204K / **66K**; `basicSetup`: 123K gz; with merge and JS: 172K gz. Languages load lazily. | Imperative, with a small wrapper | **Good**: contenteditable with native selection | **Good**: ARIA and keyboard-first | No workers, pure ESM |
| Shiki 4.4 (core + JS regex engine) | MIT ✅ | Active | 162K / 53K, plus each grammar and theme | Easy; it outputs HTML | Static HTML | Static text | Grammars load via dynamic import, which is base-safe |
| Monaco 0.56 | MIT ✅ | Active | **multi-MB** (95 MiB unpacked; not measured) | Heavy | **Not supported on mobile** | Good on desktop | Web workers and loader paths are a known pain under base paths and a CSP |
| `@pierre/diffs` 1.4 | Apache-2.0 ✅ | Active | not measured (7 MiB unpacked, Shiki-based) | Vanilla | not assessed | not assessed | not assessed |
| File icons: `@iconify-json/material-icon-theme` or `vscode-icons` | MIT ✅ | Active | per icon, through `unplugin-icons` | Already the pattern (`~icons/carbon/*`) | not assessed | not assessed | OK |
| VS Code Codicons | **CC-BY-4.0 ⚠ (not OSI)** | not assessed | not assessed | not assessed | not assessed | not assessed | not assessed |

**Recommendations:**
- **Tree: our own Svelte tree** with `@tanstack/svelte-virtual` (⚑ D10). Loading lazily per directory over the machine link is the core requirement, and `@pierre/trees` is path-list-first, beta, and lives in a shadow DOM. It is the fallback if our tree grows complicated.
- **Viewer: CodeMirror 6, read-only, from the first slice.** It supplies line numbers, search, folding, keyboard access, mobile selection and accessibility for about 66K gz plus lazy languages. The same component later becomes the editor, so we never build a viewer twice. highlight.js stays for chat.
- **Diff pane:** unchanged for now. `@codemirror/merge` is a later option to unify Changes with the editor. It is not in scope.
- **Icons:** Carbon and Lucide via `unplugin-icons`, with a small map from extension to icon. **No Codicons** unless the user approves a CC-BY-4.0 asset (⚑ D13).

### 1.4 Machine side (Go)

| Need | Choice | Licence | Notes |
| --- | --- | --- | --- |
| PTY on Unix | **`github.com/creack/pty`** v1.1.24 | MIT ✅ | The de-facto standard, pure Go (`CGO_ENABLED=0` works), with `Setsid`/`Setctty`. Last release 2024-10, last push 2026-06: stable. |
| PTY on Windows (later) | `github.com/aymanbagabas/go-pty` (creack on Unix, ConPTY on Windows) | MIT ✅ | Only if Windows ever comes into scope. Hide it behind a small `pty` interface now. |
| Confinement | **stdlib `os.Root`** (Go 1.24; `Rename` and `WriteFile` in 1.25) | BSD-3 (Go) ✅ | Built on openat. It refuses `..` and symlink escapes, and removes the TOCTOU window of a "check realpath, then open" approach. |
| Watch | `github.com/fsnotify/fsnotify` | BSD-3 ✅ | inotify on Linux. On macOS it uses kqueue, which costs one fd per file, so the watch set stays small with a polling fallback. The dependency is added only in F3. |
| Ignore, status, search | the **git CLI** (`check-ignore`, `status --porcelain=v2 -z`, `ls-files`, `grep`), plus `rg` when present | none | Consistent with `internal/checkout`, and no gitignore parser to maintain. Outside git: a bounded Go walker. |
| Screen-state snapshot (optional, later) | `github.com/charmbracelet/x/vt` | MIT ✅ | Only if raw-ring replay artifacts prove annoying (§5.2). Its API is still moving. |

**Licences:**
- Everything recommended is MIT, BSD-3 or Apache-2.0: OSI-approved, permissive, and fine as dependencies of our OSI-licensed work.
- Flagged and **not** recommended:
  - Codicons: CC-BY-4.0, not OSI;
  - Theia: EPL-2.0, which is OSI but weak copyleft and unnecessary here;
  - Zed's server: GPL or AGPL;
  - tmate: tmux-derived, and not a library anyway.
- galopin stays at two non-stdlib dependencies until F3: `coder/websocket` plus `creack/pty`.

---

## 2. UX

### 2.1 Where things live

```
desktop ─ /code?device=&ws=&agent=
┌ sidebar ─────────┐┌ agent transcript ───────────────┐┌ workspace pane (SidePane) ─────────────┐
│ device           ││ …                               ││ [Changes] [Files] [Terminal ▾ 2]    ✕  │
│  └ workspace ⌁2  ││                                 ││ ┌ tree ────────┐┌ viewer ────────────┐ │
│     └ session    ││                                 ││ │ ▸ src   M    ││ src/app.ts  ⟳  ✎   │ │
│     └ session    ││ composer                        ││ │   app.ts M   ││ 1 import …         │ │
└──────────────────┘└─────────────────────────────────┘│ │ .env  🔒     ││                    │ │
                                                       └────────────────────────────────────────┘
```

- **One "workspace" side pane with tabs: Changes | Files | Terminal.** It replaces today's `diff` view in the single-slot `sidePane`. The store gains `view: "workspace"` and `workspaceTab`. The header button that toggles "Changes" today opens the pane on its last tab.
- **Scope follows the session's workspace.** Each worktree is its own workspace (M8), so each gets its own explorer and its own terminals. A terminal's cwd is the workspace path.
- **Workspace-level screens without a session:** the sidebar workspace kebab gains "Browse files" and "Open terminal". They open `/code?device=&ws=&view=files` or `&view=terminal&term=<id>` full-width in the main pane. The addresses are shareable between the owner's own tabs, since everything is owner-only.
- **Links between views:**
  - Changes → file header "Open in Files";
  - Files → "Open terminal here" (cwd = that directory, confined);
  - tool cards that mention a path → "Reveal in Files" (F2);
  - a terminal line matching `path:line` → open in Files (T2, via web-links' custom matcher).
- **Sidebar signal:** a small `⌁N` badge on a workspace row with running terminals.

### 2.2 Files tab

- **The tree:**
  - It loads lazily, one directory per expand, with directories first, then names in natural sort.
  - Git decorations: `M`, `A`, `D`, `U`, `R` and untracked, rolled up to folders.
  - Ignored entries are dimmed and never auto-expanded. `node_modules` shows as one dimmed row.
  - Deny-listed secrets show a lock and "hidden by this machine's policy".
  - `.git/` is not shown.
- **The viewer:**
  - CodeMirror read-only.
  - Large files open the first 1 MiB with "Load more", which fetches the next range.
  - Images (png, jpg, gif, webp) preview through `<img>` on a blob URL. SVG also goes only through `<img>`, never inline.
  - Markdown gets a Preview toggle through chat's existing renderer.
  - Binary files show "Binary file · 2.3 MB" (download is ⚑ D11).
- **Freshness:**
  - Manual refresh.
  - An automatic refresh of status and of the open file at each **turn boundary** (`status idle`) of any session in the workspace. This catches every agent edit with no watcher at all.
  - Live watch comes later (F3).
- **Search (F2):** `Ctrl-P`-style filename search, plus a content-search box with results grouped by file.
- **Edit (F4, behind `--allow-file-write`):**
  - An explicit ✎ Edit toggle.
  - Save sends the base revision. On a conflict, a dialog offers "reload theirs" or "overwrite", with a diff.
  - A warning banner shows while any session in this workspace is busy: "the agent is working here".
  - F4 covers new file only. Rename and delete are deferred; the agent or the terminal can do them.

### 2.3 Terminal tab

- A tab strip for multiple terminals per workspace: `+ New`, rename, close, exited state with exit code, and "Restart".
- Opening one, or reattaching after a reload, restores what the machine still holds (the last 2 MiB of output).
- It follows the Cerea theme (light and dark) and uses a bundled monospace font served under `${base}`.
- **Resize:** the focused viewer claims the size. When two viewers are attached (laptop and phone), the last one to focus wins, following paseo's size ownership.
- **Veto state:**
  - When the machine vetoes terminals, the tab shows disabled with the exact fix: "This machine was enrolled without `--allow-terminal`. Re-enroll with it to use terminals here." This is the same pattern as the auto-accept toggle fix.
  - When the deployment disables terminals, the tab is hidden.
- **First open per machine:** a one-time confirmation reads "A terminal is a full shell on ‹machine› as ‹user›". Acknowledging it is audited.

### 2.4 Mobile (below 768 px)

- The workspace pane becomes a full-screen sheet over the transcript, as the side pane already does, with the tabs at the top.
- **Files:** the tree and the viewer are two stacked screens. Tapping a file pushes the viewer, and Back returns to the tree.
- **Terminal:**
  - It opens in **view mode**: no keyboard, touch-scroll only, so an accidental tap never types into a shell. A **Type** button focuses xterm's textarea.
  - While typing, an **extra-keys bar** sits above the keyboard: Esc, Tab, Ctrl (sticky), Alt, the four arrows, `|`, `~`, `/` and `-`. There are A−/A+ font buttons.
  - The playwright mobile project covers it (`code-dialogs-mobile.spec.ts` style).

---

## 3. Protocol additions (diff-able spec section for `agent/PROTOCOL.md`)

Additive only. `protocol` stays `1`. The features exist only when `hello.machine.capabilities` says so, and unknown ops still answer `unsupported`. So an old Cerea paired with a new galopin works unchanged, and so does the reverse.

### 3.1 Changes to existing sections

```diff
 ## 4. Pairing and authorization
 - **Machine-side policy (the machine's veto, C4):** …
   - `allowFreeModels`: bool (default false). …
+  - `files`: `"read" | "off"` (default `"read"`, ⚑ D2). `off` answers every `files.*` op `forbidden`.
+  - `fileWrite`: `"allowed" | "denied"` (default `denied`; `enroll --allow-file-write`). Gates `files.write`.
+  - `fileDeny`: glob list (default: §3.4 deny list; `enroll --file-deny GLOB` adds, `--no-default-file-deny` drops the defaults, ⚑ D3).
+    Matching entries are listed with `redacted: true`; reading them is `forbidden`; search skips them.
+  - `terminal`: `"allowed" | "denied"` (default `denied`; `enroll --allow-terminal`). Gates every `terminal.*` op.
+  - `maxTerminals`: int (default 8). `terminal.open` beyond it is `invalid`.
   - The policy is reported in `hello` so the UI can explain refusals.

 ## 5. Framing
-JSON text frames, one object per frame, `type` discriminates.
+JSON text frames, one object per frame, `type` discriminates — plus **binary frames** for terminal
+streams only (§5.1). A peer that does not know binary frames never receives one: galopin sends them
+only on a channel Cerea opened with `terminal.attach`.

-| M→C (first frame) | `{"type":"hello","protocol":1,"agent":{…},"backends":[Backend],"policy":Policy,"credential":{"state":"ok"}}` |
+| M→C (first frame) | `{"type":"hello","protocol":1,"agent":{…},"backends":[Backend],"machine":Machine,"policy":Policy,"credential":{"state":"ok"}}` |
+| M→C | `{"type":"notice","scope":{"workspaceId"?:"…","terminalId"?:"…"},"event":Notice}` — machine-level, lossy, unsequenced (§7.1) |
+| C→M | binary `term.input` / `term.ack` (§5.1) |
+| M→C | binary `term.output` (§5.1) |

-`Policy = {"autoAccept":"denied","workspaceRoots":[],"allowFreeModels":false}`
+`Policy = {"autoAccept":"denied","workspaceRoots":[],"allowFreeModels":false,
+          "files":"read","fileWrite":"denied","fileDeny":[…],"terminal":"denied","maxTerminals":8}`
+`Machine = {"capabilities":{"files":true,"fileSearch":true,"fileWatch":false,"fileWrite":true,"terminal":true}}`
+   // capability = "this galopin implements it on this OS"; policy = "the owner allows it". Both must hold.
+   // terminal is false on non-unix builds.

 error codes: … "unsupported"
+  "conflict" (files.write revision mismatch; `error.details = {revision}`), "too_large" (over a cap).
```

### 3.2 §5.1 Binary frames (new)

```
byte 0        kind   0x01 term.output (M→C) · 0x02 term.input (C→M) · 0x03 term.ack (C→M)
byte 1        L      channel id length, 1..32
bytes 2..L+1  channel id, ASCII [A-Za-z0-9_-] (chosen by Cerea in terminal.attach, one per viewer)
next 8 bytes  u64 big-endian offset
                term.output: absolute output offset of the payload's first byte
                term.ack:    the viewer has consumed output up to (excluding) this offset
                term.input:  0
rest          payload: raw bytes. term.output ≤ 32 KiB; term.input ≤ 16 KiB; term.ack empty
```
Unknown kinds are ignored. Offsets are per terminal, start at 0 when the terminal is spawned, and never reset for the life of that terminal. An offset is meaningful only together with a `terminalId`, and terminals die with the galopin process (§5.2).

### 3.3 §6 Operations (new rows)

Paths are **workspace-relative**, `/`-separated, with no leading `/` and no `..` segments (`invalid` otherwise). `"."` is the root.

| op | args | result |
| --- | --- | --- |
| `files.list` | `{workspaceId, path=".", ignored?: bool=true}` | `{path, entries: Entry[], truncated}`. At most 5 000 entries; directories first, then natural sort. |
| `files.stat` | `{workspaceId, path}` | `{entry: Entry}` |
| `files.read` | `{workspaceId, path, offset?=0, length?=1048576, as?: "text"\|"base64"}` | `{path, revision, size, offset, length, eof, kind:"text"\|"binary"\|"image", mime, encoding:"utf-8"\|"base64"\|"none", content?}`. `length` is at most 1 MiB. A text range is trimmed to a UTF-8 boundary, and `length` reports the bytes actually returned. `binary` carries no content unless `as:"base64"`, and images are capped at 8 MiB (`too_large` beyond). Redacted paths are `forbidden`. |
| `files.status` | `{workspaceId}` | `{isGitRepo, branch?, head?, entries: [{path, x, y, origPath?}], truncated}`. `x`/`y` are the porcelain-v2 XY codes. At most 10 000 entries. |
| `files.find` | `{workspaceId, query, limit?=50}` | `{paths: string[], truncated}`. Fuzzy over `git ls-files -co --exclude-standard`, or over a bounded walk (at most 50 000 files, 3 s) outside git. |
| `files.grep` | `{workspaceId, pattern, regex?=false, caseSensitive?=false, glob?, limit?=200}` | `{matches: [{path, line, column, text}], truncated, engine:"rg"\|"git"\|"walk"}`. `text` is capped at 512 characters, the search at 5 s. It skips ignored, redacted and binary files. Capability `fileSearch`. |
| `files.watch` | `{workspaceId, paths: string[]}` (directories or files, at most 64) | `{watchId, ttlSeconds: 60}`. A **lease**: renewing is calling `files.watch` again with `watchId`, and it expires unless renewed. Capability `fileWatch` (F3). |
| `files.unwatch` | `{watchId}` | `{}` |
| `files.write` | `{workspaceId, path, content, encoding:"utf-8"\|"base64", baseRevision: string\|null}` | `{entry}`. `baseRevision: null` means the file must not exist yet. On a mismatch → `conflict` with the current revision. At most 1 MiB. Written atomically (temp + rename in the same directory, with the mode preserved). Policy `fileWrite`. |
| `terminal.list` | `{workspaceId?}` | `{terminals: Terminal[]}` |
| `terminal.open` | `{workspaceId, cwd?: path, cols, rows, title?}` | `{terminal}`. Policy `terminal`; `maxTerminals`. |
| `terminal.attach` | `{terminalId, channel, from?: offset}` | `{terminal, from, reset: bool, prelude?: base64}`. Streaming starts on `channel` at `from` = max(requested, ring start). `reset: true` means the requested offset had been evicted (or none was given): the viewer clears, then writes `prelude` (for example, re-entering the alternate screen) before the stream. The machine then nudges the foreground program to redraw (§5.2). |
| `terminal.detach` | `{terminalId, channel}` | `{}` |
| `terminal.resize` | `{terminalId, cols, rows, claim?: bool=true}` | `{applied: bool}`. `false` when another channel owns the size and `claim` was false. |
| `terminal.rename` | `{terminalId, title}` | `{terminal}` |
| `terminal.close` | `{terminalId, force?: bool}` | `{}`. SIGHUP to the process group, then SIGKILL after 5 s (immediately with `force`). |

Types:
```
Entry    = {name, path, type:"file"|"dir"|"symlink"|"other", size, mtime, revision?,
            hidden: bool, ignored: bool, redacted: bool,
            symlink?: {target: string, escapes: bool, dangling: bool}}   // escapes → never followed
Terminal = {id, workspaceId, title, cwd, shell, cols, rows, pid, createdAt,
            state:"running"|"exited", exitCode?, signal?, offset /* bytes produced so far */,
            viewers: number}
Notice   = {kind:"files.changed", paths: string[], overflow?: bool}         // scope.workspaceId
         | {kind:"terminal.exit", exitCode, signal?}                          // scope.terminalId
         | {kind:"terminal.title", title}                                     // scope.terminalId (OSC 0/2)
         | {kind:"terminal.state", terminal: Terminal}                        // opened/closed/renamed
```
Deadlines: the default is 15 s. `files.grep` and `files.find` run 5 s machine-side and 10 s in Cerea.

### 3.4 Default `fileDeny` (⚑ D3)

`.env` · `.env.*` except `.env.example`, `.env.sample` and `.env.template` · `.envrc` · `*.pem` · `*.key` · `*.p12` · `*.pfx` · `*.kdbx` · `id_rsa*`, `id_ecdsa*`, `id_ed25519*` · `.netrc` · `.npmrc` · `.pypirc` · `.git-credentials` · `.aws/credentials` · `.docker/config.json` · `*.tfstate` · `secrets.y*ml`.

The deny list is **not a security boundary** once a terminal or the agent can `cat` the file. It prevents *accidental* exposure: shoulder-surfing, screen sharing, and content flowing through Cerea into logs or caches. The UI says so.

### 3.5 §7.1 Notices (new)

`notice` frames are machine-level and lossy: no epoch or seq, no replay. A receiver that might have missed some re-queries (`files.status`, `terminal.list`). `files.changed` is debounced to 200 ms, with at most 256 paths; beyond that it sends `overflow: true` and the receiver refreshes everything.

---

## 4. Transport, flow control and backpressure

### 4.1 Machine ↔ Cerea (the single WSS)

1. **galopin's writer becomes a scheduler.** `writeMu` gives way to one writer goroutine with **two lanes**:
   - **control**: `res`, `event`, `notice`, `credential`, `auth`;
   - **stream**: `term.output`.

   Between messages it always drains control first, and stream frames are at most 32 KiB. A session event therefore waits behind at most one 32 KiB terminal frame, never behind a flood.
2. **Credit window per channel.** galopin sends `term.output` on a channel only while `sent − acked ≤ 256 KiB`. Acks originate **in the browser**, from xterm's `write(data, callback)` after each 64 KiB processed (the ttyd pattern), and Cerea relays them. In-flight data per viewer is therefore bounded end to end, and Cerea's memory is bounded at about N viewers × 256 KiB.
3. **What a slow viewer does to the process.** Out of credit, galopin **stops reading that PTY**, which is real terminal semantics (as over a slow ssh link): `yes` blocks rather than burning the CPU and the ring. But with zero attached viewers, or when every viewer has been out of credit for 10 s, galopin **keeps reading into the ring** (dropping the oldest). A background build never hangs because a tab went to sleep. A viewer that comes back behind the ring start gets `reset` (§5.2).
4. **The coalescer:** a 5 ms leading edge (echo is instant), trailing flush at 5 ms or 32 KiB, as paseo does.
5. **Binary, not base64.** For terminal bytes, JSON costs +33 % for base64, and much worse for escaped control characters. File content stays JSON: it is request/response, capped at 1 MiB, and mostly UTF-8. Large files are read as sequential 1 MiB ranges, so no file frame exceeds about 1.4 MiB.
6. **What remains of head-of-line blocking:** a single large *control* message, such as a multi-MB `session.sync` snapshot or a 50 MB diff, still occupies the socket while it is written. That already happens today and is rare: session open or diff refresh. The mitigation is milestone **H1**, chunked results (`res` with `part`/`parts`) for anything over 256 KiB. Tracked as a risk.
7. **Cerea's side of the link:**
   - `ws.on("message", (data, isBinary))` gets a binary branch that parses the header and routes by channel;
   - set `maxPayload` explicitly, at 160 MiB to match galopin;
   - relay output to the browser socket immediately. There is no buffering beyond the credit window, because acks only flow while the browser keeps up.

### 4.2 Browser ↔ Cerea

- **Files:** plain REST on the forwarder, with the same rules, `callOp` mapping and `getPairedDevice` check as today. `conflict` maps to 409, and `too_large` and `unsupported` map to 413 and 404.
  - `GET v1/workspaces/:ws/files?path=` · `…/files/content?path=&offset=&length=` · `…/files/raw?path=` (images only) · `…/files/status` · `…/files/find?q=` · `…/files/grep?q=&…` · `PUT …/files/content` (F4) · an SSE `…/files/events` for notices (F3).
  - **Raw bytes are served safely on the chat origin:** `Content-Type` comes from galopin's sniffed `mime`, and only raster images are served inline, with `X-Content-Type-Options: nosniff` and `Content-Security-Policy: sandbox; default-src 'none'`. Everything else goes as `text/plain` or `attachment`. HTML and SVG are never served inline, because a repository file must never become script on Cerea's origin.
- **Terminal:** a **browser WebSocket** (⚑ D9).
  1. `POST v1/terminals/:id/ticket?device=`. This passes through the hooks, so `locals.user`, C5 (JSON content type, SameSite) and `getPairedDevice` all apply. It returns `{ticket}`: 256 random bits, **single use, 30 s**, held in memory (one replica, as ADR 0089 assumes), and bound to `{userId, sessionId, deviceId, terminalId}`.
  2. The browser opens `new URL(`${base}/api/v2/code/terminal?ticket=…`, location.href)`, with the scheme swapped to ws or wss.
  3. The upgrade seam (the same global-symbol dispatcher, now routing by path) redeems the ticket. It **requires `Origin` to equal the public origin**, which blocks CSWSH, and refuses before upgrading on any mismatch.
  4. Messages: binary input (kind 0x02 with the channel filled in by Cerea), binary ack, and JSON `{t:"resize"}`. Outbound: binary output, plus JSON `{t:"reset",prelude}`, `{t:"exit"}` and `{t:"machine-offline"}` / `{t:"machine-online"}`.
  5. Cerea pings every 20 s. Every 60 s it re-checks the Cerea session and the device row. A logout, revoke or unpair closes the socket (`4403`).
- **Reconnects compose:**
  - **Browser ↔ Cerea drops** (Cerea redeploys, a network blip, the laptop sleeps): the browser mints a new ticket and reattaches with `from = the last offset xterm wrote`, with no duplicate or missing output.
  - **Machine ↔ Cerea drops:** Cerea keeps the browser socket, shows "reconnecting", and re-attaches on the new machine connection from the last offset it relayed.
  - **galopin restarts:** its terminals are gone, and the tab shows "ended: machine agent restarted" (⚑ D8).
- **Why not SSE for output plus POST for input:** it works through any proxy, but it costs a request per keystroke burst, needs its own ack channel, and doubles the auth surface anyway. The machine link already proves that WebSocket upgrades survive the `/chat` edge (Caddy on both the `proxy` and `edge` shapes).

---

## 5. galopin's side

### 5.1 `internal/files`

- `os.OpenRoot(workspace.path)` per operation, or cached per workspace and reopened when the workspace changes. Every access goes through the `Root`. That defeats `..`, absolute paths and **symlink escapes**, including a directory swapped for a symlink mid-operation, because it is openat-based with no TOCTOU. `workspaceRoots` is already enforced on the workspace itself.
- Symlinks are listed as `symlink` with `target`. `escapes: true` when the resolved target is outside the root, and then it is never followed or read. `dangling` is marked.
- `.git/` is skipped. Hidden (dot) files are listed with `hidden: true`, since dotfiles matter in development. `fileDeny` matches are redacted.
- Ignore flags come from one `git check-ignore -z --stdin` per `files.list`, fed the directory's names. Status comes from `git status --porcelain=v2 -z --untracked-files=all`, cached per workspace for 1 s and capped. Both use `checkout.git`'s helper style.
- Type detection: the extension, plus 8 KiB sniffing for NUL and invalid UTF-8, as paseo does. `revision = dev:ino:size:mtimeNs`.
- Write (F4): temp file plus rename inside the `Root` (Go 1.25 `Root.Rename`; ⚑ D12). The revision is re-checked immediately before the rename.
- Watch (F3): fsnotify on leased paths only, with a budget of 256 directories per machine. When inotify runs out of watches, or on macOS beyond the budget, it falls back to polling mtimes every 2 s. Everything is debounced to 200 ms.

### 5.2 `internal/terminal`

- **Spawn:**
  - `$SHELL -l`, falling back to `/bin/sh`, in `cwd`, which must resolve inside the workspace `Root`;
  - `creack/pty.StartWithSize` with `Setsid` and `Setctty`, and `Pdeathsig=SIGHUP` on Linux, in the same `procattrs_*` files as the opencode supervisor;
  - `TERM=xterm-256color`, `COLORTERM=truecolor`, `GALOPIN_TERMINAL=1`.
- **Env scrubbing:** the child inherits the user's environment, **minus everything galopin injected for itself**: `OPENCODE_SERVER_PASSWORD`, the shim secret, and any token or refresh variable. A unit test runs `env` in the PTY and asserts they are absent.
- **Ring:** 2 MiB per terminal, holding raw bytes and absolute offsets. The ring start is advanced to just after a `\n` within its first 4 KiB, so a replay rarely begins mid-escape.
- **Mode tracking:** a tiny state tracker follows alternate screen (`?1049/?47`), bracketed paste, cursor visibility and application-cursor mode. On `reset`, those modes go out as the `prelude`.
- **Redraw nudge:** after a reset attach, galopin sends a resize to rows−1 and back, which makes TUIs like vim, htop and less repaint.
- **Exact snapshots, if needed:** if that proves not good enough, H2 swaps in a VT emulator (`charmbracelet/x/vt`) for exact screen snapshots, as paseo does with `@xterm/headless`.
- **Lifecycle:**
  - Exited terminals are kept 10 minutes, with their exit code, for display.
  - Idle reaping: a terminal with no viewer for 24 h gets SIGHUP. Configurable, ⚑ D8.
  - All terminals are closed on `run` shutdown and on a **4403 revoke**: the process group gets SIGHUP, then SIGKILL.
- **Persistence:** terminals die with galopin. An optional later mode runs the shell inside `tmux new -A` when tmux exists, for persistence across galopin restarts (⚑ D8).
- **Windows: out of scope.** The Unix build tag gives `capabilities.terminal = true`, and on non-Unix builds it is `false`. There is no Windows dist today anyway. The later path is `aymanbagabas/go-pty` (ConPTY) behind the same small interface. `os.Root` works on Windows too, so files would follow for free.

### 5.3 Link, dispatch, enroll

- `link`: binary codec, a fuzz test on the header parser, the two-lane scheduler, and routing channels to `terminal`.
- `dispatch.go`: `files.*` and `terminal.*` are handled **before** the backend switch, like `workspace.*`, and never touch the backend.
- `enroll`: the flags `--allow-terminal`, `--allow-file-write`, `--no-files`, `--file-deny GLOB` (repeatable) and `--no-default-file-deny`.
  - The epilogue prints the policy in plain words, for example: "Terminals: ALLOWED — anyone who controls your Cerea session can run commands as ‹user› on this machine."
  - A local-only `galopin policy show|set` would let the owner **tighten** the policy without re-enrolling. Loosening would still require `enroll` (⚑ D1).
- **Local audit** (the one Cerea cannot erase): `<state>/galopin/audit.log`, JSON lines with rotation, recording:
  - `terminal.open/close` (id, cwd, shell, when);
  - `files.write` (path, bytes, old and new revision);
  - policy refusals.

  It **never records keystrokes, output or file content.**

---

## 6. Security and policy

### 6.1 Vetoes and defaults

| Power | Machine veto (enroll) | Default | Deployment switch (Cerea env) | Default |
| --- | --- | --- | --- | --- |
| Read files in workspaces | `--no-files` | **on**, confined and redacted (⚑ D2) | `CODE_FILES_ENABLED` | on when the code panel is on |
| Write files | `--allow-file-write` | **off** | `CODE_FILE_WRITE_ENABLED` | off (⚑ D7) |
| Terminal | `--allow-terminal` | **off** | `CODE_TERMINAL_ENABLED` | **off** (⚑ D7) |

A power is live only when **both** the machine and the deployment allow it, and galopin's capability says it is implemented. Cerea checks the policy and the switch before forwarding, returning 403 with the exact flag in the message, and galopin enforces again. That is the same double enforcement as `allowFreeModels`.

### 6.2 Who may use it

- The chain is unchanged: `locals.user` → device row with `userId == locals.user._id` and `status: "paired"` → the live connection is authenticated as that user's `sub`. For the terminal, the chain runs at ticket minting, is bound into the ticket, and is re-checked every 60 s on the open socket.
- CSWSH: an `Origin` check on the upgrade, plus the single-use ticket, which is never a long-lived cookie-only upgrade.
- **Step-up for terminals (⚑ D6):** recommend requiring an OIDC `auth_time` within the last 12 h to mint a terminal ticket, otherwise redirecting to re-login. This limits the "stolen long-lived cookie → shell" case. Plus the one-time acknowledgement per machine (§2.3).

### 6.3 Audit

- **Cerea:** a `codeAudit` collection with a TTL of 90 days (⚑ D14), holding `{userId, deviceId, action, workspaceId?, terminalId?, path?, bytes?, ip, userAgent, at}` for:
  - `terminal.open/attach/close`;
  - `files.write`;
  - `files.read` of a raw image (optional);
  - veto refusals;
  - ticket mint and redeem failures.
- It holds **no content and no keystrokes.** The forwarder must never log file content or terminal bytes (R6 already bans per-frame logs). A vitest asserts that the logger receives no content.
- **Machine:** the local audit log (§5.3). Under C4 this is the record that matters, because Cerea cannot rewrite it.

### 6.4 Interaction with auto-accept

- Auto-accept governs **agent permission requests** only. Explorer reads, file writes and terminal input are the owner's own actions, so auto-accept never applies to them, and they never create permission requests.
- The two are **orthogonal vetoes**, but the terminal is strictly *more* power than auto-accept:
  - auto-accept lets the model run commands unprompted;
  - the terminal lets whoever drives the browser (or Cerea) run commands directly.
- `enroll` warns when `--allow-terminal` is given without `--allow-auto-accept`: "you're denying unattended agent commands but allowing a remote shell". It does not refuse.
- Files the owner edits while an agent works: the busy-workspace banner (§2.2), and write revisions protect against clobbering the agent's newer write. The agent does not check revisions, so the reverse race exists; this is documented.

### 6.5 What this means for C4 and ADR 0089

- ADR 0089's residual: "while a paired machine is connected, a compromised Cerea process can prompt it within the machine's policy". In practice that **already reaches code execution**. Cerea sends `session.prompt` and then answers its own `permission.asked` with `permission.reply once`, since permission replies travel over the same link. It is only mediated by the model and by opencode's permission rules.
- **Explorer (read):** adds no new *class* of power. A compromised Cerea could already ask the agent to read a file. It does remove the model from the loop, so the deny list is the remaining friction, which is why ⚑ D2 is a decision rather than a given.
- **Terminal:** also no new class, but it removes every friction: no model, no opencode `permission` rules (for example `bash: deny` patterns), and no `workspaceRoots` confinement for what the shell does. It also enlarges the **non-compromise** surface: an XSS on the chat origin or a stolen session cookie becomes an interactive shell. The C4 statement for a terminal-enabled machine becomes: *"a compromised Cerea, or a hijacked owner browser session, has an interactive shell as the owner's OS user."*
- **So: yes, it needs its own ADR (⚑ D5).** The next free number (0090, unless something else takes it first) would cover:
  - the capability and the double veto;
  - the browser WebSocket transport and tickets;
  - binary frames;
  - the step-up rule;
  - the machine-side audit;
  - the amended C4 consequence.

  The explorer can be recorded in the same ADR as the lesser case.
- **Longer-term hardening, noted and not planned:**
  - browser-signed operations: a key registered with the machine at confirm time, so galopin verifies terminal input and permission replies came from the owner's browser and not from Cerea. That is the real fix for C4, and it becomes more valuable once terminals exist;
  - a machine-local "terminal session active" notification.

---

## 7. Backend-genericity

- Ops are namespaced `files.*` and `terminal.*`, dispatched in galopin before the backend, and **never call the backend**. They use the workspace registry, `os.Root`, git and a PTY.
- Capabilities live in `hello.machine`, not `backends[].capabilities`. The existing backend `files` capability (attachments) keeps its meaning, and the new machine one is a different key in a different object.
- They behave the same under `--backend opencode` and `--backend acp`, and the real-machine spec runs the explorer and terminal cases under both.
- **We don't use opencode's own `/file*`, `/find*` or `/pty`:**
  - ACP backends lack them;
  - they would bypass galopin's policy and deny list;
  - a PTY inside `opencode serve` would die with opencode's restarts.
- **Later synergy:** ACP defines *client-side* `fs/read_text_file`, `fs/write_text_file` and `terminal/*` methods, where the agent asks the client. galopin could serve those from the same confined `internal/files` and `internal/terminal` code for ACP agents that want them. That is out of scope here.

---

## 8. Tests

### 8.1 Go (`go test ./...`)

- **`files`:**
  - confinement table: `..`, an absolute path, `a/../../x`, a symlink escaping outside, a symlink inside, a symlink loop, a dangling link, a directory swapped for a symlink mid-read, and a Unicode or NUL path;
  - deny list and redaction;
  - UTF-8 range trimming, caps, `too_large`;
  - binary and image sniffing;
  - revisions and `conflict`;
  - `check-ignore` and status parsing against a temp git repo;
  - find and grep caps, timeouts, and the `rg`, `git` and `walk` engines;
  - the ignored and redacted exclusions.
- **`terminal`:**
  - ring eviction, the newline-aligned ring start, and the mode-tracker prelude;
  - the coalescer (leading and trailing edge);
  - credits: a slow fake viewer pauses reads, a detached viewer resumes ring filling, and the 10 s starvation fallback;
  - reattach at `from < ringStart` gives `reset`;
  - resize ownership;
  - exit events;
  - **env scrubbing**;
  - close kills the process group (`sleep` in the background);
  - `maxTerminals`;
  - policy `denied` gives `forbidden`;
  - revoke (4403) closes every PTY.
- **`link`:** a binary header fuzz test, and the scheduler: a control frame overtakes queued stream frames, and no stream frame exceeds 32 KiB.
- **Real-backend IT:** the existing opencode and ACP ITs gain one explorer and one terminal smoke each, with `echo $((6*7))` → `42`. The same ops under both backends prove genericity.

### 8.2 Cerea vitest (`TEST_MONGODB_URL`, `--no-file-parallelism`)

- **Forwarder routes:** capability, policy and switch gating with the exact 403 message; path validation; the error-code mapping (`conflict` → 409, `too_large` → 413).
- **Raw route headers:** `nosniff`, a sandbox CSP, `attachment` for non-images, and never `text/html` or `image/svg+xml` inline.
- **Tickets:** single use; expiry; wrong user, session or device; a revoked device; a foreign `Origin` → rejected before the upgrade.
- **Relay:** binary routing, ack pass-through, resume from the last offset after a simulated machine reconnect, and closing the browser socket on logout, revoke or unpair.
- **Audit:** records written; no content and no keystrokes in logs.

### 8.3 Hermetic e2e (Playwright + `tests/fake-machine.ts`)

- Extend the fake with an in-memory file tree (entries, contents, status, redacted flags), `files.*` handlers, and a fake terminal that echoes input and emits scripted output, with binary frames and credits.
- **Specs:**
  - `code-files.spec.ts`: browse, expand, open, "Load more", git badges, a redacted `.env`, image preview, search (F2), and the capability hidden when absent.
  - `code-terminal.spec.ts`:
    - the vetoed state shows the exact flag;
    - open, type, echo and resize;
    - reload the page, reattach, and assert the prior output is present exactly once;
    - force a reset path;
    - exit state;
    - multiple tabs.
  - `code-terminal-mobile.spec.ts`: view mode by default, "Type", and the extra-keys bar sending ESC and Ctrl-C.
- **Every spec runs twice: at root and under `E2E_APP_BASE=/chat`.** Under `/chat`, the terminal WebSocket URL and the Origin check are the parts most likely to break (compare the device-delete-under-`/chat` bug in the progress log).

### 8.4 Real-machine specs (`tests/machineHarness.ts`, which builds `agent/` in-repo)

- `code-machine-files.spec.ts`: list a real temp workspace, open a file the agent just wrote (after a turn, the auto-refresh at the turn boundary), a symlink escaping outside is shown but refused, and `.env` is redacted.
- `code-machine-terminal.spec.ts`, with the policy set to `terminal: allowed` per test through the harness:
  - `echo $((6*7))` → `42`;
  - `tput cols` follows a resize;
  - `exit` shows the exit state;
  - a reload reattaches with scrollback;
  - **coexistence**: run `yes | head -c 50000000` in the terminal while a session prompt streams, and assert that the transcript still streams and completes, with a loose latency bound.
  - A policy-denied run shows the disabled tab.
- Both run under `opencode` and `acp` backends, and at root and under `/chat`.

---

## 9. Decisions for the user

**Accepted 2026-09-24:** the user took D1–D14 **all as recommended**. Each decision below stands as its recommendation.

| # | Decision | Recommendation (accepted 2026-09-24) |
| --- | --- | --- |
| **⚑ D1** | Build the terminal at all, and should the owner be able to tighten the policy locally with `galopin policy set` without re-enrolling? | Yes to the terminal, behind `--allow-terminal`, default **off**. Yes to local tightening; loosening stays `enroll`-only. |
| **⚑ D2** | Is read-only explorer access **on by default**, confined and redacted with `--no-files` to opt out, or opt-in (`--allow-files`)? | **On by default.** The agent can already read these files, and the explorer is owner-only and confined. |
| **⚑ D3** | The default secret deny list (§3.4), and whether owners may drop it (`--no-default-file-deny`). | Ship the list and allow dropping it, with the UI saying it isn't a boundary. |
| **⚑ D4** | Is file **write** in scope (F4), and does it include rename and delete? | Yes, later, behind `--allow-file-write` (default off). Edit and create only; rename and delete deferred. |
| **⚑ D5** | A new ADR for terminal and files (amending the C4 consequence of 0089)? | **Yes**, before T1 ships. |
| **⚑ D6** | Step-up authentication to open a terminal (an OIDC `auth_time` of 12 h or less, else re-login)? | Yes, plus the one-time per-machine acknowledgement. |
| **⚑ D7** | Deployment switches: `CODE_TERMINAL_ENABLED` and `CODE_FILE_WRITE_ENABLED` default off; `CODE_FILES_ENABLED` defaults on with the panel. | As stated. |
| **⚑ D8** | Terminal lifetime: dies with galopin (v1), an idle reap after 24 h without viewers, and an optional tmux backing later? | Die with galopin, reap after 24 h; tmux as an opt-in follow-up. |
| **⚑ D9** | Browser transport for terminals: WebSocket with ticket and Origin check, or SSE plus POST? | **WebSocket.** |
| **⚑ D10** | Tree component: our own Svelte tree, or `@pierre/trees` (Apache-2.0, beta, shadow DOM)? | **Our own**, keeping pierre as the fallback. |
| **⚑ D11** | Downloading arbitrary (binary) files through Cerea, with a cap? | Not in F1 (image preview only). Revisit with a 25 MiB cap and `attachment` disposition. |
| **⚑ D12** | Bump galopin to Go 1.25 (for `os.Root.Rename`/`WriteFile`), needed by F4? | Yes, at F4. |
| **⚑ D13** | Any non-OSI asset: Codicons (CC-BY-4.0)? | **No.** Use Carbon and Lucide via `unplugin-icons`. Nothing non-OSI is proposed. |
| **⚑ D14** | Audit storage: a Mongo `codeAudit` collection with a 90-day TTL, or structured logs only? | The collection, with a 90-day TTL. |

---

## 10. Milestones

| ID | Slice | Size | Contents | Depends on |
| --- | --- | --- | --- | --- |
| **F0** | Spec + ADR | **S** | Merge §3 into `PROTOCOL.md`, draft the ADR (ai-stack, next free number, amends 0089's C4 consequence), ⚑ D1–D14 recorded 2026-09-24 | the `feat/galopin` merge |
| **F1** | **Read-only explorer** (first slice) | **M** | See F1 below. | F0 |
| **T1** | **Terminal behind a veto** (first slice) | **L** | See T1 below. | F0; the ADR accepted before release |
| F2 | Explorer search and links | S–M | `files.find`/`files.grep` plus UI; "Reveal in Files" from tool cards; markdown preview | F1 |
| T2 | Terminal polish | M | Mobile view mode and extra keys; the search addon; webgl; path links into Files; multi-viewer size ownership; the sidebar `⌁N` badge; idle reap; the step-up rule if ⚑ D6 | T1 |
| F3 | Live watch | M | fsnotify leases, `notice files.changed`, the SSE `files/events`, live status | F1 |
| F4 | Edit behind a veto | M | `--allow-file-write`, `files.write` with revisions, CodeMirror editable, conflict dialog, busy banner, new file, Go 1.25 | F1, ⚑ D4 |
| H1 | Chunked large results | M | `res` parts for results over 256 KiB (sync snapshots, diffs); removes the last head-of-line stall | T1 |
| H2 | Exact terminal restore (only if needed) | M | A VT emulator snapshot (`charmbracelet/x/vt`) replaces the prelude plus redraw nudge | T1 feedback |

**F1, the read-only explorer:**
- galopin:
  - `internal/files` with `list`, `stat`, `read` and `status`, on `os.Root`, with the deny list;
  - `hello.machine`, and the `files` and `fileDeny` policy fields plus their enroll flags.
- Cerea:
  - types, forwarder routes, and the safe raw route;
  - the workspace side pane with Changes | Files;
  - the Svelte tree, the CodeMirror viewer (read-only), git badges, and the turn-boundary refresh.
- Tests: the fake-machine extension, the hermetic spec and the real-machine spec, at root and under `/chat`.

**T1, the terminal behind its veto:**
- Policy: `terminal`, `maxTerminals` and `--allow-terminal`.
- galopin:
  - `internal/terminal` (creack/pty, ring, coalescer, credits, mode tracker, env scrub);
  - binary frames and the two-lane scheduler in `link`;
  - the local audit.
- Cerea:
  - the binary branch and the `ws` `maxPayload`;
  - tickets, the browser WebSocket and the relay with resume;
  - `codeAudit`;
  - `CODE_TERMINAL_ENABLED`.
- UI:
  - a lazy xterm.js component with fit, unicode11 and web-links;
  - the Terminal tab with multiple tabs, reattach on reload, the veto state and the one-time acknowledgement.
- Tests: Go unit tests, vitest, the hermetic spec, and the real-machine spec including coexistence, at root and under `/chat`.

Suggested order: **F0 → F1 → T1 → F2 ∥ T2 → F3 → F4**, with H1 as soon as T1 shows stalls in practice. On the box rules (at most 2 Sonnet agents, heavy runs under `flock`), F1 and T1's Go half can run in parallel. T1's Cerea half follows F1's side-pane work to avoid conflicts in `AgentView`/`sidePane`.

---

## 11. Risks

| Risk | Likelihood / impact | Mitigation |
| --- | --- | --- |
| A stolen session or XSS turns into a shell | low / **severe** | Default-off vetoes on both levels, step-up (⚑ D6), tickets plus Origin, safe raw-file serving, the audit on both sides, the ADR |
| Repository files served as script on the chat origin | medium / high | Raster images only inline; `nosniff` and a sandbox CSP; SVG only through `<img>` from a blob URL; everything else as text or attachment |
| Head-of-line stalls from big snapshots or diffs on the single WSS | medium / medium | The two-lane scheduler plus 32 KiB stream frames now; H1 chunked results |
| Secrets leak through the explorer, logs or the terminal environment | medium / high | The deny list, no-content logging (tested), env scrubbing (tested); the UI says the deny list isn't a boundary |
| Replay artifacts in TUIs after reattach | medium / low | Newline-aligned ring start, the mode prelude and the redraw nudge; H2 if needed |
| Mobile terminal input (IME, missing keys) | high / medium | View mode by default and the extra-keys bar; xterm.js has the most mature mobile story of the options |
| Huge monorepos (git status, find, grep, watch limits) | medium / medium | Caps and timeouts on every op, `truncated` flags, the watch budget with a polling fallback |
| A slow viewer stalls a process | low / medium | Credits pause the PTY only while a live viewer is keeping up; after 10 s starved or with no viewer, the ring keeps filling |
| Terminals lost on galopin restart surprise users | medium / low | A clear "ended: agent restarted" state; the tmux option (⚑ D8) |
| The owner edits while the agent writes the same file | medium / low | Revisions, the busy banner, and the turn-boundary refresh |
| `/chat` base-path breakage of the WebSocket upgrade or ticket URL | medium / medium | Specs at both bases; build the URL from `${base}`; the upgrade dispatcher compares `${base}${path}` as the machine link does |
| Windows users ask for it | low / low | Stated out of scope; `capabilities.terminal=false`; the go-pty path is noted |
| CodeMirror's move to Forgejo (supply chain, issue tracking) | low / low | npm releases continue; pin versions as usual |
