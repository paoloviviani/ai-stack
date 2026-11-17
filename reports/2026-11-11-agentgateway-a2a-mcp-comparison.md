# agentgateway vs Pystino, A2A, and lessons for MCP (2026-11-11)

Owner question: we once considered agentgateway (https://github.com/agentgateway/agentgateway) instead of building Pystino. What does it provide today? Should we have used A2A for agent coordination and chat ↔ agent communication? What can we learn or reuse for MCP?

Source: agentgateway README and docs (1.7.x, latest; `agentgateway.dev/docs/standalone/latest/llms.txt`). I read the docs, not the code.

## Owner's conclusion

Keep what we have. agentgateway adds little for us beyond support and community.

## What agentgateway provides today

**Overlap with Pystino (or more)**
- **API surfaces:** chat completions, Responses, Anthropic Messages, Gemini, embeddings, rerank, audio, OpenAI Realtime, token count; translated across providers.
- **Routing:** "virtual models" (aliases), load balancing, failover.
- **Keys and budgets:**
  - virtual keys, stored as SHA-256 hashes, with per-key `allowedModels`;
  - per-key token or dollar budgets over a window (block or audit);
  - a model cost catalogue, per-user attribution, a cost dashboard and the `agctl` CLI.
- **Auth:** OIDC sign-in for the admin UI; JWT, API-key and basic auth.
- **Beyond Pystino:**
  - MCP gateway: federation, OpenAPI → MCP, OAuth, MCP authorization with CEL policies;
  - A2A;
  - Kubernetes Gateway API, and inference routing to self-hosted models (GPU and KV-cache aware);
  - OpenTelemetry traces and a Langfuse integration;
  - vendor guardrails (Bedrock, Azure Content Safety, Google Model Armor, webhooks);
  - context compression;
  - Rust, Apache-2.0, a Linux Foundation project.

**Gaps against what we need**
- **Privacy:** regex only. Built-in types are email, phone, SSN, credit card and CA SIN, plus custom patterns. Actions are reject, mask or audit. It has:
  - no NER;
  - **no restore** of masked values;
  - no stable (HMAC) placeholders, which matter for prompt caching and embeddings;
  - no masking of streamed responses (the docs say to use reject);
  - guards per model only, not per user or group;
  - nothing like the pipelines, content-based block, classifiers, or extract/reader routing.
- **Multi-user product:** keys are managed from the admin UI. There is no end-user console ("my usage, my keys, my privacy"), no billing groups, and no per-user quotas tied to the user's own token from Cerea.
- **Scale:** standalone mode keeps budgets and logs in SQLite and rate-limit buckets in memory per instance. Shared budgets need a remote rate-limit backend that you run. Pystino uses PostgreSQL plus Valkey.
- **Integration:** BYOK, web search, citations and the Cerea contract (per-user tokens, `routing_refused`) would all need rebuilding.
- **Complexity:** it is broader rather than harder (one binary, YAML, SQLite). The cost appears when you need multi-instance, per-user identity, and privacy through a webhook you write and run yourself. A webhook still cannot restore values into a stream.

**Verdict:** don't replace Pystino. Its differentiators (privacy with restore, per-user billing, the self-service console) are absent from agentgateway.

## A2A for agent coordination and chat ↔ agent

**Not the right foundation; maybe an edge adapter later.**
- **What A2A targets:** opaque, mutually untrusted agents, often across organisations. Each agent has an Agent Card at a reachable HTTP endpoint, and work is a task (submitted → working → input-required → completed) with messages and artifacts over SSE or push.
- **What Cerea ↔ galopin needs:**
  - one trust domain, so there is nothing to discover or negotiate;
  - **no inbound ports**: galopin dials out, so A2A would need our relay anyway;
  - fine-grained control: per-tool approvals (Plan / Ask / Allow), edit diffs, transcript paging, session resume, the usage meter, compaction and stop. Under A2A these would all be custom extensions.
- **The matching standard for this layer** is the Agent Client Protocol (ACP), which we already use for goose (`goose acp`).
- **Where A2A could fit later**, as small adapters, only when a real partner or use case asks:
  1. Cerea delegating to third-party A2A agents. This maps closely onto delegate and report-back (ADR 0099).
  2. Cerea publishing an Agent Card so other systems can hand it tasks.
- **Context:** A2A adoption trails MCP, and MCP's async tasks are narrowing the gap.

**Verdict:** no regret. Owning the internal protocol was right, because it carries approvals and permissions that no standard models yet.

## MCP: what to learn or reuse

Borrow designs rather than embed agentgateway: a Rust sidecar isn't worth it while Cerea's relay works. In order of value:
1. **Federation.** A single virtual MCP endpoint per user that merges every connector the user may use, with name prefixes and conflict handling. It would simplify galopin (the "MCPs exposed through galopin" path) and give policy one place to live.
2. **Admin tool-level authorization.** Rules by claim or group, e.g. "group X never gets `send_email`" or "write tools need Ask for everyone", next to the Plan / Ask / Allow ceiling. Cerea today has only per-user, per-call approvals.
3. **MCP OAuth spec compliance.** Protected-resource metadata, dynamic client registration, token passthrough versus exchange. Check `mcp_local_oauth` against it.
4. **OpenAPI → MCP tools.** Cheap connectors for internal REST APIs; possibly an easier route to C63 (M365 / Google).
5. **Tool input and output guards.** Pystino already screens tool results and restores into tool arguments. The lesson is prompt injection: an optional check on tool outputs before the model sees them, as a privacy-pipeline condition (webhook or classifier).
6. **OpenTelemetry span per tool call** (server, tool, user, latency, outcome). A natural first step for C71.

**If we pick one:** #1 together with #2, a federated, policy-filtered MCP endpoint per user. Not scheduled; the owner is to decide.
