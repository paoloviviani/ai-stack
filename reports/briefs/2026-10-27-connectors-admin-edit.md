# Brief: deployment connectors edited only in Admin, read-only in Workspace; tools always known (Cerea 0.32.1)

## What the owner hit (0.32.0)
1. **Workspace → Connectors offers Edit on a deployment connector to an administrator.** `manageable` is `isAdmin` for deployment rows (`src/lib/server/mcp/connectors.ts:92`), so an admin's Workspace shows Edit on "Find locations" and "Kiwi Flights", which the administrator provides. The owner's rule:
   - connectors the deployment provides (deployment rows and `.env` servers) are configured **only in Admin → Connectors**;
   - in Workspace everyone sees them read-only, administrators included, just like the `.env` OpenStreetMap card today;
   - Workspace keeps the person's own switch ("Use in chats", where the mode allows it), the status, the tool count and the tool list, and Check if it's harmless (see 3).
2. **Admin → Connectors can't edit an added connector.** It has an add form and the mode controls only.
3. **A connector added with a shared key had no stored tools,** so the model's catalogue line read "Find locations: Its tools are listed when you load it." With no host and no tool names, the model couldn't tell it was the Geoapify connector its skill describes, and never loaded it. The card said "Connected · access key" with no tool count, so nobody could see that the tools were unknown.

## What to change (branch `fix/connectors-admin-edit` from origin/main)
1. **Workspace, read-only for deployment connectors.**
   - In the view Workspace uses, a deployment row is never `manageable`: no Edit, no Remove, no credential fields, for anyone.
   - Keep a separate admin listing (`?admin=1`, already admin-guarded) where `manageable` stays true for admins.
   - Server side, PATCH and DELETE on deployment rows stay admin-only. Check whether the Workspace endpoints could still change a deployment row for an admin, and make them refuse it: configuration goes through the admin API.
   - Show the tool count and the "Available tools" list for deployment rows, as the `.env` card does.
   - Check in Workspace: keep it if it only re-lists the tools with the connector's own credential (the shared key) and writes nothing but `tools`/`checkedAt`/`lastError`; otherwise make it admin-only in Admin. Say which you chose and why.
2. **Edit in Admin → Connectors**, for connectors an administrator added:
   - name, URL, a **description** (this closes backlog C35; the catalogue line already prefers `description`), and the credential (replace the shared key or token and its header, or clear it);
   - reuse the existing PATCH API and its validation; the form follows the page's design language and works at 390 px;
   - `.env` servers stay read-only there too (edited in `.env`).
3. **Tools always known.**
   - Run the tool check **automatically** when an admin adds a connector, and when its URL or credential changes. A failure is shown on the card (the stored `lastError`), not swallowed.
   - On every card (Admin and Workspace), show either "N tools", "Tools not checked yet", or the check's error. Never a bare "Connected" with nothing about the tools.
4. **An identifying catalogue line when the tools are unknown** (`turnConnectors.ts` `summaryOf` and the line built in `connectorRuntime.ts` `connectorCatalogNotice`):
   - include the connector's address host, e.g. "Find locations (api.geoapify.com): its tools haven't been checked; load it to see them.";
   - keep the line stable across turns, since it's part of the cached prompt prefix: no timestamps, nothing that changes between turns unless the row changes.

## Tests (each fails without its fix)
- Workspace view: a deployment row isn't `manageable` for an admin; the UI shows no Edit or Remove on it (client test); a Workspace PATCH to a deployment row is refused.
- Admin edit: changing name, URL, description and credential saves through the API (client and route tests).
- Auto-check on add and on URL or credential change stores the tools, or `lastError` on failure (server test with a fake MCP server).
- Cards show "N tools", "not checked yet" or the error (client test).
- The catalogue line for a row with no tools includes the host (unit test).

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-admin-edit -b fix/connectors-admin-edit origin/main`. `export TMPDIR=/var/tmp/admin-edit-tmp && mkdir -p $TMPDIR`. Read AGENTS.md first. Mongo-backed tests: use TEST_MONGODB_URL and `--no-file-parallelism` as AGENTS.md says.
- `npm ci`, builds and Playwright run under `flock /tmp/heavy.lock`; never wrap a self-locking script in another flock. The Playwright container runs as root: chown back what it leaves (`node_modules`, `src`, `.svelte-kit`) with a throwaway container before `npm run check`. Bind to 127.0.0.1, and kill the servers and containers you start.
- Strings in `messages/en.json`, wording per `docs/writing.md`, `i18n:pseudo` and `i18n:check`. Update `docs/connectors.md` and `docs/chat-admin.md` (who edits what, where). No CHANGELOG entry (I write it).
- Never git stash, never --no-verify, never force-push, no AI attribution in commits. The repo is public: no private hostnames.
- Checks:
  - `npm run check`, eslint and prettier on the changed files;
  - the server tests for `src/lib/server/mcp`, `src/routes/api/v2/mcp` and `src/routes/api/v2/admin`;
  - the client tests for the admin connectors page and `ConnectorsSection` in the Playwright container.
- Screenshots at 1440 and 412 px, dark: Workspace as an admin (deployment cards read-only, with a tool count or "not checked"), and the Admin edit form. Put them in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-27-admin-edit/` and look at them yourself.
- Push and run CI once (`gh workflow run ci.yml --ref fix/connectors-admin-edit`). Wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report per item: what changed, the fails-without-fix evidence, the screenshot paths, and the CI run and result. No sub-agents.
