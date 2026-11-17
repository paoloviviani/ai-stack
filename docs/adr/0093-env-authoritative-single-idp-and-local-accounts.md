# 0093 — One identity provider set in `.env`, console-managed bundled accounts, identities that survive a switch

- Date: 2026-09-25
- Status: **accepted** (2026-09-25). It implements the user's eight decisions of 2026-09-25, and the top orchestrator confirmed the design.
- Supersedes: 0051's "rows belong to the console" (the provider row becomes a projection of the environment); 0056's `link_local_by_email` (replaced by `OIDC_LINK_BY_EMAIL`, which links across issuers); 0088's `admin_source` per provider row (replaced by the env admin rules); the plan's Proposal A and its self-service password change, which are not built.
- Amends: 0048 (group mappings live only in the global policy); 0069 (admin can come from env rules, with provenance `env`); 0091 (`./configure` owns the IdP, the SMTP settings and the break-glass).
- Related: 0040 (the `/v1` audience), 0057 (membership provenance), 0089 and 0090 (galopin enrollment).
- Detailed design, with the env table, schemas, flows and test plan: `reports/2026-09-25-auth-redesign-design.md`.

## Context

The console could add and enable identity providers at runtime while the chat read its issuer from `.env`. A switch on either side split the two apps. Every path could also strand the last administrator: an unguarded disable, a bootstrap address that re-arms, and a break-glass that needs a prior sign-in. The review (`reports/2026-09-25-user-management-and-idp-plan-REVIEW.md`) found three wrong premises in the plan:

- `link_local_by_email` only adopts `issuer="local"` accounts;
- `./configure --idp` never reaches an existing provider row;
- Cerea refuses a sign-in from a different issuer, so any switch orphans chat history.

The user decided on 2026-09-25. What follows implements those eight decisions plus the review's advice that is coherent with them, and nothing else. The freeze on all other work stands.

## Decision

1. **The environment is the only source of the identity provider (decisions 3 and 4).**
   - One provider at a time, named by `OIDC_*` in `.env`. The console, the chat and galopin read the same variables.
   - On every start the gateway re-seeds the provider row from the environment. If the issuer changed, it inserts a new row and keeps the previous one disabled, never deleted, so identities stay intact.
   - Every non-environment row is disabled.
   - The console's provider create, edit and delete endpoints and their UI are removed. `GET` stays, read-only.
   - Group mappings move to the global identity policy (0048), which the console keeps editing.
   - Closes review correction 3, R3 (the partial switch), R9 and correction 4.

2. **Startup validation.** The gateway refuses to start, with a message naming the variable, when:
   - an external IdP has none of `OIDC_ADMIN_EMAIL` or `OIDC_ADMIN_CLAIM` plus `OIDC_ADMIN_CLAIM_VALUE`;
   - only one half of the claim pair is set;
   - an admin email doesn't parse;
   - a variable of the removed local door is still set.

   It logs a WARNING at every start while `OIDC_LINK_BY_EMAIL` is on. `./configure --check` runs the same checks before `up`.

3. **Admin from env rules, evaluated at every sign-in (decision 5).**
   - **`OIDC_ADMIN_EMAIL`** grants admin only when three things hold: the IdP asserts `email_verified` as the literal boolean `true`, the normalised address is ASCII, and it is in the list.
   - **`OIDC_ADMIN_CLAIM` plus `OIDC_ADMIN_CLAIM_VALUE`** grants admin when the claim carries one of the values.
   - **Provenance `env`.** Grants are recorded as `env`. A rule can only revoke what a rule granted, never a console grant.
   - **Removing an address from the list** takes effect at the next gateway start, through a sweep, and at that person's next sign-in.
   - **The last active administrator is never revoked** by a rule.
   - **The bundled Authelia keeps the bootstrap address,** which fires once per deployment and never re-arms. Closes R1 (re-arm) and the silent-failure half of the plan's problem 4.

4. **The gateway user id is the person, everywhere (decision 6 and the addendum on chat).**
   - The gateway's `users.id` is the stable key. Links and merges only ever move identities onto it.
   - Cerea stores it as `gatewayUserId` and resolves every login and every machine token through the gateway (`POST /v1/session/announce`, `/v1/me`). It no longer matches `(issuer, sub)` on its own.
   - The chat follows gateway links and merges lazily but convergently: at login, and at its per-minute session check.
   - `CHAT_MIGRATE_ISSUER_FROM` and the cross-issuer refusal are retired wherever there is a gateway, and kept only for the gateway-less generic preset, with normalised matching.
   - Closes review correction 10, R3's one-way migration, and the chat half of R2's normalisation finding.

5. **Linking by email is an env switch, off by default (decision 7).**
   - With `OIDC_LINK_BY_EMAIL=true`, a first sign-in from an unknown identity attaches to the one existing account whose email matches, if all of these hold:
     - the new claim is `email_verified === true`;
     - the stored address was itself verified, or set by an administrator;
     - the address is ASCII after normalisation;
     - the account is active;
     - the account is **not an administrator**;
     - the account has no identity at this issuer yet.
   - Links are made only at the two sign-in doors, the console callback and the chat's announce, never by a plain `/v1` call.
   - Every link is audited, and every refusal is logged with its reason. Closes R2.

6. **Admins merge users in the console (decision 8).** `POST /admin/users/{source}/merge` moves the source's identities, memberships, roles, keys, ledger rows, rules and decision records onto the target in one transaction.
   - A test fails if any table referencing `users.id` has no merge rule.
   - The merge is irreversible. The confirmation shows a dry-run summary, and the operator must type the source's address. The undo is the backup taken before it.
   - The chat merges its own records when it next sees the target.

7. **The bundled Authelia's accounts are managed from the Users page (decision 2).**
   - Add creates the Authelia login and a gateway user at once. The gateway user is pending until its first sign-in binds it by login name and verified email.
   - Disable, enable, delete and one-time-password reset are available. Self-service reset through Authelia's own flow exists only when SMTP is configured.
   - The Authelia file carries no group except `users`; groups and roles are the console's.
   - Every write takes an advisory lock on a sidecar lock file and keeps the atomic replace.
   - Authelia operations are keyed by the login name bound in the directory mirror, never by the editable `users.username`.
   - Closes corrections 7 and 8, R4's locking and binding findings, R5 and R12.

8. **Disable means disabled everywhere.**
   - One action sets `is_active=false` and Authelia's `disabled`. It stamps `sessions_valid_after`, which ends the console session at the next request and the chat session within 60 s.
   - It deletes the gateway's own refresh credentials and authorization codes, and marks the user's galopin devices revoked.
   - Cerea's session check fails closed after a bounded grace.
   - Already-issued IdP tokens stay valid at the IdP until they expire, and are refused by the gateway and the chat. The design spells this out token by token.
   - Closes R7.
   - **Delete erases the person everywhere,** chat included (the user's decision of 2026-09-25):
     - the gateway calls the chat's internal erasure endpoint with its own service credential, `CHAT_ERASURE_TOKEN`, minted by `./configure`, used only on the compose network and refused from the edge;
     - the erasure is idempotent, recorded as pending on the gateway, and retried until the chat confirms, with audit on both sides;
     - conversations, files and attachments, projects, assistants, knowledge bases, memories, skills, MCP connectors and tokens, settings, sessions, devices, and the user's shared-conversation links are erased;
     - content shared with others disappears for them, and the delete preview names it;
     - merge is not erasure: it never deletes the target's data.
   - Closes R10.

9. **Break-glass is a host command, `./configure --break-glass --admin-email …` (decision 6).**
   - It switches `.env` to the bundled Authelia, keeping the external values in a backup. It then runs `pystino break-glass` in the gateway container and restarts the stack.
   - `pystino break-glass` finds or creates the gateway user, creates or re-enables their Authelia login bound to that user, grants admin, and prints a one-time password once.
   - No prior sign-in is needed. Users, memberships, data and chat records are preserved, because nothing but the provider rows' enabled flags changes. Closes R1 and the review's recommendation 5.

10. **Guards and audit.**
    - The gateway refuses to deactivate, demote or delete the last active administrator, self included.
    - An append-only `identity_events` table, protected by database triggers, records user, admin, password, link, merge, break-glass, re-seed and bootstrap actions. It lands first.
    - Admin rights can't be pre-assigned to a user who has never signed in. Only break-glass creates such an admin.
    - Closes R1, R6 and R8.

11. **`pystino idp check`**, wired into `./configure --check`, fetches the candidate IdP's discovery and keys. It can run one device-flow sign-in and reports:
    - `email`, `email_verified` and its type;
    - the groups claim;
    - `azp` and `aud`;
    - whether `OIDC_ADMIN_*` would grant admin.

    That's the review's recommendation 2 with no runtime candidate state.

12. **The enrollment one-liner** in `/code` prints the install, `galopin enroll --issuer … --gateway … --cerea …/chat [--client-id …] [--allow-terminal]` and `galopin run`. The values come from Cerea's feature flags, which gain the machine client id and the gateway origin.
    - Devices enrolled against an issuer that is no longer the configured one show "re-enroll", with the same command.
    - Closes review correction 9 and R3's machine half.

## Consequences

- An IdP switch is `./configure --idp external …`, then `./configure --check`, then `docker compose up -d`. It can't be half-applied, because both apps read one set of variables and the gateway re-seeds from them.
- People keep their accounts across a switch if one of these happens:
  - they link by verified email while the operator has the switch on;
  - an admin merges their old and new records;
  - the operator goes back through break-glass, which re-binds the same people.

  Every enrolled galopin machine re-enrolls after a switch.
- The console loses its identity-provider editor and the People dialog. It gains the Users page actions, a read-only provider card and an activity list.
- The gateway gains `POST /v1/session/announce`, and the chat must reach it at login. A chat on a gateway preset refuses sign-in while the gateway is down, instead of creating an unlinked account.
- Several simultaneous IdPs remain unsupported. The operator federates them in Keycloak or a similar broker.

## Rejected

- **A runtime or candidate IdP switch (Proposal A).** It puts IdP configuration on a runtime path in two apps for a switch done once. The review advised against it and the user decided against it.
- **A self-service password-change endpoint.** It would be a second, unthrottled verifier (R4). Authelia's own reset flow, with SMTP, covers it.
- **A session-bound "link my account" flow.** The user chose link-by-email plus admin merge.
- **The chat mirroring each link and merge by its own email match.** That means two matchers with two normalisations, which is R2's failure. The chat asks the gateway instead.

## Amendment (2026-09-26): no second factor with the bundled Authelia

The user decided that the bundled Authelia offers **no two-factor authentication**. This replaces the design report's §8.6, which briefly specified an opt-in two-factor switch.

**Why:**
- Authelia has no SMTP-free self-enrolment; registering a device verifies identity through the notifier.
- The only SMTP-free alternative, provisioning TOTP from the host, needs terminal access, which regular users don't have.

**What stays:**
- The bundled Authelia stays `one_factor`, with TOTP and WebAuthn explicitly disabled and Duo never configured, so no enrolment page is reachable.
- Deployments that need MFA use an external IdP such as Keycloak (TOTP or WebAuthn there), configured through `.env` under decision 1. The documentation says so beside the one-IdP rule.
- R12 is closed by this statement, not by a feature.
