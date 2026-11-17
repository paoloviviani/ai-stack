# 0085 — The coding-agent relay: adopt the paseo daemon and self-hosted paseo-relay

- Date: 2026-09-21
- Status: **superseded by 0089** (2026-09-24): an owned machine agent over
  `opencode serve` replaced the paseo daemon and relay. Originally accepted for
  the PoC, with the daemon and relay verified live on the PoC box.
- Related: [0084](0084-bundled-idps-authelia-keycloak.md) (the bundled IdPs
  whose device grant feeds the agent its `/v1` credential — a path this ADR
  deliberately does not touch), [0040](0040-bearer-tokens-on-v1.md) (the
  bearer audience the agent's traffic bills through),
  [0061](0061-per-request-billing-group.md) (`x-bill-to`, per-request
  billing for the same), [0010](0010-api-keys.md) (the pasted-key fallback
  the enrollment CLI also serves), [0046](0046-local-api-credentials.md)
  (the local-credential door this does **not** extend — it is
  chat-session-scoped and a headless CLI is explicitly out of its door).
- Everything below marked **verified** was observed first-hand on 2026-09-21
  against paseo 0.8.0 running on the PoC box (daemon live, relay built and
  exercised, client SDK driven through the relay); vendor-doc claims were
  checked against the behaviour, not copied. Where a vendor claim did not
  survive, it says so.

## Context

The `/code` panel (Cerea) and the agent's `/v1` credential (the enrollment
CLI in Pystino) are built and committed. What is missing is the piece
between: the chat server in the cloud must reach a daemon on the user's
machine, which sits behind NAT, opens no ports, uses no VPN, and asks for
near-zero setup. The only shape that works is an outbound dial to a
rendezvous both sides can reach.

The three options considered were:

1. **Adopt the paseo daemon + self-hosted paseo-relay** (Apache-2.0).
2. Build our own single-binary daemon that dials our own relay.
3. `cloudflared` per box — rejected up front: a SaaS dependency in the
   path, two binaries, against the self-hosted ethos.

Option 1 was recommended on vendor-doc claims that had never been run. This
decision is written after running them: a paseo daemon in a container
simulating the user's NAT'd machine, a self-built paseo-relay container, and
the paseo client SDK driving the daemon from a separate container that
cannot reach the daemon's network — the full pair → create agent → stream
timeline → approve permission → read a diff sequence, over the relay, with
no direct path. The PoC scripts live with the ADR-working notes and are
re-runnable on the box that produced this.

## What verification found

### The trust and transport model is exactly as advertised — verified

- The daemon dials **outbound** to the relay and reconnects with backoff;
  the relay endpoint is a first-class setting (`PASEO_RELAY_ENDPOINT`,
  default `relay.paseo.sh:443`, TLS chosen automatically for that default
  and configurable for a self-hosted one). Verified in the daemon's own
  relay transport code and then live: the daemon in the NAT'd container
  reached the PoC relay and stayed connected; nothing listened on its side.
- The E2EE is **NaCl box over Curve25519**: key exchange `nacl.box.before`,
  payload XSalsa20-Poly1305 via `box.after`/`box.open.after`, wire bundle
  `[24-byte nonce][ciphertext]`. Verified in the `@getpaseo/relay` crypto
  module shipped inside the daemon, and the daemon's persistent keypair at
  `$PASEO_HOME/daemon-keypair.json` is real on disk.
- The relay is **identity-blind for content**: it bridges two WebSocket
  connections and forwards frames without modification. Its one deliberate
  non-opacity is narrow and stateless: a client's `hello`/`e2ee_hello` frame
  must carry a canonical base64 32-byte X25519 public key, or the client is
  closed with `1008`. It never validates an OIDC token, an account, or a
  session — there is no identity at the relay at all, which is the property
  we need. The relay operator sees IPs, timing, sizes, session ids.
- A compromised relay cannot forge traffic: the daemon accepts no command
  before an encrypted handshake completes, and the authenticated cipher
  rejects modification. Verified live by driving the daemon only through a
  completed handshake (and by the daemon rejecting nothing else — there is
  nothing else to reject into).

### The pairing model, stated precisely — verified, and it matters

A pairing offer is a URL fragment containing exactly: the daemon's
`serverId`, its Curve25519 **public** key, and the relay endpoint. The
handshake needs only that tuple plus a fresh client-side keypair, so the
**offer is the bearer capability** — paseo's own docs say to treat the QR
code like a password, and that is accurate: the fields are public-key
material, but the tuple is the secret. Consequences we accept and bound:

- The daemon keeps **no per-client identity** and has no pairing revocation
  list in 0.8.0. Whoever has seen an offer can be an encrypted client until
  the daemon's keypair is regenerated. Custody of offers is therefore a
  Cerea-side secret-handling obligation (per-device rows, the same care as
  any credential), and rotation means re-pairing the device.
- Over the relay, the daemon's optional password is **not enforced**: relay
  sockets are attached to the session server after the handshake and never
  pass the bearer/subprotocol check that gates direct connections. The
  encrypted handshake is the only gate on the relay path. Do not build a
  control path whose safety assumes the password applies to relay clients.
- The WebSocket `hello` carries a client type (`mcp|mobile|browser|cli|hub`),
  a client id, protocol version and capabilities — no credentials. A server
  client like Cerea is simply an E2EE client; `hub` is the honest type for
  it.

### The daemon's control surface is WebSocket + SDK, not REST — verified, and it changes the wiring

This is the material discovery, and it contradicts what the panel was
coded against:

- The daemon's HTTP surface is small and final: `/api/health` (liveness,
  unauthenticated), `/api/status` (`serverId`, `version`, `listen`),
  `/api/terminal-activity`, `/api/files/download`, an agent-internal MCP
  route, static web-UI files — and a catch-all that serves the web UI's
  HTML. There is **no `v1/agents`, no `v1/workspaces`, no `X-Paseo-Version`
  response header**; `GET /v1/agents` on a live 0.8.0 daemon returns the
  SPA page, not JSON. The "paseo daemon API v1 (REST)" the `api/v2/code/*`
  forwarder was coded against does not exist.
- The real control plane is the daemon's WebSocket session protocol
  (`@getpaseo/protocol`), consumed through the typed SDK
  `@getpaseo/client`: `fetchWorkspaces`/`createWorkspace`,
  `fetchAgents`/`fetchAgent`/`createAgent`, `subscribeAgentTimeline`/
  `fetchAgentTimeline`, `sendAgentMessage`, `respondToPermission`,
  `getCheckoutDiff` — one method per surface the panel assumed, plus the
  terminal and worktree machinery we are not exposing yet.
- Therefore the per-device wiring change in Cerea is not "swap the base
  URL": the allowlisted HTTP forwarder becomes a **per-device SDK client**
  held server-side. The allowlist survives as the set of SDK operations the
  panel may call (the same enumeration, enforced in code instead of path
  patterns); the browser still never talks to the daemon; the SSE bridge
  still owns the only timeline subscription, now fed by
  `subscribeAgentTimeline` over the relay. The version pin becomes two
  concrete checks: exact-pinned `@getpaseo/*` packages (0.8.0), and a
  `/api/status` `version` check against the pinned minor before use.

Nothing in this finding changes the option ranking — it changes the Cerea
side of option 1, bounded and typed, and it would have been discovered
expensively later had the PoC not run first.

### Self-hosting the relay — verified

- The relay is a separate project, `paseo-relay` (Elixir/OTP,
  Apache-2.0 — licence file read). It builds a **generic container from
  source** (`docker build -t paseo-relay .`); settings are
  deployment-agnostic (`PASEO_RELAY_HOST`/`PASEO_RELAY_PORT`, default
  4000) with `/health`, `/ready` and Prometheus `/metrics`. There is no
  published relay image on GHCR as of this date — an operator builds it,
  which suits us (our registry, our pin). The PoC built and ran it this
  way.
- The relay is explicitly under active development and its README warns
  internal protocols may change without notice; the daemon's relay client
  already speaks protocol **v2** (a control socket plus one data socket
  per connected client). This is the churn risk, and it is managed the way
  the recommendation said: pin versions, keep the daemon behind our proxy,
  re-verify on upgrade.
- Multiple concurrent clients per daemon are the designed shape, not an
  accident: protocol v2 gives each client connection its own data socket
  and its own E2EE channel, and the daemon's runtime metrics count
  simultaneous sessions. Verified live in the PoC with two independent
  encrypted clients driving one daemon.

### What did not survive verification

- "The daemon runs opencode (and 39 other agents)": opencode is native and
  was verified running under the daemon on this box; "39" is not a current
  documented number. The current shape is two native providers (opencode,
  Pi) plus an ACP catalog of one-click installs. Immaterial to the
  decision; recorded so nobody quotes the stale number.
- The REST surface the earlier research report believed in (and the panel
  stub was built on): see above — it does not exist.

## Decision

**Adopt option 1: the paseo daemon, self-hosted paseo-relay, driven by
Cerea as an E2EE relay client through the paseo SDK.** The vendor claims
survived contact with the running system on every load-bearing point —
outbound-only dial, identity-blind relay, Curve25519/NaCl end-to-end
encryption, one-container self-hosting — and the one place reality differs
from our assumptions (WS/SDK instead of REST) is a wiring correction on our
side, not a defect in the adopted stack.

Boundaries that come with the adoption:

- **Pin everything.** `@getpaseo/client`/`@getpaseo/protocol` 0.8.0 exact
  in Cerea; the daemon image and relay image built from tagged sources and
  held in our registry; the relay protocol is v2 today and may change
  without notice.
- **The relay stays identity-blind and dumb.** It never sees OIDC tokens,
  never validates users, never terminates our TLS to inspect. It is an
  untrusted middle we happen to operate.
- **The two trust axes stay separate.** The relay carries only the control
  channel (chat ⇄ daemon). The agent's LLM traffic to `/v1` rides the
  enrollment CLI's `serve` shim on the daemon's machine and never touches
  the relay; the relay must never see `/v1` credentials. ADR 0040/0061 own
  that axis; nothing here amends them.
- **Pairing offers are credentials.** Cerea stores the per-device offer
  material (serverId, daemon public key, relay endpoint) with
  secret-handling discipline; the daemon has no revocation, so rotation is
  re-pairing. The panel's `codeDevices` row is the right home for it.
- **Default agent posture stays plan/read-only** until the user opts in —
  the panel already defaults to `plan`, and nothing in the daemon changes
  that.

Option 2 (our own daemon + relay binary) remains the documented fallback,
and the tripwires that would trigger it are concrete: a paseo release that
breaks the pinned SDK protocol in a way we cannot absorb, a licensing
change (both Apache-2.0 today), or the relay's development cadence
outrunning our re-verification appetite. None of those fired; building a
reconnecting, multiplexing, E2EE tunnel with the daemon's whole agent
lifecycle behind it remains strictly worse than adopting this one.

## The two open topology questions, answered from the PoC

**Q1 — can one chat server represent many independent user↔daemon
pairings?** Yes. The relay routes by `serverId`; each user's daemon dials
out with its own id, and the chat server opens one encrypted client
connection per device it serves — the daemon-side v2 protocol gives every
client connection an independent socket and E2EE channel, verified live
with two concurrent clients on one daemon and a second daemon addressable
on the same relay. Cerea's per-user routing is therefore: look up the
caller's `codeDevices` row, take its stored offer material, connect (or
reuse a pooled connection) as that device's relay client. One Cerea
process holds many pairings; none of them share state.

**Q2 — what is the chat server's identity to the relay and daemon?** To
the relay: nothing — an IP with a WebSocket. To the daemon: an E2EE client
that completed the handshake, presenting client type `hub` (the machine
client type) with no further credentials — because over the relay the
password is not enforced and the offer is the capability. The trust is
bounded by custody: Cerea holding a device's offer material is exactly as
powerful as the user's own phone holding the same QR, which is the model
paseo documents. We accept that a Cerea compromise equals compromise of
every paired daemon's control plane, mitigated the boring way — offers
stored like secrets, revocation by re-pairing, the daemon bound to
loopback on the user's side, and the allowlist of SDK operations keeping
the panel from becoming a full daemon shell.

## Verification

- paseo 0.8.0 daemon run live on this box (CLI 0.8.0, daemon 0.8.0,
  opencode 1.18.31 as its agent provider, actively streaming a timeline
  while these observations were taken).
- Relay behaviour read from the shipped code of the exact version the PoC
  ran (`@getpaseo/server`/`@getpaseo/relay`/`@getpaseo/client`/`@getpaseo/
  protocol` 0.8.0), then exercised: PoC containers for the NAT'd user
  machine (daemon on loopback only), the relay, and the "chat server"
  driver, with the driver on a separate docker network so no direct path
  to the daemon existed.
- PoC script drove, through the relay only: pairing-offer import → agent
  list/create → timeline subscription → a real permission request surfaced
  and approved → diff read back. Second concurrent client connected in
  parallel. Scripts and their transcript are the concrete evidence for
  Q1/Q2 above.
- Licences read at source: `paseo` Apache-2.0 (with third-party carve-out
  note), `paseo-relay` Apache-2.0. The npm packages omit the licence field;
  the repos carry it.
- Not verified here, flagged for the follow-on: the enrollment CLI's live
  device/loopback flows against a real bundled IdP (ADR 0084's requirement,
  no live IdP in this environment), and the `/v1` leg of the PoC agent's
  traffic — the PoC agent used the box's existing provider credential
  stand-in, since no Pystino gateway is live. Both are the enrollment
  workstream's live-verification items, independent of this decision.
