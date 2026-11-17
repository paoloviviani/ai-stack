# Brief: per-user quota reset and a per-user quota consumption page (Pystino 0.19.0)

## What the owner wants
1. **Reset one user's consumption of a per-user quota.** A rule scoped to a group with `applies_to = each_member`, or to the whole deployment with `applies_to = each_user`, is enforced per user. The admin must be able to reset **that rule for a single user**, without resetting everyone's. Shared rules (a group's total, a global total) keep only the whole-rule reset; a per-user reset on them is refused.
2. **A dedicated page showing each user's quota consumption:** which quotas apply to each user, how much each has used of each, the limit, the window and when it resets, with the per-user reset from 1 available there.

## How resets work today (read first)
- `POST /admin/limits/{rule_id}/reset` (`routers/admin.py` ~3649) creates a `QuotaReset` row (`models.py` ~2630). `QuotaEngine.reset_epoch_for(rule)` (`quota/engine.py` ~355) takes the latest reset's `effective_at` as an epoch, which goes into the **counter key** (ADR 0025, `quota/counters.py` ~110-273). A reset therefore renames the keys, and the old values are orphaned. The ledger and bills are untouched.
- `scope_for_rule(rule, subject)` (~366-385): an `each_member` group rule counts under `(group, member)`, and an `each_user` global rule counts under `(user, person)`, the same counter a `scope=user` rule for that person reads.

## Design
- **`QuotaReset` gains an optional `user_id`:** a migration (next number) adds the column, a foreign key to users with the repo's erasure conventions (when a user is erased or merged, their reset rows go or move with them, following how other user-keyed rows are handled), and an index on `(rule_id, user_id)`.
- **The epoch for a subject:** `reset_epoch_for(rule, subject)` = the latest of the rule's whole-rule resets and that subject's own resets. Every call site that builds a counter query or delta for a subject (reserve, settle, `current_values`, notifications, `caller_usage`) passes the subject. Whole-rule-only callers keep the old behaviour. Make sure reserve and settle for the same request use the same epoch.
- **The shared-counter caveat:** an `each_user` global rule shares its counter with `scope=user` rules for the same person **only when the epochs match**. A per-user reset of the global rule gives it a new epoch for that person, so it counts from zero while that person's own `scope=user` rule keeps its count. That's correct (the reset is per rule), but check that nothing assumes the shared counter is one key, and document it.
- **The API:**
  - `POST /admin/limits/{rule_id}/reset` accepts an optional `user_id` (and the reason). It answers 422 if the rule isn't per-user, and 404 if the user doesn't exist or isn't subject to the rule (for `each_member`: not a member of the group);
  - `GET /admin/limits/{rule_id}/resets` lists both kinds, with the user's email for per-user ones;
  - everything is audited like the existing reset.
- **The consumption data:** an admin endpoint, e.g. `GET /admin/quota-usage?user_id=…`, or a paged list over users, returning for each user every rule that applies to them:
  - their own `scope=user` rules;
  - `each_user` global rules;
  - `each_member` rules of their groups;
  - the shared group or global rules they count towards (marked "shared", value = the shared total, no per-user reset).

  Each entry has the rule's metric, the limit, the current value for that subject (through the engine's `current_values` with the subject, so resets apply), the window and its next reset or roll-over time, and the latest reset (whole or per-user) with who did it. Honour the override rule (`overrides_each_user`: a user rule that replaces `each_user` rules of the same metric and window for that person): show the replaced rule as "replaced by …", not as a second budget. Pagination and search follow the console's existing user list.
- **The console:**
  - a new page **"Quota usage"** (under the existing quotas or limits section): a table of users (search, paging) with, for each, their most constrained quota (the highest percentage used) and a bar, then a click-through to the user's detail;
  - the user detail lists every applicable rule with bars, values, windows and the reset time, and a **"Reset for this user"** button on per-user rules (with a reason field, confirmed), and the shared ones read-only, marked shared;
  - also add the per-user reset to the existing user page if one shows quotas, so it's reachable from both places;
  - say "users", not "people", in new strings. Follow the console's design system and the i18n setup, if any.

## Tests (each fails without its fix)
- The engine: after a per-user reset of an `each_member` rule, that member's counter reads 0 and another member's doesn't; the same for an `each_user` rule; a whole-rule reset still resets everyone; reserve and settle use the same epoch around a reset.
- The API: a per-user reset on a shared rule gives 422; an unknown or non-member user gives 404; the audit row is written; the resets list shows the user.
- The consumption endpoint: the rules applicable to a user (all four kinds), the override shown as replaced, values honour resets, shared rules are marked, and non-admins get 403.
- The migration: up and down, and erasure or merge of a user with per-user resets.
- The console: the page lists users and opens the detail; the reset button posts with `user_id` and refreshes the values; shared rules have no reset button.

## Rules
- Read Pystino's AGENTS.md, CLAUDE.md and ADR 0025 first. Worktree: `git -C /home/ubuntu/workspace/Pystino worktree add /home/ubuntu/workspace/Pystino-user-quotas -b feat/user-quota-reset origin/main`. `export TMPDIR=/var/tmp/pystino-user-quotas-tmp && mkdir -p $TMPDIR`.
- Another Pystino worker is on `feat/tool-images` (a migration too). You'll both take the next migration number: when you merge origin/main before CI, renumber yours if it collides, and keep the down-revision chain linear. Don't touch its files (capabilities, `CapabilityPicker`).
- Run the PG leg as CI does. Use the heavy lock for builds and Docker; never wrap a self-locking script in another flock. Bind to 127.0.0.1, and kill what you start.
- Never git stash, never --no-verify, never force-push, no AI attribution in commits. The repo is public.
- Checks: pytest (SQLite and PG), ruff, mypy, and the console's typecheck, lint and tests. Screenshots of the Quota usage page and the user detail at 1440 and 412 px, in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-28-pystino-user-quotas/` (look at them yourself). Push, run CI once, and wait. Don't merge or release: this ships with Pystino 0.19.0 and Cerea 0.32.3.
- Report: the design as built, the migration number, the fails-without-fix evidence, the screenshots, the CI result, and changelog lines. No sub-agents.
