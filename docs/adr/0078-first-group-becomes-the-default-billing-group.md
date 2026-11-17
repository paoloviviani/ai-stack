# 0078 — A user's first group becomes their default billing group, on every path that grants one

- Date: 2026-09-18
- Status: **accepted, built**
- Extends the "sole group becomes the default" rule [0057](0057-group-ownership-and-sync.md)
  already applies on login, to the one path it did not reach. Depends on
  [0061](0061-per-request-billing-group.md) for why the console gets a picker
  rather than a second membership check, and on [0050](0050-group-management.md)
  for the admin group-membership routes this touches.
- Prompted by a failure on the live deployment, diagnosed and verified against
  the running stack and its database.

## The failure

The deployment's documented bootstrap administrator — created exactly as
`deploy/.env.example` and `docs/getting-started.md` instruct, with
`gateway passwd admin@local` and no `--group` — signed into the console, was
added to a group there, and then got a 403 on every single `/v1` call:
`/v1/me`, `/v1/models`, `/v1/billing/groups`. `resolve_billing_group`
(`deps.py`) said exactly why:

> No billing group is set for this key or user. Set a default billing group in
> the management API before making requests.

The account held a group **membership** but no `default_billing_group_id` —
membership is not the field that route reads. Checked against the database:
it was the only one of three accounts with a null default, and the only one
failing. Signing in again did not fix it, because a local account never runs
`provision_user` — there is no directory to sync from — and the route that
*did* run, `POST /api/admin/groups/{id}/members`, had no default-setting logic
at all.

That is the gap this ADR closes: not a missing case in one function, but one
whole membership-granting path that had never been given the rule the other
two already had.

## What already existed, and the one path that did not

Three places create a `Membership` row for a user who did not already have
one at hand:

| Path | Sole-group default rule |
|---|---|
| `provision_user` (`oidc.py`), the directory sync on login | **Present.** Clears an invalid default first, then adopts the sole remaining group — "order matters" is in the code's own comment |
| `create_user` (`routers/admin.py`), an account created with groups named at creation | **Present.** `if len(groups) == 1: user.default_billing_group_id = groups[0].id` |
| `add_group_member` (`routers/admin.py`), an administrator adding an *existing* user to a group | **Absent.** This is the path the bootstrap admin went through |

`gateway passwd --group` (the CLI) sets the default whenever it is `None`,
without counting groups — a narrower, deliberate CLI behaviour discussed below,
and left as it is.

## Decision

**`add_group_member` gets the same rule the other two already apply:** if the
user's `default_billing_group_id` is `None` and they held no membership before
this one, the newly granted group becomes their default.

```python
is_first_group = user.default_billing_group_id is None and not user.memberships
session.add(Membership(user_id=user.id, group_id=group.id, source=MembershipSource.MANUAL))
if is_first_group:
    user.default_billing_group_id = group.id
```

`user.memberships` is read **before** the new row is added, which matters for
a reason ADR 0057 already found the hard way: `user.memberships` is
`lazy="selectin"`, loaded once when the user was fetched, and a sibling insert
in the same session does not invalidate it. Reading it first is not a
workaround for that staleness — it is the question this rule actually asks
("did they have a group *before* this one"), and asking it before the insert
means the collection's staleness is irrelevant rather than merely avoided.

### Why "sole group", not "any null default"

The rule fires on the **zero-to-one** transition only, not on every grant made
while the default happens to be null. A user with two groups and no default —
because their old default group was just revoked, say — who is then added to
a third does **not** get the third one auto-picked. `test_a_second_group_added_before_any_default_does_not_pick_arbitrarily`
covers exactly this.

That restraint is [0061](0061-per-request-billing-group.md)'s argument,
applied one level earlier: *"the client picks one arbitrarily and does not
change the gateway... the arbitrariness belongs in the interface, not in the
money."* A user's first-ever group is not arbitrary — there is exactly one
group to choose and choosing it is not a guess. A third group added to someone
who already holds two and picked neither is a guess, and this rule declines to
make it automatically, the same way the login path declines to and the
self-service endpoint exists to let the person make it themselves.

### Never overwriting a deliberate choice

The `is None` half of the condition is the whole safeguard: a user who picked
a group, then joins a second, keeps their pick. `test_a_second_group_added_does_not_change_the_default`
covers it directly, and it was already true of the two paths this ADR is not
changing.

### What happens when the default's group is revoked

Unchanged, and confirmed consistent across both paths that revoke a
membership:

- `remove_group_member` (`routers/admin.py`) clears `default_billing_group_id`
  to `None` when it named the group just removed — `test_removing_the_default_billing_group_clears_it`.
- `provision_user` (`oidc.py`) does the same for a membership the directory
  drops, then — in the same pass, because "order matters" — re-checks whether
  exactly one group is left and adopts it if so.

The two paths look asymmetric (the login path can re-adopt a sole remaining
group in the same breath; the admin route only clears) and the asymmetry is
kept rather than closed. `remove_group_member` does not re-run the sole-group
rule after clearing, because removing a membership is not granting one — doing
so would mean an administrator's *removal* of a group silently *chose* a
different one as the new default, which is a bigger decision than "clear the
one that is no longer valid." A user left with no default and one remaining
group hits it on their next login (if the group is OIDC-sourced) or reaches
the console's picker (Change 2, below) either way. Clearing to `None` is
defensible on its own; leaving it clear until the person or their directory
says otherwise is the position this ADR takes, consistent with 0061 declining
to guess among multiple groups.

### `gateway passwd --group`, left alone

The CLI sets the default whenever it is `None`, regardless of how many groups
the account already has:

```python
if user.default_billing_group_id is None:
    user.default_billing_group_id = grp.id
```

This is not the sole-group rule and is not being made to match it. `gateway
passwd` takes exactly one `--group` per invocation and exists for the
chicken-and-egg case where no admin exists to use the management API yet — an
operator running it by hand, at a terminal, having just typed the one group
name they want, is a more deliberate act than a sync or a console click. There
is no report of it producing a surprising default, and generalising a rule to
a place nobody has asked for it is the failure mode ADR 0057 itself warns
against ("mixing authoritative and local membership silently produces access
nobody intended" — the half of that ADR's old rule that stayed right).

## Change 2 — the console can fix it, not just report it

The identity menu's "No default billing group" was a dead sentence: the
gateway's own 403 names the remedy — *"Set a default billing group in the
management API"* — and nothing in the console called that API. `Shell.tsx`
now offers a picker, restricted to the caller's own groups (`me.groups`), that
calls the existing `PUT /api/me/default-billing-group`.

No new endpoint, and no new server-side rule: that route already refuses a
group the caller does not belong to
([0061](0061-per-request-billing-group.md)'s membership re-check), so the
picker is UI and a fetch, nothing more. The menu item reads "Set default
billing group…" when there is none and "Change default billing group…" when
there is, and is absent entirely for a user in no group — a picker with zero
options is worse than the sentence it would replace.

### Deliberately not built: an admin sets it for another user

There is no route, and this ADR does not add one, for an administrator to set
*someone else's* `default_billing_group_id`. Two reasons, not one:

**It is a separate authorisation decision nobody has taken.**
[0061](0061-per-request-billing-group.md) made the billing-group choice the
user's own on purpose — re-checked against membership on every request,
changeable only through the self-service route or a request header the caller
sends about themselves. An admin-for-another-user setter is a different
capability: it lets one person's action decide where a *different* person's
future spend is attributed, and nobody has asked for or reasoned through that.

**It is not needed for the failure this ADR fixes.** The bootstrap admin's
problem was that no path *ever* set the default, not that the one existing
self-service path required them to reach it. Once the console offers the
picker, the account that hit this failure can fix it themselves in the same
menu the error told them to use — the missing piece was the UI calling an
endpoint that already existed, not a new admin capability.

If a real operational need for an admin-side setter turns up — an account
locked out of its own session, say — it should be argued for on its own,
against the same question 0061 already answered once: whether a *different*
person's action should be allowed to choose where someone's money goes.

## Verified

Unit, `apps/gateway/tests/test_group_management.py`, `TestFirstGroupBecomesDefault`:
`test_the_first_group_added_becomes_the_default_billing_group`,
`test_a_second_group_added_does_not_change_the_default`,
`test_a_second_group_added_before_any_default_does_not_pick_arbitrarily`. The
first was written and run against the unfixed route to confirm it failed for
the right reason — `default_billing_group_id` stayed `None` rather than an
unrelated error — before the fix made it pass.

Full gateway suite (`uv run pytest -q`), `ruff check .` and
`mypy apps/gateway/src services` all pass with the change in place; the
existing `test_group_sync.py` and `test_bill_to.py` suites (57 tests) are
unaffected, since neither path they cover was touched.

Console: `apps/console/src/components/Shell.test.tsx`, five new cases —
offering the picker with no default, offering "change" with one already set,
offering nothing to a user in no group, saving through
`PUT /api/me/default-billing-group`, and surfacing the server's 403 rather
than closing quietly. `pnpm -r test` (console and `packages/ui`, in the
`node:24-bookworm-slim` container this host needs) passes at 235 and 26 tests
respectively.
