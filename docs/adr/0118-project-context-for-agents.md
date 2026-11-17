# ADR 0118: Project context for coding agents: a linked workspace, a project file, read-only tools and a two-way handover

- Status: **parked** (owner 2026-11-14: first "keep it warm, we are not starting now", then "park the ADR for now"). No code.
- Builds on:
  - ADR 0099 (delegate report-back);
  - the chat ↔ agents bridge (chat drives agent sessions, C67);
  - galopin's MCP relay (`connector_*` tools);
  - the privacy pipelines (Pystino, #193 withheld files).
- Replaces the agent half of C123 (#236): the `memory_*` tools and the server-side agent store, which the owner removed.
- Research: `reports/2026-11-14-memory-state-of-the-art.md`.

## Context

Users plan and decide in Cerea chat projects: project instructions, project memory, knowledge bases, files and chats. They then build in coding agents (galopin running opencode or goose). Today nothing carries a project's context into an agent session automatically. The chat → agent bridge can start and drive a session, but the agent sees only what the chat writes into its prompt.

For coding agents the field has converged on **plain files** read at session start: `AGENTS.md`, `CLAUDE.md`, Cursor rules. Agents edit them with their normal file tools. Model-written memory, where it exists, is also files, local and opt-in. Continuity within a session is handled by the agent's own compaction. A separate memory database with its own tools is not the pattern.

## Decision

Link a code workspace to a Cerea project. Let the project's context reach the agent mainly as a file, with read-only tools for the long tail, plus a handover in both directions.

### 1. Workspace ↔ project link

- An explicit link, set by the owner in /code (workspace settings) or from the project page. One project per workspace; a project may have several workspaces.
- **Permissions:** the link exists only if the user is a member of the project. It stops working the moment they are no longer one, and it is checked on every use.
- **No link, no context:** nothing crosses to an unlinked workspace.

### 2. The project file

- At session start in a linked workspace, galopin writes `.cerea/PROJECT.md`. It is generated, git-ignored (galopin adds `.cerea/` to `.git/info/exclude`) and read-only in spirit: it is overwritten at the next start.
- **Contents:**
  - the project's instructions;
  - its memory, as the same summary chat uses;
  - the names of its knowledge bases and files;
  - short summaries of recent decisions from its chats, as written by C123's chat notes when they exist;
  - a pointer to the tools below.
- **How the agent reads it:** galopin points the engine at it (opencode instructions, goose hints), or the repo's `AGENTS.md` includes it with one line. It is read once per session, so it is cache-friendly. It is refreshed only at the next session start, never mid-session.
- **Size and privacy:**
  - capped, with a truncation note;
  - the text passes through the privacy pipelines like any output to a machine;
  - withheld files are listed by name only, or not at all if the name itself is withheld.

### 3. Read-only project tools

These are MCP tools through galopin, alongside `connector_*`. They are a fixed list, so the engine's prompt stays cacheable.

| Tool | Does |
|---|---|
| `project_search` | Searches the project's knowledge bases with the same retrieval and privacy pipelines as chat. |
| `project_file` | Copies a project file into the workspace, under Plan · Ask · Allow; never a withheld file. |
| `project_chats` | Searches the project's chats; returns decisions and summaries, not raw transcripts. |

- **Read-only:** agents never write project memory, project files or chats. There is no global or personal memory for agents.
- **Untrusted output:** every result is marked as context, not instructions.
- **Audit:** every call is audited (tool, project, outcome; no content).

### 4. Handover, chat to code

- **Trigger:** a project chat offers **"Continue in code"**, using the existing bridge.
- **The brief:** Cerea writes a short handover to `.cerea/handoff-<date>-<slug>.md`: the goal, the decisions made, constraints, open questions, and the files referred to. The model drafts it and the user can edit it before sending.
- **Files:** the referenced files are staged with `project_file` semantics.
- **Start:** the session begins with "Read the handover file first."

### 5. Report-back, code to chat

- When a linked session ends, or on demand, its outcome is posted back to the project chat it came from, or to the project as a note. The outcome covers what changed, the commits or branches, tests, and open questions.
- It follows ADR 0099's delegate report-back: a summary, never the raw transcript.

## Consequences

- Project context reaches agents with no copy and paste, in the file form agents already handle well.
- One project-level permission model covers both chat and code. Removing a member cuts their agents off too.
- The privacy pipelines and withheld-file rules apply unchanged.
- Small new surface:
  - the link;
  - one generated file;
  - three read-only tools;
  - the handover and report-back on the existing bridge.

## Alternatives considered

- **A server-side memory store with agent tools** (the first C123 design): it duplicates what files already do, needs caps, audit and cleanup, and widens the poisoning surface. Removed.
- **Injecting project context into every agent prompt:** it is cache-hostile and bloats every turn. The file plus tools pulls only what is needed.
- **Committing the project file into the repository:** it leaks project content into git history. Kept git-ignored. Teams can still curate their own `AGENTS.md`.

## Rough effort (when started)

| Part | Effort |
|---|---|
| Link and project file | 2–3 days |
| Read-only tools | 3–4 days |
| Handover and report-back | 4–5 days |
