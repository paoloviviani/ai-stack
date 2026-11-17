# Brief: every file produced in a conversation's sandbox is a persisted file artifact

Repo: Cerea, plus one ADR amendment in ai-stack (see below). The orchestrator gives you the worktree, branch, base SHA, ports and Mongo in the launch message. Run `npm ci` first.

## The decision (the user's words)
"The point is not how the file is created, the point is visualization. Can we present any produced file as an artifact? With consistent visualization and retention rules?"

## The gap (found live)
"Create a hello world docx" makes the model write an **auto-running Python code block**, which is what our execution prompt tells it to do for files. That block's output files are **session-only**:
- the deliverables persistence (`src/lib/server/execution/deliverables.ts`) is deliberately wired only into the `execute_code` tool path (`builtinTools/executeCodeTool.ts`);
- so those files are never persisted, never become file artifacts (`collectFileArtifacts` in `src/lib/utils/fileArtifacts.ts` derives only from persisted `execute_code` outputs), and are gone on reload.

Read how both paths run today before designing: the execute_code tool, an auto-running chat code block, a manual Run of a block, and an artifact cell. Look at the browser sandbox runtime (`src/lib/utils/execution/`), `RunState.outputFiles`, the code-execution routes under `src/routes/conversation/[id]/code-execution/`, `deliverables.ts`, and the `codeExecutionOutputs` store.

## Target: one rule, whichever path produced the file
**Retention (one rule):**
- every file a run lists as output (`RunState.outputFiles`) is uploaded through the same `deliverables.ts` path: the same per-user store, the same content addressing (sha256), the same caps (per-file size, per-conversation count and total bytes) and the same 30-day TTL;
- downloads stay owner-only (`authCondition`), as now;
- uploads are **idempotent per run**, so a re-render, a replay or a reload never re-uploads (key on run id + sha256, or equivalent).

**Visualization (one path):**
- every persisted file is a file artifact, derived by `collectFileArtifacts` from **one persisted record type**, regardless of the source path. Unify the record if the paths store different shapes today; keep existing execute_code data readable;
- the same `FileArtifactView` and `filePreview.ts` rules: PDF in its frame with the 8 MB cap on the actual bytes, DOCX via docx-preview with DOMPurify, text and image inline, otherwise a download card;
- filename = identifier; a new run = a new version; a byte-identical file adds nothing;
- the inline FileCard under a run and the artifact panel show the same thing;
- the sidebar library row opens the artifact.

**Reload and other devices:** a code block's files survive a reload and appear on another device, exactly like execute_code's.

**Security (no new trust):**
- in both paths the bytes come from the owner's own browser sandbox. Keep the upload route's ownership check (the conversation must be the caller's), the size and count caps, and MIME sniffing as today;
- **a shared-conversation viewer's browser must never upload into the owner's store:** only the owner uploads. Enforce it server-side (the ownership check), not only in the UI;
- share-viewer downloads stay owner-only (user decision; don't change it).

**Prompt:** keep the code-block guidance as it is, since the path no longer matters. Make sure the execution prompt no longer implies code-block files are temporary. Adjust `executionPrompt.spec.ts` if it pins that wording.

**Out of scope:** files from MCP tools, and user attachments. Report whether any MCP-produced file path exists today; don't build one.

## ADR amendment (in ai-stack)
ADR 0073's "Amendment (2026-09-16): computed deliverables persist per-user, 30 days" states a conservative rule: only deliverables from execute_code persist, and scratch output stays session-only. This widens it by user decision.
- Add a new amendment section, dated 2026-09-26, at the end of `/home/ubuntu/workspace/ai-stack/docs/adr/0073-the-browser-runs-python-the-model-heals-the-rest.md`: every file a run in the conversation's sandbox lists as output persists under the same rule, whatever the path; the reason is consistent visualization and retention; the security and caps are unchanged.
- Cite ADRs by number only, never by link.
- **Edit the file but don't commit in ai-stack;** the orchestrator commits it.

## Tests
- **vitest:** the one record type and the deriver (every source path yields the same artifact; version on re-run; a byte-identical file adds nothing); upload idempotency.
- **A route test:** a non-owner (another user, or a share viewer) can neither upload into nor download from the owner's conversation.
- **Playwright,** at root AND under `E2E_APP_BASE=/chat`:
  - "create a docx" via an auto-running code block → the file artifact appears, a reload keeps it, and the sidebar library opens it;
  - the same flow via execute_code (the existing spec, `tests/chat-artifact-files.spec.ts`, should keep passing);
  - dedupe on a re-run.
- `npm run check` (0 errors); eslint and prettier on the changed files. Then the touched specs at both bases, and the whole suite once at each base, after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`.

## Box rules (mandatory)
- `timeout -s KILL <secs> flock /tmp/heavy.lock …` in the foreground, with the `E2E_*` and `TEST_MONGODB_URL` exports on the same line.
- If `free -m` shows under 1.5 GB available, wait; pause when told.
- Kill only your own processes, by PID. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199. Nothing in `/tmp`.
- No sub-agents, no deploy, no live checks.
- Don't touch sign-in, OIDC or user identity.
- No new dependencies without asking (Apache-2.0).
- **Commits (Cerea):** as Paolo Viviani from git config (never override it), with no `Co-Authored-By` trailer. Before pushing, `git fetch` and check that `git log origin/main..HEAD` lists only your commits. Push the branch; don't merge.
- **The disk is tight:** when done, delete the worktree's `build/`, `test-results/` and `playwright-report/`.

## Report
Reply with:
- the design (the record type, where uploads now happen, idempotency);
- the MCP finding;
- the commits;
- the ADR amendment text;
- the test commands and pass counts at both bases;
- anything left undone.
