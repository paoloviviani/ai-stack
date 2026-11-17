# ADR 0106: The chat drives coding-agent sessions; a project has a per-user agent profile

- Status: accepted (owner, 2026-11-04)
- Repos: Cerea (chat, /code). galopin unchanged.

## Context

A project keeps the knowledge of a matter (instructions, knowledge files, memory); a coding
agent on the user's machine can do work. Today the two do not meet: a chat cannot start, prompt
or read an agent session, so the knowledge cannot be put to work without the user copying text
between the chat and /code. The owner named this as a real pain (2026-11-04).

Most of the plumbing exists. The agent executor for scheduled actions
(`src/lib/server/code/scheduleAgentExecutor.ts`) already drives a session from the server, with no
browser: `session.create`, `session.setMode`/`setModel`, `session.setPermissionMode`,
`session.prompt`, over the same `MachineLink` the /code panel uses. Sessions already read and
message each other (`session_list`/`read`/`send`/`spawn`, ADR 0099). The chat already has tools that
act on the user's behalf through the approval card (ADR 0075), and turns that park and resume.

## Decision

### 1. Four chat tools (builtins)

| Tool | Does | Approval |
|---|---|---|
| `agent_sessions` | Lists the caller's paired machines, their workspaces and sessions, each with its state (`idle`, `working`, `needs-you`, `error`, `offline`), and the project's agent profile if any. | none (read) |
| `agent_start` | Creates a session on `{deviceId, workspaceId}` (defaults: the project profile), sets mode/model when given, sets the permission word, sends `prompt`. Returns at once with `{deviceId, workspaceId, sessionId, title}`. | the caller's approval policy (ADR 0075), like any acting tool |
| `agent_send` | Sends `prompt` to an existing session `{deviceId, sessionId}`. Refused while the session is working or waiting on the user (say so; the model can `agent_read` and retry later). | the caller's approval policy |
| `agent_read` | Returns the session's state, open questions/approvals, and its last answer; `full: true` returns the transcript, bounded (newest first, cut at a size limit, said so). | none (read) |

- **Not waiting is the default.** `agent_start`/`agent_send` return as soon as the prompt is
  accepted; the result is read later (`agent_read`), when the user asks or in a later turn. A
  waiting option may come later on the existing park/resume machinery; not in the first version.
- **Only the caller's own machines.** Every id is resolved against the caller's devices; any other
  id is refused as if it did not exist (the schedules rule). Offline machine: a clear refusal.
- **Untrusted output.** What `agent_read` returns is written by the agent from repository content
  and is untrusted input to the chat model: it carries the same untrusted marking as web fetch
  (`textGeneration/untrusted.ts`).
- **Fresh sign-in.** The tools operate machines, so they follow the /code freshness rule
  (`reauth_required` after 7 days): a stale sign-in gets a refusal telling the user to sign in
  again, never a silent failure.
- **Enabled when** /code is enabled for the deployment and the caller holds `code_agents`, and has
  at least one paired machine. Otherwise the tools are not offered.
- **Scheduled chat runs** follow the existing rule: a run on Ask refuses tools that need approval,
  so `agent_start`/`agent_send` run unattended only on an Allow schedule.
- **Audit.** Every start and send writes a /code audit row with the source conversation id.
- **Billing.** The machine pays with its own credential, as scheduled agent runs do.

### 2. Permission posture

- `agent_send` to an existing session **keeps that session's own permission word**; the chat never
  changes it.
- `agent_start` uses the **project agent profile's** permission word; without a profile (or outside
  a project) it is **Ask**. The machine's ceiling still caps it (galopin composes the ceiling last).
  Approvals of a running session surface in the Needs-you inbox, as for any session.

### 3. The project agent profile — per user, per project

Projects can be shared, and a machine is one user's. So the profile is **not** a field of the
project: it is stored per `(projectId, userId)` in a new collection `projectAgentProfiles`:

```ts
{ _id, projectId: ObjectId, userId: ObjectId,
  deviceId: string, workspaceId: string,
  permissionMode: "deny" | "ask" | "allow",
  modeId?: string, modelId?: string,
  labels: { device: string; workspace: string },   // for lists with no live machine
  updatedAt: Date }
```

- API: `GET | PUT | DELETE /api/v2/projects/[id]/agent-profile` (the caller's own profile; any user
  who can open the project may keep one; validated like a schedule target: own device, workspace
  exists on it).
- Registered in `userKeyedCollections.ts` (merge: reassign; erase: by owner) and erased with the
  project.
- A chat in the project gets the profile as the default target and the model is told in the
  prompt ("this project's default workspace is … on …").

### 4. The session card

`agent_start` and `agent_send` emit a message update so the conversation keeps a card that survives
a reload:

```ts
{ type: "agentSession", action: "started" | "prompted",
  deviceId: string, workspaceId: string, sessionId: string,
  title: string, labels: { device: string; workspace: string } }
```

The card shows the title and "machine › workspace", the live state (from the client's existing
/code device/session data), "needs you" when an approval or question is open, and **Open in /code**.
With a stale sign-in it shows the compact sign-in card (`CodeReauthCard compact`); offline, a
plain offline line.

## Not in the first version (follow-ups)

- Waiting for a session to finish inside the turn.
- Writing a session's final report back into the project's knowledge.
- A galopin tool that lets an agent search the project's knowledge itself.

## Consequences

- One new collection and API, four builtins, one message-update type, one card, a project settings
  section. No protocol change: galopin is untouched.
- The executor's session-starting code is shared between scheduled runs and `agent_start`, so the
  two cannot drift.
