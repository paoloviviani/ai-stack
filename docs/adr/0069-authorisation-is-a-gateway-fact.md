# 0069 — Authorisation is a gateway fact: the IdP authenticates, once

- Date: 2026-09-11
- Status: **accepted — implementation starting**
- Related: [0057](0057-group-ownership-and-sync.md) (the provenance and sync
  machinery this ADR gives a default), [0048](0048-oidc-policy-configuration.md)
  (the policy surface it amends), [0043](0043-local-authentication.md) (the
  "only automatic admin path" it removes), [0050](0050-group-management.md)
  (whose "manual groups only" this makes the whole story),
  [0068](0068-minimal-idp.md) (the house issuer, which follows the same rule).

## Context

The operator's directive, 2026-09-11: *for group assignment and roles,
Pystino must be authoritative, not the IdP.* An identity provider exists to
say who someone is; what they may do here — memberships, the default billing
group, the admin flag — is decided in this console and survives every login.

[ADR 0057](0057-group-ownership-and-sync.md) built the machinery and stopped
one step short of the rule: provenance per membership (`oidc` vs `manual`)
and a per-provider sync mode, with `every_login` the default and `never`
spelled out as *"authentication from the directory, authorisation decided
here"*. What was missing was a stance: a deployment had to opt out of
directory authority per provider, and one automatic admin path —
`GATEWAY_OIDC__ADMIN_GROUPS` — sat outside the machinery entirely.

## Decision

- **`first_login` is the sync stance.** It becomes the default for every
  provider created here, including the house issuer of
  [0068](0068-minimal-idp.md). The directory answers once, at provisioning:
  it creates the account and may seed its groups on the way in. Everything
  after — further membership, the default billing group, the admin flag — is
  a console fact and survives every login. (The operator chose `first_login`
  over `never` deliberately: provisioning should carry the directory's seed,
  and the gateway owns everything after.)
- **The automatic admin path is removed.** `GATEWAY_OIDC__ADMIN_GROUPS` goes
  away — not deprecated, removed. An administrator is made in the console or
  by `gateway passwd --admin`, never by a group claim. A deployment still
  setting the variable gets a startup error, not a warning: [0065](0065-unmetered-deployments.md)'s
  rule applies — a configuration that would silently do nothing is worse
  than one that refuses to start.
- **`every_login` and `never` remain per-provider choices.** The machinery of
  [0057](0057-group-ownership-and-sync.md) stays, and its provenance rule —
  a directory may revoke only what it granted — is what makes the modes
  safe to keep. A deployment that wants directory-driven revocation chooses
  `every_login` with eyes open; the change is the default and the removed
  admin path, not the removal of choice.
- **The house issuer follows the same rule.** Tokens from the gateway's own
  IdP provision exactly as a first login and never sync again; an account
  made admin in the console keeps the flag across every login from every
  issuer.

## What was rejected

- **`never` as the default.** The operator's choice: an IdP that may not seed
  anything at provisioning turns first login into an administrator's errand
  for every user, which is the cost of 0057's `never` and too much for the
  common case here.
- **Deleting the sync modes.** [0057](0057-group-ownership-and-sync.md)'s
  reasoning for provenance is what bounds them; the modes are the mechanism
  by which *this* stance is expressed per provider, not a rival to it.
- **Softening the removal to a deprecation.** A setting that means "I expect
  this to do something" and does nothing is a silent failure waiting for an
  audit. Refusing at startup names the change at the moment it matters.

## Consequences

- New providers default to `first_login`; existing rows keep whatever mode
  they were given — provenance, not retrofit.
- `is_admin` continues to be computed from held memberships, as
  [0057](0057-group-ownership-and-sync.md) already made it: a manual grant of
  an admin group works today and keeps working; the difference is that no
  claim can do it any more.
- The cost is named, as in 0057: a directory that stops naming a user's group
  cannot remove it here — the directory had its one answer at first login.
  Revoking a person's *access* remains a console act (disable the user), and
  that act is re-checked on every path.

## Tested

A new provider row defaults to `first_login`; an existing `every_login` row
survives untouched; a first login seeds groups exactly once and a second
login neither adds nor removes anything; an admin group claim on any login
does nothing while `gateway passwd --admin` and the console still do;
setting `GATEWAY_OIDC__ADMIN_GROUPS` refuses startup; the house issuer
provisions on first login and never syncs again.
