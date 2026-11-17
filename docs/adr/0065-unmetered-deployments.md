# 0065 — A deployment may keep no ledger

- Date: 2026-09-11
- Status: **accepted, built.**
- Asked directly: *"Configurability of Pystino deployment (disable
  quotas/metering, leave only model discovery and serving, passthrough)."*
- Touches [ADR 0009](0009-quota-windows.md) (the counter store) and
  [ADR 0011](0011-usage-records.md) (the ledger).

## The decision

`GATEWAY_ACCOUNTING__ENABLED=false` turns off the ledger. The gateway still
discovers models, authenticates callers, enforces model access and redacts;
it writes no `usage_records` at all.

Quotas were already switchable (`GATEWAY_QUOTA__ENABLED`, honoured in
`QuotaEngine.check_and_reserve`), so the passthrough shape is both flags off
together.

## Why this is a real shape and not a convenience

Not every deployment of this gateway is a deployment that bills. Somebody who
wants routing, API keys, model access control and redaction — and has no
interest in what anything cost — was paying two database writes per request to
populate a table nobody would ever open. The reserve→record→settle path is the
most expensive non-upstream work a request does, and it existed for a question
that deployment never asks.

The point of writing it down rather than just adding a flag is the two things
that are *not* obvious.

## Off means no row, never a row of zeros

The tempting implementation is to keep writing rows and stop computing money.
It is wrong, and it is wrong in this project's characteristic way: a row saying
a request cost nothing is indistinguishable from a row where the arithmetic
failed. This codebase already spends real effort keeping those apart —
`usage_source` separates "the provider reported" from "we estimated",
`cost_source` names which figure billed, and `own_prices_fallback` exists
precisely so a fallback is never silent. Writing zeros would undo all of it for
a deployment that had merely turned the feature off.

So `begin()` returns `None` and inserts nothing, and `finalise()` returns
before `resolve_counts` and the price arithmetic — everything it computed would
be discarded, and computing it anyway is the cost this mode exists to avoid.

The corollary is that the report must **say so**. An empty usage report is
otherwise indistinguishable from an idle week, and a person reading one has no
way to tell. `_disclosures` now leads with a sentence stating that metering is
off, that this report covers nothing, and that requests are still served and
access still enforced. A gap is reported as a gap; that rule does not have an
exception for gaps we created deliberately.

## Quotas without a ledger are refused at startup

This is the part that would have been a silent disaster.

The counter store is a **cache, not the record**. Counters are rebuilt from
`usage_records` — which is why CLAUDE.md warns that flushing Valkey alone does
not reset a limit. With accounting off there is nothing to rebuild from, so
every counter comes back at zero, every window looks empty, and **every ceiling
silently passes**. The deployment would have quotas configured, an
administrator who believes in them, and no limit that can ever fire.

That is worse than having no quotas at all, because nobody would look. So
`Settings` refuses the combination at startup with a message naming the other
flag to set, rather than warning and continuing. Ground rule 3 is the reason
it is a hard failure: this is the quota path, and a wrong answer here is an
unenforced limit rather than a stack trace.

The asymmetry is deliberate and worth stating: **metering without quotas is
fine** — a ledger with no ceilings is just reporting — but **quotas without
metering is incoherent**.

## What this does not do

**It is not a per-tenant switch.** It is deployment-wide, read from settings at
startup. A gateway that metered some callers and not others would need the
decision on the request path, and every reader of a usage report would then
have to know which callers were excluded — the same reasoning that keeps
redaction scoping (ADR 0038) a matter of rules that can only tighten.

**It does not remove the tables.** Migrations still create `usage_records` and
the quota tables, and turning metering back on starts recording from that
moment with no schema change. A deployment that runs unmetered for a month and
then wants billing has a gap in its history, not a broken database — and the
report says which it is.

**Indexing is unaffected in shape but not in fact.** Knowledge-base ingestion
bills through the same `_metered` path (deliberately, so ingestion spend is
visible in the reports built to catch it). With the ledger off, that spend is
invisible too. That is the correct consequence of the choice, and it is the one
most likely to surprise: a large ingestion run can cost more than the chat
traffic it serves, and unmetered it leaves no trace here at all.
