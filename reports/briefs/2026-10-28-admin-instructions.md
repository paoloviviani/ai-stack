# Brief: an admin-editable instructions prompt for every chat (Cerea, next release)

## What the owner wants (decided 2026-10-28)
Administrators can write one deployment-wide set of instructions that every chat's assistant follows.
- **One prompt** for the whole deployment. Not per group, not per model.
- **Chat only.** The coding agents on people's machines (the `/code` panel, galopin and opencode) are unaffected.
- **The admin chooses whether people can see it:** a switch, "Show these instructions to people" (default **on**). When it's on, people see the text read-only in Settings. When it's off, it isn't shown or sent to the browser for non-admins, and the settings page says nothing about it.

Today there's no admin-level prompt. People have their own global system prompt (`Settings.globalSystemPrompt`, applied in `textGeneration/userPrompts.ts` and `resolvePreprompt`), and custom models have theirs. Admin per-model prompts were removed earlier (`dropPerModelPrompts.ts`); don't bring them back.

## What to build (branch `feat/admin-instructions` from origin/main)
1. **Storage:** in the existing deployment config store (`collections.config` / `src/lib/server/config.ts`, like the other admin settings such as voice and web search). Find the pattern the existing admin pages use and follow it.
   - Two fields: `instructions` (a string, capped at 4,000 characters, trimmed; empty means none) and `instructionsVisible` (a boolean, default true).
   - Read with the same caching the other config values use, so a turn doesn't add a database round trip; invalidate the cache on save.
2. **Admin page:** Admin → "Assistant instructions" (a new entry beside the other admin pages, in their design language):
   - a textarea with a live character count against the cap, and a one-line explanation: "Added to every chat's instructions, before each person's own. Not used by coding agents.";
   - the visibility switch, with its one-line explanation;
   - save and revert.

   API: an admin-only route (`requireAdmin`), validated with zod.
3. **Applied to chat turns only:**
   - in `resolvePreprompt` (or where the system prompt is assembled for chat turns), the instructions go **first**, before the person's global system prompt, the custom model's prompt, the conversation's preprompt, project context and the rest;
   - they must reach every chat path: the turn route, the parked-turn and tool-approval sweepers that resume turns, nested agents, delegate and research sub-agents (they inherit the chat's system context: check how the person's global prompt reaches them and do the same);
   - not the code panel, not galopin, not title generation.

   The text is stable between turns, so it stays in the cached prompt prefix: put it where the person's global prompt sits today, or earlier, never after per-turn content.
4. **Visibility:**
   - when `instructionsVisible` is true, people see the text read-only in Settings, next to where they edit their own global prompt, labelled "From your administrator";
   - when it's false, the settings payload for non-admins carries neither the text nor its existence;
   - admins always see and edit it in Admin.
5. **Erasure and backups:** it's deployment config, not personal data, so there's nothing to add to `userKeyedCollections`. Make sure the backup or export of the config collection includes it, if such a path exists.
6. **Docs:** `docs/chat-admin.md` (the new page), and the user docs where the personal global prompt is described (how the two combine, and that the admin text may or may not be visible). Strings go in `messages/en.json`, following `docs/writing.md`; run `i18n:pseudo` and `i18n:check`.

## Tests (each fails without its fix)
- **The system prompt of a chat turn:** admin instructions first, then the person's global prompt. Absent when empty.
- **Coverage:** present for a delegate or research sub-agent turn and for a resumed (swept) turn. Absent for title generation and for the code panel path.
- **The admin API:** non-admins are refused, the 4,000-character cap is enforced, and saving invalidates the cache (the next turn uses the new text).
- **Visibility:** with it on, a non-admin's settings data includes the text and Settings shows it read-only. With it off, the data has neither the text nor the field (server test), and Settings doesn't show it (client test).
- **The admin page:** a client test of save, the count and the switch, at 390 px too.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-admin-instructions -b feat/admin-instructions origin/main`. `export TMPDIR=/var/tmp/admin-instr-tmp && mkdir -p $TMPDIR`. Read AGENTS.md first. Mongo-backed tests: use TEST_MONGODB_URL and `--no-file-parallelism` per AGENTS.md.
- `npm ci`, builds and Playwright run under `flock /tmp/heavy.lock`; never wrap a self-locking script in another flock. The Playwright container runs as root: chown back `node_modules`, `src` and `.svelte-kit` with a throwaway container before `npm run check`. If a build runs out of memory, use `NODE_OPTIONS=--max-old-space-size=4096`. Bind to 127.0.0.1, and kill what you start.
- Never git stash, never --no-verify, never force-push, no AI attribution in commits. The repo is public: no private hostnames.
- Checks:
  - `npm run check`, eslint and prettier on the changed files;
  - the server tests for `src/lib/server/textGeneration`, the settings and admin routes, and config;
  - the client tests for the new admin page and the Settings component.
- Screenshots of the admin page and the read-only Settings view, at 1440 and 412 px, dark, in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-28-admin-instructions/`. Look at them yourself.
- Merge origin/main into the branch (merge commit) before CI. Push, run CI once (`gh workflow run ci.yml --ref feat/admin-instructions`), and wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report: where the text sits in the prompt (show a sample assembled system prompt), the paths covered, the fails-without-fix evidence, the screenshots, the CI result, and a changelog line. No sub-agents.
