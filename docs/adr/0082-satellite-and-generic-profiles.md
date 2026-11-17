# 0082 — Cerea without a local gateway: the satellite and generic profiles

- Status: accepted, built
- Date: 2026-09-19
- Related: [0081](0081-public-model-listing-no-boot-key.md) (the public model
  listing, which is what lets a satellite hold no credential at all),
  [0040](0040-bearer-tokens-on-v1.md) (`USE_USER_TOKEN` — the mechanism that
  makes a satellite's every call the signed-in person's own),
  [0068](0068-minimal-idp.md) (the house IdP a satellite signs in
  against), [0070](0070-the-vector-store-belongs-to-the-chat.md) (why a
  gateway-less chat still keeps its own knowledge store),
  [0083](0083-ocr-one-shape-direct-endpoint.md) (how the generic profile reads
  documents, the one capability this decision would otherwise lose outright).

## Context

The deployment profiles until now — `homelab`, `team`, `enterprise` — differ in
what they switch on, not in shape: each is one box running a gateway with a
chat beside it. Two questions arrived that neither answers.

**Several Cereas, one Pystino.** A second site wants the chat without running a
second gateway. The obvious worry was authentication: separate deployments mean
separate user directories unless something is shared. That worry turns out to
be the answer rather than the obstacle — see below.

**A Cerea with no Pystino anywhere.** Somebody wants the chat against OpenAI,
the HuggingFace router, LM Studio or a commercial proxy, and has no interest in
running a gateway at all.

A third option was considered and rejected: shipping a cut-down gateway
alongside each satellite ("the lightest possible Pystino"). It buys
redact-before-egress — the one genuinely strong case, where prompts must not
leave the building unredacted — at the price of a second user directory, a
second provider and model catalogue mirroring central's, and a second ledger.
That is exactly the authentication mess the arrangement exists to avoid, plus
catalogue drift. It is not built, and the boundary where it would become
necessary is recorded at the end of this document.

## Decision

Two standalone profiles. Neither runs a gateway, Valkey, redaction, a smoke
upstream or a migration step; both run the chat, its MongoDB, its Postgres and
the proxy, which makes them *leaner* than `homelab`.

### `satellite` — Cerea against a central Pystino

`OPENAI_BASE_URL` is central's `/v1`. OIDC points at central's issuer.
`USE_USER_TOKEN=true`, so every call — inference, embeddings, OCR, the usage
tab — carries the signed-in person's own access token. **No key is stored
anywhere on the box.** The boot catalogue fetch needs none since 0081, and
every other call has a user to attribute.

The authentication worry dissolves on inspection: pointing the satellite at
central's IdP means one directory, one session, one `admin@local`. Adding a
satellite adds no users, no passwords and no keys. The installer refuses a
non-empty `OPENAI_API_KEY` on this profile rather than warning about it, because
a stored key would bill every user on that site to one account.

What a satellite inherits, it inherits wholesale: central's redaction policy,
central's transcript retention, central's grants, and central's `is_admin`
answer. **There is no such thing as a satellite-local administrator** — only
central administrators, who see the Admin row on every satellite.

### `generic` — Cerea against any OpenAI-compatible endpoint

A third-party base URL and one shared deployment key. `USE_USER_TOKEN` is
**forced to `false` in code, not offered as a toggle**, and a file setting it
true is refused at validation. This is the load-bearing rule of the profile:
user-token mode would put the signed-in person's IdP access token into an
`Authorization: Bearer` header sent to a third party, and that token also
unlocks their identity account. It is a credential leak, not a
misconfiguration, so it is enforced where it cannot be forgotten.

OIDC remains mandatory — an anonymous deployment answers nobody — but the
provider only proves *who someone is*. It confers nothing else, because there
is no gateway to confer it against.

What the profile loses follows from having no Pystino: no per-user billing or
quotas (all traffic lands on the key owner), no usage tab (it hides itself,
which was already the designed behaviour), no groups for sharing, no
per-caller model filtering, no redaction, no ledger. What it keeps is
everything chat-side: memory, skills, MCP connectors, code execution, web
fetch, transcription, and embeddings if the backend serves them.

## Consequences

- **Login needs browser → central reachability, not just server → central.** A
  satellite on a network where the server can see central but browsers cannot
  will never complete the code flow. No auth option fixes this; it is a network
  precondition and belongs in the install checklist.
- **A satellite cannot diverge on policy.** Redaction, persistence and grants
  are central's. A site that must not redact the way central does, or must not
  have its prompts centrally persisted, cannot exist in this shape. That
  boundary — divergent *policy*, not reachability — is the real argument for a
  local gateway, and the only one worth reopening the rejected option for.
- **The profiles compose in one direction.** A `generic` deployment can become
  a `satellite` later by pointing at a gateway and deleting its key. A
  satellite cannot become generic without losing per-user history attribution,
  because its ledger rows belong to central's users.
- **No local password store was added, and none should be.** Cerea has exactly
  two identity sources, an OIDC session or `TRUSTED_EMAIL_HEADER`; a third
  credential store diverging from central's is the mess these profiles exist to
  avoid. The proxy-header path is worth naming as a trap rather than an option:
  the session it synthesises carries **no token**, so under `USE_USER_TOKEN=true`
  every `/v1` call fails. It works only bundled with user-token mode off, a
  shared key and accounting off — a deliberately degraded shape that must be
  offered whole or not at all.
- **`gateway passwd` on central is the whole of satellite user management.**
  "OIDC is overkill for a homelab" is a statement about the protocol's
  reputation, not its operational cost here: the operator runs one command and
  the person signs in with an email and a password.

## Verified

Both profiles are implemented in Cerea's TUI installer with their env
fragments, and both guards are real code rather than documentation: the
satellite profile refuses a stored `OPENAI_API_KEY`, and the generic profile
refuses `USE_USER_TOKEN=true`.

One bug was found in the new code while reviewing it and is fixed: on the
`--phase2` resume path the standalone branch returned out of `main()` without
closing the readline interface, which hangs the installer after a successful
deploy and — if the terminal later sends EOF — prints "input ended
unexpectedly" over a deployment that worked.

**What is not verified: neither profile has been run end to end.** There is no
installer test suite; the standalone bring-up is covered by code reading, lint
and syntax checking only. The first real install of either profile should be
treated as the test it has not yet had.

One packaging question is unresolved and is not new to these profiles: every
`deploy/profiles/*.env` fragment, including the three that predate this work,
is matched by Pystino's broad `*.env` gitignore rule and so is absent from a
fresh clone, while `docs/deployment.md` cites those paths as canonical. How the
fragments are meant to reach an operator was not determined.
