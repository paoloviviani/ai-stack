# 0088 — OIDC-only identity: the house IdP goes, providers gain capabilities, policy and directory sync

- Status: **accepted**, 2026-09-24
- Supersedes: [0068](0068-minimal-idp.md) (the house IdP). It amends [0069](0069-authorisation-is-a-gateway-fact.md) (admin from a claim returns as an opt-in; the default is unchanged) and [0084](0084-bundled-idps-authelia-keycloak.md) (Keycloak is no longer bundled; Authelia is the one bundled IdP). If D3 is taken, it also amends [0043](0043-local-authentication.md).
- Keeps: [0010](0010-api-keys.md), [0040](0040-bearer-tokens-on-v1.md), [0048](0048-oidc-policy-configuration.md), [0051](0051-settings-identity-and-email.md), [0056](0056-account-linking.md), [0057](0057-group-ownership-and-sync.md), [0061](0061-per-request-billing-group.md)
- Design: `reports/2026-09-24-deployment-rearchitecture.md` §8, §10.2

## Context

The stack supports:
- a house OIDC issuer, with no device flow, so agent enrolment fails on it;
- bundled Authelia;
- bundled Keycloak;
- generic external OIDC;
- local passwords.

Each option multiplies the installer, routes and tests. Group sync is just-in-time only. The operator wants OIDC-only sign-in with the console controlling:
- batch user sync from the IdP;
- which claim carries groups, and whether groups are the IdP's or the console's;
- refresh-every-login versus seed-once;
- admin from a claim or from the console.

## Decision

1. **Humans sign in with OIDC only.** Authelia is the bundled IdP; any issuer can be brought instead. The house IdP is removed after a linking window (ADR 0056's `link_local_by_email`). A `PYSTINO_BOOTSTRAP_ADMIN_EMAIL` makes the first verified login with that address an admin while no admin exists. Break-glass is `pystino admin grant` inside the container.
2. **Providers have a `kind` that determines capabilities:**
   - claim groups;
   - directory pull (`authelia_file`, `keycloak_admin`);
   - push (inbound SCIM 2.0);
   - subject-before-login;
   - deprovision.

   The console shows only what a kind supports. Generic OIDC is JIT only, because OIDC has no listing API.
3. **Policy per provider, orthogonal knobs:**
   - `group_source` (`claim|directory|none`) says *where* groups come from;
   - `groups_claim` says *which* claim;
   - `group_sync` (`every_login|first_login|never`, default `first_login`) says *how often*;
   - `admin_source` (`console|claim`, default `console`) plus `admin_claim`/`admin_values`;
   - `internal_base_url` is the back-channel.

   Provenance extends to the admin flag (`users.admin_source`), so an IdP revokes only what it granted. A reconcile that would leave no active admin is refused.
4. **Directory sync writes a mirror** (`directory_entries`) and runs one reconciler shared with login and `/v1`. A pulled entry links to a user by subject where the IdP exposes it (Keycloak), or at first login by username plus verified email (Authelia's opaque subjects). Deprovisioning deactivates and never deletes. The first run of any adapter is a dry run, and a run that would deactivate more than max(5, 10%) of users stops for confirmation.
5. **The gateway is the only authorisation authority.** Cerea signs in against the same issuer with its own client, and keys users by `(issuer, sub)`. It reads admin, groups and active status from `/v1/me` with a 60 s cache, and ends the session when the gateway says the account is inactive.

## Consequences

- Fewer identity paths to test: one bundled IdP plus bring-your-own.
- An IdP change (a new client) reaches existing installs because the Authelia config ships in the `pystino-authelia` image and fills itself from the environment (ADR 0086).
- Batch deprovisioning becomes real for Authelia, Keycloak and SCIM-capable IdPs. Generic OIDC keeps only JIT, stated in the console.
- Admin-from-claim is back as a deliberate, per-provider choice with provenance and a guard, not a silent global path.

## Amendment 2026-09-24 (acceptance)

Accepted with D2 (Keycloak not bundled), D3 (no local-password web door; break-glass is `pystino admin grant`), D4 (admin from a claim as a per-provider opt-in with provenance), D10 (the console manages the bundled Authelia's users file) and D11 (inbound SCIM after the pull adapters; built). Two implementation facts worth keeping: an adopted install's existing provider row gets the environment's internal URL filled in once, or its gateway would keep calling the public issuer; and Authelia runs as the gateway's uid (PUID 1001) so the console can write its users file.
