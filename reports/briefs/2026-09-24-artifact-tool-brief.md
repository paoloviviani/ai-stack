# Brief: tool-based artifacts in Cerea chat (inline tags kept as fallback)

Repo: Cerea (SvelteKit, TypeScript). Worktree: `/home/ubuntu/.paseo/worktrees/artifact-cerea`, branch `feat/artifact-tool`, cut from `origin/main`, with node_modules symlinked.

**Scope: CHAT SIDE ONLY.** That means Cerea's normal chat, its artifact side panel, its builtin-tool loop (`src/lib/server/textGeneration/`), and its markdown export. Do NOT touch `/code`, `agent/`, `src/lib/server/code/`, `src/lib/components/code/` or the machine protocol.

**The design is decided.** Read it in full first: `/home/ubuntu/workspace/reports/2026-09-24-thin-agent-progress.md`, section "Tool-based artifacts: design (2026-09-24, chat side only)", plus the section above it, "Tool-based artifacts (user decision…)". Implement it as written. Key points:
- **One builtin tool `artifact`** (see `src/lib/server/textGeneration/builtinTools/` for how builtins are defined, gated and given a preprompt, e.g. `askUserQuestion.ts`, `index.ts`, `types.ts`). Its `command` is one of:
  - `create {identifier, type: html|react|svg|mermaid|markdown|code, language?, title, content}`;
  - `update {identifier, old_str, new_str, title?}`;
  - `rewrite {identifier, content, title?}`.
- **Execution writes a canonical inline block into the assistant message's content**, so the existing client parser (`src/lib/utils/artifacts.ts`, `buildArtifactRegistry`), the panel, version history and export all work unchanged:
  - `create`/`rewrite` → `<artifact identifier="…" type="…" title="…"[ language="…"]>content</artifact>`;
  - `update` → `<artifact identifier="…" type="update"[ title="…"]><old_str>…</old_str><new_str>…</new_str></artifact>`.

  Resolve the latest version server-side by running the same shared parser over the conversation's earlier assistant messages (it already strips `<think>`).
  - `update`: `old_str` must occur **exactly once** in the latest version. For 0 or more than 1 matches, return an error result the model can act on (the count, "copy old_str verbatim from the latest version, or use rewrite"), and append nothing.
  - `create` on an existing identifier → error (use rewrite/update). `rewrite`/`update` on an unknown one → error (use create). Content containing a literal `</artifact>` → error.
  - The result is short, never echoing content: `created <id> v1 (<type>)`, `updated <id> → v<n>`, `rewrote <id> → v<n>`.
  - The tool must not park the turn; see the `exemptFromToolRestraint`/`mayPark` fields.

  Find how a builtin tool's execution can append to the current assistant message's content (it may need a new MessageUpdate, or a Stream update carrying the block). Pick the least invasive path, and explain it in the report.
- **Streaming preview.** In `src/lib/server/textGeneration/mcp/runMcpFlow.ts` (~line 885), tool-call arguments stream in and accumulate in `toolCallState`. When an index's name is `artifact` and the command is create/rewrite, extract the partial `content` string with a small incremental JSON-string decoder (handle escapes, including a chunk cut mid-escape or mid-`\u` sequence) and emit a throttled (~250 ms) new update, e.g. `ArtifactDraft {toolCallId, identifier?, type?, title?, content}`. The client shows it in the panel as a streaming block (the parser already supports unterminated, growing blocks), and the final canonical block replaces it. For `update`, show a placeholder ("Editing ‹title›…"). With no streamed args, show "Writing…" until the call completes.
- **Gating.** A new per-model `artifactsMode: "tool" | "tags"` (see `src/lib/server/models.ts`, where `supportsArtifacts`/`supportsTools` live), defaulting to `"tool"` when both `supportsArtifacts` and `supportsTools` are set, else `"tags"`. There's a shared `artifactsEnabledForTurn` in `src/lib/server/textGeneration/artifacts.ts`; extend alongside it (e.g. an `artifactsModeForTurn`). The ML Assistant preset force-enables artifacts; tool mode applies there too when the model supports tools.
- **Prompting.**
  - In tool mode, `ARTIFACTS_SYSTEM_PROMPT` (`artifacts.ts`) is NOT injected. Instead, the tool description carries: when to make an artifact; the types; the sandbox allow/block list (copy that paragraph); "deliver first, never follow with `ask_user_question` in the same step"; and "earlier artifacts appear in the conversation as `<artifact>` blocks; change them with update/rewrite, never by writing tags".
  - The `ARTIFACT_TOOL_RULE` next to the tool guidance (`utils/toolPrompt.ts`) is for tags mode. In tool mode, replace it with a one-line pointer to the tool, or drop it.
  - The ML-preset 32 000-char system-message ceiling test (`src/lib/server/mlAssistantPrompt.spec.ts`) must stay green; don't raise it.
- **Fallback.** The inline parser stays: for old conversations, tags mode, and a tool-mode model that emits tags anyway (still rendered). Never parse inside `<think>`; this already works, so add tests.
- **MCP UI resources:** design only, not built. Leave a clear seam, the same "append canonical block" function, and note it in the report.
- **Security.** The same sandboxed iframe and CSP (`src/lib/utils/previewSrcdoc.ts` etc.), with no new capability.

## Tests (required)
- **vitest:**
  - the tool schema per command;
  - `update` with 0, 1 and 2 matches (only exactly one appends);
  - create-on-existing and rewrite/update-on-unknown errors;
  - the `</artifact>` rejection;
  - version numbering across messages;
  - the gating (default `artifactsMode`; the prompt drops the tag grammar in tool mode and keeps it in tags mode);
  - the partial-JSON content decoder (escapes, cuts mid-escape, `\u`);
  - the parser fallback: tags outside `<think>` render, and inside they don't.

  Run: `TEST_MONGODB_URL=mongodb://127.0.0.1:8792/ npx vitest run --no-file-parallelism <files>`.
- **e2e** with `tests/mock-openai.ts` (scenarios with `toolCalls`, `chunkDelayMs`; see `tests/chat-ask-question.spec.ts` for the pattern). A new spec, `tests/chat-artifact-tool.spec.ts`:
  1. create, update and rewrite in three turns render in the panel as v1→v3, with history navigation;
  2. a streamed-arguments draft is visible before the call completes (use a slow `chunkDelayMs`; check whether mock-openai streams tool-call arguments in chunks, and extend it if not);
  3. a tags-mode model's inline `<artifact>` still renders;
  4. tags inside `<think>` are ignored.

  Run at root and under `/chat`. Add the model config for the test models where the e2e config defines models (`playwright.config.ts` env / the mock's `/v1/models` fixture).
- `npm run check` 0/0, and `npm run lint` clean.

**How to run Playwright:**
1. Build alone: `flock /tmp/heavy.lock npm run build`, or `APP_BASE=/chat flock /tmp/heavy.lock npm run build`.
2. Then: `E2E_SKIP_BUILD=1 E2E_APP_PORT=5361 E2E_MONGO_PORT=8792 MOCK_OPENAI_PORT=18861 MOCK_OIDC_PORT=18862 MOCK_MCP_PORT=18863 flock /tmp/heavy.lock npx playwright test tests/chat-artifact-tool.spec.ts tests/chat-ask-question.spec.ts tests/smoke.spec.ts --project=chromium --reporter=line`. Add `E2E_APP_BASE=/chat` for `/chat`.

WebKit is not installed: always `--project=chromium`, and never install browsers.

## Box rules (mandatory)
- Wrap every heavy command (build, check, Playwright, large vitest runs) in `flock /tmp/heavy.lock …`. The box OOMs otherwise.
- Use only the private ports above. Never use 5199. Kill only what you started, by recorded PID; never `pkill -f` with a pattern.
- Never run `ruff format`. Use `npx prettier --write` on the files you touched.
- Cite ADRs by number only. Don't add dependencies without asking (a non-OSI dependency needs approval).
- No "WIP:" commit subjects. Commit messages should be descriptive and end with `Co-Authored-By: Muse Spark <noreply@opencode.ai>`. Push the branch; don't merge to `main`.
- Never deploy, and never touch the `llm-platform-*` containers or `/home/ubuntu/test/`.
- Delete `build/` and `test-results/` when done.
- If a capability is missing, stop and report it.

## Report
Reply with: the commits, how execution appends to the message (the path chosen, and why), the gating as built, what the gateway and mock do with streamed tool arguments, the MCP-UI seam, test results with commands and pass counts at root and under `/chat`, and anything left undone.
