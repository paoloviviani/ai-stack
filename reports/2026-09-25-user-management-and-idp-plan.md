# User management and identity providers: plan for review

Status: **HELD**. All auth and user-management work is stopped until this plan is reviewed (user, 2026-09-25).

## Decisions already taken

- Exactly **one** identity provider (IdP) at a time, shared by the console and the chat.
- No home-grown OIDC broker. An operator who needs several sources runs their own federating IdP (Keycloak, Authentik…) and points the stack at it.
- The bundled Authelia is the self-contained default.

## How it works today (Pystino `ba25a9a`, cerea-deploy `e8a178d`)

- **Admin assignment** is set per provider through `admin_source` (`identity_policy.py`, `ADMIN_SOURCES`):
  - `console` (default): admins are granted in the console;
  - `claim`: admin comes from a claim or group the IdP sends.
- **Bootstrap admin:** `PYSTINO_BOOTSTRAP_ADMIN_EMAIL` promotes a user only while the deployment has **no admin at all** (`oidc.promote_bootstrap_admin`).
- **Identity** is keyed on issuer plus subject. Signing in through a different IdP creates a **new** user with no memberships, unless `link_local_by_email` is on.
- **Break-glass:** `pystino admin grant` on the host.
- **The chat's issuer comes from `.env`** (`OPENID_PROVIDER_URL: ${OIDC_ISSUER}` in `compose.yaml`), not from the console. The console can add and enable IdPs at runtime, but those only affect the console's own sign-in page.
- **Users page:** the console's top-level Users page (`AdminUsers.tsx`) lists and manages users but can't create them. Creating an Authelia user works only through the People dialog under Settings → Identity providers (`AutheliaUsersDialog`, over `routers/directory.py` `/authelia-users`). It works, but it's awkward.

## The problem: activating an external IdP from the console with no admin group on its side

1. **Split sign-in.** The console moves to the new IdP, while the chat stays on the `.env` issuer (Authelia). That breaks the single-IdP rule.
2. **Nobody arriving through the new IdP has roles,** the operator included. Their admin rights stay on their old Authelia identity.
3. **Lockout.** If the operator then disables Authelia in the console, no admin can sign in. The bootstrap email doesn't fire, because an admin row still exists. Recovery needs `pystino admin grant` on the host.
4. **Silent failure with `admin_source=claim`.** If the IdP doesn't send the admin group, no admin is ever created, and nothing warns about it.

## Proposal

### A. One active IdP, set in one place
- The console shows the active IdP and offers a guided **Switch identity provider** flow that applies to the console **and** the chat together.
- This needs the chat to take its OIDC settings (issuer, client, secret) from the gateway at runtime, not from `.env`. `.env` would only seed the first IdP.
- Alternative, if A is too invasive: remove runtime IdP switching from the console altogether, and make `./configure --idp …` the only switch. That's simpler, but gives no GUI.

### B. A switch that can't lock anyone out, done in stages
1. Add the new IdP as a **candidate**. Nothing changes for anyone yet.
2. The acting admin signs in through the candidate once, as a test sign-in.
3. That new identity is linked to the admin's existing user: a verified-email match, confirmed explicitly.
4. If `admin_source=claim`, the switch stays blocked until the test sign-in shows that the claim yields admin.
5. Only then does the switch take effect, for both apps.

Standing guards:
- The gateway refuses to disable or delete the last provider through which an admin can sign in.
- The break-glass procedure is documented.

### C. One Users page for both kinds of IdP (extend `AdminUsers.tsx`)
- **With either IdP:** list users, roles and memberships, disable/enable, and a clear note on which actions happen in the IdP itself.
- **Bundled Authelia:**
  - **Add user** (username, display name, email, groups), with a one-time password shown once and a copy button;
  - **Reset password**;
  - the People dialog reduced to a link.
- **External IdP:**
  - accounts can't be created here, because they live in the IdP;
  - **pre-register by email**, with roles, that binds on first sign-in (the directory "preassigned" entries already exist);
  - where directory sync is configured (the `keycloak_admin` adapter, or SCIM), list people who haven't signed in yet.

### D. Self-service password change (bundled Authelia only)
- **With SMTP configured** (`email_config`): turn on Authelia's own reset-password flow.
- **Without SMTP:** a console "Change password" page with these safeguards:
  - it requires the current password;
  - it changes only the caller's own entry, keyed by the authenticated subject;
  - wrong current passwords are rate-limited and lock the account;
  - comparisons are constant-time and there's a password policy;
  - the password never appears in logs, and changes are audit-logged.

  It gets a line-by-line security review before merging.

### E. Documentation
- Managing users with the bundled Authelia.
- Switching to an external IdP, step by step:
  - a Keycloak worked example, plus notes for Entra ID, Google Workspace and Authentik;
  - redirect URIs, clients, scopes and the groups claim;
  - how admin is assigned;
  - what happens to existing users when you switch (issuer + subject identity, linking);
  - sign-out URLs;
  - break-glass recovery.
- **The one-IdP rule**, stated plainly: the operator's responsibility for multiple sources, with a Keycloak identity-brokering outline.

## Suggested sequencing, once approved

1. An Opus ADR plus a detailed design for A and B: the chat's runtime OIDC config, the staged switch, and the lockout guards.
2. C, the Authelia part, plus D and E. This doesn't depend on A and B.
3. A, B and C's external-IdP part, built in stages, with the lockout guards reviewed line by line.

## Open questions for the user

- A (runtime switch applied to both apps) or its alternative (no runtime switching; `./configure` only)?
- Should linking an identity at switch time require the IdP to assert `email_verified=true`?
- Pre-registration for external IdPs: roles only, or also group memberships?
- **Also held: the galopin enrollment one-liner.** It would have Cerea serve the IdP issuer and the public client id to `galopin enroll --cerea <url>`, so the short form stops prompting. Its source should follow decision A: the active IdP, wherever it's configured.

## Addendum (2026-09-25 evening): several IdPs at once, without a broker

This is an **input to the wider auth design discussion, not a decision.** The user wants one functional, flexible auth system designed as a whole. This addendum corrects my earlier framing: I treated "several IdPs" as if it required a broker. It doesn't.

**Already able to handle several providers:**
- **The gateway:** it picks the provider by the token's issuer and verifies against that provider's keys.
- **The console's sign-in page:** one button per enabled provider.
- **galopin:** each machine enrolls against its own issuer and client.

**What blocks it today:**
1. **The chat signs in against exactly one provider.** It inherits chat-ui's single OIDC config (`OPENID_PROVIDER_URL`, one client, automatic login, no chooser). Cerea also refuses a sign-in from a different issuer unless `CHAT_MIGRATE_ISSUER_FROM` is set (`src/lib/server/loginIdentity.ts`).
2. **The same person through two providers becomes two accounts,** because identity is issuer + subject, and nothing links them safely. `link_local_by_email` only adopts the old `issuer="local"` accounts. Matching by email across issuers is a known takeover risk.

**The standard path, with no broker:** each app is an ordinary OIDC client of several providers, and the user chooses one at sign-in. That needs:
- a provider chooser in the chat's sign-in, with one OIDC config per provider, taken from the gateway;
- relaxing the rule that refuses a different issuer;
- per-provider token settings, such as the audience;
- account linking by action: a signed-in user adds a second provider from their account page, proving control of both. Never automatic email matching. This is the security-critical part, and it matches the review's recommendation.

**Consequence for the docs:** don't describe multiple IdPs as "unsupported by design". Describe them as "not supported yet"; until then, operators can federate on their side (Keycloak, Authentik).
