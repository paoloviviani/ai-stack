# Batch A brief: galopin's commands capability, ops and policy

Worktree: /home/ubuntu/workspace/slash-cerea (branch feat/slash-commands at
df23d0b1: A0 + B done). This batch is galopin-side ONLY: agent/ Go code and
agent/PROTOCOL.md. You implement, you don't redesign; ambiguity → stop and
report.

Plan of record: /home/ubuntu/workspace/ai-stack/reports/2026-09-27-slash-commands-plan-rev1.md §2 (corrections), §3 (security delta), §4 (batch A row), §5 (test checklist), §6 (open items the IT settles) — superseding §2.1, §2.5, §2.6 of the 2026-09-26 plan. Read them fully first. Also read the A0 work you can reuse: agent/internal/backend/opencode/msgid.go (mintMessageID), the overlay's claim-spending pattern, backend/errors.go (the sentinel pattern from ErrSessionBusy).

## What ships

A machine that can list and run slash commands SAFELY, with no UI (batch C
wires the panel to it).

### 1. The `commands` capability, probed not versioned

galopin advertises `commands` in the backend's capabilities only when the
opencode server's own `GET /doc` OpenAPI lists the `session.command`
operation — never from a version string. Find how capabilities are
reported today (the hello/handshake path the panel already reads:
compactSupported, revertSupported etc. in the opencode backend) and add
`commands` the same way, populated by a one-time /doc probe at backend
start (cached; re-probed on supervise restart). ACP: `commands: true`
always (its available_commands_update carries the list per session).

### 2. `backend.commands` op

Args `{backend?, workspaceId?, sessionId?}` → `{commands: Command[]}`.
Command = {name, description?, source: "command"|"mcp"|"skill",
origin: "builtin"|"machine"|"project"|null, hints: string[], agent?,
model?, subtask?: bool, shell: bool|null, shellSnippets?: string[],
fileRefs?: string[], templateHash?: string}.

- opencode: one `GET /command?directory=` for the workspace (from
  workspaceId or the session's workspace), one for galopin's own state dir
  (cached per process). Diff the lists: a name only in the workspace list
  is `project`; `init`/`review` are `builtin`; the rest `machine`. Scan
  each template for `` !`…` `` → shell + shellSnippets (each ≤200 chars,
  max 10); `@path` → fileRefs. templateHash = sha256 of the template.
  THE TEMPLATE ITSELF IS NEVER SENT (the snippets are what a person must
  see). source "mcp" → shell: null (unknown).
- ACP: answers from the last available_commands_update cached for that
  session (empty before the first update); fields hints from input.hint,
  origin null, shell null, no hash. NOTE: events.go currently DROPS
  available_commands_update — map it now.
- Unmapped dispatch: follow how backend.models is dispatched and exposed
  today (the panel calls it the same way).

### 3. `session.command` op

Args `{sessionId, name, arguments, clientMessageId?, attachments?, templateHash?}` → `{}` once accepted; the turn streams as events.

opencode path:
1. Re-list for the session's workspace; unknown name → `not_found`.
2. templateHash given and different → `conflict`.
3. Policy gates (below).
4. Mint a messageID (reuse mintMessageID), record clientMessageId against
   it (the A0 claim pattern) BEFORE the POST.
5. `POST /session/:id/command {command, arguments, messageID, agent?,
   model?: "provider/model" string, variant?, parts?}` — re-read the
   2026-09-26 plan §1.2 for the exact body. This call BLOCKS for the whole
   turn: run it in a goroutine on the long-lived client (the fast CRUD
   client's deadline would cut it); return to the caller immediately;
   a late failure becomes an `error` event on the session.
6. Transcript marker: the user Message gains `command?: {name, arguments}`
   (opencode: from the minted messageID; ACP: set by galopin on the user
   message it creates). Snapshots carry it via the overlay (messageID →
   {name, arguments} next to the other overlay fields).

ACP path: validate the name against the cached list; `invalid` while busy
(the A0 guard); then the existing Prompt path with text `/<name> <arguments>`.

### 4. The `commandShell` policy and the gates

- Machine policy `commandShell: "allowed"|"denied"`, DEFAULT `denied`;
  set by `enroll --allow-command-shell`; a local `galopin policy set` can
  only TIGHTEN it. Reported in hello.policy so the UI can grey rows with
  the reason.
- While denied: `session.command` refuses `shell: true` AND `shell: null`
  (unknown) with `forbidden` — MCP prompts and every ACP command are off
  until opted in; the docs must say so.
- `fileRefs` against the machine's fileDeny list (find it in agent/
  internal/policy) → `forbidden`.
- The command's `model:` frontmatter vs `allowFreeModels` → `forbidden`
  (the same gate setModel applies).
- **NEW (rev1 §3.1) — the agent-escalation gate:** when the session's
  overlay mode is MORE restrictive than the command's `agent:` frontmatter,
  galopin sends the overlay mode and ignores the command's agent. If the
  command is `subtask: true` with a named agent, refuse with `forbidden` —
  it would run unsupervised in the other agent. Determine "more
  restrictive" from the modes the backend lists (plan < build); if the
  backend lists no order, treat any named agent as an escalation while an
  overlay mode is set.
- Audit: the existing audit.log gains `command {name, origin, shell,
  decision}` rows — NEVER arguments, NEVER expanded text.

### 5. PROTOCOL.md §6/§7

The two ops, the Command shape, the capability, the policy field + enroll
flag, the transcript marker, the error codes (not_found, conflict,
forbidden, invalid). This is the contract batch C implements against —
write it as such.

### 6. Tests

- Go unit (fake opencode HTTP server, the effort_test.go pattern):
  GET /command per directory + the exact POST body (string model, agent
  precedence, variant, minted ascending messageID, file parts);
  session.command returns before the POST completes; late failure → error
  event; origin diffing; shell/@ scanning + snippet caps; templateHash
  conflict; every gate (shell denied, shell-null denied, fileDeny ref,
  free-model frontmatter, agent escalation incl. the subtask refusal);
  policy set tightens only.
- ACP: fake agent emits available_commands_update → the list maps; the
  `/name args` prompt text; invalid while busy; unsupported/empty before
  the first update.
- **Live IT (gated GALOPIN_OPENCODE_IT=1, the opencode_it_test.go
  pattern: mock LLM, isolated HOME/XDG, kill by PID, NEVER port 5199):**
  the /doc capability probe on the INSTALLED opencode (report its version
  in the test log — rev1's version reconciliation); list per directory;
  a run with arguments reaches the mock with expanded text; the user
  message carries the command marker; a subtask command spawns a child;
  a shell template runs ONLY with commandShell allowed; an @.env ref is
  refused; a command mid-turn folds into the next step; RECORD whether @
  honours opencode's read permission. acp_it_test.go gains the ACP variant.

## Box + git rules (binding)

- NO sub-agents. Foreground only; heavy commands `timeout -s KILL <secs>
  flock /tmp/heavy.lock <cmd>` (go build/test 1200, the IT longer);
  free -m ≥1500 MB first — the live IT spawns opencode serve; wait if low.
  NEVER leave an opencode serve running: kill by recorded PID.
- The live IT is the ONLY sanctioned opencode-serve probing on this box
  (the OOM lesson — no ad-hoc serve probes outside gated tests).
- Git: configured identity, NO AI trailers, commit per coherent piece.
  Push feat/slash-commands; no merge, no main, no /opt/cerea.

## Report

Design as built (capability probe, both ops, the policy + all gates with
their exact refusal codes, the marker), PROTOCOL.md section list, files,
commits, exact test commands + pass counts (unit + which IT cases ran),
the open items settled (agent precedence, MCP expansion, @ vs read
permission, the installed opencode version), deviations. Then stop for
review.
