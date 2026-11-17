# 0067 — Agents belong to the chat

- Date: 2026-09-12
- Status: **accepted, built; the wire-model presentation amended
  2026-09-13 — see *Amendment* at the foot**
- Corrects: the agents half of [0062](0062-knowledge-bases.md) — knowledge
  bases stay in the gateway; agents do not.
- Related: [0066](0066-publishing-and-platform-ownership.md) (whose sharing
  machinery agents used; they stop using it), the projects precedent (what a
  chat-side construction looks like when it needs the gateway's stores).

## Context

ADR 0062 put agents in the gateway: a served model with a prompt, tools and
knowledge bases attached, addressed as `agent:<name>` on `/v1/models`, so
that any OpenAI-compatible client could pick one without knowing what it
was. The reasoning was sound and the mechanism worked.

It was also overtaken by a decision about the product: **the chat is not a
standalone product** — it is this deployment's front end, tightly coupled to
the gateway on purpose. Once no second client is coming, the premise for
gateway-side agents ("any client, ever, with no code that knows agents
exist") buys nothing, and the cost it was paying — agents as a database the
chat edits through a forwarder, model cards the chat must merge, a sharing
ACL for objects whose natural audience is one person — is paid for nothing.
The operator's direction: *agents are only within the chat; they belong to
the user; sharing agents is deferred and off.*

## Decision

- **Agents move to the chat, whole.** A Mongo collection beside the
  conversations they serve; the model picker lists the caller's own agents as
  `agent:<name>` entries; the generation loop resolves the agent — swaps the
  model to the agent's underlying model, opens the system prompt with the
  agent's persona (conversation additions follow), and retrieves from its
  knowledge bases with the **reader's token** — before anything else in the
  turn happens. The gateway never learns an agent exists: the wire name is an
  agreement between the chat's picker and the chat's pipeline.
- **Agents belong to the user, and sharing is off.** No share routes, no
  publish routes, no `resource_shares` rows of kind `agent`. The owner's id
  in the query is the whole of the ACL. Sharing is *deferred, not designed*:
  if it ever returns, it is a decision to be made then, with ADR 0066's
  machinery still in place for the resources that need it (knowledge bases).
- **The name stays the address, and stays fixed.** A conversation keeps the
  model it was started with; that model is `agent:<name>`; renaming would
  strand every conversation using it. Creation sets it, edits refuse it, and
  an agent that has gone refuses the turn with the reason rather than
  answering as somebody else.
- **Knowledge bases stay in the gateway.** The agent names gateway vector
  store ids and searches them per turn with the user's own token — the
  projects retrieval pattern exactly, including the rule that retrieval
  degrades rather than fails a turn. Per-turn re-checking is what keeps an
  agent from being a way to read a document its user lost access to.

## What was rejected

- **Keeping agents in the gateway and simply disabling sharing.** It would
  have left the gateway owning a CRUD surface whose only consumer is the
  chat, reached through the forwarder with a bearer token that cannot be an
  administrator — the worst of both: gateway complexity, chat-side
  indirection.
- **Reusing chat-ui's `assistants` collection.** The shapes differ where it
  matters (pinned model, knowledge-base ids, retrieval limits) and agreeing
  with upstream's schema is not a goal this fork has anywhere else.
- **Per-agent sampling defaults.** The gateway's agents carried a
  `generation` block that was merged into the request. Chat-side it is
  dropped rather than threaded through the endpoint signature: a setting the
  UI offers must actually apply, and per-agent sampling has no current use
  case here. It can return with one.
- **Deleting the shared agents' data on the way out.** The migration drops
  the tables and refuses to downgrade: agent definitions moved to the chat's
  store, and recreating empty shells would be worse than stopping.

## Consequences

- The gateway's `agents` and `agent_knowledge_bases` tables are dropped, and
  `agent:<name>` on `/v1/models` and `/v1/chat/completions` means nothing any
  more — a caller sending it gets the ordinary "model not found".
- The chat's model list is the *caller's own* agents plus the catalogue, so
  the boot-time-catalogue staleness the old design had (an agent created
  after restart invisible in the list) cannot recur here: the list is read
  per request.
- Two capabilities the gateway's agents had are **not** carried: sharing, and
  per-agent tool merging. The chat's own tool selection remains
  per-conversation. Both are additive later if a use case appears.

## Tested

Named now, per ground rule 3: the list is owner-only and never crosses
users; create/update/delete are owner-checked; a duplicate name is refused;
the wire name is fixed at creation; a missing or renamed agent refuses the
turn with a message naming what happened; retrieval runs with the reader's
token and a failing base degrades the turn rather than failing it; the model
list carries the caller's own agents as `agent:<name>` cards with the
underlying model's capabilities; the gateway answers 404 for `agent:<name>`
on `/v1`.

## Amendment — 2026-09-13: a wrapper, not a model

This ADR put agents on the model list as `agent:<name>` cards, "so that any
OpenAI-compatible client could pick one". Built that way, the wire name kept
leaking: the picker offered the cards, and every route that touches a model
id — create, switch, message — then needed its own agent case, each added
after the last refused something the picker had offered.

The correction returns to what an agent is: **a passthrough wrapper on a
plain model**. A conversation pointed at an agent keeps the underlying model
and holds the agent by id; each request passes through, adding the system
prompt and the knowledge retrieval — live, not snapshotted, which is what
"passes through" means. A deleted agent leaves a plain chat, not an error.
Consequences:

- The model lists carry plain models only; the picker's agent cards and the
  per-route special cases are removed, net.
- Since conversations address the agent by **id**, the name is editable —
  the rename refusal this ADR inherited from the gateway existed only for
  the wire name.
- Ownership is unchanged (per-user, shared with nobody), and the ownership
  check is the lookup itself.
