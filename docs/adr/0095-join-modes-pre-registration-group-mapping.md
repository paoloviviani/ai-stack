# 0095 — Join modes, pre-registration for any issuer, and one group-mapping surface

- Date: 2026-10-12
- Status: **accepted** 2026-10-13 (`Pystino@14c8f61`, `Cerea@008cb9a0`).
- Amends: 0048 (policy fields: `auto_provision` / `unknown_user_policy` become a derived view over `join_mode`), 0093 (pending users are no longer bundled-only; the "Refuse" wording is replaced by per-mode texts).
- Related: 0069 (admins are made here, never by a claim — which is why admins are exempt from the gate), 0088 (directory provenance and the safety valve).

## Context

External identity providers leave three gaps: nobody can be created for them (`POST /admin/users` is bundled-only), group mapping is split across Settings, Groups and the environment, and the self-provisioning rules refuse strangers with a text that tells them to ask for an account an admin cannot create. The one-issuer contract (0093) stands; this decision is about who may join under it.

## Decision

1. **One `join_mode`** (`open`, `approval`, `invite`, `group`) replaces `auto_provision` plus `unknown_user_policy`, for any issuer. Legacy rows fold without behaviour change (`true` → `open`; `false` + `create_inactive` → `approval`; `false` + `refuse`/null → `invite`). `auto_provision` and `unknown_user_policy` stay one release as derived read-only properties, then are deleted.
2. **Pre-registration for any provider.** `POST /admin/users` on a non-bundled provider creates a pending user (no login, no `directory_entries` row), claimed at sign-in by verified email. The `create_user` branch goes through an account backend chosen from provider capabilities (`creates_logins`), not from the kind name, so a later bundled IdP (Zitadel) slots in without rewriting the Users page.
3. **The gate never writes `is_active`.** Losing a required group refuses access dynamically; regaining it restores access. Deprovisioning stays the directory sync's job (provenance, safety valve). The `/v1` bearer path makes no audit write and runs no extra query in steady state.
4. **`/v1` refusals are 403 `outside_access_groups`, never 401.** The caller is authenticated, so this leaks nothing as long as no group is named — and a 401 would make Cerea's machine revalidation revoke the device permanently, forcing a re-enrol for a loss that regaining the group restores. **Cerea must close (not revoke) the machine link on this 403**; that change rides the kit/Cerea step, not this branch.
4. **Administrators are exempt from the gate** (`is_admin` and env admin rules, checked before the stranger refusal), so a misconfigured `group` mode cannot lock every admin out. Break-glass is unchanged.
5. **One group-mapping surface** on the Groups page: every seen IdP name gets one decision (import as new, map to existing, ignore). The mapping editor leaves Settings; `PUT /admin/oidc/policy` keeps accepting `group_mappings` for scripts and tests.
6. **Invitations expire after 14 days** (`invited_at` + 14 days; an expired invite behaves as no invite under the join gate, and the Users page offers re-invite, which re-stamps `invited_at`). The brief proposed no expiry; the owner chose 14 days.
7. **The invite email is sent in this round** (`send_email` flag on the invite, default false, via the configured SMTP), not only when trivial. The brief proposed copy-paste text with sending only if cheap; the owner chose to build it.
8. **`kit/configure` keeps every mode as an explicit choice** for external IdPs and defaults to `approval`. Upgrades never change behaviour (the legacy fold); only new installs meet the new default. The brief proposed `approval`; the owner confirmed the options must stay visible because the current chooser is flaky.

## Rejected

- A custom broker or any IdP-side behaviour (standing rule: single IdP, no broker).
- Gating `group` mode on raw claim names: the gate reads local memberships so the `/v1` path stays query-free; a directory name must first be imported or mapped.
- Auto-approval by email domain: spoofable without `email_verified`; deferred.
- Replacing Authelia and its random passwords: Layer 2, needs a spike first, not decided here.
