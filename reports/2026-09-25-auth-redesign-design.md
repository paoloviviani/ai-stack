# Auth redesign: detailed design (ADR 0093)

Status: **accepted** 2026-09-25 (ADR 0093). The answers to §18 are recorded there.

- **Code read:** Pystino `origin/main` at `53ecdcb`, Cerea at `3986fcc4`, cerea-deploy at `d0be633`.
- **Line references:** `file:line` references quoted from the review are the review's own, taken at Pystino `ba25a9a` and Cerea `e4b06bfd`.
- **Path prefixes:** `gw/` is `apps/gateway/src/gateway/` and `console/` is `apps/console/src/routes/`.

## 0. What this implements

- The user's eight decisions of 2026-09-25.
- The in-scope items: the enrollment one-liner, the P0 guards, disable semantics and the migration.
- The requirement that the chat's records survive a switch.
- The 21 review items the orchestrator marked binding.
- The four approved refinements:
  - link-by-email never attaches to an admin;
  - a startup warning while it's on;
  - `email_verified` is required for `OIDC_ADMIN_EMAIL`;
  - `--check` recommends SMTP for the team preset.

Nothing else is added. Section 18 lists the few points where the brief left a choice. For each, I give my default and ask for confirmation.

## 1. Environment variables

`.env` is the only place the identity provider is set. The first column is the key in `.env`; the other columns are the container variables compose derives from it.

| `.env` | Gateway | Chat (Cerea) | Default | Notes |
|---|---|---|---|---|
| `OIDC_KIND` | `GATEWAY_OIDC__KIND` | – | `authelia` | `authelia` **means the bundled Authelia**. An external Authelia is `generic`. Other values: `generic`, `keycloak`, `entra`, `okta`, `authentik`, `google`. |
| `OIDC_ISSUER` | `GATEWAY_OIDC__ISSUER` | `OPENID_PROVIDER_URL`, `CODE_MACHINE_ISSUER` | `${PUBLIC_ORIGIN}/authelia` | One issuer for all three clients. |
| `OIDC_INTERNAL_BASE_URL` | `…__INTERNAL_BASE_URL` | `OPENID_INTERNAL_URL` | `http://authelia:9091/authelia` when bundled | |
| `OIDC_CONSOLE_CLIENT_ID` / `_SECRET` | `…__CLIENT_ID` / `…__CLIENT_SECRET` | – | `pystino-console` / minted | |
| `OIDC_CHAT_CLIENT_ID` / `_SECRET` | `…__ACCEPTED_CLIENTS` (below) | `OPENID_CLIENT_ID` / `OPENID_CLIENT_SECRET` | `cerea` / minted | |
| `OIDC_MACHINE_CLIENT_ID` **(new)** | `…__ACCEPTED_CLIENTS` | `CODE_MACHINE_CLIENT_ID`, feature flag | `opencode-enrollment` | galopin's public client (device flow and loopback). An external IdP must register it. |
| `OIDC_AUDIENCE` | `…__ACCESS_TOKEN_AUDIENCE` | `CODE_MACHINE_AUDIENCE` | `pystino-api` | |
| `OIDC_GROUPS_CLAIM` | `…__GROUPS_CLAIM` | – | `groups` | |
| `OIDC_GROUP_SYNC` **(new)** | `…__GROUP_SYNC` | – | `every_login` | `every_login`, `first_login` or `never`. Forced to `never` with the bundled Authelia (§8). |
| `OIDC_LOGOUT_URL` | `…__LOGOUT_URL` **(new on the gateway side)** | `OPENID_LOGOUT_URL` | Authelia's `/logout?rd={redirect}` when bundled | This was a row-only field. |
| `OIDC_ADMIN_EMAIL` **(new)** | `…__ADMIN_EMAILS` | – | empty | A comma-separated list. §5. |
| `OIDC_ADMIN_CLAIM` **(new)** | `…__ADMIN_CLAIM` | – | empty | A dotted path, as for groups (e.g. `groups`, `realm_access.roles`). |
| `OIDC_ADMIN_CLAIM_VALUE` **(new)** | `…__ADMIN_CLAIM_VALUES` | – | empty | Comma-separated. Any value matches. Compared both before and after the global group mappings, as `AdminRule.matches` does today. |
| `OIDC_LINK_BY_EMAIL` **(new)** | `…__LINK_BY_EMAIL` | – | `false` | §6. A WARNING at every start while it's `true`. |
| `PYSTINO_BOOTSTRAP_ADMIN_EMAIL` | `GATEWAY_BOOTSTRAP_ADMIN_EMAIL` | – | the `--admin-email` | Honoured with the bundled Authelia only, once (§5.3). With an external IdP it's ignored, with a WARNING. |
| `SMTP_HOST`, `SMTP_PORT` (587), `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`, `SMTP_SECURITY` (`starttls`, `tls` or `none`) **(new in `.env`)** | `GATEWAY_SMTP__*` | – | empty | Also fed to Authelia's notifier (§8.5). The stack's single mail setting. See §18, Q1. |

**Removed:**

| Variable | What happens to it |
|---|---|
| `OIDC_LINK_LOCAL_BY_EMAIL` / `GATEWAY_OIDC__LINK_LOCAL_BY_EMAIL` | `true` is a startup error naming `OIDC_LINK_BY_EMAIL`. `false` is ignored. |
| `GATEWAY_LOCAL_AUTH__PASSWORD_RESET__*` | Any value set is a startup error naming `GATEWAY_SMTP__*`. `PasswordResetSettings` is renamed `SmtpSettings` and moved to the top level (review correction 8, `gw/config.py:186-199`). |
| `CHAT_MIGRATE_ISSUER_FROM` | No longer set or read on gateway presets. Still read by the gateway-less `generic` preset only (§4.5). |
| `CODE_MACHINE_ISSUER` / `_AUDIENCE` / `_CLIENT_ID` | Compose derives these from `OIDC_*` and no longer exposes them as separate `.env` keys. Cerea keeps reading them, so its tests can point at a mock issuer. |

### 1.1 Startup validation (gateway)

A pydantic `model_validator` on `Settings`, plus one startup check that needs the database. Each failure exits non-zero before the app serves, with one line naming the variable and the fix.

1. `OIDC_KIND != authelia`, and neither `ADMIN_EMAILS` nor both `ADMIN_CLAIM` and `ADMIN_CLAIM_VALUES` are set:
   > `an external identity provider needs an admin rule: set OIDC_ADMIN_EMAIL, or OIDC_ADMIN_CLAIM with OIDC_ADMIN_CLAIM_VALUE, in .env (./configure --admin-email / --admin-claim)`
2. Exactly one of `ADMIN_CLAIM` and `ADMIN_CLAIM_VALUES` is set: error.
3. An `ADMIN_EMAILS` entry isn't a valid address after normalisation (§6.1), or isn't ASCII: error.
4. The removed variables above: error, as listed.
5. `GROUP_SYNC` isn't one of the three values: error.
6. `ACCEPTED_CLIENTS` is empty while `ACCESS_TOKEN_AUDIENCE` is set: error. Compose always fills it from the chat and machine client ids.
7. Warnings, not errors:
   - `LINK_BY_EMAIL=true`, **at every start**:
     > `OIDC_LINK_BY_EMAIL is on: a first sign-in with a verified email will attach to the existing non-admin account with that address. Turn it off when the transition is done.`
   - a bootstrap email with an external IdP (ignored);
8. The provider re-seed (§2) runs **fatally**: an error stops the start, where today it is best-effort (`gw/main.py:231-238`). A gateway serving a stale provider is the split the redesign removes. Test mode keeps the best-effort path behind the existing test flag.

### 1.2 `./configure` and `--check`

**New flags:**
- `--admin-email` (bundled: the bootstrap address; external: `OIDC_ADMIN_EMAIL`);
- `--admin-claim` and `--admin-claim-value`;
- `--link-by-email on|off`;
- `--machine-client-id`;
- `--group-sync`;
- `--smtp-host`, `--smtp-port`, `--smtp-username`, `--smtp-password`, `--smtp-from`, `--smtp-security`;
- `--break-glass` (§10).

`--idp external` refuses to write `.env` without an admin rule. That's the same message as §1.1.1.

**`--check` adds:**
- the §1.1 rules, run on `.env` offline;
- `link-by-email is on` as a WARN, with the advice to turn it off after the transition;
- **team preset without SMTP:**
  > WARN: users can't reset their own password. Set `--smtp-*`.
- bundled Authelia without SMTP:
  > INFO: password resets are admin-issued one-time passwords.
- when the network probes are on, `docker compose run --rm --no-deps gateway pystino idp check --discovery-only` (§11);
- `--check --idp-signin`, which runs the device-flow sign-in variant interactively.

## 2. The provider row is a projection of the environment

`seed_from_env` (`gw/identity_registry.py`) becomes `reseed_from_env`. It runs on every start, in one transaction, under a Postgres advisory lock so that two workers can't race.

1. Build the env record E, with a normalised issuer.
2. **Env-owned fields:**
   - issuer, client id and secret, scopes, `groups_claim`;
   - `internal_base_url`, `logout_url`, `kind`;
   - `group_sync`, and `group_source` (`none` for bundled, else kept unless it's `directory`);
   - `admin_source`, `admin_claim` and `admin_values`, for the claim rule;
   - `link_local_by_email`, repurposed as `link_by_email`;
   - `is_enabled=true`, and `name="default"` so the callback path `/auth/callback/default` never changes.
3. **The row whose issuer equals E's** gets every env-owned field overwritten. The console-owned fields are kept: `sync_adapter`, `sync_config_encrypted`, `sync_interval_minutes`, `sync_deprovision`, `sync_create_users` and `sync_confirmed`. Those are external-IdP directory sync, set through the kept directory endpoints (§14), plus `group_source=directory` when a sync adapter fills it.
4. **No row has E's issuer**, because the issuer changed:
   - the current `default` row is renamed `previous-<yyyymmdd>-<4 hex>` and disabled;
   - a new `default` row is inserted from E;
   - directory entries of a bundled row move to the new bundled row, so login-name bindings survive an origin change;
   - the change is audited (`idp.reseed`, with the old and new issuer).
5. **Every other row** is set `is_enabled=false`. Rows are never deleted: `users` and `user_identities` reference their issuer by value, and a later break-glass or switch back re-enables the matching row in step 3.
6. **The group mappings** on the rows are no longer read (§3.4). The re-seed clears nothing; the migration copies them once.
7. `_fill_internal_base_url` and `_fill_kind` are deleted. Step 3 subsumes them.

**Consequences:**
- `_bearer_client` (`gw/deps.py:424`) already routes by issuer over **enabled** rows only. After a switch, a token from the old issuer finds no provider and answers 401, which is what ends in-flight chat sessions cleanly (§4.6).
- `list_providers` with `enabled_only` returns exactly one row. The multi-provider sign-in page and `?provider=` stay in the code but can't show two buttons.

**Also enforced on bearer tokens: `azp` and `client_id`.** When a token carries `azp` (or `client_id`), it must be in `ACCEPTED_CLIENTS`: the console, chat and machine ids. A token with neither still passes if its audience matches, and that is logged once per client. This is the "client checks" lesson on top of the existing audience check (`gw/oidc.py` `validate_access_token`).

## 3. Data model

### 3.1 Gateway: new and changed columns (migration `0047_auth_redesign`)

**`users`:**
- `email_normalized: String(320)`, indexed. Written wherever `email` is written; backfilled by the migration. It is **not unique**: two people can share an address across issuers, and link-by-email refuses when there is more than one candidate.
- `email_verified: Boolean | None`: the last sign-in's `email_verified`, stored only when it is the literal `True`, otherwise `False` or `None`. It qualifies the stored address as a link candidate (§6).
- `sessions_valid_after: DateTime | None`. A console session token with `iat` before this is refused in `load_user_for_management`, which costs no extra query. `/v1/me` returns it, and the chat compares it with each session's `createdAt`.
- `merged_at: DateTime | None`: the newest time another user was merged into this one. `/v1/me` returns it, so the chat knows to fetch `merged_from` (§4.4).
- `admin_source` gains the value `env`: set by `OIDC_ADMIN_EMAIL` or the claim rule. The old `oidc` value is migrated to `env`, because both mean "a rule granted it".
- `admin_rule: String(8) | None`: `email` or `claim`, which env rule granted admin. It is kept so that a revocation only removes what that rule gave (§5.1).
- **The pending identity.** A user created from the console before first sign-in has `issuer="pystino:pending"` and `subject=<uuid4>`. At first sign-in the pair is replaced by the real one (§8.2). A pending user can't be made admin (§5.4) and can't receive links (§6).

**`deployment_state`:** a single row, `id=1`.
- `bootstrap_admin_consumed_at: DateTime | None`. It is set the first time any administrator exists through any path. The migration backfills it with `now()` when any `is_admin` row exists, even an inactive one.

**`identity_events`:** append-only.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid pk | |
| `at` | timestamptz | server default `now()` |
| `actor_type` | `user`, `cli`, `login` or `system` | `login` is the sign-in doors (links, bindings, rule grants). `system` is startup (re-seed, sweep). |
| `actor_user_id` | uuid, **no FK** | kept after the actor is deleted or merged |
| `actor_label` | String | the email or `cli:<command>` at the time |
| `action` | String | from the enum below |
| `target_user_id` | uuid, no FK | |
| `target_label` | String | the email or login at the time |
| `issuer`, `subject` | String, nullable | for identity actions |
| `detail` | JSON | per-action allowlisted keys only; a unit test rejects unknown keys. Never a password, digest, token or secret. |
| `reason` | Text | an optional operator reason; required for merge and break-glass |

- **Actions:** `user.create`, `user.update`, `user.disable`, `user.enable`, `user.delete`, `admin.grant`, `admin.revoke`, `admin.refused_last`, `password.reset`, `login.create`, `login.delete`, `login.disable`, `identity.link`, `identity.bind`, `identity.drop`, `user.merge`, `break_glass`, `idp.reseed`, `bootstrap.admin`, `sessions.revoke`, `devices.revoke`.
- **Append-only** is enforced by `BEFORE UPDATE OR DELETE` triggers: a Postgres function that raises, and on SQLite in tests, `RAISE(ABORT)`. There is no ORM update or delete path.
- **API:** `GET /admin/identity-events?user_id=&action=&before=`, paginated and read-only.
- **Retention:** kept forever. It's small, and the operator can archive it with SQL; that's documented.

**`user_merges`:** `id`, `source_user_id` (no FK), `target_user_id` (no FK), `merged_at`, `actor_user_id`, `summary` JSON (the counts per table), `reason`. It feeds `merged_from` (§4.4). Resolution follows chains: A into B, then B into C, reports both A and B for C.

**Constraints:** `uq_user_identities_user_issuer` (one identity per issuer per person) stays. A merge whose source and target both hold an identity at one issuer drops the source's, listed in the preview (§7).

### 3.2 Gateway: removed

- Provider create, edit and delete handlers and their schemas.
- `_adopt_local_account`, whose `issuer="local"` matcher has nothing to match (review correction 1). It is replaced by §6.
- `PasswordResetSettings`, renamed and moved.
- `LocalCredential` and `PasswordResetToken` are **not** dropped: dropping tables isn't needed and the freeze argues against it. They are simply unused.

### 3.3 Cerea (Mongo)

**`users`:**
- `gatewayUserId?: string`, the gateway's `users.id`. It gets a **unique partial index** on documents where it is a string.
- `mergedInto?: ObjectId` and `mergeState?: "moving"` support crash-safe chat merges (§4.4).
- `previousIdentities?: {issuer, sub, at}[]`, used by the generic preset only (§4.5).

**Indexes:** the unique index on `hfUserId` (`src/lib/server/database.ts:576`) is **dropped** and replaced by a non-unique `{issuer: 1, hfUserId: 1}`. With resolution by `gatewayUserId`, one `(issuer, sub)` can legitimately appear on a stale record and on the record it will merge into.

**Migration:** a numbered migration in Cerea's existing `migrationResults` runner does the index change. `gatewayUserId` is backfilled lazily (§4.3), not offline.

**Sessions:** the session check reads `createdAt` and the user's `gatewayUserId`; no new fields.

**`codeDevices`:**
- `enrolledIssuer?: string`, set on each successful machine auth;
- `revokedAt?: Date` and `revokedReason?: "account_disabled" | "account_merged"`.

### 3.4 Group mappings

The provider rows' `group_mappings` move into the global policy (`oidc_config`, ADR 0048): the policy already folds mappings (`OIDCPolicy.group_mappings`), and the console already edits it (`console/AdminIdentity.tsx`).
- **The migration:** if the global policy has no mappings, it appends one policy row with the `default` row's mappings, reason `moved from the identity provider row (ADR 0093)`. It logs any other row's mappings that differ.
- **The code:** `_dc_replace(policy, group_mappings=provider.mappings_dict())` (`gw/deps.py`) and the callback's `record.mappings_dict()` go away. The global policy is the only mapping.
- **With the bundled Authelia,** group mappings have nothing to map (§8.3).

That closes R9: provisioning policy and mappings are one global object, and there is only ever one provider.

## 4. Identity resolution, gateway and chat

### 4.1 The gateway's two sign-in doors

A **sign-in door** is a call that sees the full claim set, userinfo included. Only doors make links, bind pending users, apply `OIDC_ADMIN_EMAIL` and fire the bootstrap. There are two:

1. **The console callback** (`gw/routers/auth.py:281`), as today.
2. **`POST /v1/session/announce` (new)**, called by the chat's login callback with the fresh access token. This replaces `announceToGateway`'s `GET /v1/billing/groups` side effect (`src/routes/login/callback/updateUser.ts`).
   - The gateway validates the token (audience plus `azp` must be the chat client), then **fetches userinfo itself with that token**. It never trusts claims the chat relays.
   - It then runs the same `sign_in(...)` routine as the console callback.
   - Its answer: `{id, is_active, is_admin, sessions_valid_after, merged_at, identities: [{issuer, subject}], merged_from: [uuid]}`.
   - It is rate-limited per subject, at 10 per minute.

Plain `/v1` bearer calls (`sync_user_from_claims`) still resolve existing identities and provision unknown ones. They never link, bind, apply the email rule or bootstrap. **Order matters when the chat is the first door someone uses after a switch.** The chat calls announce **before** anything else touches `/v1` with the new token, so the first sight of a new identity is at a door. One case remains: an unknown identity whose first `/v1` call comes from somewhere other than a door, a galopin machine enrolled before its owner ever signed in. That provisions a plain new user, as today, and an admin merge fixes it. It is documented.

`sign_in(...)` is extracted from the callback, so both doors run exactly one sequence:

1. `_identity_select` by (issuer, subject);
2. if unknown: bind a pending bundled user (§8.2), or link by email (§6), or create (policy gate as today);
3. update the profile, and `email_verified`;
4. groups by `group_sync` and `group_source`;
5. the admin rules (§5);
6. the bootstrap (§5.3);
7. the audit rows;
8. refuse if inactive.

### 4.2 The stable key

`users.id` never changes for a person:
- a link adds a `user_identities` row to an existing id;
- a pending bind replaces a placeholder pair on the same id;
- a merge moves identities onto the target id and deletes the source id.

So "which person is this login" has one answer, the gateway's, and the chat keys on it (`gatewayUserId`). The chat does not mirror links; it asks.

### 4.3 The chat's login resolution (replaces `findLoginUser`, `src/lib/server/loginIdentity.ts`)

This applies on gateway presets, where `OPENAI_BASE_URL` and `USE_USER_TOKEN=true` are set.

1. Call announce. If it fails (the gateway is unreachable, or answers 5xx), **the login fails** with "The gateway is unavailable, try again in a minute". The session isn't created. This fails closed, deliberately: creating an unkeyed chat account would be the orphan this design removes. If announce answers 401 or 403 (disabled or refused), the login fails with the gateway's message.
2. `target = users.findOne({gatewayUserId: id})`.
3. `strays` = the chat users with `gatewayUserId ∈ merged_from`, **or** with no `gatewayUserId` and `(issuer, hfUserId) ∈ identities`, using the normalised issuer.
4. If there is no target and exactly one stray, that stray becomes the target: set `gatewayUserId` on it. That's the lazy backfill, and it covers every existing account at its first post-upgrade login. It also covers the old Authelia chat record of a person whose new external identity the gateway linked, because the gateway lists the old identity in `identities`.
5. Any remaining strays are merged into the target (§7.2) before the session is created.
6. If there is still no target, create one with `gatewayUserId`.
7. Update `hfUserId`, `issuer`, `email`, `name` and so on to this login. That's informational; resolution never reads them again on gateway presets.

`IssuerMismatchError` and the `CHAT_MIGRATE_ISSUER_FROM` branch are not reached on gateway presets.

### 4.4 The chat's session check (`src/lib/server/gatewaySession.ts`)

`/v1/me` gains `sessions_valid_after` and `merged_at`, both columns and so free on the query budget that `test_query_counts.py` pins. `id` is already there. Each check, at most one per minute per session:

- **401:** the session ends (as today).
- **The id differs from the session user's `gatewayUserId`,** meaning the identity was merged elsewhere: the session ends. The next login resolves through §4.3.
- **`sessions_valid_after > session.createdAt`:** the session ends.
- **`merged_at` is newer than the chat user's `lastMergeSyncAt`:** fetch `GET /v1/me/identities`, which returns `{identities, merged_from}`, and run the stray merge of §4.3 steps 3 and 5 in the background. So a merge converges within a minute of the target's next activity, not at their next login.
- **Unreachable** (a network error or 5xx): fail open **for at most 5 minutes after the last good answer for that session.** After that, requests on the session answer 503 ("can't verify your account; the gateway is unreachable"). The session is not deleted, so it resumes when the gateway answers.

That bounds what the review flagged as fail-open (`src/lib/server/gatewaySession.ts:8-16, 61-64`), and it's documented.

### 4.5 The generic preset (no gateway)

`findLoginUser` keeps its current logic, with two changes:
- the migration query matches `email` by normalised equality: it stores `emailNormalized` and queries it (§6.1);
- the migration appends the old pair to `previousIdentities` rather than only overwriting `hfUserId`, and a switch back via `CHAT_MIGRATE_ISSUER_FROM=<new issuer>` finds the account again.

This preset has no console, no merge and no break-glass. It's documented as such.

### 4.6 In-flight chat sessions during a switch

A switch or a break-glass is `.env` changing plus `docker compose up -d`, which recreates the gateway and the chat.

1. **Generations in flight** die with the chat container, as on any restart. They are recorded in `abortedGenerations`, and the conversation survives.
2. **Existing chat sessions survive in Mongo** but hold old-issuer tokens. Their next session check sends the old token to `/v1/me`. The old provider row is now disabled, so the answer is 401 and the session ends. That happens within 60 s, or at once on the next inference call, which gets 401 from the gateway too.
3. **The person is sent to sign in at the new IdP.** Announce returns their gateway id:
   - linked by email: the same id, so the same chat account;
   - not linked: a new id and an empty chat account, until an admin merges, after which §4.4 folds the old records in.
4. **Galopin machines** fail `machineAuth`'s issuer check (their tokens name the old issuer) and show "re-enroll" (§12).

Nothing is deleted anywhere. The only lost state is in-flight generations and live terminals.

### 4.7 Machine tokens (`src/lib/server/code/machineAuth.ts`)

**Local JWT validation stays as it is:** issuer, audience, `azp`, expiry, not an ID token.

**The user is then resolved through the gateway.** `GET /v1/me` is called with the machine token, which is valid there: audience `pystino-api`, and `azp` in `ACCEPTED_CLIENTS`. The answer is cached per `(sub, token exp)` for 60 s. That yields the gateway id, and so `users.findOne({gatewayUserId})`. It replaces `findOne({hfUserId: sub})` (`machineAuth.ts:217-221`).

**A 401 from the gateway for a locally valid, unexpired token** means the account is refused. The chat does three things:
- it refuses the upgrade;
- it closes live links for that user on the next 60 s revalidation tick, which `machineServer` gains;
- it marks the user's `codeDevices` `revokedAt`, with `revokedReason: "account_disabled"`.

A revoked device needs a fresh `galopin enroll`, even after the account is re-enabled. `sessions_valid_after` newer than a device's `enrolledAt` revokes it the same way.

## 5. Admin assignment

### 5.1 `OIDC_ADMIN_EMAIL`

It is evaluated **at every sign-in, at both doors.** It grants when all of these hold:
- `email_verified is True`, the literal boolean;
- the normalised `email` is ASCII;
- the address is in the list.

The grant sets `is_admin=True` and `admin_source="env"`, with the audit action `admin.grant` and `detail.rule="email"`. It is **not** evaluated on plain `/v1` calls, because the claim set may lack `email_verified` there.

Revocation happens in two places, and only for `admin_source == "env"` with `users.admin_rule == "email"`:
- **At the person's next sign-in,** when they're no longer matched.
- **At each gateway start, a sweep** revokes admin from every `env`/email admin whose `email_normalized` isn't in the list. This isn't a trust decision, it only ever removes. So taking an address off the list and restarting takes effect at once.

Both revocations go through `apply_admin_answer`'s last-admin rule. If the revocation would leave no active admin, it is refused, logged, and audited as `admin.refused_last`.

### 5.2 The claim rule (`OIDC_ADMIN_CLAIM` plus `OIDC_ADMIN_CLAIM_VALUE`)

This is the existing `AdminRule` and `apply_admin_answer`, now fed from env instead of the row, with provenance `env`/claim. It is evaluated at both doors and, with `group_sync=every_login`, on `/v1` through `_admin_diverges`, as today. So a group removed at the IdP revokes admin within one access-token lifetime.

If both rules are set, either one grants. A person granted by one rule is revoked only when **neither** matches.

### 5.3 The bootstrap (bundled Authelia only)

`promote_bootstrap_admin` gains the precondition `deployment_state.bootstrap_admin_consumed_at IS NULL`. It is set:
- when the bootstrap promotes;
- by `pystino break-glass`;
- by any console, CLI or rule grant.

**Deactivating every admin no longer re-arms it.** This closes R1 and `gw/oidc.py:850-854`. The only way back is break-glass.

### 5.4 What never grants admin

- An invite. A pending user (§3.1) can't be `is_admin`: `PATCH /admin/users/{id}` refuses with "grant admin after their first sign-in", closing R6.
- A link. §6 refuses admin candidates outright.
- A directory sync.

The admin flag moves only through:
- the env rules;
- the console, by an administrator, on a user who has signed in;
- break-glass;
- the one-time bootstrap;
- a merge, where the target keeps `target.is_admin or source.is_admin` and the preview shows it.

### 5.5 Last-admin guards (gateway rules, not console rules)

An **active admin** is `is_admin and is_active and issuer != "pystino:pending"`. These actions are refused with 409 `last_admin` when they would leave zero:
- `PATCH /admin/users/{id}` with `is_active=false` or `is_admin=false`, **including on oneself**, closing R1 and `gw/routers/admin.py:2433-2450`;
- `DELETE /admin/users/{id}`: the self-delete refusal stays, and the guard is added anyway so the rule has a single implementation;
- merge (it can't reduce the count, but the guard is asserted);
- rule revocations (§5.1);
- `pystino admin revoke`, as today.

## 6. Link by email (`OIDC_LINK_BY_EMAIL`)

### 6.1 One normalisation

`normalize_email(s) = NFKC(s).strip()`, then `casefold()` in Python.

In TypeScript it is `s.normalize("NFKC").trim().toLowerCase()`, then the Python casefold exceptions that apply to ASCII, of which there are none. **Automatic trust decisions** (link, admin email, bootstrap) require the normalised address to be ASCII, and for ASCII `casefold` and `toLowerCase` agree. A non-ASCII address never links or grants; it logs `declined: non-ASCII address`. That also shuts out homoglyph addresses (R2).

A shared file of test vectors, `normalize_email_vectors.json`, is checked into both repositories and both test suites read it.

**The bundled users' email validator** (`gw/directory/authelia_users.py:118`) becomes:
- ASCII after normalisation, exactly one `@`, 254 characters at most;
- a local part of 64 characters at most, made of RFC 5322 atext and dots, with no leading, trailing or doubled dot;
- LDH domain labels of 1 to 63 characters, at least two labels, and an alphabetic TLD of two or more characters.

### 6.2 The rule

This runs at a door, only for an unknown `(issuer, subject)`, only when `LINK_BY_EMAIL=true`. It attaches the new identity to an existing user C when **all** of these hold:

1. The claims say `email_verified is True`, the literal boolean. `"true"`, `1` and absence all decline (`gw/oidc.py:554`).
2. `normalize_email(email)` is ASCII.
3. Exactly one user has `email_normalized` equal to it. Zero candidates means no link; two or more decline.
4. C's stored address qualifies: `C.email_verified is True`, or `"email" in C.admin_edited_fields`. This stops an account whose address was never proven from receiving someone else's verified identity.
5. `C.is_active`.
6. `not C.is_admin`. **Admins never receive links.** They move through a merge or break-glass.
7. C isn't pending: pending users bind by login name, never by email (§8.2).
8. C has no identity at this issuer yet: no `user_identities` row there, and C's primary issuer is a different one.

**On success:**
- a `user_identities` row with `matched_email`;
- an `identity.link` audit row (actor `login`; `detail`: the matched address and the new issuer);
- an INFO log line.

**On refusal:** a WARNING log line with the numbered reason, and the login proceeds as an ordinary new user under the provisioning policy.

## 7. Merge

### 7.1 Gateway (`POST /admin/users/{source}/merge`)

**The API:**
- `GET /admin/users/{source}/merge-preview?into={target}` returns the counts per table, the identities that move, the identities dropped (same issuer on both), the resulting admin flag, the bundled logins affected, and the chat note ("the chat folds this person's conversations into the target at their next activity").
- `POST /admin/users/{source}/merge` takes `{into, confirm, reason}`, where `confirm` must equal the source's email, or its id when it has none.

**Refused when:**
- the source equals the target;
- the source is the caller;
- either user is pending;
- the target is inactive.

**It runs in one transaction,** with `SELECT … FOR UPDATE` on both users.

1. **Identities.** The source's primary `(issuer, subject)` and every `user_identities` row move to the target as `user_identities` rows, unless the target already holds that issuer. Those are dropped and listed, and a dropped bundled login is disabled in Authelia after the commit.
2. **The per-table rules**, one for every FK to `users.id` (the 19 in `gw/models.py`) and every user-scoped `scope_id`:

   | Table | Rule |
   |---|---|
   | `memberships` | Union. On conflict, keep the higher role; the source becomes `manual` if either is `manual`. |
   | `user_model_access` | Union. On conflict, keep the target's. |
   | `api_keys` | Reassign to the target. |
   | `usage_records` | Reassign: the ledger follows the person. |
   | quota and redaction rules scoped to the user (`scope_id`) | Reassign. |
   | the actor columns (`updated_by`, `created_by` and similar on email settings, providers, policy, redaction, sync runs, quota resets, directory entries' `user_id`) | Reassign. |
   | `refresh_credentials`, `idp_authorization_codes`, `password_reset_tokens`, `local_credentials` | Delete. That revokes the source's gateway-issued tokens. |
   | `quota_notification_settings` / `_state` | Keep the target's. The source's are deleted. |
   | the profile and `default_billing_group` | Keep the target's; take the source's where the target's is null. |
   | `is_admin` | The target's OR the source's (shown in the preview). |

3. Delete the source row.
4. Write the `user_merges` row, and set `target.merged_at=now()` and `target.sessions_valid_after=now()`. That ends both people's console sessions, so the next page load is clean.
5. Write `identity_events` `user.merge` with the summary and the reason.

**A guard test** walks `Base.metadata` for every FK to `users.id`, and every column named `scope_id` in a user-scoped table. It fails if one has no entry in the merge rule table. A future table can't be silently skipped.

**Irreversible.** The console dialog says so, shows the preview, recommends a backup (the README's volume tar), and requires the typed confirmation. The documented undo is restoring that backup. Split-back isn't offered.

### 7.2 Chat (Cerea `mergeChatUsers(stray, target)`)

This is triggered by §4.3 step 5 and by §4.4.

1. It is idempotent and crash-safe: set `stray.mergedInto=target._id` and `mergeState="moving"` first. A stray with `mergedInto` set is never resolved as a login target, and any later trigger resumes the move.
2. It reassigns `userId` in every user-keyed collection, driven by a registry `USER_KEYED_COLLECTIONS` with a per-collection conflict rule:
   - conversations, projects, assistants, `vectorStores`, `knowledgeDocuments`, skills, memories, `mcpConnectors`, `mcpTokens`, `codeDevices`, `codeAudit`, `codeExecutionOutputs`, `sharedConversations` and reports are reassigned;
   - `settings`: keep the target's and delete the stray's;
   - `sessions`: delete the stray's.

   A spec fails if a collection whose documents carry `userId` isn't in the registry, checked from the collection declarations in `src/lib/server/database.ts`.
3. It deletes the stray user and logs `chat_user_merged {stray, target, counts}`. The gateway's `identity_events` holds the authoritative audit; the chat log line is the local trace.

## 8. Bundled Authelia accounts

### 8.1 The Users page (`console/AdminUsers.tsx`)

With the bundled IdP the page gains:
- **Add user**: login, display name, email, and groups, which are console groups. It shows the one-time password once, with a copy button and the note "Share it over a one-time channel (a password manager share, or in person). Authelia can't force a change at first sign-in; ask them to change it from the sign-in page's reset link (needs SMTP) or keep it."
- **Create sign-in** for an existing gateway user who has no bundled login. That's the after-switch and after-break-glass case.
- **Reset password**, which mints a one-time password; the same dialog.
- **Disable** and **Enable** (§9).
- **Delete** (§9), after a preview list.
- **Merge into…** (§7).
- An **Activity** list of `identity_events` for that user.

With an external IdP the Authelia actions disappear. The page states that accounts live in the IdP, and shows the provider and admin rule, read-only.

`AutheliaUsersDialog` (`console/IdentityDirectory.tsx`) and the People button are removed. `DirectoryDialog` stays, reached from the read-only provider card, for external directory sync (§14).

### 8.2 Pending users and binding

**Add user** does the following:

1. It writes the Authelia entry: groups `["users"]`, the password digest, the email.
2. It inserts a gateway user with the pending identity (§3.1), `email`, `email_normalized`, and `admin_edited_fields=["email"]` (the administrator set it, so it qualifies).
3. It inserts memberships, as `manual`.
4. It inserts a `directory_entries` row, keyed `(provider=bundled row, external_id=<login>)`, with `user_id` set, meaning bound in advance.
5. It writes the audit rows `user.create` and `login.create`.

If step 1 fails, nothing is written. If a later step fails, the Authelia entry is removed again, as compensation.

**Binding at sign-in (bundled issuer only).** It applies to an unknown `(issuer, subject)` whose `preferred_username` equals a bound entry's `external_id`, when `email_verified is True` and the normalised email equals the entry's.

- If the entry's user is pending, the placeholder pair is **replaced** by the real one.
- Otherwise the identity is **added** as `user_identities`. That covers an Authelia `authelia-data` volume that was lost, where Authelia mints new opaque subjects; an origin change; and break-glass.

Either way it writes an `identity.bind` audit row. Login names are trustworthy here because the console is the only writer of the file (R6). This replaces `link_at_login`'s "entry has no user" case, whose `source != "environment"` condition goes: every row is environment-sourced now.

**The stable login name.** Every Authelia operation on a user (disable, reset, delete, email change) finds the login through `directory_entries.external_id` for that `user_id`. It **never** uses `users.username`, which is admin-editable (`gw/routers/admin.py:2453-2455`). This closes R4's binding finding.

### 8.3 Groups

Every bundled user carries exactly `groups: ["users"]` in the file. The bundled row has `group_source="none"` and `group_sync=never`, so tokens' groups are ignored, and groups and roles are console-authoritative (decision 2).

The update API no longer accepts groups for the file. The migration handles existing files (§13).

### 8.4 The users file (`gw/directory/authelia_users.py`)

- **Locking.** Every load-modify-save runs under `fcntl.flock(LOCK_EX)` on a **sidecar** `users_database.yml.lock` in the same directory, with a 10 s timeout and then a 503. Locking the data file itself would be lost at the first `os.replace`, because the lock lives on the old inode. The atomic replace (`mkstemp`, `fsync`, `os.replace`) stays, and the directory is also `fsync`ed after the rename.
- **Single writer.** The gateway is the only writer. Bootstrap writes only when the file doesn't exist (`gw/deploy/bootstrap.py:189-199`) and takes the same lock.
- **Authelia's watcher across inode replacement:** an e2e test (§16) writes 50 successive password resets through the API against a real `authelia/authelia:4.39.22`. After each one, it asserts that a sign-in with the newest password succeeds and the previous one fails. If the watcher loses the file, the test fails, and the fallback is to rewrite in place under the lock. That decision is made on the test's evidence, not assumed.

### 8.5 Password reset through email (cerea-deploy, not the gateway)

**The Authelia template** (`authelia/configuration.yml`) becomes conditional on `X_PYSTINO_SMTP_HOST`, using Authelia's template filter with Go `if` and `else`.
- **With SMTP:**
  - `notifier.smtp` is set: `address: 'submission://host:port'`, `submissions://` for `tls`, `smtp://` for `none`, plus the username and sender;
  - the SMTP password arrives through `AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE`, a file bootstrap writes from the env at mode 0600, so it isn't in the rendered config;
  - `password_reset.disable: false`.
- **Without SMTP:** the file notifier, and `disable: true` as today.

**`./configure`** writes the `SMTP_*` keys, and compose passes them to Authelia, the gateway and bootstrap. A changed SMTP setting changes Authelia's environment, so `up -d` recreates it, which is the `--force-recreate` the review names. `tools/pin` refreshes the `cerea.config-rev` label.

**The gateway sends mail from `GATEWAY_SMTP__*`** (quota notifications and the console's "send test"). The console's email card becomes read-only and says "set in .env: `./configure --smtp-…`". See §18, Q1.

The gateway has **no** password-change or reset endpoint. The Authelia portal's "Reset password?" link is the self-service flow.

### 8.6 No second factor with the bundled Authelia

The user decided on 2026-09-26, reversing that morning's "build it now":
- **There is no two-factor authentication with the bundled Authelia.**
- **Why:** Authelia has no SMTP-free self-enrolment; its device registration verifies identity through the notifier. The only SMTP-free path is provisioning TOTP from the host, and host access is not an option for regular users.
- **Deployments that need MFA** use an external IdP such as Keycloak, with TOTP or WebAuthn configured there, through `.env` (§1).

The bundled Authelia stays `one_factor`, and **every second-factor method is off in the rendered config**: `totp.disable: true` and `webauthn.disable: true`, with Duo never configured. So the portal offers no half-enabled enrolment page.

A cerea-deploy test renders the template and asserts all three. The live check (§16) asserts that the portal's settings page offers no device registration.

There is no `AUTHELIA_TWO_FACTOR`, `--two-factor`, `--totp`, `--reset-totp` or global session cutoff.

### 8.7 Without SMTP

There is no self-service reset or change. The admin mints one-time passwords (§8.1), and break-glass is the fallback. `./configure --check` says so, and warns for the team preset (§1.2).

## 9. Disable and delete

### 9.1 Disable (`PATCH /admin/users/{id}` with `is_active=false`, one action)

| Where | What happens |
|---|---|
| Gateway | `is_active=false` and `deactivated_by="manual"` (subject to the last-admin guard). `sessions_valid_after=now()`. `refresh_credentials` and `idp_authorization_codes` for the user are deleted, and so are **minted** API keys (`minted_by` not null). **Personal API keys** are kept but refused on every request while the user is inactive (`gw/deps.py:173`); re-enabling brings them back, and the dialog says so. |
| Authelia (bundled) | `disabled: true` for the bound login, under the lock. New Authelia sign-ins are refused. |
| Console session | Refused at the next request (`sessions_valid_after`, and `is_active`). |
| Chat sessions | Ended at the next session check, within 60 s (401 from `/v1/me`, since the account is inactive). Any inference call is refused at once. |
| galopin | Live links close within 60 s (§4.7), and devices are marked revoked (`devices.revoke`, recorded by the chat when it observes it). |
| Audit | `user.disable`, `sessions.revoke`, and `login.disable` for bundled users. |

**Enable** reverses the gateway flag and Authelia's `disabled`. Sessions, minted keys and devices stay revoked: they sign in again and re-enroll.

**Already-issued tokens**, spelled out:

| Token | Lifetime | After disable |
|---|---|---|
| Authelia access tokens for the console and chat clients | ≤ 1 h | Still valid **at Authelia** (userinfo) until they expire. **Refused** by the gateway on every `/v1` call (`is_active`) and so by the chat's session check within 60 s. |
| Authelia machine access tokens | 1 h | The same. `machineAuth` refuses them through the gateway lookup (§4.7). |
| Authelia machine refresh tokens | 90 days | Whether Authelia 4.39 refuses a refresh for a `disabled` user is **tested, not assumed** (§16). Either way, the new access token is refused by the gateway and the chat, and the device is revoked. |
| External IdP tokens | the IdP's lifetimes | Valid at the IdP. Refused by the gateway and the chat as above. Disabling the person at the IdP is the operator's job, and the dialog says so. |
| Gateway session cookie | `session_ttl_seconds` | Refused at once (`is_active`, `sessions_valid_after`). |
| Gateway refresh credentials and minted keys | – | Deleted. |
| Personal API keys | until revoked | Refused while inactive. |

### 9.2 Delete erases the person everywhere (`DELETE /admin/users/{id}`, after `GET /admin/users/{id}/delete-preview`)

The user decided on 2026-09-25 that erased users mean erased chats. A delete removes the person from the gateway, from Authelia and from the chat. It works through a gateway-to-chat erasure call with its own service credential (§9.3).

**The preview** returns this list, and the dialog shows it verbatim.
- **Gateway:** the counts of what is removed and what is kept.
- **Authelia:** the bound login.
- **Chat:** the counts per collection, from the chat's dry run (§9.3). If the chat is unreachable, the preview says "chat counts unavailable; the erasure will be queued and retried."
- **Shared with others:** every resource of the user that someone else can see, named, with who can see it (below). The confirmation requires ticking "these will disappear for the people they're shared with."

**Removed:**
- **Gateway:** the user row, API keys, memberships, model access, refresh credentials, identities (cascade), and notification settings.
- **Authelia (bundled):** the bound login. If it is the file's last user, it is disabled instead, since Authelia refuses an empty users file.
- **Chat:** every document in every `USER_KEYED_COLLECTIONS` entry for that person (§7.2's registry, now also carrying an erase rule per collection):
  - conversations and their messages;
  - files and GridFS attachments: the conversation files, and the `code:<device>:<session>` attachment keys of their devices;
  - projects, assistants, knowledge bases (`vectorStores`, `knowledgeDocuments`, with their GridFS blobs), memories and skills;
  - MCP connectors, tokens and pending OAuth;
  - settings, sessions, `/code` devices and their audit and outputs;
  - shared conversations;
  - reports and generations;
  - anything else in the registry.

  Galopin links are closed, and the devices are deleted, so the machines must re-enroll under another account.

**Kept:**
- **Gateway:** ledger rows, with the user reference set to null (spend history stays, anonymised); rules scoped to the user, which become inert; the audit rows (actor and target labels are kept, since that is the audit's point).
- **Chat:** the chat's own erasure log entry (§9.3), holding the gateway id and the counts, and no content.
- **External IdP:** the account at the IdP is untouched, and the dialog says so.

**Content the user shared with others:**
- **Shared conversation links** (`sharedConversations`) created by the user are deleted, so their public links answer 404.
- **Projects and knowledge bases shared with named people or with everyone** are deleted, and the people they were shared with lose access. The preview names each one, with its audience. Delete isn't refused because of shares: an erasure must be completable, which is the existing rule's reasoning in `delete_user`. The tick box makes the consequence explicit instead.
- **Assistants the user published** are deleted. Other people's conversations that used one keep their own messages, and show the assistant as removed.
- **Copies are not the user's.** A conversation someone else imported from a share, or text they pasted, belongs to that other person and is untouched.

**Merge is not erasure.** A merge moves the source's data onto the target and never deletes anything of the target's. Only the source's sessions, settings and gateway tokens are dropped (§7).

**The guards:** last admin, and self, as today. A person deleted and later re-created gets a new gateway id and an empty chat account.

### 9.3 The erasure call

**The credential.**
- `./configure` mints `CHAT_ERASURE_TOKEN` (32 random bytes, url-safe) into `.env`.
- Compose passes it to the gateway as `GATEWAY_CHAT__ERASURE_TOKEN` and to the chat as `CHAT_ERASURE_TOKEN`.
- `GATEWAY_CHAT__ERASURE_URL` is `http://chat:3000/chat/internal/erasure`, on the compose network. It is empty on presets without a local chat, which makes delete refuse with "this deployment's chat is not reachable from the gateway". Satellite: the central gateway's chat is its own.
- The token is used for nothing else.

**Never from the edge.** Three layers:
1. The Caddyfile answers 404 for `/chat/internal/*` and `/internal/*` before any proxying.
2. The chat refuses any request to `/internal/*` that carries a proxy header (`X-Forwarded-For`, `X-Forwarded-Host`, `Forwarded`), whatever its token.
3. The token is compared in constant time. A wrong or absent token answers 401, and the attempt is logged.

A cerea-deploy test asserts the 404 through the proxy.

**The chat endpoints:**
- `POST /internal/erasure/preview` and `POST /internal/erasure` take `{erasure_id, gateway_user_id, identities: [{issuer, subject}]}`.
- The chat resolves the person's records as the users with `gatewayUserId == gateway_user_id`, plus the unkeyed records whose `(issuer, hfUserId)` is in `identities` (§4.3), plus strays with `mergedInto` pointing at them.
- **Erase** runs the registry's erase rule per collection, the GridFS blobs, and the device and link closing. It is **idempotent**:
  - an `erasures` collection keyed by `erasure_id` records `{gatewayUserId, startedAt, doneAt, counts}`;
  - a repeat after `doneAt` returns the recorded counts;
  - a repeat after a crash resumes: every step is a delete by owner, so re-running is safe.
- It answers `200 {erasure_id, counts}` only when every collection is done. That `erasures` document is the chat-side audit, together with a `chat_user_erased` log line.

**The gateway side:**
- A `chat_erasures` table: `id` (the `erasure_id`), `gateway_user_id`, `identities` JSON, `status` (`pending`, `done`), `attempts`, `next_attempt_at`, `last_error`, `created_at`, `done_at`, `chat_counts` JSON.
- `DELETE /admin/users/{id}` deletes the gateway rows and inserts the `chat_erasures` row **in one transaction**, audited as `user.delete`. After the commit it tries the call once, inline.
- A background task retries pending rows with exponential backoff, from 30 s up to 1 h, **until the chat confirms**, with no give-up. Each attempt takes a row lock (`FOR UPDATE SKIP LOCKED`), so several workers never double-send.
- On success: `status=done`, `identities` cleared (no PII left beyond the audit labels), and an audit row `chat.erasure_done` with the counts. The first failure and every tenth after it are audited as `chat.erasure_retrying`, so a long outage doesn't flood the audit.
- The Users page shows a banner, "N erasures waiting for the chat", while any row is pending. `pystino erasure list` and `pystino erasure retry [id]` do the same from the host.
- The person's chat sessions are already refused in the meantime: `/v1/me` answers 401 for a deleted user, so a session ends within 60 s even before the erasure lands.

**The hook point** in `delete_user`: the erasure is one step of an explicit, ordered list of erasure steps (gateway rows, Authelia login, chat), so a future store adds a step rather than a special case.

## 10. Break-glass

**The host side:** `./configure --break-glass --admin-email ops@example.org [--admin-login ops] [--reason "…"]` runs from the cerea-deploy checkout.

1. It backs up `.env` to `.env.bak-<timestamp>`, mode 0600. The external IdP values are kept there and nowhere else, so `.env` stays one-IdP.
2. It rewrites `.env` as `--idp authelia` would:
   - bundled issuer, internal URL, kind and logout URL;
   - Authelia secrets minted if they are missing, and the ones already present kept;
   - the `authelia` profile added;
   - `OIDC_ADMIN_*` kept but inert with the bundled Authelia;
   - `OIDC_LINK_BY_EMAIL` forced to `false`.
3. `docker compose up -d --wait postgres`, then `docker compose run --rm bootstrap`, which makes sure the users file exists.
4. `docker compose run --rm --no-deps gateway pystino break-glass --email … [--login …] --reason …`, described below.
5. `docker compose up -d --wait`. The gateway re-seeds: the bundled row is enabled again or inserted, and the external row is disabled. The chat now reads the bundled issuer.
6. It prints the sign-in URL, the login and the one-time password, **once**, and reminds the operator that galopin machines must re-enroll.

**`pystino break-glass`** runs inside the gateway container, against the database and the `authelia-config` volume. It replaces `pystino admin grant` as the documented recovery; `admin grant` and `revoke` stay for the ordinary case.

1. **The target.** Find users by `email_normalized`, over all issuers, pending ones included.
   - One match: that user.
   - Several: list them (id, issuer, last sign-in) and require `--user-id`.
   - None: create a pending user. This no longer needs a prior sign-in, closing the review's `gw/deploy/admin.py:27-35`.
2. **The login.** If a bound bundled entry exists for the target, reuse its login: re-enable it, mint a password and write the digest. Otherwise create the login (`--login`, or a free login derived from the email's local part, validated by `LOGIN`), with groups `["users"]` and the email, plus a bound `directory_entries` row. Every write is under the file lock.
3. **The gateway record:** `is_admin=true`, `admin_source="manual"`, `is_active=true`, `deactivated_by=null`, and `deployment_state.bootstrap_admin_consumed_at` set if it was null.
4. **The audit:** `break_glass`, with `actor_type=cli`, the reason, the target, and whether the login was new.
5. It prints the password to stdout once, never to logs.

**What is preserved.** Every user, membership, key, ledger row and identity is untouched: only provider enabled flags and the target's admin state change.
- The target's first bundled sign-in binds to the same gateway id (§8.2), and so to the same chat account (§4.3).
- Other people who had bundled logins before the external period still hold their old Authelia subjects, because `authelia-data` persists, and resolve to their old accounts.
- People who only ever had external identities get **Create sign-in** from the admin (§8.1), which binds to their existing gateway id.

**The round trip back out** is `./configure --idp external …` again, with the old values from the backup file, or re-entered. The external row with the same issuer is re-enabled in step 3 of §2, with all its identities intact.

## 11. `pystino idp check`

`pystino idp check [--issuer …] [--internal-base-url …] [--discovery-only | --device | --token <jwt>]` defaults to the environment's values, and so to the candidate `.env` when `./configure` runs it through `docker compose run`.

1. **Discovery and JWKS**, through the internal URL when it is set. It reports the issuer's exact string, whether it equals `OIDC_ISSUER`, the endpoints, the device endpoint, and the key count.
2. **`--device`:** a device-authorization flow with `OIDC_MACHINE_CLIENT_ID`. It prints the URL and code and polls. The operator signs in on any browser.
3. **`--token`:** it validates a pasted access token instead.
4. **The report**, from the token plus userinfo:
   - `sub`;
   - `email` and `email_verified` **with its JSON type** ("string `"true"` is not accepted");
   - the groups claim's value at `OIDC_GROUPS_CLAIM`;
   - `aud` against `OIDC_AUDIENCE`, and `azp` against the accepted clients;
   - and, for **each admin rule**, "would grant admin: yes or no, because …";
   - and, with link-by-email on, "would link to: <n> candidates".

   It exits non-zero if discovery fails, the audience is wrong, or no admin rule would grant for this sign-in, the last with a clear hint.
5. **The caveat,** printed: claims are per client at some IdPs (Keycloak mappers). The check uses the machine client, so map the same claims on the console and chat clients.

## 12. Enrollment one-liner

**The feature flags** (`src/routes/api/v2/feature-flags/+server.ts:47`) gain:
- `codeOidcClientId` (`CODE_MACHINE_CLIENT_ID`);
- `codeGatewayOrigin` (a new `CODE_GATEWAY_ORIGIN`, which compose sets to `${PUBLIC_ORIGIN}`, or to the central URL for satellite).

`codeOidcIssuerUrl` stays.

**`PairDeviceDialog.svelte`** prints one command block with a single copy button:

```
curl -fsSL <origin>/galopin/install.sh | sh && \
galopin enroll --issuer <issuer> --gateway <gatewayOrigin> --cerea <origin>/chat [--client-id <id>] [--allow-terminal] && \
galopin run
```

- `<origin>` is `window.location.origin`, and `--cerea` is the chat's base, so `/chat` on the stack.
- `--client-id` appears only when it isn't `opencode-enrollment`.
- An **"Allow terminal"** checkbox, off by default, adds `--allow-terminal`, with the existing warning text from `agent/enroll.go:64` next to it.

**The re-enroll state.** A device whose `enrolledIssuer` differs from the configured issuer, or which is `revokedAt`, shows "Re-enroll this machine: the identity provider changed" (or "access was revoked") in the `/code` device list, with the same command.

`fix/code-enroll-ux`, still unmerged, prints a stale paseo-era `setup-agent.sh` command (`codeReenrollCommand.ts`). This work replaces that helper's body. I'll coordinate with 403b95ea before touching it.

## 13. Migration of existing deployments

**The gateway**, through alembic `0047_auth_redesign` plus the first start:

1. The new tables and columns (§3.1): `email_normalized` backfilled, `email_verified` null, `deployment_state` with `bootstrap_admin_consumed_at=now()` when any admin exists, and `admin_source='oidc'` becoming `'env'`.
2. **Console-created provider rows:**
   - they are kept, and disabled at the first start by §2 step 5;
   - their mappings go into the global policy (§3.4);
   - a startup WARNING lists each disabled row with its issuer and user count, e.g. "`<name>` (`<issuer>`, 12 users) disabled: set it in .env to use it";
   - there's an `idp.reseed` audit row;
   - their users and identities are untouched, and they resolve again if the operator puts that issuer in `.env`.
3. **The live stack's env-seeded Authelia row:** its issuer equals `OIDC_ISSUER`, so §2 step 3 updates it in place. It gets `group_source=none` and `group_sync=never`, and its console-owned sync fields are kept.
4. **Bundled users, the first start:**
   - `memberships.source='oidc'` for users of the bundled issuer becomes `'manual'`, so today's Authelia-derived groups persist as console groups;
   - then the users file is normalised under the lock: each entry's groups become `["users"]`, and the removed group names are recorded in one `idp.reseed` audit row's detail;
   - a `directory_entries` row exists or is created for each file login, bound to the user whose (bundled issuer, `username`) matched at a verified sign-in. That's `link_at_login`'s existing data. Unmatched logins stay unbound until their next sign-in binds them by §8.2.
5. **The SMTP settings row** (`email_settings`), if the console set one. At first start the gateway **keeps using it** while `GATEWAY_SMTP__*` is empty, and warns: "mail settings are in the database; run `./configure --import-smtp` to move them to .env." `./configure --import-smtp` runs `pystino email export-env` in the container and writes `SMTP_*` into `.env`, with the password decrypted inside the container and written only to `.env`. Once the env is set, the row is ignored. (It depends on Q1.)

**The chat:**
- the Mongo index migration (§3.3);
- `gatewayUserId` backfilled lazily at each person's first login after the upgrade (§4.3 step 4). Their `(issuer, hfUserId)` is in the gateway's `identities` for them, because both apps sign in through the same issuer.

**The operator's order** is the documented upgrade: `git pull`, `./configure --check`, `docker compose pull`, `docker compose up -d`. **Nobody should switch IdP until every active user has signed in once after the upgrade** (so the chat is backfilled), or they should accept that an admin will merge the stragglers. `./configure --check` reports "N chat users not yet keyed to the gateway" through a small `docker compose exec chat` query.

**Tested:** an upgrade from a snapshot of a stack at today's pins, with synthetic data, not the live one. It covers a console-added second provider, an Authelia user in `admins`, an `email_settings` row, and chat conversations.

## 14. UI and endpoints

**Removed:**
- `POST /admin/identity-providers`, `PUT /admin/identity-providers/{id}` and `DELETE /admin/identity-providers/{id}`: the routes are gone, so they answer 404/405.
- `/admin/identity-providers/{id}/authelia-users` (list, create, patch, reset, delete): replaced by the user-centric routes below.
- In the console: `ProvidersCard`'s add, edit and delete, `ProviderDialog`, `DeleteProviderDialog`, `RedirectUri`'s editing, the People button, and `AutheliaUsersDialog`.

**Read-only:**
- `GET /admin/identity-providers`: the rows with `source`, enabled state and issuer, never secrets. The console card shows:
  - the active provider: kind, issuer, clients, admin rule, link-by-email state (with a red badge when on), group sync;
  - the disabled previous rows, with user counts;
  - the text "Configured in .env; change with `./configure`";
  - the directory sync button for external kinds.
- The email card: read-only, with "send test" (Q1).

**Kept:**
- The directory sync endpoints (`sync-config`, `sync/test`, `sync`, `sync/confirm`, `sync/runs`, `directory`, `preassigned`, `scim-token`) on the active row. They configure a directory mirror, not the IdP, and removing them would be a feature removal beyond decision 3. `preassigned` never carries admin (§5.4). See Q6.
- `GET` and `PUT /admin/oidc/policy`, now also the only home of group mappings.

**Added (gateway):**
- `POST /admin/users` (bundled);
- `POST /admin/users/{id}/sign-in` (bundled: create a login bound to an existing user);
- `POST /admin/users/{id}/reset-password` (bundled);
- `GET /admin/users/{id}/delete-preview`;
- `GET /admin/users/{id}/merge-preview`;
- `POST /admin/users/{id}/merge`;
- `GET /admin/identity-events`;
- `POST /v1/session/announce`;
- `GET /v1/me/identities`;
- in `/v1/me`, the fields `sessions_valid_after` and `merged_at`;
- the CLI commands `pystino break-glass`, `pystino idp check` and `pystino email export-env`.

## 15. How each review finding is closed

| Review item | Closed by |
|---|---|
| Correction 1: `link_local_by_email` only adopts `issuer=local` (`gw/oidc.py:489, 566-567`) | §6 replaces it with a cross-issuer rule, and §3.2 removes the old matcher. |
| Correction 2: bootstrap re-arms on "no active admin" (`gw/oidc.py:850-854`) | §5.3 `bootstrap_admin_consumed_at`. |
| Correction 3: the seed never reaches an existing row (`gw/identity_registry.py:263-266, 298-378`) | §2, a re-seed on every start in which env wins. |
| Correction 4: no active-provider notion | §2: exactly one enabled row. |
| Correction 5: no disable or delete guard on providers (`gw/routers/admin.py:2857, 2885-2897`) | §14: the routes are removed. |
| Correction 6: preassigned needs a mirror | Kept as is. External pre-registration isn't added (freeze), and it never carries admin (§5.4). |
| Correction 7: the People button condition (`console/AdminSettings.tsx:327`) | §8.1: the dialog is removed, and the Users page keys on `OIDC_KIND=authelia`. |
| Correction 8: reset needs Authelia's notifier; the gateway SMTP is a tripwire (`authelia/configuration.yml:31-32, 69-71`; `gw/config.py:186-199`) | §8.5 and §1 (`SmtpSettings`, the removed variables as startup errors). |
| Correction 9: the feature flags already serve the issuer (`+server.ts:47`) | §12 adds the client id and the gateway origin. |
| Correction 10: `CHAT_MIGRATE_ISSUER_FROM` (`loginIdentity.ts:13-16, 38-44, 52-62`) | §4.3 to 4.5: the chat keys on the gateway id; generic keeps a fixed migration. |
| Correction 11: file ownership | No change needed. The lock file is created with the same uid. |
| Correction 12: the stale `oidc_policy.py` docstring (`gw/oidc_policy.py:5-9`) | Rewritten in stage (a), because the connection *is* now env-only. |
| R1: lockout, re-arm, break-glass needs a prior sign-in (`gw/routers/admin.py:2433-2450`; `gw/deploy/admin.py:27-35`) | §5.3, §5.5 and §10. |
| R2: email linking is a takeover vector; normalisation (`gw/oidc.py:554, 566`; `loginIdentity.ts:53-56`; `authelia_users.py:118`) | §6: literal `true`, a verified candidate, never an admin, ASCII only, one normalisation plus shared vectors, a stricter validator, off by default, a warning at every start, audited. |
| R3: a partial switch; the chat orphans; machines drop; a one-way chat migration (`machineAuth.ts:33`) | §2 (one source), §4 (the gateway-id key, lazy convergence, a round trip back through break-glass), §4.7 and §12 (the re-enroll state), and the stage (f) docs. |
| R4: an unthrottled password verifier; `username` binding; no lock (`authelia_users.py:60-83, 115-176`; `admin.py:2453-2455`) | No verifier endpoint (rejected). §8.2 binds by the stable login. §8.4 adds the sidecar flock and the watcher test. |
| R5: one-time passwords | §8.1: the copy button, the one-time-channel note, an audit row per reset, and the no-forced-change statement. |
| R6: invites claimable; invites carrying admin | §5.4: a pending user can't be admin; bundled binding uses a console-controlled login plus verified email. |
| R7: disable doesn't revoke everything; the chat fails open (`gatewaySession.ts:8-16, 61-64`) | §9.1 and §4.4 (a bounded 5-minute fail-open, then 503), plus §4.7 for machines. |
| R8: no audit | §3.1 `identity_events`, landing first. |
| R9: per-provider mappings against a global policy | §3.4. |
| R10: delete leaves chat data | §9.2 and §9.3: delete erases the chat's records through an idempotent, retried, audited gateway-to-chat call with its own credential, and the preview lists everything, shared content included. |
| R11: backup and restore | Stage (f) docs: the users file, `authelia-data` and the gateway database are restored together; bootstrap never recreates an existing users file. |
| R12: no MFA | §8.6: none with the bundled Authelia, by decision, and every second-factor method is off. MFA comes from an external IdP such as Keycloak. |
| Recommendations 1 to 10 | 1 → §2. 2 → §11. 3: its session-bound half is excluded by the user; its email-migration half → §6 and §4. 4 → §4 (replaced). 5 → §5.5 and §10. 6 → §9.1. 7: no endpoint (excluded); the lock and binding → §8.4 and §8.2. 8 → §3.1. 9 → §8.6. 10 → the stage (f) order. |
| Open WebUI lessons | Audience plus **`azp` allowlist** (§2). HttpOnly cookies: the gateway's session and hint cookies are already `httponly`, and Cerea's session cookie too; a test pins both. No email auto-merge by default (§6). XSS blast radius: destructive identity actions need typed confirmation and are audited; tokens never reach page JavaScript. I didn't find the lessons report in `ai-stack/reports`; I used the lessons as the brief lists them (Q5). |

## 16. Test plan

**Unit, gateway (pytest):**
- the §1.1 refusals, each with its exact message: an external IdP with no admin rule refuses to start; half a claim pair; a bad admin email; the removed variables;
- the link-by-email startup warning, present on every start;
- the re-seed: same issuer (update), changed issuer (new row, old disabled, identities intact), extra console row disabled, bundled directory entries carried across, and two workers racing;
- the `azp` allowlist;
- the admin email rule: literal `true`, the string `"true"` refused, non-ASCII refused, revocation at sign-in and at the startup sweep, the last-admin refusal;
- the claim rule, with both rules set;
- the bootstrap: fires once, doesn't re-arm after every admin is deactivated, ignored with an external IdP;
- the last-admin guards on PATCH (self and other), DELETE and rule revocation;
- link-by-email: the eight conditions, each refused on its own, success audited, the refusal reason logged, and no linking on the plain `/v1` path;
- email normalisation against the shared vectors;
- merge: every per-table rule, identities dropped at the same issuer, the preview matching the result, transaction rollback on failure, **and the metadata guard test**;
- binding a pending user (the placeholder replaced), binding an existing user (identity added), refusal on unverified email or email mismatch, a pending user refused admin;
- the users file: the lock serialises two concurrent writers (threads), the atomic replace, the stricter validator, the groups normalisation;
- disable: every row in §9.1's gateway column;
- delete: the preview list;
- `identity_events` refuses UPDATE and DELETE, and rejects `detail` keys outside the allowlist;
- `pystino break-glass`: target resolution with one, several and no matches, an existing and a new login, the password printed once and absent from logs;
- `pystino idp check` against a mock issuer: the report fields, and a non-zero exit when no admin rule would grant;
- `test_query_counts.py` still at its budget.

**Unit, Cerea (vitest; `TEST_MONGODB_URL`, `--no-file-parallelism`):**
- the §4.3 resolution cases: existing target; a stray adopted; strays merged; a new target; announce failing closed;
- §4.4: id mismatch ends the session; `sessions_valid_after` ends it; `merged_at` triggers the merge; the bounded fail-open expires to 503;
- the chat merge: every registry collection, the settings conflict, crash-resume from `mergeState`, and the registry guard;
- `machineAuth`: resolution through the gateway and device revocation;
- the generic-preset migration with normalised email and `previousIdentities`;
- the feature flags;
- the one-liner builder, with and without the terminal flag and client id.

**Erasure (unit, both sides):**
- the gateway transaction writes the `chat_erasures` row with the delete; the backoff; `SKIP LOCKED` with two workers; `done` clears `identities`;
- the chat endpoint: 401 for a wrong token, a refusal for requests with proxy headers, a dry-run preview that changes nothing, erase over every registry collection including GridFS, idempotency after `doneAt`, resume after a mid-run crash;
- a registry guard: every user-keyed collection has an erase rule.

**Unit, cerea-deploy (its `tests/`):**
- `./configure` external without an admin rule is refused;
- the `--check` messages: link-by-email, team without SMTP, the bundled INFO;
- the SMTP keys rendered;
- `--break-glass` rewriting `.env` with a backup;
- `CHAT_ERASURE_TOKEN` minted once and kept;
- the Caddyfile's 404 for `/chat/internal/*` and `/internal/*`.

**e2e** runs on private ports, `E2E_*`, with a per-base build (root and `/chat`) and a throwaway compose project named `auth-e2e`. It uses real Authelia 4.39.22, a mock external OIDC issuer (the one Cerea's machine tests already use, extended with `email_verified` and groups control), MailHog or a Python `aiosmtpd` sink as the mock SMTP, Postgres, Mongo, gateway and chat, all under `timeout -s KILL … flock /tmp/heavy.lock`.

1. **Startup refusal:** an external IdP with no admin env. The gateway container exits non-zero with the message.
2. **Admin by email** (verified: granted; `"true"` string: not) and **by claim** (the group present, then removed and revoked at the next sign-in).
3. **Switching the IdP with users preserved:** bundled → external with `OIDC_LINK_BY_EMAIL=true`. A non-admin user's chat conversations and gateway memberships are present after signing in through the external IdP. The admin isn't linked, and gets a new account through `OIDC_ADMIN_EMAIL`. The admin merges their old account in, and the old chat history appears within one session check.
4. **Link-by-email with `email_verified=false` or absent:** no link, a new empty account, the refusal logged.
5. **Merge** from the console UI: the preview, the typed confirmation, then gateway and chat data under the target, and the source's chat session ended.
6. **The break-glass round trip:** external → `./configure --break-glass` → bundled. The same gateway id, the same chat conversations, admin working, the other bundled users signing in as before. Then back to external: the old external identities resolve again.
7. **Last-admin guard:** self-deactivation and demotion of the last admin refused in the UI and the API. A deactivated-admins scenario (via the DB) doesn't re-arm the bootstrap.
8. **Disabling a user kills their sessions:** a console tab gets 401 on its next call; the chat session is gone within 60 s; a galopin link closes within 60 s; the device shows revoked; the bundled login is refused by Authelia; an Authelia refresh for a disabled user is recorded as observed, whatever the answer.
9. **The reset flow with mock SMTP:** the Authelia portal's reset → the mail captured → the link followed → the new password works and the old one fails. Without SMTP the portal has no reset link.
10. **The Authelia watcher:** 50 resets through the API, each verified by a sign-in (§8.4).
11. **The upgrade migration** from the synthetic snapshot (§13).
12. **The enrollment one-liner** shown with values from the env, and the checkbox toggling the flag.
13. **Full erasure:** a user with conversations, files, a project shared with another user, a shared conversation link, a memory, an MCP token and an enrolled galopin device is deleted from the console. Every registry collection and GridFS bucket holds nothing for them; the share link answers 404; the other user loses the project; the device's link is closed.
14. **Erasure retry:** the chat container is stopped, and a user deleted. The gateway row stays `pending` and the banner shows. The chat restarts, and the retry completes: the audit shows `chat.erasure_done`. A second delivery of the same `erasure_id` returns the same counts.
15. **The edge refusal:** `/chat/internal/erasure` through the proxy answers 404, even with the right token.

## 17. Stages, branches, workers

The Sonnet workers use `claude/claude-sonnet-5`, at most two box-wide, after checking `list_agents`. 403b95ea currently holds both slots, so implementation starts when a slot frees. The branches:

| Stage | Pystino | cerea-deploy | Cerea | Contents |
|---|---|---|---|---|
| (a) | `auth/a-env-idp` | `auth/a-env-idp` | – | `identity_events` first, then guards and bootstrap, re-seed, validation, admin env rules, `azp`, the endpoint and UI removal, `SmtpSettings`, migration 0047, `idp check`, and `configure` and `--check`. |
| (b) | `auth/b-local-accounts` | `auth/b-smtp` | `auth/b-session-check` | Users page, pending users and binding, the flock, groups, one-time-password UI, disable cascade; the Authelia SMTP template and 2FA; the chat session check (`sessions_valid_after`, bounded fail-open). |
| (c) | `auth/c-link-merge` | `auth/c-erasure` | `auth/c-gateway-identity` | Link-by-email, merge, announce, `/v1/me` fields; the chat's gateway-keyed resolution, chat merge, `machineAuth` via the gateway, device revocation, the index migration; **delete with chat erasure** (§9.2 and §9.3), which shares the `USER_KEYED_COLLECTIONS` registry; the erasure token and the Caddy 404 in cerea-deploy. |
| (d) | `auth/d-break-glass` | `auth/d-break-glass` | – | `pystino break-glass`, `./configure --break-glass`, the round-trip e2e. |
| (e) | – | – | `auth/e-enroll-oneliner` | The one-liner and the re-enroll state (coordinated with 403b95ea about `fix/code-enroll-ux`). |
| (f) | `auth/f-docs` | `auth/f-docs` | – | The Pystino identity docs; cerea-deploy's README and `.env.example`; the one-IdP rule with Keycloak federation; break-glass; backup and restore; MFA and SMTP; switching IdP step by step.; **"Need MFA? Use an external IdP such as Keycloak (TOTP or WebAuthn there), configured through `.env`"**, linked from the one-IdP and Keycloak federation section. |

**Worker plan:**
- Worker 1 takes Pystino plus cerea-deploy through (a), (b), (c) and (d), in order.
- Worker 2 takes the Cerea branches (b), (c) and (e) once (a)'s API shapes have landed on their branch. The contracts in §4 are fixed now, so worker 2 can start with a stubbed gateway.
- I review every diff myself.
- **The security review is by Opus, at the end,** before any merge. It covers the linking, merge, erasure, break-glass, users-file writes, admin assignment and session revocation, across all branches. I do it myself, or the top orchestrator creates an independent Opus reviewer if I ask. The review goes to `reports/`, and its findings are sent to the top orchestrator before anything merges. There is no Fable reviewer.
- The merges are `--no-ff`, each after a heads-up: 403b95ea for Cerea, c308f8d0 for cerea-deploy.

## 18. Points to confirm

- **Q1, the stack's mail settings.** Decision 2 feeds Authelia's notifier "from the stack's email settings". Authelia reads its notifier only at start, from env or files, so the console-edited `email_settings` row can't feed it.
  - **My default:** SMTP moves to `.env` (`SMTP_*`, set by `./configure`), feeding both Authelia and the gateway. The console's email card becomes read-only, keeping "send test", and `./configure --import-smtp` migrates an existing row.
  - **The alternative:** keep console editing and have bootstrap render the row into Authelia's files at each `up`. Changes then need a restart the console can't do.
- **Q2, admin one-time-password reset without SMTP.** Decision 2 says "password reset only when email is configured". I read that as **self-service** reset. The admin-issued one-time password stays available without SMTP (item 14 audits "every reset", and break-glass prints one).
  - **My default:** keep it.
  - **The alternative:** without SMTP, the admin can only delete and re-add.
- **Q3, normalisation.** Python uses NFKC, strip, casefold; TypeScript uses NFKC, trim, `toLowerCase`. They agree on every address that can take part in a trust decision, because those must be ASCII (§6.1), and the shared vectors pin it. This is only for information.
- **Q4, delete and chat data.** The brief allows "consistent, or an explicit list".
  - **My default:** the explicit list. The chat's records stay unreachable, and a chat-side erasure hook is not built, because of the freeze.
  - **Say if the user wants** the gateway to call a chat erasure endpoint. That needs a new gateway-to-chat credential.
- **Q5.** The Open WebUI lessons report isn't in `ai-stack/reports` on `origin/main`. Point me to it if it exists; otherwise I've applied the lessons as listed in the brief.
- **Q6.** Directory sync (the `keycloak_admin` adapter and SCIM) stays available on the active provider (§14).
  - **My default:** keep it.
  - **The alternative** is to remove it with the provider UI.

### Answers (2026-09-25, top orchestrator)

- **Q1:** the default. SMTP moves to `.env`, the console email card is read-only with "send test", and `./configure --import-smtp` migrates an existing row.
- **Q2:** the default. The admin-issued one-time-password reset stays available without SMTP, and is audited.
- **Q3:** noted.
- **Q4:** the user decided that **erased users mean erased chats** (§9.2 and §9.3): a gateway-to-chat erasure call with its own service credential, idempotent and retried until confirmed, audited on both sides, covered by the preview. It joins stage (c).
- **Review:** no Fable reviewer. The security review is by Opus at the end (§17).
- **Q5:** there is no such report; the lessons as listed in the brief are enough.
- **Q6:** keep directory sync on the active provider.
