# Agent-chat features for the /code panel: plan

**Status: Plan only. Feature freeze: needs user approval; after auth + artifacts ship.**

Date: 2026-09-26. Written against Cerea `a52ce2f1` (galopin in `agent/`), opencode 1.18.32, and the galopin wire protocol in `Cerea/agent/PROTOCOL.md` (§6 ops, §7 events, §8 Cerea side). Paseo is not part of this design. The 2026-09-23 paseo parity plan was read for ideas only. Where its designs assumed paseo behaviour, this plan says so.

## 0. Summary

- **Native opencode slash commands: adopt. About 9.5 developer-days.** opencode has a real command API: `GET /command?directory=` lists commands per directory, and `POST /session/:id/command` runs one with arguments. The server does not expand `/name` sent as prompt text; only the TUI does. The old plan's "run = send the text" is therefore wrong for `opencode serve`. It was true only because paseo expanded commands client-side. ACP is the opposite case: the agent advertises `available_commands_update`, and a command runs as `/name args` prompt text.
- **One security finding shapes the design.** A command template's `` !`shell` `` runs on the machine during expansion, with no permission ask, even with `"permission": {"bash": "deny"}` (verified live, §1.4). A project command comes from the repository, so running one is running repository code. galopin therefore detects shell templates. A new machine policy refuses them by default, and the panel shows the exact shell snippets before a first run.
- **The same wave (§3):**
  - reasoning blocks: adopt (1 d);
  - permission-card polish: adopt the small part (1.5 d);
  - steering: adopt, spec first (2 d). opencode already folds a mid-turn prompt into its next step (verified);
  - history paging: later (2.5 d);
  - the effort pill: already shipped, with two small gaps.

## 1. What opencode 1.18.32 actually does (probed live)

Method: a throwaway `opencode serve` on a private loopback port, run under `timeout -s KILL` with isolated `HOME`/`XDG_*` and a logging mock OpenAI upstream, plus a project command, a user-level command and an `opencode.json` command. The server was killed by PID afterwards. `opencode acp` was probed the same way. Schemas come from the server's own `GET /doc` (OpenAPI).

### 1.1 Listing

- `GET /command?directory=<abs>` (operationId `command.list`) returns `Command[]`, where `Command = {name, description?, agent?, model?, source?: "command"|"mcp"|"skill", template, subtask?, hints: string[]}`.
- **Per directory: yes.**
  - For the project directory, the list was `init, review, cfgcmd, usercmd, projcmd, customize-opencode`.
  - For `/tmp` (no `.opencode/`), `projcmd` was missing.
  - With no `directory` parameter, the server uses its own cwd.
- The list merges these sources:
  - **built-ins:** `init` ("guided AGENTS.md setup") and `review` (`subtask: true`);
  - **config** `command` entries in `opencode.json`;
  - **user-level** `~/.config/opencode/command/*.md`;
  - **project-level** `<dir>/.opencode/command/*.md`;
  - **skills** (`source: "skill"`, e.g. the built-in `customize-opencode`);
  - **MCP prompts** (`source: "mcp"`).
- `hints` lists the placeholders the template uses (`$1`, `$ARGUMENTS`). The frontmatter fields `description`, `agent`, `model` and `subtask` come through as-is.
- **No scope field.** `source` does not say built-in, user or project. galopin can derive the origin: a name present for the workspace but absent for a neutral directory (galopin's own state dir) is project-scoped (§2.1).
- The TUI-only commands (`/compact`, `/undo`, `/redo`, `/models`, `/share`, `/exit`, …) are **not** in this list. They live in the TUI; the server has `session.summarize`, `revert` and the like instead.
- There is also an experimental `GET /api/command?location=` (v2). Don't use it.

### 1.2 Running

- `POST /session/:id/command?directory=` (operationId `session.command`) takes `{command, arguments, agent?, model?: "provider/model" (a string, unlike prompt_async's object), variant?, messageID?: "msg…", parts?: FilePart[]}`.
- **It is synchronous.** It answered after the whole turn: 7.5 s even against the instant mock, returning `{info: AssistantMessage, parts}`.
- An unknown name answers **500** `UnknownError` in about 0.1 s.
- Arguments substitute into `$ARGUMENTS`. `$1` took the whole argument string (`"alpha beta"`) when it was the only positional placeholder.
- `@path` in the template expands into synthetic "Called the Read tool …" parts with the file's contents.
- `messageID` is honoured as the **user** message's id. That gives an exact client-message mapping (§2.1).
- **Busy sessions:** a command sent mid-turn is accepted. Its text joined the running loop's next LLM request, the same as a queued prompt (§3.1).
- **Prompt text is not expanded.** `prompt_async` with text `/projcmd gamma` reached the LLM verbatim as `/projcmd gamma`.

### 1.3 Output

A command produces an ordinary turn on the existing event stream:

- `message.updated` (user). The user message has **no command marker**. Its first text part is the **expanded template**, non-synthetic, so today's fold would show the whole template as the person's bubble.
- Synthetic text parts for `@file` reads, then a `file` part.
- `session.status`, the assistant message, `step-start`, text parts and deltas, `step-finish` with tokens, and `session.idle`.
- A final `command.executed {name, sessionID, arguments, messageID}`. Its `messageID` is the **assistant** message, and it arrives only after the turn ends.
- A `subtask: true` command (`review`, or my `usercmd`) behaves differently. The user message carries a `subtask` part `{agent, description, command: "usercmd"}`, a child session is spawned (`GET /session/:id/children`), a `task` tool part appears, and a synthetic "Summarize the task tool output above…" user part follows. galopin already maps all of this: subtask parts, children, and the `rootSessionId` fan-out.

### 1.4 Security: template shell bypasses permissions (verified)

`` Shell: !`echo SHELL_RAN_$1` `` in a project command produced `SHELL_RAN_alpha beta` in the prompt, with no `permission.asked`. The same happened with `"permission": {"bash": "ask"}` and after a restart with `{"bash": "deny"}`. The same template run through `opencode acp` also executed. The expansion happens inside opencode, before any tool call, so galopin's auto-accept and permission plumbing never sees it.

### 1.5 ACP (`opencode acp`, and the generic adapter in `agent/internal/backend/acp`)

- After `session/new`, the agent sends `session/update` with `{"sessionUpdate": "available_commands_update", "availableCommands": [{name, description, input?: {hint}}]}`.
  - Probe result: the same six names as §1.1.
  - The list carries no template, source or origin.
- **Invocation:** `session/prompt` with a text block `/projcmd zeta`. opencode acp expanded it, and the shell snippet ran.
- galopin's ACP backend drops `available_commands_update` today (`events.go`: "available_commands_update, usage_update …: unmapped").
- ACP allows one prompt in flight per session. galopin's `Prompt` does not guard a second call while `st.busy`: it would overwrite the turn ids. The composer hides send while running, so this is unreachable today. §3.1 makes it reachable, so it becomes a fix.

## 2. Slash commands: design

### 2.1 galopin ops (PROTOCOL.md §6 additions; `protocol` stays 1)

New backend capability `commands: bool` (opencode: true; ACP: true), plus two ops.

**`backend.commands`**

- Args: `{backend?, workspaceId?, sessionId?}`
- Result: `{commands: Command[]}`

```
Command = {name, description?, source: "command"|"mcp"|"skill",
           origin: "builtin"|"machine"|"project"|null,
           hints: string[], agent?, model?, subtask?: bool,
           shell: bool|null, shellSnippets?: string[], fileRefs?: string[],
           templateHash?: string}
```

- **opencode:**
  - The directory comes from `workspaceId` (or the session's workspace).
  - One `GET /command?directory=` for the workspace, and one for galopin's state dir (cached per process). A name only in the first list is `project`. `init` and `review` are `builtin`. The rest is `machine`.
  - galopin scans each template for `` !`…` `` → `shell`, `shellSnippets` (each at most 200 chars, at most 10). It scans `@path` → `fileRefs`.
  - `templateHash` = sha256 of the template.
  - The template itself is **not** sent to Cerea: the snippets are what a person must see.
  - `source: "mcp"` → `shell: null` (unknown: the text is fetched at run time).
- **ACP:**
  - Needs `sessionId`. It answers from the last `available_commands_update` cached for that session, or an empty list before the first update.
  - Fields: `hints` from `input.hint`, `origin: null`, `shell: null`, no hash.
- `backend.models` is called the same way today, so Cerea fetches the list when the `/` menu first opens and caches it per open agent for 60 s. No new event kind is needed.

**`session.command`**

- Args: `{sessionId, name, arguments, clientMessageId?, attachments?, templateHash?}`
- Result: `{}` once accepted. The turn streams as events.
- **opencode:**
  1. Re-list for the session's workspace. An unknown name is `not_found`, which avoids opencode's 500.
  2. `templateHash` given and different is `conflict`. The repo changed between the confirmation and the run.
  3. Apply policy (§2.5).
  4. Mint an opencode-style ascending `msg…` id, and record `clientMessageId` against it (exact, unlike the prompt path's "next user message" heuristic).
  5. Fire `POST /session/:id/command {command, arguments, messageID, agent: overlay mode (only if the command has no agent of its own; precedence to verify in the IT), model: "provider/model" from the overlay, variant: overlay effort, parts: file attachments}`.
  6. This runs **in a goroutine on the long-lived client**, because the call blocks for the whole turn. The fast CRUD client's deadline would cut it off.
  7. A failure after acceptance becomes an `error` event on the session.
- **ACP:** validate the name against the cached list. `invalid` while `st.busy`. Then the existing `Prompt` path with text `/<name> <arguments>`.
- **Transcript marker:** `Message` gains `command?: {name, arguments}` on the user message.
  - opencode: from the minted `messageID`.
  - ACP: set by galopin on the user message it creates.
  - Cerea renders "/name args" as the bubble and folds the expanded template into a collapsed "Expanded command" disclosure.
  - Snapshots carry it too: galopin's overlay keeps `messageID → {name, arguments}` next to the other session overlay fields. A session run before a galopin restart loses the marker and shows the expanded text. That's acceptable, and should be documented.

### 2.2 Forwarder allowlist rows (`src/routes/api/v2/code/[...path]/+server.ts`)

| Method | Browser path | Op | Checks |
| --- | --- | --- | --- |
| GET | `v1/agents/:id/commands` | `backend.commands {sessionId}` | `getPairedDevice`. Maps to `CodeCommand[]`. `unsupported` → 404, and the menu then shows only panel commands |
| POST | `v1/agents/:id/command` | `session.command` | zod `{name: /^[A-Za-z0-9][\w.:-]{0,63}$/, arguments: string ≤ the messages cap, messageId?, templateHash?}`. Attachments exactly as `messages` (`promptAttachments` under `messageId`). `forbidden` → 403 naming the enroll flag. `conflict` → 409 "This command changed on the machine; review it again". Audit row `code.command {name, origin, shell}` (never the arguments, same as prompts) |

`$lib/codeApi.ts` gains `listAgentCommands` and `runAgentCommand`. The header comment's "Deliberately NOT offered" list stays true: there is no raw template read.

### 2.3 The composer's `/` menu (reuse chat's `@` idiom)

Chat's composer already has the idiom:

- `ChatInput.svelte` drives the `@` Hub mention through `HubMentionState` (`$lib/utils/hubMention.svelte.ts`): a tested state machine with `update(value, caret)`, `move`, `accept`, `dismiss`, `reset`, and accept-versus-send precedence.
- It renders `HfHubMentionAutocomplete.svelte`: a listbox with grouped options, a sibling live region, and anchoring to the caret via `getCaretCoordinates`.

`AgentComposer` already embeds `ChatInput` with hub mentions off.

- **`SlashCommandState`** (`$lib/utils/slashCommand.svelte.ts`): the same shape as `HubMentionState`. It has no debounce and no network: it filters a list it is given, by prefix first and then substring. It opens only when the draft starts with `/` and the caret is inside the first token. `//` at the start escapes to a literal slash.
- **`SlashCommandAutocomplete.svelte`**: the Hub listbox's markup and ARIA pattern (`aria-controls`/`aria-activedescendant` on the textarea, `data-result-index` scroll-into-view). The groups are:
  - "Panel" (client-side, §2.4);
  - "Project" (badge "from this repo");
  - "Machine";
  - "Skills";
  - "MCP".

  A shell icon marks `shell: true`, with a tooltip. Hints render as ghost text after accept (`/review ‹$ARGUMENTS›`).
- **`ChatInput` props:** `slashCommands?: SlashCommand[] | null` and `onslashcommand?`. Chat itself passes none, so chat's behaviour is unchanged.
- **Submit rules:**
  - A draft matching `^/(\S+)(?:\s+([\s\S]*))?$` whose name is a panel command runs it.
  - A known backend command goes through `runAgentCommand`.
  - Anything else is sent as ordinary text, today's behaviour. A message that starts with a path, such as `/etc/hosts is wrong`, still works.
- Mobile uses the same component. The panel anchors above the composer on narrow viewports, as the Hub panel does.

### 2.4 Client-side commands (mapped to existing ops)

| Command | Does | Existing route / op | Capability gate |
| --- | --- | --- | --- |
| `/compact` | Compact now | `POST v1/agents/:id/compact` → `session.compact` | `compact` |
| `/undo` | Revert to before the last user message | `POST …/revert {messageId}` → `session.revert`. Same confirmation as the transcript's own revert action, because files are restored | `revert` (+ `revertFiles` in the copy) |
| `/redo` | Undo the last revert | `POST …/unrevert` → `session.unrevert` | `revert` |
| `/model [q]` | No argument: open the model/effort pill. With an argument: the unique fuzzy match (or the pill pre-filtered) | `POST …/model` (`allowsModel` still enforced) | — |
| `/mode [id]` | Same pattern with the mode pill | `POST …/mode` → `session.setMode` | — |
| `/effort [level]` | Pick an effort level | `POST …/effort` → `session.setEffort` | `efforts` |
| `/new` | Open the new-agent dialog on the same workspace | existing create flow (`session.create`) | — |

**Excluded,** never shown even if a backend lists them:

- `/share` and `/unshare`: they publish the session to opencode's share service. That is outward-facing, and the panel must never do it implicitly.
- `/connect` and provider auth: credentials live in the enrollment.
- `/exit`, `/quit`, `/editor`, `/theme(s)`, `/sessions`, `/export`, `/details`, `/thinking`: TUI-only concerns.
- `/help`: the menu itself is the help.

**Collisions:** panel names are reserved. A backend command with a reserved name is listed greyed out as "shadowed by a panel command".

### 2.5 Security

- **A command has a prompt's power.** Its expanded text is a prompt, and every tool call in the turn still goes through permissions and auto-accept (including subagent inheritance and the handoff/question exclusions, §7). Nothing about auto-accept changes for commands.
- **Template shell and `@file` do not.** They run during expansion, outside permissions (§1.4). Project commands come from the repository, so a cloned repo's `.opencode/command/x.md` is code the person has not reviewed. The design:
  - **Machine policy `commandShell: "allowed" | "denied"`, default `denied`,** set by `enroll --allow-command-shell`. A local `galopin policy set` can only tighten it. When `denied`, galopin refuses `session.command` for `shell: true` and for `shell: null` (unknown: MCP, and ACP agents that don't expose templates) with `forbidden`. The forwarder maps that to a 403 naming the flag. It is reported in `hello.policy` so the menu can grey those rows out with the reason.
  - **Confirmation in the panel.** Even when allowed, the first run of a `project`-origin or `shell: true` command per (device, workspace, name, templateHash) opens a confirmation sheet listing the shell snippets and the file refs. The run then carries that `templateHash`, and galopin refuses with `conflict` if the template has changed since. The confirmation is remembered in `localStorage` per device. It is a UI speed bump, and the policy is the real veto.
  - **`fileRefs` against `fileDeny`.** galopin refuses a command whose `@path` refs match the machine's `fileDeny` (§9.4 list) with `forbidden`. The expansion would otherwise put a `.env` into the prompt, and from there into the gateway's logs, with no ask. The live IT must also check whether opencode's own `read` permission (`*.env: ask`) applies to `@` expansion (unknown).
  - **Model policy.** A command's own `model:` frontmatter can name a non-gateway model. galopin applies `allowFreeModels` to it (refuse with `forbidden`), the same as `setModel`.
- **Audit:** Cerea `codeAudit` and galopin's `audit.log` record `command {name, origin, shell, decision}`. They never record arguments or expanded text.
- **Residual risk, stated in the docs:** with `commandShell` allowed, running a project command is running repository code on the machine. The same is true of asking the agent to "run the tests" with auto-accept on.

### 2.6 Tests

- **Go unit tests** (`agent/internal/backend/opencode`, `…/acp`, `agent/*_dispatch_test.go`):
  - a fake opencode HTTP server asserting `GET /command?directory=` and the exact `POST /session/:id/command` body (string model, agent precedence, variant, minted ascending `messageID`, file parts);
  - `session.command` returns before the POST completes;
  - a late failure becomes an `error` event;
  - origin diffing, shell and `@` scanning, snippet caps, and `templateHash` conflict;
  - the policy gates: shell denied, unknown shell denied, a `fileDeny` ref, a free-model frontmatter;
  - `policy set` only tightens `commandShell`.
  - **ACP:** a fake agent emits `available_commands_update`, and the test asserts the list and the `/name args` prompt text, `invalid` while busy, and `unsupported`/empty before any update.
- **Live opencode IT** (`commands_opencode_it_test.go`, gated `GALOPIN_OPENCODE_IT=1`, pinned to 1.18.32, with the mock LLM and isolated env like `opencode_it_test.go`):
  - project, user and config commands listed per directory;
  - a run with arguments reaches the mock with the expanded text;
  - the user message carries `command`;
  - a `subtask` command spawns a child visible through `session.children`;
  - a shell template runs only with `commandShell: allowed`;
  - an `@.env` ref is refused;
  - a command sent mid-turn is folded into the next step;
  - it records whether `@` honours opencode's read permission.
  - `acp_it_test.go` gains the ACP variant.
- **Hermetic** (`tests/fake-machine.ts` + a new `tests/code-commands.spec.ts`; Vitest for the unit parts):
  - `SlashCommandState` unit tests modelled on `hubMention.svelte.test.ts`;
  - forwarder route tests (zod, 403/409 mapping, audit row);
  - `machineTimeline` renders the command bubble and the collapsed expansion.
  - **Playwright:** `/` opens the menu; filtering and arrow keys work; groups and badges show; Tab/Enter inserts the name; Enter runs and the fake machine sees `session.command` with the right args; panel `/compact`, `/undo` and `/model` hit their existing routes; an unknown `/foo` goes out as text; `//x` stays literal; a shell command shows the confirmation sheet with its snippets; a policy 403 shows the flag; the mobile viewport works.
- **Live check** on the real stack with a paired machine, in a scratch git repo: `/init`, a project command with arguments, `/review` (subtask), `/compact`, `/undo` and `/redo`. Confirm that a shell command is refused under the default policy.

### 2.7 Effort

| Piece | Days |
| --- | --- |
| galopin: two ops, capability, overlay marker, policy field + enroll flag, audit | 2.5 |
| galopin tests: unit + live IT (opencode + ACP) | 1.0 |
| Cerea: forwarder rows, `codeApi`, audit, `machineTimeline` command bubble | 1.0 |
| Composer: `SlashCommandState`, autocomplete component, `ChatInput` props, a11y | 2.0 |
| Panel commands (§2.4) + confirmation sheet | 1.5 |
| Vitest + Playwright hermetic suite | 1.0 |
| PROTOCOL.md §6/§7, `docs/code-panel.md`, live check | 0.5 |
| **Total** | **≈ 9.5 d** |

The old plan's 1.5 d assumed "send the text". The expansion rules, the synchronous endpoint and the shell finding account for the difference.

## 3. Other agent-chat features for the same wave

### 3.1 Steering a running turn: **adopt, spec first, 2 d**

- **Verified live:** with a turn busy, `prompt_async` answers 204, and the queued prompt joins the **next LLM step** of the same loop. The second model request carried `FIRST, reply, SECOND, <command text>`.
- So opencode steers natively at step boundaries. There is no mid-token interrupt, and none is needed.
- **galopin:**
  - opencode needs nothing new. Advertise capability `steer: true`.
  - ACP gets `steer: false`, and `session.prompt` answers `invalid` while busy (the §1.5 fix).
- **Cerea:**
  - While `running`, the composer shows send beside stop. Enter sends ("the agent reads this at its next step"), and a small menu offers "Stop and send".
  - The fold must accept a user message arriving mid-turn: a new assistant message follows it, with no fresh idle/busy pair.
  - Write the hermetic spec first, replaying opencode's real order (user echo mid-turn, then assistant parts, then idle once), and assert one bubble per prompt and a correct running indicator.
- **Product decision:** is the default Enter-while-running "steer" (opencode's behaviour) or "queue until idle" (client-side hold)? I recommend steer.

### 3.2 Richer permission cards: **adopt the small part (1.5 d); plan approval: wait**

- **Today:** the card gets `toolApproval: {tool, args: metadata}` and three buttons. `patterns` and `always` are dropped in `permissionRequestToUpdate`. `permission.reply` supports `message`, but the forwarder's zod schema doesn't pass it.
- **Adopt:**
  - show the command or path patterns;
  - label "Always" with the exact scope it grants (`always[]`, e.g. "Always allow `git status*`");
  - "Reject with feedback" (a text field → `message`, which opencode relays to the model);
  - a diff preview when an edit permission's metadata carries one (to verify against a live edit ask).
- **Plan approval:** opencode's `plan_exit` tool is behind `OPENCODE_EXPERIMENTAL_PLAN_MODE`. When on, it asks through the **question** tool ("Plan at … is complete. Would you like to switch to the build agent…", header "Build Agent"), which galopin and `AskQuestion.svelte` already handle. A richer card (render the plan file via `files.read`, "Start building") is optional polish.
- **Product decision:** should galopin set `OPENCODE_EXPERIMENTAL_PLAN_MODE=1` for its supervised `opencode serve`? I recommend not until upstream drops the flag.

### 3.3 History paging: **later, 2.5 d, measure first**

- opencode's `GET /session/:id/message` takes `limit` and `before` (OpenAPI 1.18.32). galopin's `Transcript` reads everything, so a long session's `session.sync` snapshot is one large frame.
- **Design:**
  - `session.sync {…, limit?}` → a snapshot with `hasMore` and `before`;
  - a new `session.history {sessionId, before, limit}` returns older messages (immutable, so no epoch interaction; a revert invalidates it, and a client re-syncs as today);
  - "Load earlier" at the column head, with the fold re-run over `older + current`.
  - ACP (`session/load` replays everything) pages from galopin's in-memory copy.
- **First step:** log snapshot sizes in production. Build this only if real sessions exceed a few MB.
- **Product decision:** the default window (I suggest the last 50 messages).

### 3.4 Reasoning blocks: **adopt, 1 d**

- Both backends already emit `reasoning` parts (opencode passes the part type through; ACP maps `agent_thought_chunk`). Cerea drops them on purpose (`machineTimeline.ts`: "reasoning: no panel shape yet").
- Chat already has `MessageUpdateType.Reasoning` and its collapsed rendering. Map the reasoning part and deltas onto it, flushing pending text first, as `Stream` does.
- **Product decision:** shown collapsed by default (recommended), or hidden behind a setting? Gateway models may return only summaries.

### 3.5 Thinking/effort pill: **already shipped; two gaps, 0.5 d**

- `session.setEffort` (capability `efforts`) exists end to end:
  - galopin keeps it in the session overlay and sends it as `prompt_async`'s `variant`;
  - a model's `efforts` are its configured variants (enroll writes `low`/`medium`/`high` for gateway models with `reasoning`);
  - Cerea's effort submenu lives inside the shared `ModelEffortPicker`, with the forwarder row `POST …/effort`.
- **Gaps:**
  1. `session.command` must send the same `variant` (covered in §2.1).
  2. `session.create` takes no effort, so a new agent always starts at the model default. This is optional.
- ACP reports `efforts: false`. Whether `opencode acp`'s bespoke `configOptions` carries a variant is unverified and not worth chasing now.

### 3.6 Side finding (a fix, allowed under the freeze)

`prompt_async`'s body in 1.18.32 accepts `messageID`, like `session.command`. galopin's comment in `internal/backend/opencode/http.go` says there is no such field, and it maps `clientMessageId` by "next user message". Minting the id, as §2.1 does for commands, would make that exact. It is small, and it can ship as a fix independent of this plan.

## 4. Decisions for the user

**Decided 2026-09-26:** the user accepted every recommendation below (1: yes, 2: `denied` by default with an opt-in, 3: no deployment switch, 4: steer, 5: collapsed, 6: after measuring, 7: plan mode off). **Nothing is queued.** The current wave (auth, artifacts) finishes first, then the user tests the deployment by hand and cuts a first release, and after that a slower, steadier roadmap is planned. This work goes into that roadmap.


1. Approve slash commands for the post-freeze wave (§2, ≈ 9.5 d)?
2. `commandShell` default `denied`, with `enroll --allow-command-shell` to opt in (recommended)?
3. Do you want a deployment switch `CODE_COMMANDS_ENABLED`, like files and terminal? I suggest no: commands are prompts, and the machine policy covers the dangerous part.
4. Steering: steer (recommended) or queue-until-idle?
5. Reasoning: collapsed by default (recommended) or hidden?
6. History paging: build now, or after measuring snapshot sizes (recommended)?
7. Plan approval: leave opencode's experimental plan mode off (recommended)?
