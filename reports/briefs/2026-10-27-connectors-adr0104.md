# Brief: ADR 0104, connector enablement in one place and tools on demand (Cerea 0.32.0)

The design is fixed in ADR 0104. Its decisions are restated here; cite the ADR by number only, because the repo is public. Continue on branch `feat/deployment-connector-modes` (worktree `/home/ubuntu/workspace/wt-conn-modes`), building on commit 5372e8af: the mode storage and the server resolver. There's no hurry; get it right. Ship one release, not two.

## Decisions to implement
1. **One place to switch connectors: Workspace → Connectors.**
   - Remove every connector choice from the composer's + menu, and remove per-chat selection entirely, including the request fields the browser sends (`selectedMcpServerNames`, `selectedMcpServers`, `connectorIds`). Old clients that still send them must be ignored safely.
   - The browser stores (`mcpServers.ts`, `mcpConnectors.ts`, localStorage selected/disabled ids) shrink to what Workspace needs, or go.
2. **Deployment connector modes** (`.env` and the administrator's), set in Admin → Connectors:
   - **Off:** offered to nobody;
   - **On** (the default): on for everyone, and a person may switch it off in Workspace;
   - **On, locked:** a person can't switch it off.

   Rename the stored modes (from always/optional/off) accordingly, and add an **"always loaded"** flag per deployment connector (default false).
3. **The person's switches** are stored server-side, per user, in the settings collection or a small owner-keyed collection. A new collection must go in `identity/userKeyedCollections.ts` and its roster spec, for erasure and merge. They cover deployment connectors in mode On, and personal connectors. Locked connectors show as on, with no switch.
4. **Tools on demand** (in `runMcpFlow` and the tool assembly):
   - **Core built-ins stay fully loaded:** web search and fetch, code, document tools, plan, ask the person, delegate and research, artifacts, memory, and whatever else is built in today. Check `getEnabledBuiltinTools`.
   - **Each enabled connector that isn't loaded** gets one catalogue line in the system or tool context: its name, a one-sentence summary (the connector's description if it has one, otherwise derived from its tool names), and its tool names.
   - **A new built-in `load_tools({connectors: string[]})`** makes those connectors' tools callable from the next model round of the same turn. It answers with what was loaded, or why not (unknown, off, needs sign-in).
   - **The loaded set persists on the conversation** (`Conversation.loadedConnectors`, a list of connector keys) and stays loaded on later turns. Newly loaded tools are appended after existing ones, so the request prefix is stable and prompt caching keeps working.
   - **"Always loaded" deployment connectors** skip the catalogue and are loaded from the start.
   - **The catalogue line uses the cached tool listing** (connector rows store tool names from the last check; `.env` servers need an equivalent cache, refreshed on boot and on a timer or on the first failed call). Building a turn must not contact every enabled connector. A connector is contacted only when it is loaded or called.
   - If a model calls a tool of an unloaded connector directly, by name from the catalogue, load it implicitly and run the call; don't fail.
5. **One resolver, server-side,** for every path:
   - the turn route, the parked-turn and tool-approval sweepers, `resumeElicitation`, and nested agents and delegate (they inherit the catalogue and the loaded set; a sub-agent may call `load_tools`, and what it loads counts for the conversation);
   - the inputs are the modes, the person's switches and the conversation's loaded set;
   - browser state can't widen or narrow it.
6. **Approvals are unchanged.** `load_tools` itself never needs approval; calling a connector's tools asks exactly as before.
7. **Project connector defaults are retired** (`Project.defaultMcpConnectorIds` and the project page's connector section). Ignore the stored field, remove the UI, and note it in the changelog.
8. **Measurement:** log the tool-definition size per turn (characters, and an estimated token count) at debug or info level, with the catalogue and loaded counts, so before and after can be compared. Put a sample in the report: a turn with search and maps enabled, before and after loading.

## UI
- **Workspace → Connectors:**
  - a "Provided by your deployment" group, with a switch per On connector and a locked mark for locked ones (off ones are not shown);
  - "Your connectors", with switches, sign-in state and the add form as today.
- **Admin → Connectors:** per deployment connector, a mode control (Off / On / On, locked) and an "Always loaded" switch, each with a one-line explanation, in the page's design language.
- **The composer's + menu** no longer lists connectors.
- **The tool card for `load_tools`:** a compact line ("Loaded Maps"), not a big card.
- Wording follows `docs/writing.md`; strings go in `messages/en.json`; run `i18n:pseudo` and `i18n:check`.

## Docs
- `docs/connectors.md`: how people turn connectors on and off, and that the assistant loads a connector's tools when it needs them.
- `docs/chat-admin.md`: the modes and "always loaded", and the advice to review after upgrading.
- The kit README's MCP section, in one sentence.
- AGENTS.md: the resolver, the loaded set, the catalogue cache and `load_tools`.
- The maps skill in `kit/tools/mcp/skills/maps-routing/SKILL.md`: add "load the Maps connector first if its tools aren't available", worded to work whether it is loaded or not.

## Tests (each must fail without its fix)
- **Resolver:** the modes, locked versus a person's switch, off never offered, client fields ignored, used by every path (the sweepers and resume included).
- **On demand:**
  - unloaded connectors appear only as catalogue lines;
  - `load_tools` adds the tools for the next round and persists them;
  - loaded tools come after existing ones;
  - "always loaded" skips the catalogue;
  - a direct call to an unloaded tool loads it implicitly;
  - building a turn doesn't contact unloaded connectors (use a fake server that counts connections).
- **Client:** the Workspace switches and the locked mark; the admin mode control; the composer + menu has no connectors.
- **E2E:** if there is an existing connector smoke spec, update it. Add a smoke-tagged spec only if one fits the main path cheaply.

## Rules
- Same worktree and branch. `export TMPDIR=/var/tmp/conn-modes-tmp`. Never `git stash`, never `--no-verify`, never force-push. No AI attribution. No private hostnames or paths.
- Checks:
  - `npm run check`, plus eslint and prettier on every changed file, tests included;
  - `i18n:check`;
  - the server tests for the touched areas;
  - client tests for the changed components, in the Playwright container under `flock /tmp/heavy.lock`;
  - mkdocs `--strict`;
  - the kit tests if the kit changed.
- Screenshots (AGENTS.md rules): Workspace → Connectors and Admin → Connectors at 1440 and 390, and the composer + menu before and after. Put them in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-27-connectors-0104/` and look at each one yourself.
- Rebase-free: merge origin/main into the branch before the final CI if main moved. Push and run CI once at the end: `gh workflow run ci.yml --ref feat/deployment-connector-modes -f full=true`, because this touches the turn path. Wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report:
  - what changed, by area;
  - the fails-without-fix evidence;
  - the measurement sample;
  - the screenshot paths;
  - the CI run and result;
  - the changelog wording, including the upgrade note for administrators and the retired project defaults.
- No sub-agents. The box has 4 cores and 6 GB; don't leave servers running.
