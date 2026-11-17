# 0076 — Deployment profiles: one stack from homelab to enterprise, as env fragments plus a derived overlay list

Date: 2026-09-18

## Status

Accepted. Implemented as `deploy/profiles/{homelab,team,enterprise}.env` plus
`deploy/profiles/overlays.sh` in Pystino, with the matching profile section in
`docs/deployment.md`. The Cerea TUI installer and Pystino's `install.sh` both
consume `overlays.sh` rather than restating the overlay lists.

## Context

The Cerea + Pystino combination spans a central enterprise gateway with a
powerful chat interface down to a self-hosted homelab box, and the flag
surface that range needs is large: gateway env with restart-only semantics
(OIDC discovery is read once at startup), gateway database records that apply
immediately, chat env, the chat ConfigManager's live overrides, and build-time
values baked into images. An operator facing that surface as individual flags
misconfigures it — the inventory that motivated this ADR found failure modes
in the deployment's own example file where a misspelled variable was silently
discarded while its comment promised the feature was on.

The compose topology itself is not the problem: eight overlay files, each
adding one deliberate capability on one base file, with the overlays-separate-
from-base rule that a fake upstream must never be one careless `-f` from
production. What was missing is a named answer to "which flags and which
overlays for my size" — the three shapes below.

## Decision

**Three profiles — `homelab`, `team`, `enterprise` — each an env fragment plus
a derived overlay list, never new compose topology.**

| Profile | Fragment | Overlays (before exposure) | Shape |
|---|---|---|---|
| `homelab` | `deploy/profiles/homelab.env` | base + chat | No ledger and no quotas (ADR 0065, both off together — quotas without a ledger are refused at startup), no redaction service (`noop`), local passwords plus the house IdP, direct URL fetching, the browser code tool on, an empty `CHAT_USAGE_ENABLED` (no ledger, nothing to read). ~700 MB RSS, ~3.8 GB disk, 2 vCPU. |
| `team` | `deploy/profiles/team.env` | base + redaction (pattern-only) + chat | Homelab plus accountability: the ledger and quotas on, Presidio pattern-only (empty `SPACY_MODELS` build **and** `REDACTION_NLP_ENGINE=disabled`, ~150 MB) with the local extractor. +~300 MB RSS. |
| `enterprise` | `deploy/profiles/enterprise.env` | base + redaction (NER) + chat + Playwright (from Cerea) | NER redaction (`SPACY_MODELS=en_core_web_lg`, ~900 MB — and its licence: CC BY-NC-SA 3.0 where the default build is MIT throughout), the headless-browser fetch backend (+3.45 GB disk), an external OIDC provider instead of the house IdP, ledger and quotas on for per-group billing. |

Four rules hold across all three:

1. **The overlay list is derived by `profile_overlays <profile> <edge|proxy>`
   in `deploy/profiles/overlays.sh` — the single source.** The docs carry the
   same mapping as a table for humans; both installers call the function.
   Exposure is a second axis with no loopback option: the chat publishes no
   port, so without an exposure overlay it is unreachable, and compose refuses
   the set outright (the chat depends on the proxy).
2. **Smoke travels with nothing.** No profile selects the smoke overlay: a
   fake upstream in any production set is one careless `-f` from the failure
   the overlay model exists to prevent. Smoke stays a development shape,
   combined by hand with whatever it verifies. The redaction overlay carries
   no fixture stanza — at HEAD it published `8081:9099` with no interface,
   overriding smoke's loopback pin and putting the fake on every interface,
   which is why the edge overlay carried a re-pin at all. Deleting the stanza
   removed the hazard and the workaround together; the edge and proxy
   overlays know nothing about the fixture either.
3. **The chat overlay interpolates what profiles must vary, with house
   defaults.** `CHAT_CODE_TOOL/USAGE/KNOWLEDGE_ENABLED` use the no-colon form
   (`${VAR-default}`) so an explicitly emptied value stays empty — that is how
   homelab switches the Usage tab off. The chat's `OPENID_*` take
   `CHAT_OIDC_*` overrides defaulting to the house IdP, which is how
   enterprise points the chat at the external provider. Everything else in the
   chat overlay is untouched.
4. **The knowledge pipeline stays on in every profile.** Its Postgres is a
   second database on the gateway's instance, not a second container, so it
   costs nothing extra to keep. Deployments without that database set
   `CHAT_KNOWLEDGE_ENABLED=false` and the surface hides instead of erroring.

Fragments are complete `.env` templates: every secret ships empty with its
local generation command beside it (`token_urlsafe`, `openssl ecparam`), and
values no profile can invent — the upstream provider key, the external OIDC
client, the public origin — are empty slots the installer asks for. Three
values cannot exist before the stack runs (the catalogue `gwk_` key, the
local admin password, the chat Postgres role), so the installers bring the
stack up in two phases with resume.

## Consequences

- **The installers are thin.** Profile choice, per-component toggles within
  the profile, secret generation, and the two-phase bring-up are their whole
  job; the mapping they implement lives here and in `overlays.sh`, not in
  installer code. A new profile is a fragment plus a case branch, never a
  compose file.
- **Switching `SPACY_MODELS` between pattern-only and NER is a rebuild**, not
  a restart — the model is a build argument. The installers say so at
  selection time; changing it later re-runs the detection image build.
- **An existing `deploy/.env` needs a rename with the new compose files.**
  The house-IdP variables changed spelling to the `__` delimiter the gateway
  reads (`GATEWAY_IDP_ENABLED` → `GATEWAY_IDP__ENABLED`, and likewise ISSUER,
  INTERNAL_BASE_URL, INTERNAL_TOKEN, SIGNING_KEY, CLIENTS — six variables,
  the entire blast radius). `docs/deployment.md` carries the migration table;
  the rename and the compose files land in the same deploy, never one without
  the other.
- **Found while building, fixed alongside:** the deployment example
  misspelled two redaction variables (silently discarded — the exact failure
  the file says must never happen) and the upstream ones; the base compose
  interpolated single-underscore names while the migrate job already used
  double, so the two read different shell variables; `deploy/keycloak/
  setup.sh` printed the removed `GATEWAY_OIDC__ADMIN_GROUPS` tripwire (ADR
  0069); and the base compose forwarded `GATEWAY_KNOWLEDGE__*` values no
  settings section reads since ADR 0070 moved the store to the chat.
- **What profiles do not cover.** Development shapes stay manual: the
  smoke-only dev stack, the override conveniences, the Keycloak underlay.
  Per-group billing is console records after boot, not environment. The
  deferred items from the flag review — a deployment-level tool-approval
  switch and the ConfigManager's single-consumer generality — are a later
  pass, not profiles.
