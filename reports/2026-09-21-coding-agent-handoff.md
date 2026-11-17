# Handoff — Self-hosted coding-agent integration, and the missing relay

Date: 2026-09-21. Written to hand the work to a fresh agent with **zero prior
context**. Read this top to bottom before touching anything. The near-term
frontier is the **relay / daemon connectivity layer** (Section 5) — everything
else is either built or is live-verification of built code.

---

## 0. One-paragraph orientation

We are letting a user run a self-hosted **`opencode`** coding agent on any
machine they like (laptop or cloud box), driven from a **dedicated screen in
the Cerea chat app** (a separate surface, like Claude Code in the Claude app —
*not* a chat mode), with the agent's LLM traffic going through our
OpenAI-compatible **Pystino gateway `/v1`** so it lands in the same
billing/quota/redaction ledger as chat. Two halves are built: (1) the agent's
**authentication to `/v1`** (an enrollment CLI + IdP clients, in Pystino), and
(2) the **chat-side `/code` panel** (client UI + server proxy + pairing broker,
in Cerea). The **connective tissue that lets the chat server reach a daemon on
a user's NAT'd machine — the relay — does not exist yet.** That is the key
missing piece.

## 1. The goal and its hard constraints

- Users deploy the agent **wherever they want**: their laptop, a cloud VM,
  a homelab box.
- **No tailnet / VPN** may be required of the user, and setup must be **as close
  to zero-config single-binary as possible**.
- A laptop is typically **behind NAT** with no inbound reachability.
- The differentiators (why this beats just running opencode standalone): **one
  SSO login for chat + agent**, **one billing/quota/redaction/audit ledger**
  (because the agent talks to our `/v1`), and a **place to delegate a coding
  task per-user**.
- **opencode-first**; other agents are a later config concern, not a blocker.

## 2. Architecture at a glance

```
                         ┌─────────────────────────── Cerea (chat) ───────────────────────────┐
  Browser  ── OIDC ───▶  │  /code panel (Svelte)  ──▶  api/v2/code/* (SvelteKit server proxy)  │
  (the user)             │                                     │  (holds daemon creds/pairing) │
                         └─────────────────────────────────────┼───────────────────────────────┘
                                                                │  ??? THE RELAY (missing) ???
                                                                ▼
  User's machine (laptop / cloud, behind NAT):  paseo-style daemon ──▶ opencode ──┐
                                                 └─ enrollment CLI `serve` shim ───┴─▶ Pystino /v1 ─▶ providers
```

Two independent trust axes — keep them separate:
- **Agent → `/v1`**: authenticated by the **enrollment credential** (Section 4a).
  The relay is *not* involved here.
- **Chat server → daemon**: authenticated/pairing brokered by **Cerea**; the
  relay is an **identity-blind** untrusted middle (see Section 5).

## 3. Credential & auth model — the load-bearing facts (verified in code)

These were established by reading Pystino's source; a future agent must not
re-derive them wrongly (an earlier report got the ADR citation wrong):

- **`/api/*` (incl. `POST /api/me/keys`) is session-cookie only**
  (`get_management_user` reads the cookie; `deps.py`). A bearer client — the
  CLI *or* Cerea — **cannot mint an API key**. Key minting is a browser/console
  action.
- The gateway is built for opencode to **call `/v1` as the human via an OIDC
  access token** (`config.py`: "device flow) call the gateway as the human
  using it **without minting**"). That is **ADR 0040** (OIDC bearer accepted on
  `/v1` when an audience is configured). Access tokens expire fast, so a
  refresh mechanism is required (that is the `serve` shim, Section 4a).
- **ADR 0010** = API keys (`gwk_…`, minted once via the session-authenticated
  console) — the pasted-key fallback path.
- **ADR 0046 does NOT apply** to a headless CLI (it is chat-session scoped and
  explicitly leaves opencode on its own door). Do not cite it for agent creds.
- **ADR 0061**: an OIDC-token caller picks its billing group per request via
  `x-bill-to` (options from `GET /v1/billing/groups`); an **API key may not**
  send `x-bill-to` (refused) — its group is fixed at mint.
- **Spend/quota is not readable via `/v1`** (no `/v1/usage`, no rate-limit
  headers; only `retry-after` on 429). Usage visibility lives in the console,
  never in opencode.
- **ADR 0084**: the installer can bundle **Authelia 4.39.x** or **Keycloak
  26.7.3** as the IdP; audience `pystino-api`, issuer derived. Both support the
  device grant (Authelia since 4.39.0; pin ≥4.39.22 for its device-grant
  bugfixes). The **house IdP (`idp.py`) has no device endpoint** — device flow
  requires the external bundled IdP.

## 4. What is already built

### 4a. Pystino — agent authentication  (repo `/home/ubuntu/workspace/Pystino`, branch `opencode-enrollment`)

Commits (all build/vet/test/gofmt clean; Go 1.27.1 is installed at
`/usr/local/go`):
- `e4c3c40` — a **public OAuth client `opencode-enrollment`** added to BOTH
  bundled IdPs (`deploy/idp/generate-authelia-config.sh`,
  `deploy/idp/keycloak-realm.json.template`), same client id on both; PKCE S256,
  `authorization_code` + device grant, `groups` scope, audience `pystino-api`.
  Authelia pinned ≥4.39.22. Plus `deploy/opencode/install.sh` +
  `opencode.json.template` — the **pasted-key** path (ADR 0010).
- `880b124` — enrollment CLI **`enroll`**, loopback-PKCE flow.
- `f64701a` — **`enroll`** device-code flow fallback (headless boxes, RFC 8628).
- `ff7e411` — `.gitignore` for the Go build artifact.
- `c52a6d4` — **`enroll serve`**: the local refreshing proxy shim. opencode
  points `baseURL` at it; it refreshes the access token under a lock, injects
  `Authorization: Bearer` + `x-bill-to`, forwards to `/v1`, streams responses
  unbuffered (SSE). Shim port recorded on the credential.
- `a15115a` — **IdP redirect alignment**: both IdPs register the canonical
  portless `http://127.0.0.1/callback` (+ localhost), relying on RFC 8252
  loopback matching for the CLI's ephemeral port.

The Go module lives at `deploy/opencode/enroll/` (`enroll.go`, `oauth.go`,
`device.go`, `serve.go`, `store.go`, `gateway.go`, `prompt.go`, `main.go` +
tests). **It produces a working opencode↔`/v1` setup. It does NOT do relay
pairing.**

### 4b. Cerea — the `/code` chat panel  (repo `/home/ubuntu/workspace/Cerea`, branch `code-panel`)

A dedicated top-level `/code` route (NOT a chat mode — a "mode" here is a
`Conversation` flag and is inherently conversation-bound). Flag-gated on
`CODE_AGENTS_ENABLED`; per-user, OIDC-session gated; the browser never talks to
the daemon directly. Commits:
- `f38a07b2` — scaffold + pairing: route + `+page.server.ts` 404-gate,
  flag-gated `NavMenu` row, `CodePanel`/`DeviceTree`/`PairDeviceDialog`,
  `api/v2/code/devices` (list/revoke) + `enroll` (start/claim), a `codeDevices`
  Mongo collection (owner-scoped, single-use codes). Reads cleanly with no
  daemon configured.
- `1ad6d328` — read-only view: `api/v2/code/[...path]` **allowlisted daemon
  forwarder** (server-side credential, unlisted→404, version pin) +
  `api/v2/code/agents/[id]/stream` **SSE bridge** (validated frames, unknown
  dropped); `AgentTimeline`/`AgentDiff` (reuses `artifactDiff`)/`AgentView`.
- `6f042e7e` — control: `AgentComposer` (posture defaults to `plan`, writes
  opt-in), `PermissionCard` (blocking approve/deny).
- `5332a89d` — review fixes: SSE single-read-loop + independent heartbeat (no
  read-race); pairing TTL (unclaimed codes self-expire, paired devices never
  swept).

**Key stubs in the panel** that the relay work must replace:
- `enroll`'s `claim` is a **stand-in** for a real daemon pairing callback.
- **All daemon traffic goes to a single `CODE_DAEMON_URL`** — there is no
  per-device routing. `codeDevices` rows carry a `daemonId` field ready for it.

## 5. THE MISSING PIECE — the relay / daemon connectivity layer

This is what to build (or adopt) next, and the reason the panel can't yet reach
a real agent on a user's machine.

### 5.1 The problem, precisely
The chat server (ours, in the cloud) must reach a **daemon on the user's
machine, which is behind NAT, with no VPN/tailnet, zero-config**. Inbound
connections to the user's box are impossible. The only shape that works is:
the daemon **dials outbound** to a **rendezvous/relay** that both sides can
reach; the chat server meets it there. The daemon opens **no ports**.

### 5.2 The shape (paseo's model, which fits our constraints)
- A **self-hosted relay**: a small service the operator deploys once (its own
  container). The daemon connects **outbound** to it and stays connected; the
  chat server connects to the same relay and is routed to the right daemon.
- **Identity-blind / untrusted middle**: the relay should see only
  IP/timing/sizes, not content — traffic E2E-encrypted between chat-server and
  daemon (paseo uses Curve25519 ECDH → NaCl box). **Do not make the relay
  validate OIDC tokens** — that would destroy the untrusted-middle property.
- **Cerea brokers pairing**, because the relay is identity-blind: a user's
  device is a `codeDevices` row owned by that user; pairing associates that row
  with a daemon reachable via the relay.

### 5.3 Options (build vs adopt)
1. **Adopt paseo daemon + self-hosted paseo-relay** (Apache-2.0). This is the
   off-the-shelf shape: single daemon image, relay in one container, the exact
   NAT-traversal + E2E model above. The daemon also manages worktrees/terminals
   and runs `opencode` (and 39 other agents). **Lowest effort.** Risks: the
   daemon HTTP API is de-facto (not a frozen contract) and the project moves
   fast — pin a version, keep it behind the `api/v2/code/*` proxy (already done).
   *(These are vendor-doc claims; verify against paseo's current docs — no live
   daemon was available in this environment.)*
2. **Build our own single-binary daemon that dials our own relay**
   (frp/rathole/chisel/bore-style tunnel embedded, multiplexing opencode's HTTP
   over WSS; add a key exchange for E2E). Truly ours, truly single-binary — but
   you are rebuilding reconnect/auth/multiplexing that paseo already solved.
   Only choose this if owning the binary matters more than shipping.
3. **`cloudflared` per box** — rejected: SaaS dependency in the path, two
   binaries, against the self-hosted ethos.

**Recommendation:** start with option 1 for a PoC (retire the integration risk
fast), keep option 2 in mind only if paseo's API churn or licensing becomes a
problem. Note the enrollment CLI's `serve` shim + opencode config are
independent of this choice — they run *on the daemon's machine* regardless.

### 5.4 How it wires into what's built
- Cerea's `api/v2/code/[...path]/+server.ts` currently targets one
  `CODE_DAEMON_URL`. With a relay it must **route per user/device**: look up the
  caller's paired `codeDevices` row, get its `daemonId`, and address that
  daemon **through the relay** (not a direct URL). This is the main server-side
  change.
- `api/v2/code/enroll`'s `claim` stub becomes a **real pairing handshake**: the
  daemon (having dialed the relay) presents a pairing code the user got from the
  panel; Cerea verifies it against the user's pending `codeDevices` row and
  records the association (daemon's relay identity / public key).
- The SSE bridge (`agents/[id]/stream`) already owns the single daemon
  subscription — it just needs to open that subscription **via the relay** for
  the caller's daemon.
- On the daemon machine: it runs `opencode` + the enrollment CLI's `serve`
  shim; the shim is what gives opencode a live `/v1` credential. The relay
  carries the **control** channel (chat ↔ daemon); the shim carries the
  **LLM** channel (opencode → `/v1`). Two separate paths — don't conflate them.

### 5.5 Open questions to resolve in the PoC (highest-risk first)
1. **Per-user pairing / multi-identity.** We chose *per-user* pairing (each user
   pairs their own daemon; Cerea proxies per-user). Confirm the daemon/relay can
   represent **multiple independent user↔daemon pairings** and that the chat
   server (one process) can hold/route many of them. This is the single biggest
   unknown.
2. **What is the chat server's identity to the relay?** It is not a human phone.
   Either it holds one pairing secret per user-daemon, or it is a privileged
   relay client that can address any paired daemon. Decide, and bound the trust.
3. **Where do worktree mounts / filesystem scope get set?** Agents read/write
   whatever the daemon sees — the installer must scope mounts (no `.env`-bearing
   dirs; dedicated worktree roots). Default agent posture stays plan/read-only
   until the user opts in (the panel already defaults to `plan`).
4. **Adopt-vs-build decision** (5.3) — make it explicitly, in an ADR.

### 5.6 Suggested first step
A script-driven PoC on one box, no Cerea changes: run the paseo daemon (or the
chosen relay) + `opencode` pointed at our `/v1` via the `serve` shim; from
"outside," drive: pair a device → create an agent → stream its timeline →
approve a permission → read a diff. Success = the daemon's control surface does
everything the `api/v2/code/*` proxy assumes. Only then wire per-user routing
into Cerea.

## 6. Other outstanding items

- **Live verification of the enrollment path** (no IdP/gateway was available):
  does each live IdP admit an ephemeral-port `127.0.0.1:<port>/callback` against
  the registered portless form? (flagged in both templates); real device-code +
  loopback + refresh exchanges. Pin Authelia ≥4.39.22.
- **Rebase `code-panel`** onto Cerea `main` (it is one commit behind:
  `f984d02d`, a PDF-mime fix).
- **The muse-spark handoff agent repeatedly stalled** mid-task on multi-step Go
  work; the CLI tail (serve shim + IdP alignment) was finished directly, not by
  the agent. If delegating, expect to shepherd it item-by-item with
  commit-after-each discipline, or do multi-step work directly.

## 7. Build / test / environment

- **Go**: 1.27.1 at `/usr/local/go` (on PATH). Enrollment CLI:
  `cd Pystino/deploy/opencode/enroll && go build ./... && go vet ./... && go test ./... && gofmt -l .`
- **Cerea**: `npm run check` and `npm run lint`. Note `npm run test` skips the
  **client** (Playwright) project; and **`mongod` SIGILLs on this host (no AVX)**
  so Mongo-dependent test files can't run here — pre-existing, not caused by
  this work.
- **No live paseo daemon and no live IdP/gateway** exist in this environment;
  anything needing them is unverified and flagged as such.
- Pystino house rules: OSI-approved licences only (ask before non-OSI deps); commit messages carry
  *why*; cite ADRs by **number** (the ADR record is private — never link it);
  do NOT run `ruff format` across the repo.

## 8. References

- ADRs (repo `/home/ubuntu/workspace/ai-stack/docs/adr/`, cite by number):
  **0040** bearer on `/v1`, **0010** API keys, **0046** local credentials (NOT
  for the CLI), **0061** `x-bill-to`, **0084** bundled IdPs, **0032** providers.
- Prior research report (previews + the original paseo/opencode proposal):
  `/home/ubuntu/workspace/reports/2026-09-21-artifact-previews-and-coding-agent-mode.md`.
### Where the code physically is (read this before checking out)

The work is **committed** on two branches (not merged to `main`). Each branch is
currently **checked out inside a paseo-managed worktree**, so it is held there
and cannot be checked out again in the main repo until that worktree is removed.

| Repo (main checkout) | Branch | Worktree it's checked out in (work here now) | Branch head |
|---|---|---|---|
| `/home/ubuntu/workspace/Pystino` | `opencode-enrollment` | `/home/ubuntu/.paseo/worktrees/1se0mw8r/opencode-enrollment` | `a15115a` |
| `/home/ubuntu/workspace/Cerea` | `code-panel` | `/home/ubuntu/.paseo/worktrees/3cxk3jn7/code-panel` | `5332a89d` |

- To work now: `cd` into the worktree path and use it directly (the branch is
  already checked out there, build/test toolchains apply as in §7).
- To use the branch from the main repo instead: the worktrees are throwaway and
  may be auto-cleaned; run `git -C <repo> worktree list` to see them, then
  `git -C <repo> worktree remove <worktree-path>` before
  `git -C <repo> checkout <branch>`. Either way the commits live in the repo's
  object store, so **the work survives worktree cleanup** — only the checkout
  location changes.
- Neither branch is pushed to any remote; `code-panel` still needs the rebase
  onto Cerea `main` (`f984d02d`).
