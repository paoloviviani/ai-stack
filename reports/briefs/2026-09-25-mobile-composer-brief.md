# Brief: a one-row compact composer toolbar on mobile (/code and chat)

Repo: Cerea. Worktree `/home/ubuntu/.paseo/worktrees/mobile-composer-cerea`, branch `fix/mobile-composer`, already cut from `origin/main` (`980a5fe1`). Run `npm ci` first.

## The problem (live, Android, about 390 CSS px wide, the /code composer)
Under the text, the composer takes THREE rows:
1. the "+" attach button alone;
2. the pills `build ⌄`, `glm-5.3-flash ⌄` and `🛡 Auto-accept`, which wrap;
3. the context ring "20.2k" and the send button on their own row.

The user wants smaller pills, and Auto-accept without its full text on mobile.

## Where to look
- `src/lib/components/code/AgentComposer.svelte` and `src/lib/components/code/AgentView.svelte`: the mode, model, effort and auto-accept pills, and the context ring with its popup and quotas.
- `src/lib/components/chat/ChatInput.svelte`, `ChatWindow.svelte` and `ModelEffortPicker.svelte`: the pill shared with chat. Also `ModelPicker.svelte`.
- Existing specs to extend or imitate: `tests/code-composer.spec.ts`, `tests/code-dialogs-mobile.spec.ts`, `tests/chat-model-picker.spec.ts`.

## Fix
1. **One toolbar row.** On narrow widths (Tailwind `max-sm:`, or a container query on the composer), lay it out as `[+] [mode] [model] [effort] [auto-accept] … [ring] [send]`, with no wrapping. If it still doesn't fit, the pill group scrolls horizontally, with a fade edge at the overflow side, rather than wrapping. The `+`, ring and send never scroll away.
2. **Smaller pills on mobile:**
   - lower height, `text-xs`, tighter padding and smaller chevrons;
   - the model name truncates with a max-width and an ellipsis, while the full name stays in the popup and in `title`.
3. **Icon-only Auto-accept on mobile:**
   - the shield icon only, with an `aria-label` and a `title`;
   - a clear on/off state: a filled or colored shield when on;
   - when the machine vetoes it, a distinct disabled look, and the veto explanation shown on tap, because there's no hover on a phone;
   - keep the text on desktop.
4. **The effort pill** gets the same compact treatment. The mode pill (`build`/`plan`) may show a short label or an icon on mobile, keeping an accessible name.
5. **Compact ring on mobile:** show the ring only, without the "20.2k" text. The value and quotas stay in its popup.
6. **Chat composer:** apply the same compact rules to chat's model pill, which is the shared component. Check whether chat on mobile got cramped the same way, and fix it too if so.
7. **Desktop is unchanged:** at `sm` and up everything looks as today.

## Tests (Playwright, required)
- At 390×844, for `/code` (the fake-machine or real-machine harness, whichever the existing composer specs use) and for chat:
  - assert a single toolbar row: the `+`, every pill, the ring and send share one row, meaning their bounding boxes overlap vertically, with no second row;
  - no wrap;
  - Auto-accept is icon-only, has an accessible name, and its on/off state is exposed (e.g. `aria-pressed`);
  - the veto explanation appears on tap when vetoed.
- A desktop viewport (1280×800) check that the text labels (Auto-accept, the ring's value) are still shown.
- Run the new and touched specs **at root and under `/chat`**, then the whole suite once at each base. Use `E2E_SKIP_BUILD=1` after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), `--project=chromium`. WebKit isn't installed.
- Also `npm run check` (0 errors), `npx eslint` on the changed files, and prettier on the changed files.
- **Environment for every Playwright run:**
  ```
  export E2E_APP_PORT=5371 E2E_MONGO_PORT=8797 MOCK_OPENAI_PORT=18871 MOCK_OIDC_PORT=18872 MOCK_MCP_PORT=18873
  unset OPENCODE_CONFIG_CONTENT OPENCODE_CONFIG
  ```
  The Mongo container `e2e-mongo-8797` is yours; I've started it. Example command:
  `E2E_APP_BASE=/chat E2E_SKIP_BUILD=1 flock /tmp/heavy.lock npx playwright test tests/<spec> --project=chromium --reporter=line`.

## Box rules (mandatory)
- Wrap EVERY heavy command (npm ci, build, check, playwright, vitest) in `flock /tmp/heavy.lock …`. The box OOMs otherwise. Before each heavy command, if `free -m` shows under 1.5 GB available, wait.
- Kill only the processes you start, by recorded PID: dev servers, preview servers, anything else. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199.
- Don't spawn sub-agents.
- Never deploy. Never touch the `llm-platform-*` containers, docker volumes or `/home/ubuntu/test/`.
- No new dependencies without asking (a non-OSI dependency needs approval). Cite ADRs by number only. Never run `ruff format`.
- Commits: descriptive subjects, no "WIP:", with NO `Co-Authored-By: Claude` trailer (a commit-msg hook rejects it). Push the branch; DON'T merge to main (the orchestrator reviews and merges).

## Report
Reply with:
- the commits;
- what changed per component;
- screenshots' paths at 390×844 for /code and chat, and at desktop;
- the test commands and their pass counts at both bases;
- anything left undone.
