# 0089 — The coding-agent host: an owned machine agent over `opencode serve`, replacing paseo

- Date: 2026-09-24 (drafted as 0086, renumbered to 0089 because 0086–0088 are the deployment re-architecture)
- Status: **accepted**. P0 and the nine parity milestones are merged into `main` in Cerea and Pystino and deployed.
- Supersedes: 0085, which adopted the paseo daemon and a self-hosted paseo-relay.
- Related: 0084 (the bundled IdPs and the `opencode-enrollment` device-grant client), 0040 (bearer tokens on `/v1`), 0061 (`x-bill-to`), 0086 (the stack the agent's Cerea side deploys in).
- Amended by: 0090 (files and a terminal on the machine agent; its C4 consequence for machines enrolled with those powers).
- Wire spec: Cerea `agent/PROTOCOL.md`. The agent was renamed **galopin** and moved from Pystino `deploy/agent` into Cerea `agent/` with its history on 2026-09-24; `pystino-agent` below is its former name.

## Context

0085 put paseo in the `/code` data path: a paseo daemon on the user's machine, a self-hosted relay, and Cerea holding each daemon's pairing offer as a bearer capability. The 2026-09-23 code and architecture review (§3.2) found that its tripwires had fired:

- **Churn.** A minor release came out every 11 days, and Cerea's exact-minor pin broke for new installs within 12 days.
- **Unsupported surface.** Cerea depended on `@getpaseo/client/internal/*`, which paseo documents as unsupported.
- **Trust model.** paseo assumes one person pairing their own devices, with no per-client identity, no revocation and no auth hook on the relay path. Used as a multi-tenant backend, that left Cerea holding a plaintext, irrevocable capability for every machine (review C4).
- **Two unrelated credentials.** The control axis ran on the daemon keypair and the LLM axis on the OIDC refresh token (review §3.3). Nothing bound one to the other.
- **Mostly unused.** The panel drove opencode only.

## Decision

Replace paseo with a thin agent we own.

1. **One binary on the machine**, `pystino-agent`, grown from the enrollment CLI. Its subcommands:
   - `enroll`: the device or loopback OIDC flow, as before;
   - `serve`: the `/v1` shim alone;
   - `run`: the shim, a supervised `opencode serve`, a session materializer and an outbound WSS link to Cerea.
2. **One credential root.** The enrollment's refresh token yields the access token that authenticates both `/v1` (through the shim) and the WSS link to Cerea. Revoking the grant at the IdP ends both within one access-token lifetime, because the link must renew its token in-band and is closed at `exp + 60 s` without a renewal.
3. **Cerea validates machine tokens locally**, against the issuer's JWKS: `iss`, `aud ∋ pystino-api`, `azp == opencode-enrollment`, and `exp`. It never asks userinfo (review C1).
4. **Pairing is "a machine enrolled as Alice appears in Alice's panel, pending, until Alice confirms it."** There is no paste flow, no pairing code and no stored offer. Revoking tombstones the machine id and closes the socket.
5. **A backend interface we own, shaped like ACP.** Its nouns are sessions, prompts, an update stream, permission requests (once, always or reject), cancel, modes and models. Optional capabilities cover what ACP lacks: usage, diffs, children and compaction. The first implementation is opencode over `opencode serve`'s HTTP API plus a single `GET /global/event` SSE stream. A generic ACP adapter is the planned second backend.
6. **Our own versioned wire protocol** between the agent and Cerea: JSON frames, typed ops and normalized events, carrying a per-session `(epoch, seq)` cursor and a text-part contract. With these, a snapshot plus deltas is exact and dedup is identity-based only.
7. **Machine-side policy that the link cannot write:**
   - `autoAccept` (denied by default);
   - `workspaceRoots`;
   - `allowFreeModels` (false by default, so only gateway models are offered).
8. **The relay goes away.** Cerea's origin terminates the WSS, and `@getpaseo/*` leaves Cerea.

### Why not ACP as the interface

ACP (JSON-RPC over stdio) is multi-vendor, and it covers the prompt, update, permission, cancel and mode core. It lacks, or has only unstable drafts for:

- session listing;
- usage and context reporting;
- diffs;
- subagent trees;
- more than one client attached to a session.

It also binds each session to the client process that spawned the agent. `opencode serve` offers all of the above, persists sessions across restarts, and serves every directory from one process. So the interface borrows ACP's vocabulary, and ACP becomes an adapter rather than the lowest common denominator. That adapter is how Gemini CLI, Claude Code and Codex (through their ACP adapters) and Pi (through `pi-acp`) plug in, each reporting fewer capabilities.

## Consequences

- **What C4 becomes.** Cerea stores nothing that reaches a machine: a database dump yields names and ids. Authority is per device and per user, and it ends on revoke or on IdP revocation. The machine can veto auto-accept and confine the directories agents work in. What remains: while a paired machine is connected, a compromised Cerea process can prompt it within the machine's policy. The panel is a remote control by design.
- **What we now own.** Reconnect, multiplexing, process supervision and the wire protocol, in Go on the machine and TypeScript in Cerea. opencode's API churns too, but it is one dependency instead of two, and it has a published OpenAPI document (`GET /doc`).
- **Deployment.** Cerea must be able to accept a WebSocket upgrade on its own origin. A single Cerea replica routes to its own live sockets, which is the same assumption the old pool made.
- **Installation on the machine.** `setup-agent.sh` shrinks to fetching the binary and running `pystino-agent enroll` and `pystino-agent run`. User service units come later.

## Verification

Verified live on 2026-09-24 against opencode 1.18.31 with the hermetic mock LLM:

- one `GET /global/event` stream carries every directory's events;
- `prompt_async` streams `message.part.delta` tokens, then `session.idle`;
- a bash tool call raises `permission.asked`, and `POST /permission/:id/reply {reply:"once"}` runs it;
- `OPENCODE_SERVER_PASSWORD` enables basic auth.

The real-machine end-to-end specs (Cerea `tests/code-machine-p0.spec.ts` and `tests/code-machine-parity.spec.ts`) exercise the whole chain: browser → Cerea → WSS → `pystino-agent` → a real `opencode serve`, with only the LLM and the IdP mocked. Both pass on the merged `main`, alongside the rest of the `/code` suite (44/44). The agent's own integration tests run against real `opencode serve` and `opencode acp` through an in-process mock LLM.

## What was built

Everything above, plus these specifics, which refine the draft:

- **Agent** (`deploy/agent`, one Go binary, the only dependency beyond the standard library is `coder/websocket`).
  - Subcommands: `enroll`, `serve` and `run`.
  - `run` mints the machine id in its state dir, supervises `opencode serve` (basic auth, process group plus Pdeathsig), and materializes sessions with a per-session `(epoch, seq)`. Every list on the wire is an array: Go's nil slices broke the first real pairing.
  - The link accepts prompt frames up to 160 MiB, because attachments travel inline.
- **Backends.** `opencode` over `opencode serve`, and a generic `acp` adapter (`run --backend acp --acp-command …`) that is proven against `opencode acp`. The ACP backend reports no usage, compaction, subagents or worktrees, because ACP has no messages for them.
- **Workspace concerns live in the agent, not the backend.** The Changes pane reads the checkout's uncommitted diff from git (opencode's own diff misses files written by a shell command). Worktrees are `git worktree` operations. Directory suggestions stay inside the policy's `workspaceRoots`.
- **Policy, enforced twice.** Non-gateway models are hidden unless the machine was enrolled with `--allow-free-models`: the agent filters them and reports how many it hid, and Cerea filters again and answers 403. Auto-accept needs `--allow-auto-accept`.
- **Cerea.**
  - The browser-facing `/api/v2/code/*` surface was kept. Behind it sit `machines.ts` (the registry, handshake, deadlines and token renewal), `machineAuth.ts` (local JWT validation, including the discovery issuer cross-check and bounded fetches) and a forwarder of typed ops.
  - The SSE bridge resumes on `epoch:seq`.
  - Transcripts still fold into chat messages. A native renderer is proposed as follow-up work.
- **Features at parity with the panel paseo gave:**
  - modes and models;
  - auto-accept, permissions and stop;
  - a context meter with compaction;
  - the git-based Changes pane;
  - subagent cards anchored at their task call;
  - images and files through chat's attachment store;
  - fork handoffs to a new session on any of the person's paired machines;
  - workspaces with git worktrees.
- **Not built:** agent-initiated handoff through an injected tool, which is follow-up work.
