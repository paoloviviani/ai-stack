# Brief: conversation-scoped memory, and memory for agents (C123)

Owner go 2026-11-13: "build it, also for agents, but no global for agents at all."
Shared box rules: `ai-stack/reports/briefs/2026-11-12-box-rules.md`.

## The problem

Cerea's memory today has a personal (global) scope and a project scope:
`src/lib/server/memory/service.ts`, with the `Scope` abstraction, `personalScope` and `projectScope`.
When the owner asked a model to "remember this for this chat", it wrote to global memory, so the
note leaked into every future chat. Writing too broadly is worse than forgetting.

## What to build

### Chat

1. **A conversation scope** in the existing memory service, built on the same `Scope` abstraction,
   not a parallel store.
   - Notes belong to one conversation.
   - Deleting the conversation deletes them (wire into `deleteConversationStorage`).
   - Shared conversations follow the conversation's own access rules.
   - Sensible caps: number of notes and size per note.
2. **One tool, explicit scope.** The model-facing memory tool(s) take `scope: conversation | project | global`.
   - Default to the narrowest scope that fits: inside a project chat, "for this project" means project.
   - `global` only when the user clearly means always or about themselves ("always", "about me",
     "in every chat"). When unclear, ask.
   - Every write result tells the model where it went, so it can tell the user ("Saved to this
     chat's notes").
   - Update the tool description and preprompt.
3. **Visible and editable.** A small "Notes (n)" control in the conversation, following existing UI
   patterns and docs/writing.md: list, edit, delete, and undo of the last write.
4. **Used every turn.** Conversation notes are injected into the model's context on every turn of
   that conversation, as project memory already is, so they survive long chats where early
   messages fall out of the window. Mind token budgets.
5. **Privacy.** Notes reach the model through Pystino like any message, so the privacy pipelines
   apply. Notes never contain withheld file content beyond what the user typed.

### Agents (galopin)

6. **MCP tools for local agents** (opencode, goose), the same way galopin exposes `connector_*`
   (`agent/agenttools.go`, `agent/agenttools_connectors.go`, and the Cerea side that serves them
   over the link):
   - **session scope:** notes tied to one agent session, kept across opencode compaction and
     restarts of that session;
   - **workspace scope:** notes for one workspace (a folder on one machine), shared by every
     session in that workspace.
7. **No global, and no project or conversation access, for agents at all.** Agents can't read or
   write personal (global) memory, project memory or conversation memory. Enforce this server-side
   by the caller's kind (a machine/agent call), not only by omitting a parameter.
   - Workspace and session notes are visible to the owner in the code panel: a small notes list per
     session or workspace, editable and deletable.
   - Delete session notes with the session, and workspace notes when the workspace is removed.
8. **Agent notes are untrusted input.** An agent reading untrusted code may write anything. Notes
   are shown as notes, never as instructions with authority, and the chat never reads agent notes.

### Docs

`docs/` user docs for memory: the scopes, what agents can and cannot do, and how to see and delete
notes. AGENTS.md / docs/dev pointer. `kit/CHANGELOG.md` Unreleased bullets. ADR-worthy? Add a short
ADR in `ai-stack/docs/adr/` only if the design departs from the existing memory model; otherwise a
docs/dev page is enough.

## Tests

- Scope selection and the global-only-when-explicit rule (tool description plus server validation
  where possible).
- Conversation notes are injected and deleted with the conversation.
- Agent calls can never touch global, project or conversation scopes (server-side refusal).
- Session and workspace isolation across users and machines.
- The galopin MCP tool round trip (Go tests, plus Cerea specs).
- Component tests for the notes UI.

## Delivery

Worktree `../Cerea-wt-memory` on `feat/scoped-memory` from origin/main. Focused commits. A PR whose
body ends with "🤖 Generated with [Claude Code](https://claude.com/claude-code)". Wait for CI and
fix failures at the cause. Do not merge. Report the design (where each scope lives, the
enforcement), files, tests and CI.

## Owner additions (2026-11-13)

- The notes UI lives in the chat's **side panel** (with artifacts/files), not in the header or composer.
- **Cache friendly, hard requirement:** notes never in the system prompt or cached prefix; the notes block is injected in the uncached tail just before the newest user message; deterministic rendering (stable order, no timestamps); capped; agents pull notes via MCP calls (no injection), tool list static. Test: identical bytes for unchanged notes; editing a note changes only the tail.
