# Batch B brief: the composer's `/` menu and panel commands

Worktree: /home/ubuntu/workspace/slash-cerea (branch feat/slash-commands, at
0724980b: A0 done — minted prompt ids, ACP busy guard, tooltip). This batch
is Cerea-side ONLY: no galopin/agent changes, no new backend ops. You
implement, you don't redesign; ambiguity → stop and report.

Plan of record: /home/ubuntu/workspace/ai-stack/reports/2026-09-27-slash-commands-plan-rev1.md (§4 batch B) which supersedes §2.3–2.4 of the 2026-09-26 plan. Read both sections plus the anchors below before writing code.

## What ships

A `/` menu in the agent composer (AgentComposer → ChatInput) that:
- opens when the draft starts with `/` and the caret is inside the first
  token (`//` at the very start escapes to a literal slash — the draft is
  sent as ordinary text);
- lists PANEL commands only in this batch (backend commands arrive in
  batch C): `/compact`, `/undo`, `/redo`, `/model [q]`, `/mode [id]`,
  `/effort [level]`, `/new`;
- filters by prefix first, then substring; no debounce, no network;
- accepts via Enter/Tab (inserts the name; the hint placeholder renders as
  ghost text after accept, e.g. `/review ‹$ARGUMENTS›`), arrows navigate,
  Esc dismisses; accept-over-send precedence IDENTICAL to the hub mention
  menu's (study it: ChatInput.svelte + $lib/utils/hubMention.svelte.ts +
  HfHubMentionAutocomplete.svelte — your components mirror that exact
  shape and ARIA pattern: aria-controls/aria-activedescendant on the
  textarea, data-result-index scroll-into-view, sibling live region);
- a draft matching ^/(\S+)(?:\s+([\s\S]*))?$ whose name is a panel command
  RUNS it on submit; anything else is sent as ordinary text (so
  `/etc/hosts is wrong` still works);
- a slash command can't be sent while a turn is running (send is hidden
  while running — steering is a later wave).

## The panel commands (all over EXISTING routes/ops — no new API)

| Command | Does | Existing route/op |
| --- | --- | --- |
| `/compact` | compact now | POST v1/agents/:id/compact → session.compact |
| `/undo` | revert to before the last user message | POST …/revert {messageId} → session.revert (same confirmation as the transcript's revert — files are restored) |
| `/redo` | undo the last revert | POST …/unrevert → session.unrevert |
| `/model [q]` | no argument: OPEN the model/effort picker; with argument: unique fuzzy match (or open the picker pre-filtered) | POST …/model (allowsModel still enforced) |
| `/mode [id]` | same pattern with the mode pill | POST …/mode → session.setMode |
| `/effort [level]` | pick an effort level | POST …/effort → session.setEffort |
| `/new` | open the new-agent dialog on the same workspace | the existing create flow (session.create) |

Find the exact route call sites in src/lib/codeApi.ts and how the
AgentComposer/CodePanel drive them today (the revert confirmation lives in
the transcript view). Reuse, don't fork.

**Excluded, never shown** (the menu is the help): /share /unshare
(outward-facing), /connect (credentials live in enrollment), /exit /quit
/editor /theme /sessions /export /details /thinking (TUI-only), /help.

## The bindable pickers (one-line enablers)

- ModelEffortPicker.svelte: `open` becomes `$bindable` so `/model` with no
  argument can open it (and so the menu can close it — see interactions).
- AgentComposer's mode DropdownMenu.Root gets `bind:open`.
These are the only changes to shared components; chat's own use is
untouched (it doesn't pass the new props).

## Menu interactions (rev1 §2 additions)

- Dismiss the `/` menu when the mode pill or model/effort picker opens
  (and don't fight it for the Esc key).
- Keep the mobile send/stop overlay from covering the menu (the menu
  anchors above the composer on narrow viewports, as the Hub panel does).
- Accept-over-send precedence identical to the hub mention menu.

## Files (expected — verify against reality)

- NEW src/lib/utils/slashCommand.svelte.ts — SlashCommandState (the
  HubMentionState shape: update(value, caret), move, accept, dismiss,
  reset)
- NEW src/lib/components/chat/SlashCommandAutocomplete.svelte — the
  listbox (groups are: "Panel" only in this batch)
- ChatInput.svelte — new props: slashCommands?: SlashCommand[] | null and
  onslashcommand? (chat itself passes NONE — chat's behaviour unchanged)
- AgentComposer.svelte — builds the panel command list, passes the props,
  handles runs; dismisses the menu when its pickers open
- ModelEffortPicker.svelte — open $bindable

## Tests (hermetic; the fake machine exists)

- Vitest: SlashCommandState unit tests modelled on
  hubMention.svelte.test.ts (open/close/escape rules, filter order,
  accept vs send precedence, `//` escape).
- Playwright (tests/code-commands.spec.ts, new; follow
  tests/chat-artifact-*.spec.ts for the harness + fake machine): `/`
  opens the menu; filtering + arrows work; Tab/Enter inserts; Enter on
  `/compact` hits the existing compact route on the fake machine; `/undo`
  shows the existing revert confirmation; `/model` no-arg opens the
  picker; an unknown `/foo` goes out as text; `//x` stays literal; the
  menu closes when the mode pill opens; the narrow-viewport menu is
  usable with the send/stop overlay present.
- npm run check (0 new errors — the 13 pre-existing in code/CodeFileViewer
  + code/CodeTerminal are the baseline); eslint + prettier on changed
  files.

## Box + git rules (binding)

- NO sub-agents. Foreground only: every heavy command `timeout -s KILL
  <secs> flock /tmp/heavy.lock <cmd>` (build 1500, Playwright 1800);
  check free -m ≥1500 MB and the lock free first; wait and retry.
- Client tests need a real mongo (no AVX box): TEST_MONGODB_URL=mongodb://127.0.0.1:8801
  for vitest; the e2e-mongo-8801 container is running.
- Build per base is heavy: build once (npm run build), then E2E_SKIP_BUILD=1.
- Git: configured identity (Paolo Viviani), NO AI trailers, no WIP
  commits, commit per coherent piece. Push feat/slash-commands; no merge,
  no main, no /opt/cerea, never port 5199.
- node_modules is a symlink to the main checkout — do not run npm install.

## Report

Design as built (state machine, component, how each command runs),
files, commits, exact test commands + pass counts, deviations. Then stop
for review.
