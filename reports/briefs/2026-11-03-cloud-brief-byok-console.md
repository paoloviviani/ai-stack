# Brief: BYOK pages in Pystino's admin console

Repository: `paoloviviani/Pystino` (public). Create branch **`feat/byok-console` from
`feat/byok`** (PR #25, not merged; the backend for this feature). Do not base it on
`main`. Read `AGENTS.md` first and follow it. The console is the React app in
`apps/console`, using pnpm, with the design primitives in `packages/ui`.

## The feature

**Bring your own key (BYOK)** lets users whose group has the `byok` capability add their
own providers (their own API key) and models, privately. Only the owner sees or uses
them. On `/v1` the models appear as `my/<name>` with `"byok": true`.

The backend is done. **Read `docs/byok.md` on the branch**, especially "The API": it
lists every endpoint, payload, error code and the naming. Also read:
- `apps/console/src/lib/api-schema.ts`, the regenerated typed client schema, already including the new endpoints;
- `apps/gateway/src/gateway/routers/me.py`, `routers/admin.py` and `routers/admin_byok.py` when a detail is unclear.

## Build (console only; no gateway changes unless a real bug blocks you)

### 1. "Your providers and models", for users with the capability

- **Route:** `/me/providers`. Cerea links to `<origin>/console/me/providers`, so keep that path. Tabs or sections for Providers and Models.
- **Sidebar:** a sidebar entry in the user part of the shell (`src/components/Shell.tsx`), shown only when `/api/me` says `capabilities.byok` is true.
- **Providers:** the same form as the admin Providers screen (`src/routes/AdminProviders.tsx`): **one "Provider" select**, with the catalogue entries followed by "OpenAI-compatible (generic)" and "Anthropic (generic)", using the plugin's `protocol` field.
  - Fields: base URL, the API key (write-only; never shown back), prefix and name.
  - Actions: test connection (`POST /api/me/providers/{id}/test`), edit and delete.
  - **Reuse the admin component** with a scope prop pointing it at `/api/me/...` instead of `/api/admin/...`. Do not copy it.
  - The provider types offered are the ones `GET /api/me/provider-plugins` returns: language-model providers only.
- **Models:** the same list, form and catalogue import as the admin Models screens (`AdminModels.tsx`, `AdminModelDetail.tsx`), scoped the same way:
  - discover from a provider (`/api/me/models/discover`, `/tags`) and import (`/api/me/models/import`);
  - edit a model, delete it, and set its prices (append-only rows, as for admins);
  - show each model's `/v1` name `my/<name>`, with a copy button.
  - No grants, public flag, aliases, routing or quotas on these screens: the backend refuses them, so don't show them.
- **Errors to explain clearly:**
  - `provider_url_blocked`: the network guard refused a private or internal address. Say so, and that an administrator can allow private networks.
  - `byok_not_allowed`;
  - the 25-provider and 500-model ceilings;
  - the reserved `my/` prefix;
  - the refused headers.
- **A short note at the top:** "Models you add here use your own key. Only you can see or use them. Their usage is shown to you only and doesn't count against your group's limits."

### 2. "Your usage" shows your own keys separately

The usage endpoints now carry an `own_keys` total, and `/api/me/reports/usage` and `/api/me/requests` accept `own_keys=true`. Add a "Your own keys" section or toggle on the user's usage and requests pages. Keep the existing numbers' meaning unchanged.

### 3. Admin side

- **Group capability toggle:** a "Bring your own key" capability on the Groups screen, next to API keys and local connectors, exactly like them, including the bulk toggle (`capability: "byok"`).
- **Deployment policy:** in the identity/policy settings, where `code_agents`/`local_connectors` modes live (`PUT /api/admin/oidc/policy`):
  - `byok_mode` on/off (the default for new groups);
  - `byok_private_networks`, with a warning that it lets users point the gateway at internal addresses.
- **New admin page "Private providers"** (`GET /api/admin/byok/providers` and `/models`):
  - columns: owner, provider name, type, host, models, enabled, last used, usage totals;
  - Disable/Enable actions (`POST …/disable|enable`), with a confirmation;
  - never any key: the API doesn't return one, so don't add placeholders suggesting otherwise;
  - its sidebar icon added to the shared icon map in `src/lib/adminNav.ts`, which the admin landing cards read too.

### 4. Strings

Strings go in `apps/console/messages/en.json`, plus the pseudo-locale as the repo does, passing `i18n:check`. Say "users", not "people".

## Checks

Run from the repo root, per AGENTS.md:

```
pnpm install --frozen-lockfile
pnpm --filter @llmp/console typecheck
pnpm --filter @llmp/console test
pnpm build
```

- **The console has no lint script:** keep the files formatted like their neighbours.
- **Tests to add:**
  - the BYOK page is shown only with the capability;
  - the provider form posts to `/api/me/providers`, and the key is never rendered;
  - a guard error shows the explanation;
  - model import goes through `/api/me/models/import`;
  - the Groups toggle sends `byok_allowed`;
  - the admin Private providers page lists rows without keys and disables one;
  - usage shows the own-keys section.
- **If you change any gateway schema** (only if needed), run `uv run python scripts/export_openapi.py` and `pnpm --filter @llmp/console api:generate`, and commit both.

## Rules

- **Git:**
  - never `git stash`, never `--no-verify`, never force-push;
  - real commit messages (why, not what), ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or your model's line) and this session's link;
  - no other AI attribution.
- **Publishing:**
  - push `feat/byok-console`;
  - open a PR **into `feat/byok`** (not `main`) titled "BYOK: console pages for users and administrators";
  - start CI: `gh workflow run ci.yml --ref feat/byok-console`.
- **Do not merge.** Report the PR link, screens built, tests and CI results, and anything uncertain.
- **The repository is public:** no private hostnames or credentials anywhere.
