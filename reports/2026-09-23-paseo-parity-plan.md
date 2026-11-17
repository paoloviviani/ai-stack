# Paseo parity plan for Cerea's coding-agent panel

Date: 2026-09-23 · Scope: research and planning only (no source file edited in any repo) · SDK pin: `@getpaseo/client` / `@getpaseo/protocol` 0.8.0 · Architecture: ADR 0085

## 0. Summary

- **Where Cerea stands.** Cerea drives about 25 of the daemon's ~200 SDK methods, all through a sound allowlisted forwarder and an SSE bridge that folds into chat's own components. Each target feature has a stock upstream path in 0.8.0:
  - **usage:** `usage_updated`, `turn_completed.usage`, `lastUsage`;
  - **images:** `sendAgentMessage{images}`;
  - **file uploads:** `uploadFile` plus `attachments[uploaded_file]`;
  - **handoffs:** `buildAgentForkContext` for user forks, the paseo MCP `create_agent` for agent-initiated handoffs;
  - **multi-agent:** `agent_update`, attention events, the `paseo.parent-agent-id` label, `detachAgent`.
- **The live daemon confirms it.** Real context numbers are present (11,955 / 1,048,576). The relay link is an **owner** principal. Agent-to-agent handoff is **off** by default (`mcp.injectIntoAgents: false`).
- **Three existing risks to fix first (M0):**
  - the minor-version pin will cut users off when their daemon self-updates to 0.9 (upstream ships about one minor a week);
  - the history/live seam dedups by text, so identical tokens or prompts can vanish;
  - SDK use is spread across modules via an `internal/` import path.
- **The plan.** Nine milestones, M0 → M5b, about 24.5 developer-days for the requested minimum. Every milestone is feasible on stock upstream. Fold changes are limited to side-channel cases (usage, compaction) plus one property on the user frame (attached files). Steer and history paging, which touch the turn structure, come later, spec first.
- **Fork vs track: track upstream now.** Contain the churn with an adapter module and contract fixtures, upstream three small generic PRs, and **spike "Cerea as Paseo Hub"**. That stock feature gives a scoped principal, no relay, and IdP-native enrollment. A fork is justified only under the triggers in §8.6: relicensing, loss of the client path, a scoped-principal mandate, workaround weight, an upstream stall, or owning distribution anyway.

## 1. Method and sources

| Source | What was read | Where |
| --- | --- | --- |
| Cerea `main` snapshot | `codeDaemon.ts`, the forwarder, the SSE bridge, `codeTimeline.ts`, `consumeAgentUpdates.ts`, `types/CodeAgent.ts`, `components/code/*`, `ChatInput`/`ChatWindow` file machinery, `server/files/uploadFile.ts`, `docs/code-panel.md`, `tests/code-*.spec.ts` | `/home/ubuntu/.paseo/worktrees/review-cerea` |
| SDK 0.8.0 (as installed) | `daemon-client.d.ts`/`.js`, `connection/index.js`, protocol `messages.js`, `agent-types.d.ts`, `client-capabilities.d.ts`, `agent-labels.js` | `node_modules/@getpaseo/*/dist` |
| Paseo source at **tag `v0.8.0`** (`b8e24677e`, 2026-09-10) | `packages/server` (session, agent-manager, opencode provider, file-upload, prompt-attachments, authorization, hub, MCP tools), `packages/app` (composer, attachments, subagents, fork, context meter), `packages/cli` (hub), `docs/hub.md`, `docs/permissions.md`, `skills/paseo-handoff` | `/tmp/paseo-080` (a worktree of `/tmp/paseo-src`) |
| Paseo upstream head | `v0.9.1` (2026-09-22), used for drift measurement only | `/tmp/paseo-src` |
| Relay | `getpaseo/paseo-relay` at Cerea's pinned commit `3fc41c9` (Elixir) | `/tmp/paseo-relay` |
| Live daemon `test-pv` | Two read-only probes: `getDaemonStatus`, `getLastServerInfoMessage`, `listAvailableProviders`, `fetchAgents`, `fetchAgent`, `getHubStatus`, `getDaemonConfig`, `listProviderModels/Modes/Features`, `listProviderUsage`, `fetchAgentTimeline`, `listCommands`, `listProviderSubagents`, `fetchWorkspaces`, `scheduleList`, `listTerminals` | `/app/probe-tmp/x.mjs`, `x2.mjs` in `llm-platform-chat-1` |

The tag matches the pin, so nothing was inferred across versions. Claims marked **[unverified]** were not checked against code or the live daemon.

### 1.1 What the live probe established (2026-09-23 17:06 UTC)

- The daemon reports **0.8.0**, `serverId srv_6qh_KrcwRZlE`, with relay endpoint `cerea.example.org:443`. Only `opencode` is available; claude, codex, copilot and pi are not.
- **The relay session carries all nine daemon permissions**: `daemon.read`, `daemon.manage`, `tunnel.manage`, `access.manage`, `workspace.read`, `workspace.write`, `workspace.manage`, `automation.manage` and `hub.execute`. Cerea's pooled link is an **owner** principal, so the forwarder allowlist is the only thing narrowing what a browser can make the daemon do. (The code's default admission is `OWNER_SESSION_ADMISSION = {principalId: "owner", permissions: OWNER_PERMISSIONS}`, `websocket-server.ts:502`. The probe confirms the relay path gets it.)
- `server_info.features` includes `agentForkContext`, `agentDetach`, `providerSubagents`, `providerSubagentNesting`, `rewind`, `explicitEventSubscriptions`, `selectiveAgentTimeline`, `hubRelationship`, `hubAgentRpc`, `agentRequestReceipts`, `workspaceTerminals`, `workspaceFileEditing`, `providerUsageList`, `agentThinkingUpdate` and `agentConfigApply`. `capabilities.voice` has dictation and voice both enabled.
- Daemon config: `mcp.enabled: true` but **`mcp.injectIntoAgents: false`**. The upstream default is `false` (`server/config.ts:530`). As things stand, **agents on this machine cannot create or hand off to other agents.** The hub state is `not_connected`.
- There are 3 opencode agents, all in `status: "error"` with `attentionReason: "error"`. One agent's `lastError` is the enrollment shim's `invalid_grant` 502, so Cerea's expired-enrollment classifier is matching real data.
- **Usage is real.** Agent `206b23da`'s `lastUsage` is `{inputTokens: 240, cachedInputTokens: 10944, outputTokens: 587, contextWindowMaxTokens: 1048576, contextWindowUsedTokens: 11955}` on `pystino/deepseek-v4-flash-0731`. The other two agents have no `lastUsage`. `listProviderModels("opencode")` returns 10 models and **none of them carry `contextWindowMaxTokens`**, so the maximum comes only from the running agent's usage.
- Timeline entries have the keys `provider, item, timestamp, seqStart, seqEnd, sourceSeqRanges, turnId, collapsed`, and the response carries `epoch`, `startCursor`, `endCursor`, `hasOlder`, `hasNewer`, `gap` and `staleCursor`. Item kinds seen: `user_message`, `assistant_message`, `reasoning`, `tool_call`, `error`. User messages carry `messageId` and `clientMessageId`.
- `listCommands` answers with `compact, summarize, init, review, customize-opencode`.
- Agent capabilities for opencode: `supportsRewindBoth: true` (conversation-only and files-only are false), `supportsMcpServers: true`, `supportsReasoningStream: true`.
- The only feature toggle is `auto_accept`. There are 0 subagents, 0 schedules and 0 terminals, and one workspace of kind `local_checkout`.
- `listProviderUsage` lists subscription quotas for claude, codex, copilot, cursor, zai, grok, kimi and minimax. All are `unavailable`, and nothing in it is relevant to Pystino.

## 2. What Cerea implements today

**Link (`codeDaemon.ts`).** There is one `DaemonClient` per paired device, `clientType: "hub"`, E2EE through the relay. On connect it checks `serverId` against the row and refuses any daemon whose **minor** differs from `0.8`. SDK calls in use: `connect`, `getDaemonStatus`, `fetchWorkspaces`, `createWorkspace` (directory source only), `setWorkspaceTitle`, `archiveWorkspace`, `fetchAgents`, `fetchAgent`, `createAgent` (modeId hardcoded to `build`/`plan`), `updateAgent` (name), `archiveAgent`, `deleteAgent`, `sendAgentMessage` (text only), `cancelAgent`, `setAgentMode`, `setAgentModel`, `setAgentFeature`, `respondToPermission` (allow/deny only), `listAvailableProviders`, `listProviderModes/Models/Features`, `fetchAgentTimeline` (tail 500, no paging), `listProviderSubagents`, `fetchProviderSubagentTimeline`, `getCheckoutDiff` (uncommitted), and `subscribeAgentTimeline` (bridge only).

**Forwarder (`api/v2/code/[...path]`).** 27 allowlisted routes. Each one maps to a single SDK call, validates its body with zod, and answers through `superjsonResponse`. The only authorization is ownership of the device row. Agent and workspace ids are not checked against anything further, which is correct because every agent on a device belongs to its owner.

**Bridge (`agents/[id]/stream`).** It subscribes before fetching, buffers, replays history, then drains the buffer with a content-key seam dedup. It also emits a synthetic turn state from `agent.status`, plus pending permissions from the snapshot. SSE ids are a deterministic replay count, with a 5-minute lifetime and a 15 s heartbeat.

**Mapping (`codeTimeline.ts`).** `user_message → user`, `assistant_message → Stream`, `tool_call → Tool call/result/error`, `todo → Plan`, `error → TurnState failed`. Dropped: `reasoning`, `notification`, `compaction`, `plugin`. Among stream events, `permission_*` becomes an Elicitation and `turn_*` becomes a TurnState. Dropped events: `usage_updated`, `thread_started`, `mode_changed`, `model_changed`, `thinking_option_changed`, `attention_required`, and **`turn_completed.usage`**.

**Fold (`consumeAgentUpdates.ts`).** A `user` frame opens a turn, and everything else folds into that turn's one assistant message. Commits are batched per animation frame (RAF) with a 48 ms timer fallback. The fold de-duplicates tools by uuid and pairs elicitation resolutions across the whole transcript. `adoptRunning` has three rules: a mid-run mount, running after the echo, and running before the echo.

**UI.** `AgentView` renders through `ChatMessageColumn` → `ChatMessage`. `AgentComposer` is `ChatInput` with `mimeTypes={[]}`, so it shows no upload affordance, plus pills for mode, model and feature toggles, and a stop button. `SubagentCard` anchors provider subagents at their Task tool call. `AgentDiff` is a side pane over `getCheckoutDiff`. `CodeNavTree` lists devices → workspaces → agents, with rename and archive.

### 2.1 Latent defects the plan must fix on the way (verified by reading)

1. **Seam dedup by content.** `frameKey` uses `s:${token}` for stream deltas and `u:${text}` for user messages. Two identical deltas (`"\n"`, `"the"`) or two identical prompts (`"continue"`) that straddle the history/live seam collapse into one. The daemon already sends `seq` + `epoch` on `agent_stream` timeline events (`AgentStreamMessageSchema`), and every history entry has `seqStart`/`seqEnd`. The seam should dedup on `(epoch, seq)`.
2. **The minor-version pin will strand users.** Upstream cut a minor roughly every 7–10 days (§8.1), and the daemon self-updates (`daemonSelfUpdate` feature, `updateDaemon`). The day a user's daemon moves to 0.9, every call 502s with "unsupported API version". The 0.9 protocol still accepts every message type Cerea sends (checked for 12 of them, §7).
3. **The internal import path.** Cerea imports `@getpaseo/client/internal/daemon-client`, an export named "internal" (paseo's own app uses it too). 0.9.1 still exports it, but it carries no stability promise.
4. **History is capped at 500 with no paging.** `hasOlder`/`startCursor` are ignored, so a long session silently loses its head.
5. **The mode is hardcoded to opencode.** `createAgent` maps `write → "build"` and `plan → "plan"`. Those are opencode's mode ids. Claude and codex modes differ.

## 3. API surface inventory (SDK 0.8.0)

`DaemonClient` has about 200 public methods (`daemon-client.d.ts:577-1195`), and the protocol defines about 220 outbound message schemas. The rows below group them by domain. **Gate** names the `server_info.features` flag or client capability each row depends on. Every flag listed is `true` on the live daemon. "✓" in *Cerea* means it is used today.

**Verdict key:** **A** = adopt (in a milestone below) · **L** = adopt later / worth it but not now · **N** = not worth it · **?** = unclear, needs a decision or a spike.

### 3.1 Connection, identity, capabilities

| Method / event | Purpose | Payload (key fields) | Gate | Cerea | Verdict |
| --- | --- | --- | --- | --- | --- |
| `connect`, `close`, `subscribeConnectionStatus`, `getConnectionState` | session lifecycle | `hello{clientId, clientType, protocolVersion:1, capabilities}` | — | ✓ (no status listener) | A: add the status listener so the pool can mark a link down instead of waiting for a call to fail |
| `getDaemonStatus` | identity and version | `serverId, version, pid, listen, relay{…}, providers[]` | `daemonStatusRpc` | ✓ | A: keep the serverId check, replace the minor pin with a floor and feature gating (§7) |
| `getLastServerInfoMessage` | server_info push: `permissions[]`, `features{…}`, `capabilities.voice` | see §1.1 | — | — | **A**: cache it per link, gate every feature on it, and expose a sanitized feature set to the browser |
| `DEFAULT_CLIENT_CAPABILITIES` (sent in hello) | `all_providers, selective_agent_timeline, reasoning_merge_enum, custom_mode_icons, terminal_reflowable_snapshot, provider_subagents, project_updates, compact_provider_snapshots, provider_snapshot_references, timeline_replacement_invalidation, timeline_notifications, plugin_timeline_items` | — | implicit | A: keep the defaults, and add `explicit_event_subscriptions` once Cerea subscribes explicitly (legacy broadcasts are slated for removal after 2027-03-08, `session.ts:7781`) |
| `ping`, `measureLatency`, `getLastLivenessRttMs`, `sendHeartbeat` | liveness / presence | — | — | — | N (the SDK already runs its own liveness heartbeat) |
| `registerPushToken`, `unregisterPushToken` | mobile push | Expo token | `pushTokenRevocation` | — | N: Cerea would notify through its own channel |
| `getDaemonConfig`, `patchDaemonConfig`, `reloadDaemonConfig` | daemon config (mcp, relay, providers, plugins…) | `MutableDaemonConfigPatch` | `daemonConfigReload` | — | **A (narrow)**: read-only `getDaemonConfig` for a "machine settings" view. One write, `mcp.injectIntoAgents`, is needed for handoffs (§4.2). Nothing else |
| `restartServer`, `shutdownServer`, `updateDaemon`, `collectDiagnostics` | machine admin | — | `daemonSelfUpdate`, `daemonDiagnostics` | — | N: the panel drives agents, not machines (ADR 0085 stance) |
| `getDaemonPairingOffer` | produces an offer (needs `access.manage`) | offer URL | — | — | N: pairing stays brokered by Cerea |
| `connectHub`, `getHubStatus`, `updateHubPermissions`, `disconnectHub` | the daemon's outbound **Hub relationship** | `hubOrigin, token, permissions[]` → `{state, daemonId, permissions}` | `hubRelationship`, `hubAgentRpc` | — | **?**: this is the stock way to get a *scoped* principal and drop the relay. See §8.3 |

### 3.2 Agents

| Method / event | Purpose | Payload | opencode | Cerea | Verdict |
| --- | --- | --- | --- | --- | --- |
| `fetchAgents(filter/sort/page)` | agent directory | `entries[{agent: AgentSnapshot, project}]`, `pageInfo`, directory-sync metadata | ✓ | ✓ (unpaged, client-side filter) | A: filter by label and workspace server-side, page when > 200 |
| `fetchAgent` | one snapshot | `AgentSnapshot`: `status, activeTurn, capabilities, currentModeId, availableModes, pendingPermissions, runtimeInfo, lastUsage, lastError, labels, requiresAttention, attentionReason, features, thinkingOptionId` | ✓ | ✓ | A: also read `lastUsage`, `labels`, `requiresAttention`, `activeTurn`, `capabilities` |
| `createAgent` | new agent | `config{provider,cwd,modeId,model,thinkingOptionId,featureValues,systemPrompt,mcpServers,toolPolicy}`, `workspaceId`, `initialPrompt`, **`images`, `attachments`**, `worktree`, `labels`, `idempotencyKey`, `clientMessageId`, `outputSchema`, `autoArchive`, `env` | ✓ | ✓ (provider, cwd, mode, title, workspaceId) | A: use `initialPrompt` + attachments (the fork handoff), `idempotencyKey` (retry-safe), and live mode ids |
| `sendAgentMessage` | a prompt | `text`, **`messageId`**, **`activeTurnBehavior: "interrupt"\|"steer"`**, **`images[{data base64, mimeType}]`**, **`attachments[]`** (§4.4–4.5) | ✓ (images become data-URL file parts; `steerActiveTurn` implemented) | ✓ (text only) | **A**: images, attachments, a stable `messageId`, and steer |
| `cancelAgent`, `archiveAgent`, `deleteAgent`, `updateAgent{name,labels}` | lifecycle | — | ✓ | ✓ | keep. Archive cascades to MCP-created children (`agent-manager.ts:1728`) |
| `detachAgent` | cut a delegated child loose (drops `paseo.parent-agent-id`) | agentId | ✓ | — | **A** (with handoffs) |
| `refreshAgent`, `resumeAgent`, `importAgent`, `fetchRecentProviderSessions` | reload or import a provider session | persistence handle | ✓ (session listing) | — | L: "import an opencode session started in the terminal" is a nice-to-have |
| `fetchAgentHistory` | archived agents, searchable | `entries`, `pageInfo` | ✓ | — | L: an archive browser |
| `setAgentMode`, `setAgentModel`, `setAgentFeature` | live config | notice / void | ✓ | ✓ | keep |
| `setAgentThinkingOption` | reasoning effort | `thinkingOptionId` | ✓ (per model; muse-spark models list `default…xhigh`) | — | **A**: a small pill beside the model pill |
| `applyAgentConfig` | atomic multi-field config | `AgentConfigApply` | ✓ | — | L (only matters once several pills can change at once) |
| `respondToPermission` | answer a prompt | `{behavior, selectedActionId?, updatedInput?, message?, interrupt?}` | ✓ | ✓ (allow/deny only) | A: honour the request's `actions[]` and `kind: "question"` (plan-exit and question kinds carry their own actions) |
| `waitForFinish`, `waitForAgentUpsert`, `respondToPermissionAndWait` | CLI helpers | — | — | — | N |
| `rewindAgent(messageId, mode)` | roll back the conversation and/or files | `mode: conversation\|files\|both` | **`both` only** | — | ? (§5): valuable but destructive on the user's disk |
| `buildAgentForkContext` | "chat history" text attachment up to a boundary | → `{attachment: {type:"text", contextKind:"chat_history"}, itemCount, boundaryCursor, boundaryMessageId}` | provider-agnostic | — | **A** (the handoff, §4.2) |
| `listCommands` | provider slash commands | `commands[{name, description…}]` | ✓ (`compact, summarize, init, review, customize-opencode`) | — | **A**: slash autocomplete. Commands run by sending `/name` as text (`opencode-agent.ts:4938`) |
| `appendAgentTimelineItem` | plugin-authored timeline rows | `PluginTimelineItem` | — | — | N |
| `listAgentTimelinePrompts` | index of user prompts (jump to prompt) | — | ✓ `agentTimelinePromptIndex` | — | L |
| `clearAgentAttention`, `clearWorkspaceAttention`, `markWorkspaceUnread` | attention bookkeeping | agentId(s) | — | — | **A** (multi-agent, §4.1) |

### 3.3 Timeline and streams (pushed)

| Event / call | Carries | Cerea today | Verdict |
| --- | --- | --- | --- |
| `fetchAgentTimeline(direction, cursor, limit, projection)` | `entries[{item, seqStart, seqEnd, turnId, timestamp, collapsed}]`, `epoch`, `startCursor/endCursor`, `hasOlder/hasNewer`, `gap`, `reset`, `staleCursor` | tail 500, drops the cursors | A: seq-keyed seam, "load older" paging |
| `subscribeAgentTimeline` → `agent_stream{agentId, event, timestamp, seq?, epoch?}` | every `AgentStreamEvent` | ✓ | A: keep, and read `seq`/`epoch` |
| event `timeline{item}` | user/assistant/reasoning/tool/todo/error/notification/**compaction**/plugin | partly mapped | A: add `compaction` (§4.3) and `notification` (level + message) |
| event `turn_started / turn_completed{usage} / turn_failed{error, code, diagnostic} / turn_canceled` | turn lifecycle, **usage at end of turn** | mapped, usage dropped | A: forward usage |
| event **`usage_updated{usage}`** | `AgentUsage{inputTokens, cachedInputTokens, outputTokens, totalCostUsd, contextWindowMaxTokens, contextWindowUsedTokens}` | dropped | **A** (§4.3) |
| event `mode_changed / model_changed / thinking_option_changed` | live config echo | dropped | A: the pills reconcile from these instead of re-reading the snapshot |
| event `attention_required{reason}` and `agent_attention_required` (session-level) | finished / error / permission | dropped | **A** (§4.1) |
| event `permission_requested / permission_resolved` | `AgentPermissionRequest{kind, title, detail, actions[]…}` | ✓ | keep, widen `actions` |
| `agent_update{kind: upsert\|remove, agent, seq}` (session-wide) | every agent snapshot change: status, **lastUsage**, title, labels, attention | — | **A**: a device-level event bridge (§4.1) |
| `agent_timeline_replacement` | the timeline was rewritten (rewind/compaction reprojection) | — | A: treat as "refetch history". Needs cap `timeline_replacement_invalidation`, already sent |
| `workspace_update`, `project.update`, `script_status_update`, `workspace_setup_progress` | workspace directory pushes | — | L (tree liveness) |
| `providers_snapshot_update`, `getProvidersSnapshot`, `refreshProvidersSnapshot` | cached provider catalog (models with thinking options, modes) | — | L: cheaper than three list calls per pill |
| `listProviderSubagents`, `fetchProviderSubagentTimeline`, `agent.provider_subagents.update` | provider Task subagents | ✓ (polled on turn boundaries) | A: consume the update push instead of polling |

### 3.4 Workspaces, projects, worktrees, scripts

| Method | Purpose | Cerea | Verdict |
| --- | --- | --- | --- |
| `fetchWorkspaces`, `createWorkspace{source}`, `setWorkspaceTitle`, `archiveWorkspace`, `setWorkspacePinned` | directory | ✓ (not pinning) | keep; pinning is L |
| `listProjects`, `openProject`, `addProject`, `renameProject`, `setProjectIcon`, `removeProject`, `createProjectDirectory`, `cloneGithubProject`, `searchGithubRepositories` | project registry, clone | — | N / L (clone: L) |
| `createPaseoWorktree`, `getPaseoWorktreeList`, `archivePaseoWorktree`, `createAgent{worktree}` | isolated git worktrees per agent | — | **L**: the right isolation for parallel agents and handoffs "in a worktree" |
| `listWorkspaceScripts`, `startWorkspaceScript`, `stopWorkspaceScript`, `fetchWorkspaceSetupStatus`, `runWorkspaceSetup` | `paseo.json` scripts (dev servers, setup) | — | ? (only useful with terminals or a preview URL) |
| `listWorkspaceLabels`, `setWorkspaceLabel…` | labels on workspaces | — | N |
| `inspectWorkspaceRecovery`, `restoreWorkspace` | unarchive | — | L |
| `getDirectorySuggestions` | path autocomplete for "new workspace" | — | **A** (cheap win for the Workspace dialog, which asks for an absolute path by hand today) |

### 3.5 Git / checkout

| Method | Cerea | Verdict |
| --- | --- | --- |
| `getCheckoutDiff(cwd, {mode})` | ✓ uncommitted | keep; add `mode: "base"` (branch vs base) |
| `subscribeCheckoutDiff` / `checkout_diff_update` | — | A: the diff pane updates live instead of on open. **Renamed `observeCheckoutDiff` in 0.9**, so put it behind the link |
| `getCheckoutStatus`, `checkoutRefresh`, `listCheckoutCommits`, `getCommitFileDiff`, `stashList` | — | L (read-only branch/commit context in the diff pane) |
| `checkoutCommit`, `checkoutPush`, `checkoutPull`, `checkoutMerge*`, `checkoutSwitchBranch`, `renameBranch`, `stashSave/Pop`, `checkoutDiscardChanges` | — | ? (commit/push from a browser is powerful and irreversible; revisit after worktrees) |
| `checkoutPrCreate`, `checkoutPrMerge`, `checkoutPrStatus`, `pullRequestTimeline`, forge auto-merge / check details, `searchForge/GitHub`, `validateBranch`, `getBranchSuggestions` | — | N for now (needs `gh`/forge auth on the machine; Cerea is not a forge UI) |

### 3.6 Files

| Method | Purpose | Cerea | Verdict |
| --- | --- | --- | --- |
| **`uploadFile{fileName, mimeType, bytes, chunkSize=1 MiB}`** → `{file: {type:"uploaded_file", id, fileName, mimeType, size, path}}` | binary-framed upload into `$PASEO_HOME/uploads/<id>/<name>` | — | **A** (§4.5) |
| `listDirectory`, `readFile(maxBytes)`, `subscribeFile` | file explorer / preview | — | **L** (read-only explorer; "attach a workspace file") |
| `writeFile`, `createFileEntry`, `renameFileEntry`, `duplicateFileEntry`, `deleteFileEntry` | editing | — | N (agents edit; people review) |
| `requestDownloadToken` | a token for a direct HTTP download from the daemon | — | N: the daemon's HTTP is local-only. Stream bytes through `readFile` instead |
| `requestProjectIcon`, `getProjectIcon` | icons | — | N |

### 3.7 Providers

| Method | opencode (live) | Cerea | Verdict |
| --- | --- | --- | --- |
| `listAvailableProviders` | only `opencode` available | ✓ | keep |
| `listProviderModes` | `build`, `plan` (with `icon`, `colorTier`) | ✓ | keep |
| `listProviderModels` | 10 models, **no `contextWindowMaxTokens`**, thinking options on some | ✓ | keep; add the thinking pill |
| `listProviderFeatures` | `auto_accept` toggle | ✓ toggles only | keep (the select type is dropped on purpose) |
| `getProviderDiagnostic` | health text | — | L (the "why can't I pick opencode" explainer) |
| `listProviderUsage` | subscription quotas for claude/codex/…; nothing for Pystino | — | N: Pystino spend belongs to Cerea's own `UsageBar` |

### 3.8 Terminals

`listTerminals`, `createTerminal`, `renameTerminal`, `subscribeTerminal` (binary stream frames), `sendTerminalInput`, `killTerminal`, `captureTerminal`, `subscribeTerminals`, `closeItems`, `onTerminalStreamEvent`, and `terminal_attention_required`. The gate is `workspaceTerminals`, and nothing uses them in Cerea. **Verdict: ?** (§5).

### 3.9 Automation

`scheduleCreate/List/Inspect/Logs/Pause/Resume/Delete/RunOnce/Update` (cron cadence; target `self` / `agent` / `new-agent`). Heartbeats are MCP-only (`create_heartbeat`). Loops use `loop/*` (the MCP and CLI). **Verdict: L** (§5).

### 3.10 Voice, plugins, skills, chat rooms, browser

| Group | Methods | Verdict |
| --- | --- | --- |
| Dictation / voice | `startDictationStream`, `sendDictationStreamChunk`, `finishDictationStream`, `cancelDictationStream`, `setVoiceMode`, `sendVoiceAudioChunk`, `audioPlayed`, `abortRequest` | N: Cerea has its own speech-to-text path, and dictation belongs in the browser, not on the user's laptop via a relay [chat-side STT not re-verified here] |
| Plugins | `getPluginCatalog`, `listPlugins`, `install*`, `enable/disable/remove/reloadPlugin`, `getPluginLogs`, `invokePluginRpc`, `updatePluginSources` | N for the UI. **?** as an *extension point* (§8: a plugin could replace a fork patch) |
| Agent skills | `getAgentSkillsStatus`, `reconcile/uninstall/saveAgentSkillsSelection` | N (installs paseo's skills into provider configs) |
| Chat rooms | `chat/create/list/inspect/post/read/wait/delete` (agent-to-agent message boards) | L: this is how orchestrated agents coordinate. Surfacing it read-only could come after handoffs |
| Browser automation | `browser.automation.execute.*`, `browser_host` cap | N |
| Project config | `readProjectConfig`, `writeProjectConfig` (`paseo.json`) | N |

## 4. Target features

Conventions for every design below:

- **Forwarder:** each new route is a row in `RULES` plus one zod schema, mapped to one link method, answered through `superjsonResponse`. The link methods stay in `codeDaemon.ts`, and the browser never names the daemon's wire shapes (ADR 0085).
- **Ownership:** it is what `linkForDevice` already does, the row checked against `locals` before anything dials. The daemon side is an owner principal (§1.1), so **every new route is a new power over the user's machine** and needs its own justification in the allowlist comment.
- **Fold discipline:** `consumeAgentUpdates` keeps its invariants: the `user` frame opens a turn, one assistant message per turn, RAF/48 ms commits, `adoptRunning`'s three rules, and pairing across the whole transcript. New frames are **side-channel** frames: a `case` that never touches `current`, `buffer` or `updatesBuffer`, never calls `openAssistant`/`closeTurn`/`flushBuffer`, and never fires `ctx.onTurnEvent`. That keeps the hard-won turn structure out of blast range. Where a feature *must* touch the transcript, it is called out.

### 4.1 Agents and multi-agent views

**What paseo does.** Workspaces open as tabs, and on desktop they split into panes (`supportsDesktopPaneSplits`). Above the composer, an *agent track* row (`panels/agent-tracks.tsx`) shows three things: the workspace diff-stat pill, a **subagents track**, and the task list. The subagents track merges two kinds of child: **paseo-managed children** (full agents labelled `paseo.parent-agent-id`) and **provider subagents** (opencode/claude Task spawns). Rows open beside the parent. Managed children can be **detached**, which is gated on `agentDetach`, and finished children can be archived in bulk. The sidebar is kept live by `agent_update` upserts, which carry status, title, `lastUsage` and attention. `agent_attention_required` (finished/error/permission) drives unread badges and push notifications.

**SDK calls and events.**

| Call or event | Details |
| --- | --- |
| `agent_update{kind:"upsert"\|"remove", agent, seq}` | Arrives via `client.on("agent_update")` or `subscribe()`. Today it is a legacy broadcast to every session; the explicit `session.events.set_subscription` path does not cover it yet in 0.8 |
| `onAgentAttentionRequired(handler)` | → `{agentId, reason, timestamp, shouldNotify, notification?}` |
| `clearAgentAttention(agentId)` | |
| `fetchAgents({filter, sort, page})` | |
| `detachAgent(agentId)` | |
| `archiveAgent` | cascades to non-detached children |
| labels via `getParentAgentIdFromLabels` | `@getpaseo/protocol/agent-labels` |

**Cerea design.**

- **Device event bridge.** A new SSE endpoint, `GET /api/v2/code/devices/[id]/events`. The link holds **one** daemon listener per device and fans out to N browser connections through a tiny in-process broadcaster, never one daemon listener per tab. Frames:
  - `{type:"snapshot", agents}`, first (from `fetchAgents`);
  - `{type:"agent", agent: CodeAgentSession}`, per upsert;
  - `{type:"agent_removed", agentId}`;
  - `{type:"attention", agentId, reason}`.

  There is no history replay: the snapshot frame *is* the resync, and `Last-Event-ID` is ignored. It keeps the same 5-minute lifetime and heartbeat as the timeline bridge.
- **`toSession`** gains `parentAgentId` (from the label), `requiresAttention`, `attentionReason` and `usage`.
- **CodeNavTree.** Status dots update from events, not from refetches. An unread badge appears on `requiresAttention`. Children labelled `paseo.parent-agent-id` nest under their parent as a collapsible "N subagents" group, which matches paseo's track and stops handoff children cluttering the workspace level. Opening an agent posts `v1/agents/:id/attention/clear`.
- **Browser notification.** Optionally, when the tab is hidden and `reason ∈ {permission, finished}`, show a Notification ("agent X needs you"). Cerea is the notification channel; paseo's push tokens are not.
- **Side-by-side.** `/code/<device>/<agent>?beside=<agentId>` renders a second `AgentView` on wide screens. The component is self-contained (its own EventSource, fold and column), so this is layout only. The `SubagentCard` "open" action for a managed child targets `beside`.
- **Forwarder routes:** `POST v1/agents/:id/attention/clear`, `POST v1/agents/:id/detach` and, for 4.2, `GET v1/agents?parent=:id`.
- **Fold:** no change. The tree is not the transcript.

**Security.** Device events are owner-only via `linkForDevice`. `notification` text can contain the agent's last message, which is fine for the owner, but keep it out of logs. Each browser tab holds at most 1 device stream plus 1–2 agent streams (HTTP/1.1 allows 6 connections per origin; the deployment is behind Caddy with HTTP/2 **[unverified]**).

**Open questions and risks.**
- 0.9 replaces `setAgentTimelineSubscription` with `observe*` APIs, and the legacy broadcast is due to end after 2027-03-08 (`session.ts:7781`). Put the listener behind a link method so the swap is local.
- Provider subagents (Task) and managed children look alike in the UI but have different lifecycles: provider subagents are read-only transcripts, while managed children are full agents. Keep them distinct in the types (`CodeSubagent` vs a `CodeAgentSession` with a `parentAgentId`), as paseo does (`SubagentRow.kind`).

**Effort:** about 4 days (1.5 bridge and broadcaster, 1.5 tree and badges, 1 side-by-side and specs).

### 4.2 Handoffs

Paseo has **two** handoff mechanisms, and neither is called "handoff" on the wire.

**(a) User-initiated fork.** This is the app's "Fork" in a turn footer, with the targets "tab" and "workspace" (`hooks/use-fork-agent.ts`, `components/assistant-fork-menu.tsx`).
1. `buildAgentForkContext(agentId, {boundaryMessageId | boundaryCursor})` curates the source timeline up to that boundary: user messages, assistant messages and tool calls, excluding external tool input (`activity-curator.ts:294`). The result is a `{type:"text", mimeType:"text/plain", contextKind:"chat_history", title:"Chat history", text:"<chat-history-summary>…"}` attachment.
2. The app opens a **draft** seeded with the source's provider, cwd, mode, model, thinking option and feature values. The person can change any of them, **including the provider and model**, so a fork is also the cross-model handoff.
3. On submit, `createAgent({config, workspaceId, initialPrompt, attachments:[chatHistory]})` runs. The daemon's `buildAgentPrompt` puts `chat_history` attachments *before* the prompt text (`prompt-attachments.ts:19-31`), and opencode renders non-image attachments as text parts. No lineage label is set, so a fork is independent. (The seeding is verified; the draft→create path's labels are **[unverified]**.)

**(b) Agent-initiated handoff and delegation.**
1. When `mcp.injectIntoAgents` is true, the daemon injects an HTTP MCP server named `paseo` into every agent: `…/mcp/agents?callerAgentId=<id>`, authenticated by a capability token (`runtime-mcp-config.ts`).
2. Its tools cover `create_agent`, `send_agent_prompt`, `get_agent_status`, `list_agents`, `cancel/archive/kill_agent`, `update_agent`, workspaces, terminals, schedules and heartbeats (`tools/paseo-tools.ts:1166-2740`). `create_agent` from inside an agent is *agent-scoped*: it defaults to the caller's workspace, runs in the background, can notify on finish, and labels the child `paseo.parent-agent-id=<caller>`.
3. The `paseo-handoff` skill is just a prompt recipe over that tool: build a zero-context briefing, then `create_agent` with the title `[Handoff] <task>`. The child stays in the parent's subagent track until the **user** detaches it. Archiving the parent cascades to attached children.
4. **Upstream default is `injectIntoAgents: false`, and the live daemon has it off.**

**SDK calls:** `buildAgentForkContext` (gate `agentForkContext`, `agentForkContextCursor`), `createAgent{initialPrompt, attachments, idempotencyKey}`, `sendAgentMessage{messageId}` (gate `agentRequestReceipts`), `getDaemonConfig` / `patchDaemonConfig({mcp:{injectIntoAgents}})` (`daemon.manage`), `detachAgent` (`agentDetach`), `fetchAgents` with a label filter.

**Cerea design.**

*Fork handoff (stock, provider-agnostic):*
- **UI.** A "Hand off…" action on each completed assistant message. It goes in `ChatMessage`'s footer actions slot, which `AgentView` fills, so chat is untouched. It opens the existing `AgentDialog` in *handoff mode*:
  - prefilled with the source's device, workspace, provider, model and mode, each changeable;
  - a "Carry the conversation up to here" checkbox (default on);
  - a prompt box;
  - an optional target of **another paired device**. That is a Cerea-only capability: build the context on A, create on B. It's safe because both rows are the caller's.
- **Route:** `POST v1/agents/:id/handoff`, body `{prompt, provider, model?, modeId?, workspaceId?, targetDevice?, boundaryMessageId?, nonce}`.
- **Link:** `forkContext = buildAgentForkContext(id, {boundaryMessageId})`, then use hub.md's retry-safe pair:
  1. `createAgent({..., idempotencyKey: hash(user, nonce), labels: {"cerea.handoff-from": id}})` with **no** `initialPrompt`;
  2. `sendAgentMessage(child, prompt, {messageId: nonce, attachments: [forkContext.attachment]})`.

  `cerea.*` labels are ours; paseo only interprets `paseo.*`. The new agent's header then reads "Handed off from ‹title›", looked up by the label.
- **Fold:** no change. The child's transcript starts with a user message whose text is the prompt. Opencode may render the attachment's text into the echoed user message **[unverified; see the M3 spike]**. If it does, the bridge collapses the `<chat-history-summary>` block into a single "Conversation carried over (N items)" chip rather than dumping it into the bubble.

*Agent-initiated handoff:*
- **Machine settings panel** (new, per device): it reads `getDaemonConfig`, shows "Let agents start and hand off to other agents (paseo MCP): on/off", and toggles it with `patchDaemonConfig`. This is the one daemon-config write the panel would make, so it gets an explicit confirmation. Agents created before the change do not gain the MCP server until they restart **[unverified: injection happens at config build time in `withRuntimePaseoMcpServer`]**.
- **Transcript.** The parent's `create_agent` tool call is claimed by the existing `subagentFor(toolCall)` mechanism in `AgentView`: match on tool name `create_agent` from the `paseo` server, exact naming **[unverified; spike]**. It renders as a **Handoff card**, which is `SubagentCard` with a managed-agent variant: title, live status from the device bridge, open-beside, and detach. **Mapping change:** `codeTimeline.toolOutput` currently returns nothing for `detail.type: "unknown"`. It must surface MCP result text (or structured `agentId`) so the card can bind.
- **Tree.** Children nest under the parent (4.1).

**Security.**
- Fork context is the whole curated transcript as text. It already passes through Cerea (the server sees every frame), so no new exposure. Cap it (for example 200k characters) and tell the user when it is truncated. `maxItems: 0` means unlimited upstream.
- Turning on `injectIntoAgents` lets any agent on that machine spawn agents daemon-wide. That is the user's machine and the user's call, but the toggle's copy must say so.
- Cross-device handoff moves conversation text from machine A to machine B, both the caller's.

**Provider differences.** Fork context is provider-neutral text. MCP injection needs `capabilities.supportsMcpServers` (opencode: true). The handoff skill's availability inside opencode depends on `agent.skills` reconciliation into the provider's config (`getAgentSkillsStatus`), which is **[unverified for opencode]**. Without the skill, an agent can still call `create_agent` when asked.

**Effort:** fork handoff about 3 days; agent-initiated about 3 days plus a 1-day spike on a disposable machine (never the user's).

### 4.3 Context length and usage reporting

**What paseo does.** `components/context-window-meter.tsx` draws a ring in the composer. It is grey below 70%, amber from 70% and red above 90%. Its tooltip shows used/max tokens, the session cost (`totalCostUsd`) and a provider-usage section. The ring shows a loading state while the agent is initializing or running. The data is `agent.lastUsage` from the snapshot, kept fresh by `agent_update` (`composer/index.tsx:263`). Compaction renders as a divider in the transcript with a label from `message-compaction-label` (status loading/completed, trigger auto/manual).

**Where the numbers come from (opencode, `opencode-agent.ts:925-960`).**
- On every step-finish part, `contextWindowUsedTokens` = input + output + reasoning + cache read + cache write *of that step*. That approximates current occupancy.
- `inputTokens`, `cachedInputTokens` and `outputTokens` are that step's values.
- `totalCostUsd` accumulates opencode's configured pricing.
- `contextWindowMaxTokens` is resolved from the model catalog when the assistant message's model is known.
- The stream carries `usage_updated`, and `turn_completed{usage}` carries the final value. Live data: 11,955 / 1,048,576 for a Pystino model (§1.1). Model listings carry no maximum.

**Cerea design.**
- **Types.** Add `AgentUsageUpdate {type:"usage", usage:{used?, max?, input?, cachedInput?, output?}}` and `AgentCompactionUpdate {type:"compaction", status, trigger?, preTokens?}` to `AgentStreamUpdate` and `AGENT_STREAM_UPDATE_TYPES`. The shapes are Cerea-owned: map the daemon's names at `codeTimeline.ts` so an upstream rename is a one-line fix.
- **Mapping.** `streamEventToUpdate` maps `usage_updated` and `turn_completed.usage` to a `usage` frame; `turn_completed` still also emits TurnState done. `timelineEntryToUpdate` maps `compaction` to a `compaction` frame.
- **Bridge.** Append one `usage` frame from `agent.lastUsage` to `initial` after history. `frameKey` returns null for both kinds, because they re-converge (last write wins) and are never deduped.
- **Fold.** Two side-channel cases:
  - `case "usage": ctx.onUsage?.(update.usage); break;`
  - `case "compaction": ctx.onCompaction?.(update); break;`

  These are the only fold changes. They obey the discipline above; in particular they don't count as turn events, so the pending placeholder is unaffected. A replay of history re-delivers compaction markers in order, which is correct.
- **Snapshot route.** `GET v1/agents/:id` adds `usage` for first paint, before the SSE arrives.
- **UI.** A new `ContextMeter.svelte` ring sits in `AgentComposer`'s pill row, right-aligned inside the prompt box as in paseo. It shows a percentage when `max` is known and a token count otherwise, never a made-up maximum. Its popover shows used/max, input/cached/output, and the last compaction ("compacted automatically, was 180k"). Above 70% the popover also offers a **"Compact now"** button, which sends `/compact`: slash commands are ordinary messages (`opencode-agent.ts:4938`) and `compact` is in the live `listCommands` answer. The ring is pending while the turn state is running.
- **Cost.** Hide `totalCostUsd` for now. For Pystino models it is opencode's configured estimate, not the ledger; the authoritative spend is Pystino's, shown in Cerea's `UsageBar`. Showing both would present two different numbers for the same spend.
- **Compaction in the transcript** (divider or chip): deferred. Chat has no divider update type, and adding one touches `ChatMessage`. The meter's popover carries it first.

**Provider differences.** Claude and codex also fill `AgentUsage`; field completeness varies (`contextWindowMaxTokens` may be absent) **[unverified beyond opencode]**. The UI already degrades to "tokens only".

**Effort:** about 2 days, most of it the component and specs.

### 4.4 Images

**What paseo does.**
- **Composer.** Paste, drop and pick images. They are persisted in a local attachment store with GC retention.
- **Send.** `encodeImages` produces base64 `images[{data, mimeType}]` on `send_agent_message`, alongside `attachments`. The only client cap seen is the 50 MB file cap (`composer/index.tsx:983`); image-specific downscaling is **[unverified]**.
- **Daemon.** `buildAgentPrompt` produces image content blocks.
- **opencode.** Images become `file` parts with a `data:` URL and the name `attachment-N.<ext>` (`opencode-agent.ts:1000-1022`). The canonical user timeline text is `"…\n[Image]"` (`buildOpenCodeUserTimelineText`). Paseo's app shows the actual image from its **local optimistic message**, matched by `clientMessageId` (`canonicalSubmittedPrompts`). The daemon never stores or serves the image back.

**Transport.** Images ride inline in the JSON frame, E2EE through the relay. The pinned relay's limits are generous: a 512 MiB weighted ingress budget at ×4 per byte, and a per-socket heap fuse of about 256 MiB (`paseo-relay/README.md`). The binding limit is **Cerea's own `BODY_SIZE_LIMIT` = 15 MiB** (`Dockerfile:48`).

**Cerea design (reuse, not rebuild).**
- **Extract, don't duplicate.** `ChatInput` already owns the picker and `bind:files`. `ChatWindow` owns paste filtering (`onPaste`, `mimeMatchesAllowlist`), `FileDropzone` and the `UploadedFile` chips. Lift those three into a shared piece: a `ComposerAttachments.svelte` wrapper plus a `composerFiles.ts` helper. `ChatWindow` and `AgentComposer` both use it. This is a pure refactor of chat code under chat's existing tests. After it, `AgentComposer` passes `bind:files`, `mimeTypes`, `onPaste` and the dropzone, exactly as chat does.
- **Which types to offer.** Offer `IMAGE_MIME_ALLOWLIST_DEFAULT` (jpeg/png; add webp/gif, which opencode supports) **only when the agent's model is known multimodal**. Cerea's model registry already knows this for Pystino models (`multimodal`, `multimodalAcceptedMimetypes`), and agent models are named `pystino/<id>`, so map by id. For non-Pystino models (opencode's free catalog), keep the picker off and explain why in a tooltip; opencode would otherwise forward a data URL to a text-only model.
- **Route.** `POST v1/agents/:id/messages` also accepts `multipart/form-data` (`text`, `images[]`, `messageId`); the JSON path stays for text. The server:
  - sniffs the mime with `file-type`, as `uploadFile.ts` does;
  - enforces **≤ 8 images, ≤ 5 MiB each, ≤ 12 MiB total** (under 15 MiB);
  - base64-encodes;
  - calls `sendAgentMessage(id, text, {messageId, images})`.
- **Showing the image after the echo.** The daemon's echo is text-only (`[Image]`). Two options (decision in §9):
  1. **Attachment ledger (recommended).** Store each sent image in Cerea's existing GridFS files store, keyed `code:<deviceId>:<agentId>:<messageId>` with owner metadata. `messageId` is ours, and the daemon echoes it back as the user item's `clientMessageId` (seen live). The bridge attaches `files: MessageFile[]` (`type:"hash"`) to the `user` frame and strips the `[Image]` placeholders. **Fold change:** `case "user"` copies `update.files` onto the pushed user message. `ChatMessage` already renders user files, and nothing else in the fold moves. The bytes are served by an owner-checked GET, mirroring chat's conversation-file route. This is a narrow, deliberate exception to "no second agent store": it holds bytes the person sent, not agent state.
  2. **No ledger.** Keep showing `[Image]` text. The image is visible only in the tab that sent it, and only if the composer inserts an optimistic bubble, which the composer deliberately doesn't do.
- **Seam dedup.** Two "[Image]" prompts with the same text dedupe under today's `u:${text}` key. M0's seq-keyed seam fixes that first.

**Security.** Caps and mime sniffing apply before anything dials. Images cross the relay E2EE. Cerea sees them in plaintext, as it does all text. Ledger entries carry `userId`/`sessionId` and are deleted when the device is revoked, which extends `revokeDevice`. Stripping EXIF metadata is **L**.

**Provider differences.**
- opencode passes images to the model as file parts. Whether they reach the model depends on the opencode model config declaring image input, and on Pystino accepting image content for that model. **[unverified; M2 spike on a multimodal Pystino model.]**
- Claude and codex take native image blocks **[unverified in code]**.
- The echo text differs by provider.

**Effort:** about 3 days, plus about 1.5 for the ledger.

### 4.5 File uploads

**What paseo does.**
1. **Upload.** `uploadFile({fileName, mimeType, bytes})` sends `file.upload.request`, then binary `FileBegin` / `FileChunk` (1 MiB) / `FileEnd` frames (`daemon-client.js:3088`). Permission: `workspace.write`.
2. **Storage.** The daemon writes `$PASEO_HOME/uploads/<requestId-attempt>/<sanitized name>` and checks the declared size (`file-upload/index.ts`). There is **no server-side size cap**; the app caps at 50 MB. Pending uploads expire after 10 minutes idle. **Completed uploads are never deleted**: removal exists only on failure or expiry.
3. **Reply.** `{file: {type:"uploaded_file", id, fileName, mimeType, size, path}}`.
4. **Send.** `sendAgentMessage(..., {attachments:[uploaded_file]})`. The prompt gets a text block `Uploaded file: <name>\nPath: <abs path>\nMIME: …\nSize: …`, and **the agent reads the file with its own tools**; nothing is inlined.

Other attachment kinds on the same `attachments[]` wire are `text` (with `contextKind:"chat_history"` for forks), `review` (diff line comments with context), `forge_issue` and `forge_change_request` (plus legacy GitHub kinds).

**Cerea design.**
- **Route `POST v1/agents/:id/uploads`** (multipart, one file per request). It sniffs the mime, caps at **10 MiB** while `BODY_SIZE_LIMIT` is 15 MiB, and calls `link.uploadFile`. It answers `{upload: {id, fileName, mimeType, size}}`. The **path is kept server-side** in a short-lived map `(owner, device, uploadId) → descriptor`, with a 30-minute TTL, in memory or in Mongo if the server is replicated. The send route then takes only `uploadIds[]` and resolves the descriptors itself. The browser never gets to put an arbitrary `path` into a prompt, which keeps the forwarder "one typed op per route" honest even though the caller owns the machine.
- **Documents.** Chat already runs PDFs, DOCX and the like through the gateway extractor (`extractDocument`). For agents, send **both**: the raw upload (so the agent can process the file itself) and, for `DOCUMENT_MIME_ALLOWLIST` types, a `text` attachment `{title: fileName, text: extracted, capped}`. opencode has no PDF reader, so without the second one the agent would need `pdftotext` on the machine.
- **UI.** This rides on the same shared attachments piece as 4.4, with the non-image allowlist (`TEXT_MIME_ALLOWLIST ∪ DOCUMENT_MIME_ALLOWLIST`, or any type, §9). Chips show upload progress: the upload starts on pick, as paseo's does, so send is instant.
- **Echo.** Whether the canonical user item text includes the rendered `Uploaded file:` block depends on whether the daemon records the prompt text or the provider's rendering **[unverified; M3 spike]**. With the ledger (4.4), the bridge strips that block and attaches file chips from the descriptors. Without it, the lines show as text: honest, if noisy.
- **Later (L):** a **review attachment** from `AgentDiff`. Line comments in the diff pane get sent as `{type:"review", cwd, mode, comments[]}`. It's a natural fit for the existing side pane.
- **Later (L):** an "attach a workspace file" picker over `listDirectory`. It's low value, because the agent can already read the workspace.

**Security.**
- Upload bytes cross the relay E2EE. The daemon writes under `$PASEO_HOME`, not the repo. The sanitized basename means no traversal (`sanitizeFileName`).
- Uploads accumulate on the user's disk with no delete RPC. Document this, or propose an upstream delete RPC (or carry it as a fork patch, §8).
- Size caps are enforced by Cerea, since the daemon has none.

**Provider differences.** Paths are absolute on the daemon's machine; a sandboxed provider might not see `$PASEO_HOME` **[unverified]**. The text rendering is provider-neutral (`renderPromptAttachmentAsText`).

**Effort:** about 3 days (plus the 4.4 refactor, if M2 hasn't shipped).

### 4.6 Extras worth adopting

| Extra | Paseo | SDK | Cerea design | Fold impact | Effort |
| --- | --- | --- | --- | --- | --- |
| **Steer while running** | the composer can send during a turn | `sendAgentMessage{activeTurnBehavior:"steer"}`; opencode implements `steerActiveTurn` | While a turn runs, keep stop *and* show send: Enter steers, and a menu offers "interrupt and send". Route: `messages` body gains `behavior` | **Touches the transcript.** The mid-turn `user` echo closes the turn's assistant message and opens a new one, and there may be no fresh `turn_started`. So the new bubble has no `running` TurnState until tokens arrive, and the final `turn_completed` lands on it via `stateTarget`. It needs a hermetic spec that replays the daemon's live order for a steer, plus possibly a rule "a `user` frame while a turn is running adopts running for the next bubble". Write the spec first | 2 d |
| **Thinking/effort pill** | per-model thinking options | `setAgentThinkingOption`, `thinking_option_changed` | A pill beside the model pill, only when the model lists `thinkingOptions` | none | 1 d |
| **Slash commands** | autocomplete | `listCommands` | A `/` menu in `ChatInput` (chat has a mention/menu idiom **[unverified which]**); run = send the text | none | 1.5 d |
| **Live diff and base mode** | changes pane, live | `subscribeCheckoutDiff` (0.9: `observeCheckoutDiff`), `getCheckoutDiff{mode:"base"}` | The diff pane subscribes while open, through a link method, with an "uncommitted / vs base" switch | none | 1.5 d |
| **Richer permission cards** | plan approval ("implement"), questions | `AgentPermissionRequest.kind/actions[]`, `respondToPermission{selectedActionId, updatedInput}` | Map `actions[]` to the chat approval card's buttons; `question` kind to chat's AskQuestion | permission mapping only | 2 d |
| **Reasoning** | collapsed reasoning | `timeline{reasoning}` | Map to chat's `MessageUpdateType.Reasoning` block (chat already renders it). It is dropped today by choice, so this is a product decision | yes: a new update kind inside the turn, like Stream (it must flush text first) | 1 d |
| **History paging** | infinite scroll up | `fetchAgentTimeline{direction:"before", cursor}` | "Load earlier" at the column head. It prepends, so the fold must support a *prepend* mode; simplest is to re-fold `older + current` into a fresh array | yes, careful | 2 d |
| **Directory suggestions** | path autocomplete | `getDirectorySuggestions` | In `WorkspaceDialog` | none | 0.5 d |
| **Worktree isolation** | per-agent worktrees | `createAgent{worktree}`, `createPaseoWorktree`, `archivePaseoWorktree` | A "Run in a new worktree" option in AgentDialog and the handoff dialog. The worktree lifecycle stays the daemon's | none | 2 d |

## 5. Extras classified

| Feature | Verdict | Reason |
| --- | --- | --- |
| Providers / modes / models / features | **Adopt (mostly done)** | Already live-listed. Add the thinking pill, `mode_changed`/`model_changed` reconciliation, and select-type features once one exists for opencode (none today). Stop hardcoding `build`/`plan` in `createAgent`: pass the chosen mode id from `listProviderModes` |
| Commands (slash) | **Adopt** | Cheap (`listCommands` + send text) and unlocks `/compact`, `/review`, `/init` |
| Git / checkout diff (read) | **Adopt** | Live subscription and base mode make the existing pane accurate. Commit/log context is L |
| Git write ops (commit, push, PR, merge) | **Unclear** | High value for "ship it from my phone", but irreversible on the user's repo, and push/PR need credentials on the machine. Revisit after worktrees; if adopted, every op gets a confirmation and its own allowlist row |
| Worktrees | **Adopt later** | The right isolation for parallel agents and "hand off in a worktree". The daemon owns the lifecycle, and Cerea just asks for `worktree` on create |
| Workspace scripts / setup | **Not now** | Only meaningful with terminals or a forwarded preview port, and neither exists in the panel |
| File explorer (read) | **Adopt later** | Read-only browse and preview (`listDirectory`, `readFile{maxBytes}`) helps review an agent's work beyond the diff. File preview "accepts any daemon-readable regular file" (`docs/permissions.md`), so a browser explorer is effectively `cat` on the whole machine for the owner. Acceptable only with a path jail to the workspace root, enforced **in Cerea** (normalize, then prefix-check against the workspace directory) |
| File editing | **No** | Agents edit and people review. Editing from a browser adds conflict semantics for no core value |
| Terminals | **Unclear, lean no** | Paseo streams PTY frames (binary, reflowable snapshots). In Cerea that means a WebSocket bridge (SSE is one-way) plus xterm.js, and it is a full remote shell on the user's machine behind a web session. Enormous power and a security review of its own. Consider read-only `captureTerminal` if agents start using terminals via MCP |
| Schedules | **Adopt later** | Cron cadence targeting self/agent/new-agent is useful ("every morning, triage CI"). It is a list/create/pause/delete UI over 9 RPCs and needs `automation.manage`. Schedules run on the user's machine and bill to Pystino via the enrollment. Say so in the UI |
| Heartbeats | **Adopt later (with schedules)** | MCP-created periodic wakeups of an agent. Show them read-only in the schedule list, with pause/delete |
| Loops | **No (for now)** | CLI/MCP-driven repeat-until; no UI value yet |
| Dictation / voice | **No** | Audio would travel browser → Cerea → relay → laptop for transcription on the laptop. Cerea already controls the browser and can transcribe server-side if wanted. The daemon's voice mode is for paseo's own mobile app |
| Plugins | **No for the UI; unclear as a mechanism** | Managing plugins from Cerea is machine admin. A **Cerea-authored plugin** installed on enrollment could replace some fork patches, for example injecting Pystino env or MCP servers per agent (`paseo-plugin` skill: "transform agent configuration, environment, MCP servers"). This is §8's cheapest middle path |
| Paseo MCP injection | **Adopt (as a per-device toggle)** | It is what makes agent-initiated handoff and delegation work (§4.2) |
| Custom MCP injection (`createAgent{mcpServers}`) | **Unclear** | Cerea could hand agents its own MCP servers (knowledge base, memory). But that ships Cerea credentials to a machine Cerea doesn't control, and every token would need to be scoped and short-lived. Revisit after the Hub decision (§8) |
| Rewind | **Unclear** | opencode supports only `both` (conversation and files together). A "rewind to here" that also reverts files on the user's disk is valuable but destructive. If adopted: gated on `capabilities.supportsRewind*`, with an explicit confirmation, handled via `agent_timeline_replacement` → refetch |
| Provider usage (subscription quotas) | **No** | It reports claude/codex/copilot quotas. Pystino spend is Cerea's own `UsageBar` |
| Import sessions / agent history | **Adopt later** | "Pick up the opencode session I started in the terminal" (`fetchRecentProviderSessions` + `importAgent`) is a genuine continuity feature |
| Chat rooms (agent message boards) | **Adopt later, read-only** | Useful to watch orchestration once agents delegate |
| Daemon admin (update, restart, diagnostics) | **No** | Machine admin. At most, show the daemon version and "update available" |

## 6. Milestones

Each milestone ships on its own behind `CODE_AGENTS_ENABLED`. Anything upstream-gated is also gated on the relevant `server_info.features` flag, surfaced by M0, so an older or newer daemon without the flag hides the affordance instead of erroring.

**Testing pattern.** Hermetic Playwright specs stub `/api/v2/code/**` with `page.route` and `superjson.stringify` bodies, as in `tests/code-composer.spec.ts`. SSE routes are fulfilled with a literal `text/event-stream` body of `id:`/`event: update`/`data:` records, so each spec replays an exact daemon order. Vitest covers `codeTimeline`, the fold and the link mappers with fixtures. Nothing in CI touches a real daemon. Live checks happen by hand, and only against a **disposable** daemon, never `test-pv`.

**Fork column.** "Stock" means feasible on upstream 0.8.x as shipped. Fork patches are listed where one would remove a workaround; none is required.

| # | Milestone | Scope | Depends on | Tests (hermetic unless noted) | Stock or fork | Effort |
| --- | --- | --- | --- | --- | --- | --- |
| **M0** | **Foundation and contract hardening** | (1) Seam dedup on `(epoch, seq)` using entries' `seqStart/seqEnd` and `agent_stream.seq`. (2) Replace the minor pin with a **floor ≥ 0.8.0, below the next major**, plus feature gating from a cached `server_info`, and expose `features` on `GET v1/agents/:id` and the devices list. (3) Wire `subscribeConnectionStatus` into the pool. (4) Live mode ids in `createAgent`. (5) **Contract fixtures**: sanitized payloads recorded from the read-only probes, checked in as `paseo-0.8/*.json`, with vitest asserting that every mapper parses them. (6) A link-level `protocol.ts` adapter that is the only module importing `@getpaseo/*` types (§7) | — | vitest: identical-token deltas and identical prompts across the seam both survive; a 0.9-reporting daemon is admitted and a 1.x one refused; fixtures parse. Existing `code-*.spec.ts` stay green | Stock | 3 d |
| **M1** | **Context meter and compaction** | §4.3: `usage`/`compaction` frames, side-channel fold cases, `ContextMeter` in the composer pill row, "Compact now" → `/compact` | M0 | Playwright: an SSE with a `usage` frame shows "1%" and "11,955 / 1,048,576" in the popover; unknown max shows tokens only; a `compaction` frame shows in the popover; "Compact now" posts `{text:"/compact"}`. vitest: `usage_updated` and `turn_completed.usage` map; the fold leaves `messages` byte-identical and calls `onUsage` | Stock | 2 d |
| **M2a** | **Shared composer attachments (refactor)** | Lift paste, dropzone and chips out of `ChatWindow` into a shared component and helper; chat adopts it unchanged | — | All chat upload/paste specs green; one new agent spec asserting the dropzone renders when `mimeTypes` is non-empty | n/a | 1.5 d |
| **M2b** | **Image prompts** | §4.4: multimodal gating from Cerea's model registry, multipart `messages`, caps and sniffing, `sendAgentMessage{images, messageId}`. **Spike first:** confirm on a disposable daemon that a multimodal Pystino model receives the image through opencode | M0, M2a | Playwright: paste a PNG → chip → send → the stubbed route receives multipart with the image and a `messageId`; the picker is disabled on a non-multimodal model; an oversize image is refused client-side. vitest: the server refuses a 6 MiB image and a spoofed mime | Stock | 2.5 d |
| **M2c** | **Attachment ledger** (decision §9) | GridFS entries per `(device, agent, messageId)`, `files` on the `user` frame, placeholder stripping, owner-checked GET, cleanup on revoke | M2b | Playwright: an SSE `user` frame with `files` renders the thumbnail in the user bubble after reload. vitest: the fold copies `files` and nothing else changes; revoke deletes entries | Stock (a fork patch could make it unnecessary, §8.4) | 1.5 d |
| **M3** | **File uploads** | §4.5: `uploads` route, server-side upload map, `uploadIds` on send, document text via `extractDocument`. **Spike first:** what the canonical user item text contains when attachments are sent | M2a (M2c for chips) | Playwright: pick a PDF → the upload route is called → the chip shows progress → send posts `uploadIds`; an 11 MiB file is refused. vitest: an unknown or expired uploadId is refused; another user's uploadId is refused | Stock (fork for a daemon-side cap and cleanup) | 3 d |
| **M4** | **Multi-agent: live tree, attention, nesting, side-by-side** | §4.1 | M0 | Playwright: a stubbed `devices/:id/events` SSE (snapshot → upsert status → attention) changes the dot and shows a badge; opening posts `attention/clear`; a labelled child nests under its parent; `?beside=` renders two columns, each with its own stream | Stock | 4 d |
| **M5a** | **Handoff by fork** | §4.2(a): the "Hand off…" action, AgentDialog handoff mode, `POST …/handoff` (fork context, create with idempotency key, then send with messageId), a `cerea.handoff-from` label, cross-device target | M4 (nesting and live status) | Playwright: the dialog is prefilled from the source; the POST body carries prompt, provider, model and boundary; the new agent's header shows "Handed off from". vitest: the link sequence and retry are idempotent (same nonce → one create) | Stock | 3 d |
| **M5b** | **Agent-initiated handoff** | §4.2(b): the machine-settings toggle for `mcp.injectIntoAgents`, Handoff card on `create_agent` tool calls, detach. **Spike first** on a disposable daemon: tool-call naming and result shape for opencode | M4, M5a | Playwright: a stubbed `create_agent` tool call renders the Handoff card bound to the child id; detach posts; the toggle shows the daemon's value and asks for confirmation | Stock (fork only for a per-agent injection flag) | 4 d |
| **M6** | **Composer extras** | Thinking pill, slash commands, **steer** (spec first), permission `actions[]` and question kind, directory suggestions | M0 | Playwright: the steer spec replays the daemon's live order (user echo mid-turn, no new `turn_started`) and asserts one bubble per prompt and a correct running indicator; thinking pill posts; the `/` menu lists stubbed commands | Stock | 7 d |
| **M7** | **Diff, worktrees, history** | Live diff subscription (behind the link; renamed in 0.9), base mode, "run in a new worktree", "load earlier" paging (a re-fold on prepend) | M0 | Playwright: stubbed diff updates re-render; the worktree option lands in the create body; "Load earlier" prepends without duplicating the seam | Stock | 5.5 d |
| **M8** | **Later** | Schedules and heartbeats, read-only file explorer (workspace-jailed), import provider sessions, review attachments from the diff pane, chat rooms read-only, reasoning blocks | per item | per item | Stock | ~10 d |

**Critical path:** M0 → M2a → M2b → M4 → M5a. M0–M5b (the user's minimum list: agents, handoffs, context, images, file uploads) add up to **about 24.5 developer-days**, excluding the spikes' calendar waits. M6 and M7 add about 12.5 more.

```
M0 ──┬─ M1
     ├─ M2a ─ M2b ─ M2c
     │    └──── M3
     ├─ M4 ── M5a ── M5b
     ├─ M6
     └─ M7
```

## 7. Protocol and versioning risk

The protocol is de facto: `"This project is under active development and its internal protocols may change without notice"` (paseo-relay README, repeated in Cerea's `docs/code-panel.md`). The drift observed from 0.8.0 to 0.9.1 (12 days) is the best predictor of what the plan exposes.

### 7.1 What breaks on an upgrade, by exposure

| Exposure in this plan | Observed drift (0.8.0 → 0.9.1) | Breaks when | Containment |
| --- | --- | --- | --- |
| **Cerea's minor pin** (`versionMinor` equality) | the daemon went 0.8 → 0.9 | **the first time a user's daemon self-updates** (`daemonSelfUpdate`, `updateDaemon`) | M0: a floor plus max-major plus feature gating. This is the single biggest risk today, and it's Cerea-made |
| Import path `@getpaseo/client/internal/daemon-client` | still exported in 0.9.1 | upstream tidies exports | Keep every `@getpaseo/*` import inside **one adapter module** (link plus mapper). Any rename is then a one-file change |
| SDK method names | **`setAgentTimelineSubscription` → gone (`observeTimeline`); `subscribeCheckoutDiff`/`unsubscribeCheckoutDiff` → gone (`observeCheckoutDiff`); `subscribeTerminals` → gone**. `fetchAgents`/`fetchWorkspaces` gained overloads, and `observeAgents`/`observeWorkspaces`/`observeEvents` were added | an SDK bump | The link wraps every call; M4 and M7 go through link methods named for Cerea's intent (`watchAgents`, `watchDiff`) |
| Wire message types Cerea sends | all 12 checked still present in 0.9.1 (`create_agent_request`, `send_agent_message_request`, `fetch_agent_timeline_request`, `agent_stream`, `agent_update`, `file.upload.request`, `fetch_agents_request`, `subscribe_checkout_diff_request`, `agent.provider_subagents.list.request`, `set_agent_feature_request`, `cancel_agent_request`, `agent.detach.request`). 0.9 adds `agent.create.request` and `creation.subscribe` alongside, not instead | an upstream `COMPAT` removal date passes | Track the dates below. An old SDK against a newer daemon keeps working until then, and the daemon speaks older clients' dialects by design (`COMPAT(...)` comments with removal dates) |
| **Feature-flag gating itself** | flags are *retired* on a schedule: `agentDetach` "remove gate after 2026-12-19", `agentForkContext` 2026-12-28, `providerSubagents` 2027-01-12, `canonicalSubmittedPrompts` 2027-01-30, `daemonStatusRpc` 2026-11-18 | a newer daemon **stops advertising** a flag because the feature became unconditional | Gate rule: *flag true, **or** daemon version ≥ the version where the flag retires*. Simpler: gate only on flags for features newer than Cerea's floor, and treat older ones as present. A naive `features.x === true` check would **hide** detach and fork on a newer daemon |
| Legacy session broadcasts (`agent_update` and friends to every session) | still on in 0.9 | after **2027-03-08** (`session.ts:7781`) | Before then: send `explicit_event_subscriptions` and subscribe explicitly (0.9's `observeEvents`) |
| Timeline projection (`projected`, `collapsed`, `sourceSeqRanges`, `seqStart/seqEnd`) | 0.9 adds `projectedSubagentTimeline` and timeline search | the projection rules change | M0's seam dedups by **seq range and epoch** (drop a live frame whose `seq ≤ max(seqEnd)` for the same epoch; an epoch change triggers a full reset), not by content. `agent_timeline_replacement` also triggers a refetch |
| Item/event shapes (`ToolCallDetail` variants, `AgentUsage` names, `AgentPermissionRequest.actions`) | `agent-types.ts` changed only additively (a catalog normalizer) | a rename | All mapping happens in `codeTimeline.ts` into **Cerea-owned** frame types. Unknown kinds are dropped, as they are today |
| Relay protocol and E2EE handshake | the relay is a separate Elixir repo, pinned at `3fc41c9` (2026-08-22) | users' daemons speak a newer relay dialect than the pinned relay | Re-verify the relay pin on each SDK bump. The relay is identity-blind and carries opaque frames, so it has historically been the stable layer **[no drift measured for the relay itself]** |
| Hub contract (if §8.3 is adopted) | 24 commits to `server/hub` in 3 months, 3 of them between the tags; "Cloud owns its copy of the Hub wire schemas" | Paseo Cloud and the daemon evolve together without Cerea | Only adopt behind a spike, with contract fixtures, and treat it as more volatile than the session protocol |

### 7.2 Upgrade procedure (applies with or without a fork)

1. Bump `@getpaseo/*` to an exact version in a branch. Diff `packages/protocol/src/messages.ts` and `packages/client/src/daemon-client.ts` between the two tags, for every symbol the adapter module imports. This is mechanical: a grep list generated from the adapter's imports.
2. Run the vitest contract fixtures. Re-record them with the read-only probe against a **disposable** daemon at the new version, and diff.
3. Re-check the `COMPAT(...)` removal dates that are due before the next planned bump.
4. Re-verify the relay pin against a new-version daemon (pairing plus one timeline stream).
5. Only then raise the floor or the max-major.

## 8. Fork vs track upstream

### 8.1 Upstream churn and cadence (measured on `/tmp/paseo-src`)

- **Releases.** Minors cut on 2026-07-24 (0.2), 08-08 (0.3), 08-13 (0.4), 08-23 (0.5), 08-25 (0.6), 08-31 (0.7), 09-10 (0.8) and 09-22 (0.9), with patch releases in between. That is **8 minors in 60 days**, roughly one a week, plus betas.
- **Commits.** 1,392 in the last 3 months and 335 in the last month; `git rev-list v0.8.0..v0.9.1` counts 84. **1,045 of the 1,392 are by one author**, then bots (107) and a long tail. It is effectively a single-maintainer project with high velocity.
- **The files a fork would patch are hot.** Over the last 3 months, `server/session.ts` (7,981 lines) had 96 commits, `protocol/src/messages.ts` 99, `client/src/daemon-client.ts` 77, the opencode adapter 52 (31 + 21 in `providers/opencode/`), and `server/hub/` 24.
- **Licence history.** MIT (2026-02-05) → AGPL-3.0-or-later → **Apache-2.0 since `a8734a972` on 2026-08-27** (#3944). That is two licence changes in seven months.

### 8.2 Licence implications (Apache-2.0, 0.8.0 is covered)

- **Freedoms.** A fork may be modified, run as a service, and distributed, privately or publicly, with an express patent licence from contributors (§3). There is no copyleft: Cerea's own code is unaffected, and **unlike the AGPL window, running a modified daemon or relay for users triggers no source-offer duty**.
- **Duties when we distribute** (and we would: users install the daemon on their machines):
  - ship the licence;
  - keep the copyright and attribution notices;
  - mark modified files as changed (§4(b));
  - carry any `NOTICE` file forward (there is none today, checked in the monorepo and the relay repo).
- **Trademark (§6).** No right to the "Paseo" name. A fork's packages, CLI name and UI copy must be ours, for example "Cerea agent host (based on Paseo)".
- **Relicensing risk.** Anything forked from ≥ `a8734a972` stays Apache-2.0 forever. But upstream can relicense *future* versions, and has done so twice. A tracking strategy inherits that risk at every bump; a fork caps it. It's a trigger condition, not a reason by itself (§8.6).
- Third-party components keep their own licences (the LICENSE preamble). A redistributed daemon bundle needs a dependency licence scan. `expo-two-way-audio` is MIT; the voice deps would go in a fork anyway.

### 8.3 Two stock middle paths that remove most of the reasons to fork

1. **Cerea as a Paseo Hub (stock daemon, stock CLI).** 0.8.0 ships a full, opt-in *Hub relationship* (`docs/hub.md`, `server/hub/*`):
   1. The user runs `paseo hub connect <cerea-origin>`.
   2. The CLI gets a one-time token from `POST <origin>/api/v1/daemons/enrollment-tokens`.
   3. The daemon enrolls at `POST <origin>/api/daemons/enroll`, sending `{daemonId, serverId, daemonPublicKey, credentialVerifier, permissions}` and receiving `{daemonId, permissions, webSocketUrl}` on the same origin.
   4. It then keeps a **direct outbound WebSocket** to that URL with a bearer credential, and the Hub speaks the ordinary session protocol over it. The SDK's `transportFactory` can wrap an accepted socket **[unverified end-to-end]**.

   What this buys, with no fork:
   - **a scoped principal.** "Hub connections have no daemon permissions by default", and grants are explicit (`hub.execute`, `workspace.read/write/manage`, `automation.manage`), where the relay pairing is owner (§1.1);
   - **no relay container and no E2EE pairing ceremony.** Enrollment could reuse Pystino identity: Cerea mints the one-time token for the signed-in user, which is close to "native gateway auth";
   - `PATCH`/`DELETE /api/daemons/:id` for permission updates and revocation.

   Costs:
   - Cerea implements an undocumented server contract that "Paseo Cloud owns", and it has changed (24 commits in 3 months);
   - one Hub per daemon, so a user who also wants Paseo Cloud can't have both;
   - TLS instead of E2EE. That is no real loss: Cerea is already the decrypting endpoint today.

   **Verdict: spike** (2–3 days, disposable daemon), not a commitment.
2. **A Cerea plugin (stock, installed by the enroll flow).**
   - The `agent.create` hook may rewrite `config` (model, system prompt, `mcpServers`) and `env`.
   - `agent.session_open` may rewrite `env` on every create, resume, refresh or import (`plugins/lifecycle/index.ts:28-44`).

   That covers injecting a fresh Pystino token or `x-bill-to` into opencode's environment at each session open. The enrollment shim is still needed for **mid-session** refresh, since opencode holds the token for the session's life **[unverified: whether opencode re-reads env or config per request]**. Plugins are off on the live daemon (`pluginsEnabled: false`), so the enroll script would enable them.

### 8.4 What a fork would let us simplify or add

| Want | Stock answer | Fork patch (minimal) | Size / hot-file risk |
| --- | --- | --- | --- |
| **Scoped principal for Cerea** | Hub relationship (§8.3); otherwise none. Relay pairing = owner | Admit relay sessions from a Cerea pairing with a stored permission set; the docs' "pairing invitation creates a principal with selected permissions" model is described but not implemented in 0.8 | ~200 lines in `websocket-server.ts` and pairing. **High** conflict risk |
| **Images and attachments survive reload** | the Cerea attachment ledger (M2c) | Persist `images`/`attachments` metadata on the canonical `user_message` item and serve image bytes by id | ~150 lines in protocol, agent-manager and a timeline store. Medium. **Upstream-PR material** |
| **Upload cap and cleanup** | caps enforced by Cerea; files accumulate | A `maxUploadBytes` config, a `file.upload.delete` RPC, TTL GC of `$PASEO_HOME/uploads` | ~120 lines, isolated (`file-upload/`). Low. **Upstream-PR material** |
| **Per-agent paseo-MCP injection** | the daemon-wide `mcp.injectIntoAgents` | `createAgent{config.paseoTools: boolean}` | ~60 lines. Medium |
| **Typed enrollment errors** | Cerea's `invalid_grant` substring classifier | A `turn_failed.code = "provider_auth_expired"` set by the opencode adapter | ~40 lines. Medium (the opencode adapter is hot) |
| **Native Pystino auth (no shim)** | plugin env injection plus the shim (§8.3) | A daemon-owned credential with refresh and an in-process proxy for opencode | ~400 lines, new module. Low conflict, **high ownership cost** (we'd own token refresh inside someone else's daemon) |
| **Frozen protocol** | pin plus adapter plus COMPAT tracking (§7) | Stop rebasing | 0 lines, but see §8.5: the opencode adapter rots |
| **Hub-client ergonomics** (a server-side SDK without the `internal/` path and the app-centric session store) | wrap it in our adapter | A slim `@cerea/paseo-client` | Medium. Only worth it if the fork exists anyway |
| **Drop mobile/voice/web-UI weight** | Cerea doesn't ship app, desktop or website; the weight is the daemon's voice/dictation deps on users' machines | Strip `dictation`, `voice`, `speech` from `packages/server` | Large deletion diff, conflicts on every rebase touching session wiring. Benefit: install size **[unmeasured]** |

### 8.5 Cost of a fork

- **Rebase load.** The minimal useful fork (scoped principal, attachments on user messages, upload cap and cleanup, per-agent MCP, typed auth error) is about 600 lines across `websocket-server.ts`, `session.ts`, `agent-manager.ts`, `messages.ts`, `file-upload/` and the opencode adapter. These are the hottest files in the repo (§8.1). At about one minor a week, expect **0.5–1.5 developer-days per upstream minor**, about 15–30% of one developer, plus a CI pipeline to build and publish.
- **Distribution.** Users would install *our* daemon: an npm scope or binary, the install step in the enroll script, update channels. **Upstream self-update (`updateDaemon`) must be disabled or redirected**, or a user's click replaces the fork with upstream.
- **Compatibility with paseo's own app.** The daemon's config points at `app.paseo.sh` (live `getDaemonConfig`). Users can drive the same daemon from paseo's app, and a fork that bends the protocol breaks that for them.
- **The frozen-fork trap.** Freezing avoids rebases, but the opencode adapter has to follow **opencode's** releases: 52 upstream commits in 3 months on the adapter alone ("Wait for authoritative provider readiness…", "show child session prompts", …). A frozen daemon degrades as users update opencode. So a fork isn't a one-off cost; it means maintaining an opencode integration.

### 8.6 Recommendation

**Track upstream. Don't fork now.** Concretely:
1. **M0 first**: an adapter module, a version floor, seq-based seams, contract fixtures. This turns upstream churn into a bounded, scheduled task (§7.2) and fixes the self-update cliff that would otherwise hit users soon.
2. Build M1–M5 on **stock** 0.8.x/0.9.x. Every milestone is feasible on stock (§6). The fork would only remove Cerea-side workarounds: the attachment ledger and the upload map.
3. **Upstream the three generic gaps as PRs**: attachments on the canonical user message, upload cap and cleanup, per-agent paseo-MCP injection. They are generic, small and isolated, and would help paseo's own app.
4. **Spike "Cerea as Hub"** (§8.3) as the stock route to a scoped principal, relay removal and IdP-native enrollment. Decide after the spike; this is the main alternative to forking for security.
5. Keep the relay pinned (Elixir, separate repo). Forking it buys nothing.

**Triggers that would flip this to a fork** (any one of them):
- **Licence.** Upstream relicenses new versions away from Apache-2.0 or another permissive licence. Then freeze on the last Apache commit and fork, accepting the opencode-adapter maintenance.
- **Loss of the client path.** Upstream removes or cripples third-party client or relay access (for example, hub or relay access tied to Paseo Cloud accounts) without a `COMPAT` window.
- **Security mandate.** A scoped (non-owner) principal becomes a hard requirement, and within a quarter neither the Hub spike nor an upstream PR delivers it.
- **Workaround weight.** Upstream declines the gap PRs, and the Cerea-side workarounds (ledger, upload map, error-string classifiers) cost more to maintain than a roughly 600-line patch set.
- **Stall.** Upstream goes quiet (no release for more than 2 months, bus factor) while opencode keeps moving. At that point we maintain the adapter regardless, and owning the daemon is cheaper.
- **Distribution.** Cerea decides to ship its own agent-host installer anyway, with enrollment and Pystino auth baked in. Distribution is then already paid for, and the marginal cost of patches drops.

## 9. Open questions

**Decisions for the user**

1. **Attachment ledger (M2c).** Accept a narrow Cerea-side store of the images and files a person sent to an agent, so they render after a reload? The alternative is `[Image]` text after reload. It is a deliberate exception to "no second agent store" and could be retired if the upstream PR in §8.6 lands.
2. **Upload policy (M3).** Allow any file type, or only chat's text and document allowlist? Is the cap 10 MiB (under today's 15 MiB `BODY_SIZE_LIMIT`), or should uploads stream so they can approach paseo's 50 MB?
3. **Daemon-config write (M5b).** May the panel flip `mcp.injectIntoAgents`, the only `daemon.manage` write in the plan, or only display it and tell the person which `paseo` command to run?
4. **Reasoning.** Show agent reasoning in chat's reasoning block, for parity with chat and paseo? Today it is dropped on purpose.
5. **Cost.** Hide opencode's `totalCostUsd`, as recommended, or show it labelled as an estimate?
6. **Hub spike (§8.3).** Go or no-go? It is the stock route to a scoped principal and removing the relay.
7. **Cross-device handoff.** Handing off from machine A to machine B is a Cerea-only capability. Is it wanted?
8. **Terminals and git write ops.** What is the product stance? The recommendation is no, and revisit after worktrees.
9. **Non-Pystino models.** The live model list includes opencode's hosted `opencode/*-free` models. An agent using them bypasses Pystino's billing and quota ledger entirely. Should the panel offer only `pystino/*` models? A filter in `listProviderModels` would do it.

**Unverified; each is resolved by the named spike, always on a disposable daemon**

| Item | Resolved by |
| --- | --- |
| A multimodal Pystino model receives images through opencode's data-URL file parts | M2b spike |
| What the canonical `user_message` text contains when attachments or images are sent (the daemon's text vs opencode's rendering) | M3 spike |
| The opencode tool name and result shape for paseo-MCP `create_agent` calls | M5b spike |
| Whether MCP injection reaches existing agents or only new ones | M5b spike |
| Whether paseo skills (`paseo-handoff`) are installed into opencode by `agent.skills` reconciliation | M5b spike |
| Hub contract end to end with `transportFactory` over an accepted socket | Hub spike |
| Whether opencode re-reads env or config per request, which decides whether plugin env injection can replace the shim | plugin spike |
| Usage-field completeness for claude/codex; fork drafts carrying no lineage label; paseo's image downscaling; the size of the daemon's voice deps | code reading, when relevant |

---

## 10. Implementation progress (started 2026-09-23, evening)

**Scope change** (orchestrator instruction, from the parallel code and architecture review, §3.2 and §4 #9): paseo-parity feature work is **frozen** until the user decides the agent-host strategy (keep paseo, or build a thin owned agent over `opencode serve`/ACP). Until then, only **M0 plus model filtering** are built, together with review quick wins R1 (connect deadlines) and R6 (per-frame logs). M1 and later are not started; M2c is research only (§10.4).

### 10.1 Workstreams

| Workstream | Worktree / branch | Agent (Sonnet 5) | Scope |
| --- | --- | --- | --- |
| M0a link | `parity-m0-link` / `parity/m0-link` | `892ec492` | adapter module (one quarantined internal import, guard test), version floor ≥ 0.8.0 < 1.0.0, server_info cache, re-verify on reconnect (R2 part), R1 deadlines, contract fixtures |
| M0b bridge | `parity-m0-bridge` / `parity/m0-bridge` | `191613d2` | seq/epoch seam (R3/R4), cursor SSE ids, resume via `after` cursor, `reset` event and a clean client restart, idempotent elicitation frames (the one named fold change), R6 |
| Model filter (Cerea) | `parity-model-filter` / `parity/model-filter` | `15094fbc` | `allowFreeModels` on `codeDevices`, a policy module, forwarder enforcement (list, set, create), a hidden-count hint, docs |
| Model filter (Pystino) | `pystino-free-models` / `parity/allow-free-models` | `e4d541b4` | `--allow-free-models` in `enroll` (persisted), sent by `pair`, `setup-agent.sh`, docs |

Contract fixtures were recorded read-only against `test-pv` (0.8.0), sanitized (text fields redacted, host, serverId and relay endpoint replaced), and handed over at `/tmp/paseo-fixtures-0.8.0.json`. They confirmed the daemon's resume contract: a stale-epoch cursor answers `reset: true, staleCursor: true` with the full timeline, and `direction: "after"` plus a cursor returns rows with `seq >` the cursor, in one seq space shared by projected and canonical rows.

### 10.2 Decisions taken by default, please confirm

1. **The internal SDK import stays, quarantined.** The public root (`createPaseoClient`) covers neither 0.8.0 nor 0.9.1 for cancel, set mode/model/feature, delete, rename, subagents, checkout diff or daemon status. So `@getpaseo/client/internal/daemon-client` is imported by exactly one adapter module, and a test fails if any other file imports `@getpaseo/*`. Removing it fully needs either upstream to widen the public API or the strategy decision.
2. **Version policy: accept ≥ 0.8.0 and < 1.0.0**, re-checked on every SDK reconnect. Feature gating uses the cached `server_info`, and nothing is gated yet.
3. **Two enrollment flags, not one.** `--allow-opencode-provider` is the machine posture (what opencode offers locally). `--allow-free-models` is the web-panel posture (whether Cerea may drive non-gateway models), and it *implies* the former. The name says "free", but it covers every non-`pystino/` model.
4. **Default-model safety.** With non-gateway models disallowed, "reset to provider default" and "create without a model" are resolved by Cerea to the gateway default, so the daemon's own default (possibly non-gateway) is never used silently. Agents *already running* on a non-gateway model keep it until switched; there is no retroactive policing.
5. **A re-pair overwrites the permission.** The latest enrollment wins. The paste flow always stores false.
6. **Reset semantics.** A stale cursor, epoch change or timeline replacement makes the client drop the transcript and re-replay from scratch, rather than attempt a merge.

### 10.3 Milestone log

(appended as branches land)

### 10.4 Research notes (no code)

**0.8.0 SDK against a 0.9.1 daemon** (verified 2026-09-23 against a disposable daemon: `paseo daemon run --home /tmp/paseo-disposable-091`, `PASEO_LISTEN=127.0.0.1:6899`, relay off, stopped afterwards).
- The pinned 0.8.0 `DaemonClient` connected directly and got answers from `getDaemonStatus` (version `0.9.1`), `server_info` (71 feature flags), `fetchAgents`, `fetchWorkspaces`, `listAvailableProviders` and `listProviderModes`. An unknown agent id produced a clean `Agent not found` error. So the wire is compatible for everything tested; timeline and agent calls on 0.9 were not exercised, because that needs a real agent.
- **R1 reproduced live.** The first connect attempt, made while the daemon was still booting, hung for the full 30 s outer timeout and never rejected. That is the hang the deadline fix removes.
- Side observation for §8.4: a fresh 0.9.1 daemon immediately starts downloading local speech models (`parakeet-tdt-0.6b-v2-int8`, `kokoro-en-v0_19`) into its home. That is the voice weight on users' machines.

**M2c storage: reuse chat's attachment store, no new store.** How chat persists and serves files:
- `ChatInput` files are uploaded through `uploadFile()` (`src/lib/server/files/uploadFile.ts`) into the GridFS bucket `collections.bucket`. The filename is `<conversationId>-<sha256>`, with `metadata: {conversation, mime}`; extracted document text gets its own entry.
- The message stores a `MessageFile {type: "hash", value: sha, mime, name}`.
- Bytes are served by `GET /conversation/[id]/output/[sha256]` → `downloadFile(sha, convId)`, which checks `metadata.conversation`, after an `authCondition` ownership check on the conversation. The response is "download, never render": `Content-Disposition: attachment` plus a sandbox CSP.
- `execute_code` deliverables use the same pattern through `conversation/[id]/code-execution/output/[sha256]`.
- Deletion goes by `metadata.conversation` (`deleteConversationAttachments.ts`).

M2c can reuse all of it unchanged:
1. Store each sent image or file with the same helper and naming, keyed by a synthetic owner key `code:<deviceId>:<agentId>` in place of the conversation id. Add `messageId` (the id Cerea sends, echoed back by the daemon as `clientMessageId`) to the metadata.
2. The bridge looks up `{metadata.conversation: key, metadata.messageId}` and attaches `MessageFile[]` (type `hash`) to the `user` frame.
3. Serve the bytes from `GET /api/v2/code/agents/[id]/files/[sha256]?device=`. It checks device ownership through the same row check as every `/code` route, then calls `downloadFile(sha, key)`. `downloadFile` already takes a string id and checks `metadata.conversation`, so it needs no change.
4. On device revoke, delete by `metadata.conversation` prefix `code:<deviceId>:`, mirroring `deleteConversationAttachments`.

**The one seam needed.** `UploadedFile.svelte` builds its URL from the *page path* (`page.url.pathname + "/output/" + sha`). The agent screen lives at `/code` (a single page), so the derived URL would carry no device or agent. The smallest reuse is an optional `fileBaseUrl` prop on `UploadedFile`, threaded through `ChatMessage` for user files. The default stays the page path, so chat is byte-identical. I found no clearly better design. The alternative (content-addressing per user with no device or agent in the key) makes revoke-time deletion ambiguous when the same file went to two machines, so it is not recommended.
