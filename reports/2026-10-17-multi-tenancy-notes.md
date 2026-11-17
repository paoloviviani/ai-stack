# Multi-tenancy for Pystino: working notes

2026-10-17. Not an ADR, and nothing decided. These notes capture a
conversation so it can be picked up later.

## The idea

Use Pystino as the foundation for a hosted service in the style of Cortecs:
- **Platform admins** fix the set of upstream providers and models.
- **Organisations (tenants)** run their own users, groups and quotas through
  their own admins.

## Identity: organisations are application objects, not realms

- There is one platform identity provider, the same "one IdP, no broker" rule
  as today. People sign in once.
- **Organisations live in Pystino's data.** A person creates one, or joins by
  invitation, and picks which one they are acting in. This is how most SaaS
  products work, and as far as we can tell Cortecs too: an extra billing and
  membership layer, with no OIDC realms per tenant.
- **Users are global; memberships belong to an organisation.**
  - A person can be in several organisations, with a different role in each.
  - The session or token carries the active organisation.
  - API keys belong to an organisation, so a key always implies its billing
    context.
- Today's `billing_group` (resolved per request from the caller's memberships)
  is the same idea one level down. The organisation becomes the billing
  account above groups.
- Per-organisation SSO (a customer bringing its own Entra ID) could come later
  as an enterprise add-on. It is not the foundation.

## What else it needs

1. **Router or gateway?** Cortecs's core is *routing*: one model offered by
   several providers, picked by price, latency, residency or ZDR, with
   fallback. Pystino maps a model to one provider. Multi-tenancy alone gives
   "a hosted Pystino per customer", not a Cortecs. Routing is a separate track,
   and it changes the catalogue: a platform model becomes a set of provider
   offers.
2. **Money has layers:**
   - what the platform pays upstream (cost);
   - what an organisation pays the platform (plan or contract price, margin);
   - optionally, an organisation's own internal chargeback to its groups.

   This also needs credits or a prepaid balance, invoices, VAT, usage export,
   and probably a payment provider.
3. **Quotas become a hierarchy.** The platform caps each organisation
   (contract, credit, rate limits), and organisation admins set group and user
   quotas inside that cap, never above it. Organisations must not starve each
   other: per-organisation concurrency and rate limits, with Valkey counters
   keyed per organisation. The existing engine covers much of this once rules
   and counters gain an organisation scope.
4. **Isolation enforced, not just modelled.**
   - `org_id` goes on everything an organisation owns: groups, memberships,
     keys, quotas, usage, audit entries and invitations.
   - Postgres row-level security acts as a backstop.
   - Tests must actively try to cross organisations.
   - User rows are shared, so reads of user data check that the caller can see
     the organisation in question.
5. **Roles.** Platform admin, organisation admin and member, with the console
   split by role. Platform support access to an organisation is audited
   (impersonation leaves a record).
6. **A model plan per organisation.** Platform admins choose which platform
   models an organisation can use, and possibly residency constraints (EU-only
   providers). Organisation admins grant models to their groups within that
   plan, as they do today.
7. **Per-organisation policy.** Redaction can only be made stricter than the
   platform minimum. Capability flags (coding agents, API keys) are set per
   organisation.
8. **Lifecycle.** Creation, suspension (for example when credit runs out),
   deletion with GDPR erasure, data export, DPA terms, log retention per
   organisation.

## Self-provisioning is the painful part

Open signup brings:
- fraud and abuse;
- payment verification;
- free-tier limits;
- stopping usage when credit runs out;
- support load.

A sensible first version: organisations are created by platform admins, or
self-signup stays inactive until payment or approval. Fully open signup only
once credit limits and suspension exist.

## Cerea

A Cortecs-style service is an API product. Making Cerea itself multi-tenant
(Mongo data, knowledge bases, agent machines) is a second, larger project.
Keep it out of scope: one Cerea per organisation pointed at the shared
Pystino, or no chat offered.

## If it goes ahead

1. Settle the scope:
   - router or not;
   - Pystino only, or Cerea too;
   - the money model;
   - self-signup or admin-created organisations.
2. Put organisations into the data with no visible change: `org_id`, row-level
   security, and a migration that makes today's deployment the `default`
   organisation, plus isolation tests.
3. Roles and the console split; organisation-scoped admin APIs.
4. Plans: model subsets, platform caps, price layers, organisation usage
   reports and export.
5. The commercial side: credits, payments, invoices, onboarding, suspension.
6. Routing, as its own track, if the service is meant to be a router.
