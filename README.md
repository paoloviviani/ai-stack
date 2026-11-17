# AI Stack

**The coordination repository.** No code lives here. What lives here is the
decision record, the scope, and the map of which repository does what.

Split out of the Pystino monorepo on 2026-09-08. The reason: the gateway had
become a product that stands on its own, and the decision record had become a
record of an *endeavour* — one numbered series spanning a gateway, a chat
application, a RAG pipeline, a desktop shell and a design language. A sequence
like that cannot be cut in half without either renumbering, which
[the index](docs/adr/README.md) forbids, or leaving holes in two repositories.
Keeping the whole series in one place and letting the code repositories cite it
by number is the answer that costs the least.

## The repositories

| Repository | What it is | State |
|---|---|---|
| [pystino](https://github.com/paoloviviani/Pystino) | The gateway and its console: OpenAI-compatible `/v1` surfaces, accounting, quotas, redaction, the admin SPA | **Built and running.** Six `/v1` surfaces, 1241 tests |
| [Cerea](https://github.com/paoloviviani/Cerea) | The chat application, a `/v1` *client* — it imports nothing from the gateway | Restarting from scratch; the monorepo's version is archived, not carried over |
| this one | Decisions, scope, roadmap | — |

The boundary that makes this work is that the chat application talks to the
gateway over `/v1` with an API key or an OIDC bearer token
([ADR 0040](docs/adr/0040-bearer-tokens-on-v1.md),
[ADR 0046](docs/adr/0046-local-api-credentials.md)) — a supported public
interface, not an internal coupling. That is what removes the rebase debt the
monorepo had accumulated: when the split was made, the chat branch was **56
commits behind** the gateway's main, and every gateway change made the eventual
merge worse.

## What is here

- **[docs/adr/](docs/adr/README.md)** — the decision record, 0001 to 0060.
  Read the index first. An ADR whose decision was reversed is kept and marked,
  never deleted: the reversal is usually the most useful part.
- **[docs/architecture.md](docs/architecture.md)** — the topology across all
  three repositories.
- **[docs/phase-2-plan.md](docs/phase-2-plan.md)** — what Phase 2 planned and
  what was added afterwards, including the bugs each addition surfaced.
- **[docs/mcp-gateway-plan.md](docs/mcp-gateway-plan.md)** — an MCP gateway,
  scoped around authentication and access. Recorded, not started.
- **[docs/next-steps-plan.md](docs/next-steps-plan.md)** — the chat
  deployment: authentication stance, the seven steps, and the ADRs to cut.

Operational documentation stays with the code it operates: how to run the
gateway, how to deploy it, what it costs to run, and how to configure OIDC or
redaction are all in
[pystino/docs](https://github.com/paoloviviani/Pystino/tree/main/docs).

## How the citation works

Code in the other repositories cites decisions **by number** — `(ADR 0032)` —
and that reference stays valid wherever the file lives, which is the whole
reason the numbers exist. Roughly 690 such citations were left untouched by the
split. The ~250 links that were *paths* to a file were rewritten to point here.

Each code repository also carries a generated index mapping every number to its
title and its URL here, so a reader in the gateway is one click from the
reasoning without having to know this repository exists.

## Licensing

First-party code is under an OSI-approved licence ([ADR 0001](docs/adr/0001-licensing.md)):
Apache-2.0 in every repository since 2026-10-04 (ADR [0094](docs/adr/0094-apache-2.0-for-all-repositories.md)). The
dependency policy in 0001 applies to every repository in the table above. Anything with a non-OSI licence, a CLA or an
open-core model needs a decision before it is adopted.

## About this snapshot

This is a public snapshot. Screenshots, operational runbooks and some internal reports were left out, so a few
reports refer to files that are not here.

## Adding a decision

Copy the shape of an existing ADR. Number sequentially, never renumber, never
delete — supersede instead, and say which ADR supersedes which. The series is
shared across the repositories, so the next number is the next number here,
whichever repository the work lands in.
