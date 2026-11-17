# Brief: deployment connectors managed by the administrator, transparent to users (Cerea 0.32.0)

## Owner decision (2026-10-27)
Today the deployment's own connectors appear in every user's Connectors view with an on/off switch, and the selection is kept per browser. That covers the `.env` base list (`MCP_SERVERS`) and the administrator's connectors. With search, maps and more, they clutter the user's view, while the owner wants people to use them transparently.

New behaviour:
1. **A mode per deployment connector, set in Admin → Connectors** (`src/routes/admin/connectors`):
   - **On for everyone:** always offered on every turn, with no switch in the user's view. This is the default for every deployment connector, including the `.env` base servers.
   - **Optional:** shown to users with a switch, exactly as today.
   - **Off:** not offered to anyone.

   Store the mode server-side (a settings collection, or a field on the admin connector row). For `.env` base servers, store it keyed by server name. Administrators change it in the admin page; an env default isn't required.
2. **Enforced on the server.** The turn route (`src/routes/conversation/[id]/+server.ts`, around `selectedMcpServerNames` / `selectedMcpServers` / `connectorIds`, lines ~185–260) and wherever the resolved server list is built must:
   - always include "on for everyone" connectors, whatever the browser sends;
   - never include "off" ones;
   - include "optional" ones only when selected.

   The same applies to every other path that resolves a turn's servers: the parked-turn and tool-approval sweepers, resume, nested agents and delegate (they get the turn's servers), schedules if they use connectors, and project defaults (`include built-in connectors` and the client-side code that turns base servers on for a project's chats: see `src/lib/stores/mcpServers.ts` around line 109).

   Stale browser state (`mcp:selected-ids`, `mcp:disabled-base-ids` in localStorage) must not be able to switch an always-on connector off or an off one on. Clean up or ignore it.
3. **User view** (`src/lib/components/mcp/ConnectorsSection.svelte`, `MCPServerManager.svelte`, and the composer's per-chat connector picker if there is one):
   - "On for everyone" connectors are not listed with switches. Show one short read-only line instead, such as "Provided by your deployment: Search, Maps", so people know which outside services may see their questions.
   - "Optional" connectors keep their switches, as today.
   - Personal connectors are unchanged.
   - Any "N connectors enabled" counts should count what is really used.
   - Wording follows `docs/writing.md`, and strings go through `messages/en.json` (Paraglide), run `npm run i18n:pseudo` and `i18n:check`.
4. **Approvals unchanged:** tool approval policy still applies to always-on connectors.
5. **Admin page:** a mode control per connector, with one-line explanations, shown in the same design language as the page. Changing a mode takes effect from the next turn. Gate it on `gatewayIsAdmin` like the rest of admin.
6. **Docs:**
   - `docs/connectors.md` (user): deployment connectors are provided automatically;
   - `docs/chat-admin.md` (admin): the three modes, and the token cost (every always-on connector's tool descriptions go into every turn, so keep big or rarely used ones Optional);
   - the kit README's MCP section, in one sentence;
   - AGENTS.md: where the mode lives and the server-side rule.
7. **Tests** (each must fail without its fix):
   - server: the route or resolver always includes always-on connectors, excludes off ones, and respects optional selection; stale client state can't override; the sweepers and resume path use the same resolver;
   - client: the user view shows the read-only line and no switch for always-on connectors; the admin page changes the mode.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-conn-modes -b feat/deployment-connector-modes origin/main`. `export TMPDIR=/var/tmp/conn-modes-tmp && mkdir -p $TMPDIR`. Run `npm ci` in the worktree under `flock /tmp/heavy.lock`, because the main checkout's node_modules lacks paraglide.
- Never `git stash`, never `--no-verify`, never force-push. No AI attribution in commits. The repo is public: no private hostnames or paths.
- Another worker is editing docs on branch `docs/office-tools` (office.md, configuration.md, deploy-kit.md, skills.md, index.md, README.md, kit/README.md, AGENTS.md "Document tools"). Keep your doc edits to the connector sections to limit conflicts.
- Checks:
  - `npm run check`, plus eslint and prettier on every changed file, tests included;
  - `npm run i18n:check`;
  - the server tests for the areas you touch (`src/lib/server/mcp`, the route, the sweepers);
  - client tests for the components you change, in the Playwright container as AGENTS.md shows, under the heavy lock. If you touch the admin page or the sidebar, run its test too.
  - Run the mkdocs build `--strict` if you change docs.

  No full suites.
- Screenshots (AGENTS.md "Validating UI with screenshots"): the user's Connectors view before and after (desktop 1440 and phone 390) and the admin page with the mode control. Put them in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-27-connector-modes/` and look at each one yourself.
- Push and run CI once: `gh workflow run ci.yml --ref feat/deployment-connector-modes`. Wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report:
  - where the mode is stored, and every path that now uses the resolver;
  - the fails-without-fix evidence;
  - the screenshot paths;
  - the CI run and result;
  - the changelog wording, including what an operator sees after the update: every deployment connector becomes "on for everyone" by default. Is that right for an existing install? Say what you think.
- No sub-agents.
