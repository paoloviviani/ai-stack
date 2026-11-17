# opencode 1.19 to 2.x: migration report for galopin

Date: 2026-11-14. Branch `feat/opencode-2` in Cerea. Backlog G1 and G15, Cerea issues #19 and #49.
Pin before: 1.19.3. Pin after: **2.3.0** (see "Version choice"). Sources read: the v2.0.0 to v2.3.0 release
notes, the repo's `CHANGELOG.md`, `services/site/src/docs/content/` (notably `migrate-v1.mdx`,
`permissions.mdx`, `tools.mdx`, `build/plugins/*`, `cli/acp.mdx`), `packages/protocol/openapi.json` (the
v2 HTTP API: 150 routes, 500 schemas) and live probing of the 2.2.7 and 2.3.0 binaries against galopin's
mock LLM.

## Summary

opencode 2 is a rewrite behind the same `opencode` command. opencode's own guide names three intentional
breaks: **plugins**, the **server API and clients**, and the terminal client's config file. Everything else
(`opencode.json`, agents, commands, skills, `AGENTS.md`) keeps reading in the 1.x shape. galopin touches two
of the three:

* the server API: `opencode serve` no longer serves any 1.x route (`/global/health`, `/session`, `/event`,
  `/doc` all answer the web UI's HTML), so the whole backend transport changed;
* plugins: galopin's coordination and schedule tools were 1.x `tools/*.js` files; they are now one 2.x
  plugin.

The config galopin generates (`opencode.json`: provider, models, variants, `enabled_providers`, static
`permission`) is **accepted unchanged** by 2.x. Verified live: a 1.x-shaped file loads, models resolve, the
variants become 2.x variants. So no config migration is needed for machines enrolled under 1.x.

## Breaking-change table

| # | 1.19 | 2.x | galopin impact | Handled |
|---|------|-----|----------------|---------|
| 1 | Health: `GET /global/health` | `GET /api/info` (version, pid, paths) | start-up wait | `opencode.go` waits on `/api/info` |
| 2 | Routes `/session`, `/session/:id/prompt_async`, `/abort`, `/summarize`, `/permission/:id/reply`, `/question/...`, `/agent`, `/config/providers`, `/doc` | `/api/session`, `.../prompt`, `.../interrupt`, `.../compact`, `.../permission/:rid/reply`, forms, `/api/agent`, `/api/model`, ... ; replies wrapped `{data, location?}` | every call in `internal/backend/opencode` | `http.go` rewritten on `doData` |
| 3 | Directory chosen by `?directory=` | `location[directory]=` query (or `x-opencode-directory` header); session routes take it from the session | every per-workspace call | `withLoc` |
| 4 | SSE `GET /global/event`, frames `{directory, payload:{type,properties}}`, `message.updated` / `message.part.updated` / `.delta` / `session.status` / `session.idle` | SSE `GET /api/event`, event-sourced frames `{type, created, location?, data}`: `session.step.started/ended/failed`, `session.text.started/delta/ended`, `session.reasoning.*`, `session.tool.input.* / called / progress / success / failed`, `session.execution.started/succeeded/failed/interrupted`, `session.inbox.*`, `permission.asked/replied`, `form.*`, `session.compaction.*`, `session.revert.*`. `session.status`/`session.idle` are not emitted | the translation layer | `v2.go`: a stateful adapter turns each 2.x event into the 1.x-shaped frames the rest of the package reads; `events.go` reads the new envelope. Events without a `location` get the session's directory from a cache |
| 5 | Message = `{info, parts[]}`, each part has an id; tool state under `part.state` | Messages are typed (`user`, `assistant`, `synthetic`, `shell`, `compaction`, `idle`, `agent-switched`, ...). An assistant message carries a `content` array (text / reasoning / tool, no part ids) and tokens/cost/finish/error. `idle` markers record each run's outcome | transcript, history, usage, attachments | `v1Entries` rebuilds `{info, parts}`; part ids are `<msg>:<content index>` (text, reasoning) and `<msg>:<callID>` (tools; providers may reuse call ids across turns) |
| 6 | Prompt takes `agent`, `model`, `variant`, `system`, `parts[]`, caller `messageID` | Prompt takes `{id, text, files, delivery, resume}`. Agent, model and variant are **session state** (`POST .../agent`, `POST .../model` with `variant` inside the model ref). No per-turn `system` | overlay (mode/model/effort), Plan-mode note, preface | `applySelection` writes agent/model/variant once, when they change, before a prompt or compaction. The Plan note is a keyed session instruction entry (`PUT/DELETE /api/experimental/session/:id/instructions/entries/galopin-plan`). The preface is a synthetic message sent ahead (`resume:false`) and folded into the next user message when the transcript is read. Caller-minted `id` is honoured (`msg_` ids unchanged) |
| 7 | Stop: `POST /session/:id/abort`; the abort is recorded on the message | `POST .../interrupt`; `session.step.failed` with error type `aborted`, then `session.execution.interrupted` | Cancel, "a Stop is not a failure" | Aborted maps to the 1.x `MessageAbortedError`, so the existing rule holds |
| 8 | Permission ask: `{permission:"bash", patterns, always, tool:{messageID,callID}}`; reply `POST /permission/:id/reply {reply}` needs `?directory` | `{action:"shell", resources, save, source:{type:"tool",messageID,id}}`; reply `POST /api/session/:sid/permission/:rid/reply {decision, message}`; pending asks per location (`/api/permission/request`) or per session | the decision function, cards, `PendingAsks` | `v1Permission` renames to the 1.x keys (`shell`->`bash`, `subagent`->`task`) so `internal/decide`, `permrules` and the panel are untouched; `PendingAsks` walks the directories seen |
| 9 | Rules: per-tool object (`permission.bash["git *"]`), last match wins, session `permission` appended by PATCH | One **ordered array** `permissions: [{action, resource, effect}]`; actions renamed (`bash`->`shell`, `task`->`subagent`, `write`/`patch`->`edit`); default policy per agent; global rules after an agent's defaults, `agents.<id>.permissions` last. **`external_directory` is now allowed by default** (1.x asked). Session `permissions` is settable on create/PATCH | the ceiling, Plan/Ask/Allow semantics | The floor (ADR 0097) is re-emitted as arrays in `OPENCODE_CONFIG_CONTENT`: global `* ask` plus every named key, then agent blocks restating plan's edit deny (plan dir ask), explore's blanket deny, general's question/subagent deny, the hidden agents' deny. `external_directory` asks under `*`. `execute` (Code Mode) is denied so each tool call is its own ask. A 1.x `permission` object in pinned content is converted and placed before the floor so the floor is last |
| 10 | Question tool: `question.asked`, `POST /question/:id/reply {answers}` / `/reject` | A form (`form.created`, metadata `kind:"question"`, fields `q0..`); reply `POST .../form/:fid/reply {answer:{q0:"A"}}`, dismiss `DELETE .../form/:fid` | Questions capability | `v1Question`, `formAnswer`, `answersFromForm` |
| 11 | Compaction: `POST /summarize {providerID, modelID, auto}` | `POST .../compact` (uses the session's model); `session.compaction.started/ended/failed`; a `compaction` message | Compact, the compaction part | Overlay model written first; the live part is emitted at `started`, the transcript is re-read at `ended` (resync) |
| 12 | Revert: `POST .../revert {messageID}`, `/unrevert`; session `revert.messageID` | `POST .../revert/stage {messageID, files}`, `DELETE .../revert` (clear), `.../revert/commit`; `session.revert.*` events | Revert, Unrevert, transcript hiding | Same cut at `revert.messageID`; staged with `files:true` |
| 13 | Diff: `GET /session/:id/diff` gives before/after | `GET .../diff` gives a unified `patch` per file | Differ | `fileDiffFromPatch`: After from the workspace file, Before by reversing the patch; the tracker's own record still merges in |
| 14 | History paging: `before` cursor `{id,time}` | Opaque cursor `{id, order, direction}`; a cursor and `order` together are a 400 | `session.history` | `messageCursor`; pages read until `limit` mappable entries |
| 15 | Models: `GET /config/providers` | `GET /api/model` (flat, `capabilities.input[]`, `variants[]`, `limit`), default `GET /api/model/default` | Models, efforts, images, context window | `Models` rewritten; reasoning = has variants |
| 16 | Agents: `name` is the id | `id` is the id, `name` the display name ("Build"); `hidden`; `model` is a ref object | Modes, AgentModels | `id` preferred; hidden agents skipped |
| 17 | Subagent tool `task` (`subagent_type`, foreground; `background:true` only with `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=1`); result in `<task_result>`; child id in metadata | Tool `subagent` (`agent`, `background` always allowed, no flag). **2.3.0 makes every subagent a background one** (immediate return, the parent is woken by a `<subagent>` synthetic message). 2.2.7 keeps foreground by default. The child session carries `agent`; result is `<subagent sessionID=... state=...>` | delegation, the background-subagent policy, the panel's task rows | Tool names are mapped back (`subagent`->`task`). A machine without background subagents gets the `subagent` tool denied in the floor (no foreground form exists) |
| 18 | Custom tools: `OPENCODE_CONFIG_DIR/tools/*.js`, `{description, args, execute(args, ctx)}`; plugins run `.opencode/plugin` | V1 tool files and plugins **do not run**. A 2.x plugin: `export default {id, setup(ctx)}` registering tools through `ctx.tool.transform`; `execute(input, {sessionID, id, messageID, signal})`; plugin tools are not asked about by opencode. `--pure` is gone; `OPENCODE_DISABLE_PROJECT_CONFIG` also stops project plugins | the nine coordination/schedule tools, the delegation skill | `tools.go` writes `<ToolsDir>/plugins/galopin-tools/index.js`, removes the old `tools/` folder, keeps the loopback relay.  |
| 19 | Tool names `bash`, `edit`, `read` (`filePath`), `write`, `task`, `list`, `todowrite` | `shell` (a call to `bash` still runs, with a note), `read` takes `path`, `write` `path`, `edit` `{path, oldString, newString}`, `subagent`, no `list`, todos off by default | the panel's tool names, mock-driven ITs | Names mapped to 1.x in events and transcripts; the ITs' scripted calls updated |
| 20 | Commands: `GET /command` carries `template`, `source`, `hints`; `POST /session/:id/command {command, arguments, messageID, agent, model, variant}` blocks for the turn | `GET /api/command` is `{name, description}` only; `POST .../command {name, text, files, delivery}` answers at once with the queued prompt, id server-minted | command origin proofs, shell/file scan, expansion | Origins cannot be proven without templates: every command reads as `project` with shell unknown, the fail-closed shape (confirmation sheet; refused under a denied shell policy). `RunCommand` records the client-message mapping from the answer's id |
| 21 | `OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD` | username is always `opencode`; `OPENCODE_PASSWORD` or `OPENCODE_SERVER_PASSWORD` | server auth | unchanged (galopin used user `opencode`) |
| 22 | env `OPENCODE_CONFIG`, `OPENCODE_CONFIG_CONTENT`, `OPENCODE_CONFIG_DIR`, `OPENCODE_DISABLE_PROJECT_CONFIG`, `TMPDIR` | all still read (`cli/src/server-process.ts`). The Bun temp extraction is now `$TMPDIR/opencode` | child env, `opencodetmp.go` | unchanged |
| 23 | `opencode --version` prints `1.19.3` | prints `opencode v2.3.0` | version checks in CI, images, `launch` | normalised (`sed`/Go) wherever compared |
| 24 | Install: npm `opencode-ai` | npm **`@opencode/cli`** (`opencode-ai` stays at 1.19.5), GitHub archives with the same names (`opencode-linux-x64.tar.gz` ...), single `opencode` binary | CI, `bump-opencode.sh`, docs | CI installs `@opencode/cli@<pin>`; the latest-release job asks npm for `@opencode/cli`; archive names and the served installer are unchanged |
| 25 | Session store: SQLite `opencode.db` in the data dir | same file name, new schema; V1 history is migrated by the server on first start (`GET /api/experimental/migration/v1`: `required`/`running`/`completed`) | existing machines | see "Existing machines" |
| 26 | LSP tools and diagnostics | accepted in config, **never run** | none (galopin does not rely on LSP) | none |
| 27 | `todowrite` on | off by default (`experimental.todo`) | the panel's todo list stays empty | not enabled; noted |
| 28 | `CLAUDE.md` fallback for instructions | only `AGENTS.md` is read | repos that relied on `CLAUDE.md` | noted in the changelog |
| 29 | ACP: `opencode acp` | same command; `available_commands_update`, commands run asynchronously (the prompt answers when queued, the model request follows) | the generic `--backend acp` path | one IT assumed the request had arrived at idle; it now waits for it |

## process-daemon

The `process-daemon` releases (v0.3.2 to v0.5.2, tags `process-daemon-v*`) are a separate helper binary
(`opencode-pty daemon`) that the server downloads into `$XDG_CACHE_HOME/opencode/bin/opencode-pty/<ver>/` and
spawns lazily for persistent terminals and, on Windows only, local shell commands ("Local Windows shell
commands now run through the process daemon", 2.3.0). It is **not required** to run `opencode serve` on Linux
or macOS and is not in the opencode release archives. galopin does not use PTYs. Consequences: the first use
of a terminal needs network once to fetch it; the galopin image and offline machines do not need it. Nothing
to bundle.

## Version choice

**2.3.0** (2026-11-13), on the owner's decision of 2026-11-14 that always-background subagents are wanted.
An earlier draft of this report chose 2.2.7 because 2.3.0 ends foreground subagents; that choice was
reversed and the code adapted instead of gating `background`. 2.2.7 passed the same suite apart from the
foreground assumptions and stays the fallback if 2.3.0 regresses.

How galopin handles always-background subagents:

| Concern | Behaviour |
|---------|-----------|
| The call | `subagent` returns the child's session id at once (`metadata.sessionID`); galopin links the tool part to the child (`SubtaskSessionID`) and the panel shows the child under its parent from `childSummary` (running / waiting / done). The parent's turn may end while children run. |
| A child's report | opencode injects a `<subagent sessionID state>` synthetic message into the parent; if the parent is idle that starts a new execution. The adapter turns the injected message into a user-role message whose only part is synthetic (never a typed prompt), and the new turn is ordinary events, usage and cost. |
| Approvals in a child | Unchanged: the floor asks for every call in every agent, the child follows its root's selector, the card names the child session. |
| galopin's own tools | `session_spawn`, `session_committee` and the ADR 0099 reports cover only the sessions galopin creates; opencode's `<subagent>` report covers only opencode children. The two paths never overlap, so nothing is reported twice. The delegation skill now says so. |
| Stop | opencode interrupts only the session asked (probed on 2.3.0: the child keeps running to success and its report wakes the parent again). Followed and documented, not overridden. |
| Scheduled runs | The schedule executor fires and forgets; the next run is refused while the session is busy. `busyReason` now also counts children running or waiting, so a run is not started, nor the session called idle (`sessionState`), until they finish. |
| Policy `--no-background-subagents` | There is no foreground form left, so the floor denies the `subagent` tool (fail closed). |

## Existing machines

Owner scope (2026-11-14): the three machines are disposable, so 1.x to 2.x is a documented hard migration:
machines move by reinstalling or upgrading galopin and opencode, and 1.x session history may not carry over
(back up `~/.local/share/opencode/opencode.db` first). `requireMajor2` keeps its clear error for a 1.x binary.
The generated `opencode.json` is read as is by 2.x.

**Within 2.x, history carries.** `TestOpencodeUpgradeWithin2KeepsHistoryAndGalopinState` makes a session
(mode plan, model, selector Allow, an exception, one turn) under 2.2.7 in a temp data dir and overlay file, then
opens the same dirs under 2.3.0: the session is listed, its history reads, and mode, model, selector and
exception still apply and the session still runs. galopin keys its state on session ids and its own files, not
on versioned paths. CI installs 2.2.7 beside the pin so the test runs there (`GALOPIN_OPENCODE_PREV_BIN`).

## Behaviour changes users may notice

* Subagent results read `<subagent sessionID=... state="completed">` instead of `<task_result>`.
* `external_directory`: asks as before (the floor restates it), so no change; opencode's own default changed.
* Slash commands are listed by name and description; the panel treats all of them as repo commands
  (confirmation sheet). Templates are not exposed by the 2.x API.
* Todos do not appear (off in 2.x unless `experimental.todo`).
* `CLAUDE.md` is no longer read as an instructions fallback.

## Further findings during the port

* **A location answers partially while it loads** (`/api/agent`, `/api/command`: empty, then builtins, then the
  project's). galopin reads each until stable the first time per directory and process.
* **Models claim image input by default.** A 1.x models map with no `modalities` is read by 2.x as taking
  images. Enroll now writes `["text"]` for models the gateway does not say take images, and galopin states
  `["text"]` in `OPENCODE_CONFIG_CONTENT` for an existing file that lacks it (no re-enroll).
* **`POST .../command` answers 204 with no message id.** The command marker is claimed by the session's next
  user message created after the run.
* **Two asks per outside file** (`external_directory`, then `read`/`edit`): an `external_directory` exception
  now covers both (internal/decide).
* **`always` is a project-wide saved approval in 2.x.** The backend answers opencode `once` whatever it is told.
* **Stop** interrupts the parent only (verified on 2.3.0); children keep running and their report wakes the
  parent. Followed as is.
* The mock LLM treats opencode 2's image-only follow-up user message as a tool carry-over.

## Test status

* `go vet ./...`, `go test ./...` in `agent/` (no gates): pass.
* Real-opencode suite against 2.3.0 (`GALOPIN_OPENCODE_IT=1 GALOPIN_ACP_IT=1`): passes except the known list in
  the PR description (the nine-large-screenshots tool-image subtests, `TestModelImagesIntegration`/provider
  override rechecks, and anything the last run did not cover).
* vitest `codeEnrollCommand.spec.ts` and the new `agentSessions.spec.ts`: pass.
* Cerea `tests/code-*` e2e (fake machine, no opencode): not run locally; CI runs them.
