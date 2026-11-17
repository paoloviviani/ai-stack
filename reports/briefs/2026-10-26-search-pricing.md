# Brief: per-request pricing for web search backends (Pystino)

Repo /home/ubuntu/workspace/Pystino (public). Owner: web search requests appear in the usage table billed at 0, which looks wrong. At the start we chose to bill searches by request on the Pystino side and settle the real vendor cost out of band; the machinery to attach a price exists. Add a **per-request price per search backend**. An operator who settles out of band sets it to 0. Ships in the next Pystino release.

## Read first
- AGENTS.md, CONTRIBUTING.md, the ADRs on pricing/currency (ADR 0053, 0054 are cited in code), `apps/gateway/src/gateway/accounting/` (`cost.py` `compute_cost`, `recorder.py`, which already records `own_search_backend` / `own_search_tier` on usage rows), `plugins/search.py`, `routers/search.py`, `models.py` (`UsageRecord` cost fields, the model price table and how prices are versioned / effective-dated), the console's Search admin page (`apps/console/src/routes/AdminSearch.tsx`) and Reports.

## Want
1. **Price data:** a per-request price for each configured search backend (and tier, if tiers are priced differently: decide from how `own_search_tier` is used; if unsure, price per backend with an optional per-tier override), in a currency, effective-dated and append-only like model prices, so a later price change never rewrites history. Reuse the existing price-row machinery or table shape where it fits rather than inventing a parallel system. Default when unset: no price, recorded as cost 0 with the price reference null, exactly like an unpriced model, so the gap is visible.
2. **Accounting:** each billed search request records its cost on its usage row at request time: `cost` (billing currency, through the existing FX conversion), `cost_native` / `cost_currency`, `computed_cost`, and the price reference. Searches done inside a chat completion (if the gateway runs them on the model's behalf) are priced too: one search = one request, whatever the result count. Quotas and budgets must count search cost like any other cost.
3. **Console:**
   - The Search page lets an admin set and see the price per request per backend (and tier), with its history and currency, worded plainly. Say that 0 means "billed out of band".
   - The usage and request tables show the search cost, not 0.
   - Reports include search cost, and a visible "unpriced searches" note when some searches had no price.
4. **Migration:** an Alembic migration (follow the repo's migration conventions and tests), additive only. Existing usage rows are not repriced (say so in the changelog).
5. **Docs:** the admin docs page for search/pricing and the CHANGELOG (Unreleased).

## Tests
- Pricing applied at request time; effective-dating (an old row keeps the old price); 0 price recorded as 0 with a price reference (distinct from unpriced, which has none); FX conversion; quota counting.
- The console Search page sets a price; the usage table shows it.
- Every new test is shown to fail without the change.

## Rules
- `git fetch origin && git worktree add -b feat/search-request-pricing /home/ubuntu/workspace/Pystino-wt-searchprice origin/main`; work only there.
- `export TMPDIR=/var/tmp/searchprice-tmp && mkdir -p $TMPDIR`.
- NEVER git stash, never --no-verify, no AI attribution. Push the branch only, no PR, never main. No nested sub-agents.
- Run only the tests you touch, plus ruff, mypy --strict on changed modules, console typecheck, i18n:check, api:check (regenerate the OpenAPI schema if the API changes). Don't run prettier over the whole console.
- CI: `gh workflow run ci.yml --ref feat/search-request-pricing -R paoloviviani/Pystino`, wait with an `until … completed` loop, and report the result.

Report: the data model chosen and why, migrations, every file changed, tests, CI result, and one screenshot of the Search page price field to /home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-26-search-pricing/.
