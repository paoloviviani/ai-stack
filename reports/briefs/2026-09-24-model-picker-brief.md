# Brief: a model and effort picker in the style of Claude's (chat and /code)

Repo: Cerea. It contains the Go machine agent **galopin** in `agent/`. Worktree: `/home/ubuntu/.paseo/worktrees/picker-cerea`, branch `feat/model-picker`, cut from `origin/main`, with node_modules symlinked.

**The design is decided.** Read it in full first: `/home/ubuntu/workspace/reports/2026-09-24-thin-agent-progress.md`, section "Design: the model picker in the style of Claude's (chat and `/code`)" (around line 411). Implement it as written. The summary:
- **Shared `ModelEffortPicker.svelte`:** anchored to a composer pill reading "<model name> <effort>". The popover has search, a short list (the current model plus recents, about 6, each with a one-line description and a check on the current one), a divider, "Effort ▸ <value>" with a submenu (only when the model supports effort), and "More models ▸", which opens the existing full `ModelPicker` overlay. Callbacks: `onpickModel`/`onpickEffort`. It takes an `efforts: string[] | null` capability. Links use `${base}`.
- **Chat:**
  - The pill replaces `ThinkingEffortChip.svelte` in the composer.
  - Model picks reuse `ModelPicker`'s semantics (PATCH the conversation, or `settings.activeModel` on a new chat).
  - Effort is persisted per conversation (a new optional `Conversation.reasoningEffort`). The user default is `settings.reasoningEffortOverrides[modelId]`; the effective value is conv, else user default, else the model default. It's sent as `reasoning_effort` only when the model `supportsReasoning` (`endpointOai.ts`, `models.ts`).
- **/code:**
  - The model pill shows the real model name (the backend default via `isDefault` when the session has none, never "Model").
  - Effort is its own pill, hidden with no efforts.
  - Protocol: `Model.efforts?: string[]` (the opencode variant ids from `/config/providers`), `Session.effort?`, and a new op `session.setEffort {sessionId, effort|null}`. It's stored in galopin's session overlay and sent as `variant` on every `prompt_async`, like mode and model. The capability is advertised per backend as `efforts`; ACP reports none.
  - Update `agent/PROTOCOL.md` and `src/lib/types/machineProtocol.ts`.
  - `galopin enroll` writes `variants` (`low`/`medium`/`high`, each mapping to opencode's `reasoningEffort` option) for gateway models marked reasoning-capable. Check the opencode config schema for the exact shape against the installed opencode (1.18.31/32).

## Tests (required)
- **vitest:** search filtering, the short-list composition, the effort capability (hidden with none, levels otherwise), and the chat effective-effort resolution.
- **Go:** `session.setEffort` stored and sent as `variant`, `efforts` in the model list, and enroll writing variants.
- **Playwright:**
  - chat pill: pick a model, pick an effort, and the mock request carries `reasoning_effort`;
  - `/code` pills: the real model name, and the effort pill hidden or shown;
  - the real-machine parity spec: picking "high" makes opencode's request to the mock LLM carry the variant's `reasoning_effort`.

  At root and under `/chat`.
- `npm run check` 0/0, and `npm run lint` clean.

**How to run Playwright:**
1. Build alone: `flock /tmp/heavy.lock npm run build`, or `APP_BASE=/chat flock /tmp/heavy.lock npm run build`.
2. Then: `E2E_SKIP_BUILD=1 E2E_APP_PORT=5351 E2E_MONGO_PORT=8799 MOCK_OPENAI_PORT=18851 MOCK_OIDC_PORT=18852 MOCK_MCP_PORT=18853 flock /tmp/heavy.lock npx playwright test <specs> --project=chromium --reporter=line`. Add `E2E_APP_BASE=/chat` for `/chat`.

WebKit is not installed: always `--project=chromium`. vitest runs: `TEST_MONGODB_URL=mongodb://127.0.0.1:8799/ npx vitest run --no-file-parallelism <files>`.

## Box rules (mandatory)
- Wrap every heavy command in `flock /tmp/heavy.lock …`. The box OOMs otherwise.
- Use only the private ports above. Never use 5199. Kill only what you started, by recorded PID; never `pkill -f` with a pattern.
- Never run `ruff format`. Use `npx prettier --write` on the files you touched, and gofmt for Go.
- Cite ADRs by number only. Don't add dependencies without asking (a non-OSI dependency needs approval).
- No "WIP:" commit subjects. Commit messages should be descriptive and end with `Co-Authored-By: Muse Spark <noreply@opencode.ai>`. Push the branch; don't merge to `main`.
- Never deploy, and never touch the `llm-platform-*` containers or `/home/ubuntu/test/`.
- Delete `build/` and `test-results/` when done.
- If a capability is missing, stop and report it.

## Report
Reply with: the commits, the design as built (any deviation, and why), test results with commands and pass counts at root and under `/chat`, and anything left undone.
