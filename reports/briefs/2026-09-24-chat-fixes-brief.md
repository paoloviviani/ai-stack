# Brief: three small Cerea chat fixes (chat side only)

You're working in Cerea (SvelteKit, TypeScript). Your worktree is `/home/ubuntu/.paseo/worktrees/chatfix-cerea` on branch `fix/chat-steps`, cut from `origin/main`, with node_modules already symlinked. This is **chat-side only**: Cerea's normal chat, its artifact prompt, its tool loop and its markdown export. Don't touch `/code`, `agent/`, `src/lib/server/code/` or the machine protocol.

## Background
In a live conversation (glm-5.3-flash), the model drafted an artifact inside its `<think>` reasoning. It announced "here it is", then ended the step with an `ask_user_question` call instead of emitting the artifact. It did this five times in one message. The question-tool description is already fixed on `main` (never to confirm, and deliver first). These fixes are the rest.

## 1. The artifact instruction vs the tool loop (investigate, implement the cheap part, report)
`src/lib/server/textGeneration/artifacts.ts:52` says: "Do not call tools while creating or editing an artifact…".
- Find how the artifacts prompt and the tool preprompt (`builtinTools/*`, the `runMcpFlow` system-message assembly) are composed and ordered, and where each sits relative to the tool list.
- **Implement:** when tools are offered, the artifact/tool rule also sits next to the tool guidance, so the model sees both together. Keep it one short sentence. The ML Assistant system message has a hard 32 000-char ceiling test (`src/lib/server/mlAssistantPrompt.spec.ts`, "stays under the ceiling"); stay under it and don't raise it.
- **Assess only, don't build:** is there a cheap guard for "this step's answer text announces an artifact (e.g. 'here it is', 'here's the artifact'), contains no `<artifact` outside `<think>`, and ends in a tool call"? Report what's feasible, with file/line pointers.

## 2. Separate multi-step text
When a turn spans several tool-loop steps, their text segments are concatenated with no separator in the UI and in the export, e.g. "…play with trails.That one's on me…".
- Insert a paragraph break (`\n\n`) between consecutive steps' text segments.
- Do it where the steps are joined (find it in the text-generation / `runMcpFlow` stream handling, or wherever `message.content` accumulates across steps), so the UI and the export both get it.
- Don't add a break when a segment is empty, or when the text already ends with a newline pair.
- Must hold: streaming still renders incrementally, and no double breaks.

## 3. The export's tool count
`src/lib/utils/exportConversationMarkdown.ts` (~line 183) prints `_Called N tool(s): …_` from `collectToolNames`. For 5 calls of `ask_user_question` it says "Called 1 tool". Count the calls, not unique names, and list the names with multiplicity (e.g. `` `ask_user_question` ×5 ``). Also check `src/lib/components/chat/ToolCallsSummary.svelte`, which shows "Called N tools" in the UI, for the same bug.

## Tests (required)
- vitest for 1: the prompt text/placement (the artifact rule appears alongside the tool guidance when tools are offered), plus the ceiling test still green.
- vitest for 2: the step-separator logic (a unit test on the join function), including empty segments and existing newlines.
- vitest for 3: `exportConversationMarkdown.spec.ts` with 5 calls of one tool, plus a mixed case; and `ToolCallsSummary.svelte.test.ts` if you change it.
- Run with a real Mongo: `TEST_MONGODB_URL=mongodb://127.0.0.1:8792/ npx vitest run --no-file-parallelism <files>`. Don't use `MONGODB_URL`, and don't use mongodb-memory-server; it SIGILLs on this box.
- `npm run check` must be 0 errors / 0 warnings, and `npm run lint` clean.
- No Playwright is required for these. If you do run any, see the box rules.

## Box rules (mandatory)
- Wrap every heavy command (`npm run build`, `npm run check`, Playwright, a large vitest run) in `flock /tmp/heavy.lock …`. The box OOMs when builds run in parallel.
- Use private ports only if you start servers: E2E_APP_PORT 5311, MOCK_OPENAI_PORT 18811, MOCK_OIDC_PORT 18812, MOCK_MCP_PORT 18813, E2E_MONGO_PORT 8792. Never use 5199. Kill only the servers you started, by their recorded PID; never `pkill -f` with a pattern.
- Never run `ruff format`. Prettier runs through `npm run lint`; to fix formatting, run `npx prettier --write <file>` on files you touched.
- Cite ADRs by number only, never by link. Adding any dependency that isn't OSI-licensed needs the user's approval, so don't add dependencies without asking.
- No commit subjects starting "WIP:". Commit with descriptive messages ending with the line `Co-Authored-By: Muse Spark <noreply@opencode.ai>`. Push the branch (`git push -u origin fix/chat-steps`). Don't merge to `main`: the orchestrator reviews and merges.
- Never deploy, and never touch the `llm-platform-*` containers or `/home/ubuntu/test/`.
- Delete `build/` and `test-results/` before finishing.
- If a capability is missing (a tool you can't run, a permission), stop and report it; don't work around it.

## Report
Reply with: the commits, what you changed per item, the item-1 feasibility assessment, the test results (commands plus pass counts), and anything you left undone.
