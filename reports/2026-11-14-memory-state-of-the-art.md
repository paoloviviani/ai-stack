# Memory for LLM assistants and agents: state of the art, November 2026

Prepared for Cerea scoped memory. Confidence: [P] primary source read, [S] secondary or vendor-reported, [?] uncertain or conflicting. OpenAI's help pages returned 403, so ChatGPT details lean on search snippets and reverse-engineering write-ups.

## 1. Product memory

**ChatGPT.** Two layers: explicit "saved memories" and "reference chat history" ([OpenAI help](https://help.openai.com/en/articles/8590148-memory-faq) [S, snippet only]). Deleting a chat does not delete a saved memory. Projects can be "project-only" (chats see only that project's chats, and the reverse); shared projects are always project-only [S, third-party guides]. Reverse-engineering ([Gupta](https://manthanguptaa.in/posts/chatgpt_memory), [overview](https://llmrefs.com/blog/reverse-engineering-chatgpt-memory)) found no vector search: session metadata, a block of user facts, a digest of recent chats (user messages only) and the live window are all injected up front [S, prompting experiments, may be stale]. Newer "Dreaming" and 2026 variants are unconfirmed [?].

**Claude (consumer).** A memory summary of the user's work context, viewable and editable in settings; each project gets its own separate memory; incognito chats neither save nor read it; admins can disable it. Anthropic reports testing for harmful reinforcement and over-accommodation ([claude.com/blog/memory](https://claude.com/blog/memory) [P]).

**Claude API.**
- *Memory tool*: client-side file directory under `/memories`. The API injects a "view your memory first, assume interruption" protocol into the system prompt. The app owns storage and must block path traversal ([docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool) [P]). This is search-style, not always-injected.
- *Context editing*: clears old tool results or thinking blocks.
- *Compaction*: server-side summary of older turns; on-demand and threshold variants, recent turns can be kept verbatim ([docs](https://platform.claude.com/docs/en/build-with-claude/compaction) [P]). Anthropic positions memory as "what must survive summarization".

**Gemini.** "Past chats" was renamed "Memory" on 2026-03-26; on by default, needs Keep Activity; "Personal Intelligence" is a separate opt-in layer over Gmail, Photos and so on; import from other assistants exists ([overview](https://www.ai-toolbox.co/gemini-management-and-productivity/gemini-memory-saved-info-2026), [9to5Google](https://9to5google.com/2026/02/26/gemini-past-chats-free/)) [S].

**Microsoft 365 Copilot.** Saved memories (user-confirmed), inferred chat details and custom instructions, stored in a hidden Exchange mailbox folder; admins can switch off "enhanced personalization"; turning memory off does not delete; reportedly discoverable via Purview ([MS Learn](https://learn.microsoft.com/copilot/microsoft-365/copilot-personalization-memory), [support](https://support.microsoft.com/en-US/Microsoft-365-Copilot/manage-copilot-memory-in-microsoft-365-copilot)) [P/S].

**Perplexity.** Stored preferences plus past searches; memories cited in answer sources; incognito never stored; enterprise Spaces do not use memories ([help mirror](https://intercom.help/perplexity-ai/en/articles/10968016-memory)) [S, mirror].

**Known issues.** [PersistBench](https://arxiv.org/html/2602.01146) (Feb 2026) reports cross-domain leakage and memory-induced sycophancy, with most models failing sycophancy cases and prompt constraints insufficient [S, abstract only]. [MemSyco-Bench](https://arxiv.org/abs/2607.01071) finds systems often pick stale or mixed memories. A gating router recovers most accuracy ([2610.07403](https://alphaxiv.org/abs/2610.07403v1)) [S]. Privacy: memories outlive source chats in ChatGPT and Copilot.

## 2. Frameworks and research

| System | Idea | Notes |
|---|---|---|
| Letta/MemGPT | Always-in-context labelled blocks the agent edits, plus archival store; sleep-time agents rewrite memory in the background ([blocks](https://docs.letta.com/guides/agents/memory-blocks) [P], [sleep-time](https://letta.com/blog/sleep-time-compute) [S]) | Shared blocks are last-write-wins |
| mem0 | LLM extraction of facts, vector (+graph) retrieval | Claims large latency/token savings vs full context ([paper](https://arxiv.org/abs/2504.19413)); benchmark numbers disputed |
| Zep/Graphiti | Temporal knowledge graph with validity times | DMR 94.8%, LongMemEval up to +18.5% over baseline, self-reported ([paper](https://arxiv.org/abs/2501.13956)) |
| A-MEM | Self-linking Zettelkasten notes | Links rely on embedding similarity [S] |
| cognee | Ontology-constrained graph pipeline | [S] |
| LangMem | Memory primitives, no fixed backend | [S] |

**Benchmarks.** LoCoMo, LongMemEval and BEAM are the usual ones. Vendor scores are not comparable: Mem0 reports about 92% on both (2026), Zep about 71% on LongMemEval, and an independent run put OSS Mem0 at 32% [S] ([survey](https://mem0.ai/library/agent-memory/ai-memory-benchmarks-in-2026), [dev.to](https://dev.to/everest_an/-i-benchmarked-ai-agent-memory-in-2026-and-the-numbers-tell-a-different-story-than-the-marketing-2ae4)). The only same-setup comparison I found ([User as Code](https://arxiv.org/pdf/2606.16707)) has full-context at 79.8% on LoCoMo and 85.4% on LongMemEval, at or above every memory system tested [S, single paper].

**What works.** Plain files plus grep: Letta's filesystem agent got 74% on LoCoMo with gpt-4o-mini, above Mem0's then-reported 68.5% ([Letta](https://www.letta.com/blog/benchmarking-ai-agent-memory), vendor claim). Small always-visible blocks; background consolidation; temporal validity for changing facts.
**What doesn't, or is unproven.** Extraction pipelines losing detail; graph gains of about 2% (Mem0's own number); stale-vs-new memory conflict; benchmarks that measure retrieval rather than memory management.

## 3. Coding agents

| Agent | Persistent memory | Compaction |
|---|---|---|
| Claude Code | CLAUDE.md at managed/user/project scope, path-scoped rules, `@` imports (max 4 hops); auto memory the model writes, first 200 lines or 25KB loaded each session; both are "context, not enforcement", hooks enforce ([docs](https://code.claude.com/docs/en/memory) [P]) | Auto-compact; behavior for CLAUDE.md after compaction not verified here [?] |
| Codex | Off by default; background-generated summary files under `~/.codex`, injected when enabled, per-chat toggles, secrets redacted, skipped for tool-assisted chats; team rules belong in AGENTS.md ([docs](https://learn.chatgpt.com/docs/customization/memories?surface=app) [P]) | not covered |
| Cursor | Memories UI removed in 2.1 (Nov 2025); export to Rules; conflicting staff statements ([forum](https://forum.cursor.com/t/memory-tool-dissapeared/148405)) [S]. A forum report says continual-learning wrote personal memory into tracked AGENTS.md [S] | not covered |
| opencode | AGENTS.md then CLAUDE.md, project + global, `instructions` globs/URLs ([docs](https://opencode.ai/docs/rules/) [P]) | `compaction.auto`/`prune` flags, pruning old tool output before summarizing [S] ([thread](https://forums.basehub.com/anomalyco/opencode/20)) |
| Aider | CONVENTIONS.md via `--read`, read-only and cached when caching is on ([docs](https://aider.chat/docs/usage/conventions.html)) [S] | not verified |
| goose | not verified (docs URL 404; search found nothing) [?] | not verified |

Pattern: hand-written instruction files are the portable layer (AGENTS.md); model-written memory is secondary, per-machine, and opt-in or recently trimmed.

## 4. Memory and prompt caching

Anthropic's cache prefix order is tools, then system, then messages; any change invalidates that level and all later ones; hits need exact match; default TTL 5 minutes, 1 hour optional; up to 4 breakpoints; put the breakpoint on the last block identical across requests, not one with per-request content ([docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) [P]). Context editing's tool-result clearing invalidates the prefix and offers `clear_at_least` to skip clearing when the saving would not repay the cache rewrite ([docs](https://platform.claude.com/docs/en/build-with-claude/context-editing) [P]).

Vendor placement, as observed: ChatGPT injects memory blocks up front [S]; Claude Code loads CLAUDE.md and the memory index at session start [P]; Codex injects at session start [P]; the Claude memory tool is pulled in via tool results mid-conversation, so the prefix never changes [P]. Nobody documents a per-turn memory rewrite of the system prompt. Stable-prefix patterns that follow: (a) snapshot memory at session start and freeze it for the session; (b) write new entries to a store and surface them in the turn (tool result or message), not the system prompt; (c) rebuild the summary only on a threshold or at idle; (d) order stable then volatile; (e) a marker or breakpoint after the memory block.

## 5. Security

- Rehberger's SpAIware (2024): indirect injection wrote persistent instructions into ChatGPT memory, giving ongoing exfiltration; OpenAI blocked the link-following vector, and memory writes from untrusted content remain open ([TechRadar](https://www.techradar.com/pro/hacker-creates-false-memories-in-chatgpt-to-steal-victim-data-but-it-might-not-be-as-bad-as-it-sounds)) [S].
- 2025-26 reports: LayerX on Atlas, Radware "ZombieAgent" [S, secondary; check originals].
- Research: [sleeper memory poisoning](https://arxiv.org/abs/2605.15338) (very high write rates, 60-89% attacker-intended actions when recalled) and [MPBench](https://arxiv.org/abs/2606.04329) (about 50% average attack success; more aggressive memory read/write means more exposure) [S, preprints, self-reported].
- Mitigations seen: Codex skips memory generation for chats that used MCP or web search and redacts secrets [P]; Claude Code asks approval for external imports and says to use hooks for enforcement [P]; Anthropic's memory-tool docs require path validation, size caps, expiry and sensitive-data stripping [P]; user-visible review, edit and delete; provenance and gating routers (research, [S]).

## What this means for Cerea's design

**Agree.**
- Summaries in the system prompt for global and project memory, with a stable prefix. This matches Claude Code, Codex and ChatGPT.
- Not re-injecting an entry in the chat that created it. The text is already in the conversation, and the prefix stays byte-identical.
- Project-scoped separation, which matches Claude and ChatGPT. No global memory for agents is sensible given the cross-context leakage findings.
- Conversation notes living in the turn.

**Disagree or caution.**
1. *Summaries drift the prefix.* Every edit to a global or project summary breaks the cache for every other chat. Snapshot per chat at its first turn and refresh only on new chats or after compaction. Late edits then appear only in the creating chat, which your rule already covers.
2. *"Survive compaction" needs a mechanism, not a hope.* Anthropic's own advice is memory outside the summary. Store notes as structured records and re-attach them after compaction or trimming. Do not rely on the summarizer to keep them.
3. *Summaries alone lose detail.* The evidence favours files plus search over lossy extraction. Keep entries as discrete rows with a human-readable summary rendered on top, plus a search or read tool for the long tail.
4. *Writes from untrusted content.* Agent session and workspace notes written after reading web pages, tool output or repo files are the poisoning path. See below.

**Ideas worth borrowing.**
1. **Provenance and trust tags on every entry** (user-typed, model-written, from tool or web context), shown in the UI, with model-written entries rendered as data, not instructions. Block or require confirmation for writes in turns that touched untrusted content, as Codex does. Effort: 3-5 days.
2. **Per-chat memory toggle** plus incognito, like Claude and Codex `/memories`. Effort: 1-2 days.
3. **Freeze-and-refresh summary snapshots** with a threshold trigger, and an `at_least`-style rule (rebuild only if it saves enough). Effort: 2-3 days.
4. **Workspace memory as an AGENTS.md-compatible file** in the repo (opencode and Codex already read it), with session notes kept machine-local. Effort: 2-4 days.
5. **Background consolidation at idle** (Letta sleep-time, Codex) to dedupe and drop stale entries, with a size cap and expiry. Effort: about 1 week; do it last.

Uncertainties: ChatGPT internals, Cursor status, goose and Aider specifics, and all benchmark figures are secondary or self-reported. Verify before citing externally.
