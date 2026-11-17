# 0098 — Per-member group quota rules

- Date: 2026-10-15
- Status: **accepted** 2026-10-15 (`Pystino@60006c1`, `Cerea@d0524064`; released as Pystino 0.9.0, shipped by Cerea 0.14.0).
- Related: 0009 (overrun policy, all rules must pass), 0024/0025 (calendar budgets, the reset watermark), 0052 (the quota notifier), 0057 (membership provenance), 0074 (the `/v1/pystino/usage` document), 0087/0091 (the contract and deploy pins).

## Context

A group rule caps the **aggregate** usage billed to that group: every request
billed to the group counts, by all members together. Operators also want the
opposite shape — "€50 per person per month on this group" — and today the
only way there is a `user`-scoped rule per member. That breaks two ways: a
new member arrives uncapped until someone creates their rule, and a departure
leaves orphan rules behind. Memberships are the only per-user fact the `/v1`
path already loads, so a group rule that counts each member separately needs
no new identity plumbing — only a second way to read the group scope.

## Decision

1. **`LimitRule.applies_to`: `aggregate` (the default) or `each_member`.**
   Every existing rule becomes `aggregate` in migration 0061, so nothing in
   force changes. `each_member` is meaningful only for `scope=group`: the
   admin API refuses it elsewhere with 400, and a check constraint refuses it
   at the database regardless of writer. `applies_to` joins
   `uq_limit_rules_identity`, so a group may hold both an aggregate rule and
   a per-member rule for the same metric and window. It is not updatable —
   like the scope and the window, changing it would orphan the counters under
   the old key.
2. **An `each_member` rule caps a member's usage billed to that group.**
   A request billed to group G by user U counts against U's (G, U) budget;
   U's spend billed to other groups does not count, and other members' spend
   does not count. Where both kinds exist the request must pass both — rules
   stay all-must-pass (0009), with no priority and no override. Spend through
   an API key counts against the key owner's (G, U): the quota subject
   already carries the owner, never the key. A request with no user skips
   per-member rules. No reserve path allows one today — the anonymous
   catalogue call runs no quota at all, the group-less `/v1/me` doors never
   reserve, and out-of-request callers (KB ingestion) still supply a
   principal — so the skip is a guard for a future path, not a live branch.
3. **Counting is a second key, not a second mechanism.** `ScopeRef` gains an
   optional `member_id` (group scope only); the counter key becomes
   `group:<G>:member:<U>` in all three stores. The Valkey key builder is
   generic over the key part, so the same `MULTI`/`EXEC` reserve-then-read
   keeps the admission atomic; the database store filters the ledger by
   billing group **and** user. Reserve → settle → refund is unchanged, and
   `load_rules` is still one indexed query per request, so the metered path
   keeps its query budget (`test_query_counts` gains a per-member case to pin
   it).
4. **Per-member counters have the same lifecycle as scope counters, expanded
   over members.** A member here is a user holding a membership in the group
   — the only per-user fact, and therefore the counter namespace. Seeding a
   new rule primes the members with usage in the window (one grouped query,
   not one per member); a cold-cache rebuild checks those same keys; a
   reconcile covers *all* members, because its job is drift repair and a
   zero-usage member with a non-zero counter is exactly the drift it must
   reach; quota health reports one row per member. Health is per member
   rather than sampled because each member's budget is independently
   enforced — sampling would hide one member's drift behind the choice of
   sample and make the output nondeterministic — and health is a diagnostic,
   not the hot path, so the per-member reads are an acceptable cost.
5. **Reporting names the member's share, never anyone else's.**
   `GET /v1/pystino/usage` shows a per-member rule as the caller's *own*
   limit and remaining, with an additive `"applies_to": "each_member"` so a
   client can tell the two kinds apart; nothing is removed, so existing
   consumers keep parsing. A 429 from a per-member rule says the member's
   share ran out (their own current, which they are entitled to know), a 429
   from an aggregate rule says the group's total ran out — neither names
   another member's usage. `quota health` (CLI and admin view) carries the
   member on each per-member row.
6. **The console offers the choice only where it means something.** The quota
   form shows "Applies to: the group's total | each member" for group scope
   alone; the rules list prints the mode with the limit ("€50/month per
   member"). The rules list has no single consumption figure for a per-member
   rule and says so plainly instead of borrowing the "counter unavailable"
   wording; the per-member consumption lives in the health table beside it.

## Consequence

The counter namespace grows with members × rules rather than rules alone;
Valkey key counts and the health/reconcile fan-out follow group sizes. The
migration backfills `aggregate` and the API default matches, so a deployment
that never touches the new control behaves exactly as before — including the
admin API, whose create still defaults and whose update still forbids
scope/window/mode edits.

## Rejected

- **A new scope value** (e.g. `group_member`): it splits the group concept
  across two scopes and two pickers, while one scope with two modes keeps the
  group identity — and its existence check — in one place.
- **Materialising one user rule per member**: rule churn on every join and
  leave, a silently uncapped window for every member without a copy yet, and
  orphans for every departure.
- **A sampled health view**: nondeterministic output that can only hide the
  drift of whoever was not sampled, on the one view whose job is drift.
- **"Most specific wins" between the two kinds**: the codebase already
  rejected priority between scopes for the same reason — a per-member rule
  silently raising a group ceiling would surprise exactly the operator who
  set both.
