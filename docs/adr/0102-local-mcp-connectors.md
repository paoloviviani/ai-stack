# 0102 — Local MCP connectors through galopin

- Date: 2026-10-22
- Status: **Accepted** 2026-10-22 by the owner, with the changes in "Owner decisions" below. Wire contract: Cerea `agent/PROTOCOL.md` §10 and its fixtures.
- Related: 0090 (machine powers: files and terminals), 0097 (agent permission architecture: the machine ceiling), the machine protocol (`agent/PROTOCOL.md`). A step towards a desktop app; this one is headless.

## Context

The chat reaches MCP servers over HTTP. A server that has to run on the
person's own computer, such as a stdio server that reads local files or talks
to a local application, can only be used today by exposing it: wrapping it in
`mcp-proxy` or similar and publishing it over a VPN (NetBird) or a tunnel.
That opens a listening port, puts a second authentication layer in front of
it, and makes the server reachable by anything on that network.

galopin already solves the hard parts for coding agents. It dials **out** to
Cerea over an authenticated WebSocket, so nothing listens on the machine. The
machine is paired to one person with a human confirmation and is usable only
by its owner. Cerea reaches it through `MachineLink`, which fails fast when
the machine is offline. The owner asked for the same link to carry local MCP
servers to the chat.

## Decision

1. **Servers are configured on the machine, and only there** (owner,
   2026-10-22). galopin reads them from a file in its config directory, next
   to `policy.json`: name, command, arguments, environment, working
   directory. They are set with a `galopin connectors` command or by editing
   the file. Nothing in the protocol lets Cerea add, change or start a
   command: Cerea can use what the machine offers and nothing else. This is
   the same rule as the permission ceiling (0097), and it is what keeps the
   feature safe.

2. **MCP passes through the link unchanged.** Cerea opens a channel to one
   named server, and MCP JSON-RPC messages travel in both directions:
   - `mcp.list` → the machine's servers: name, description, state;
   - `mcp.open {server}` → `{channelId}`, which starts the server if needed;
   - `mcp.send {channelId, message}` carries a message from Cerea to the
     server;
   - an `mcp.message {channelId, message}` event carries the server's
     messages (responses, notifications, and server-to-client requests such
     as elicitation);
   - `mcp.close {channelId}`.

   galopin does not interpret tools. Tools, resources, prompts and whatever
   MCP adds later work with no protocol change. Messages are size-capped like
   other frames, and a binary result above the cap is refused, not truncated.

3. **On the Cerea side, a machine transport** implements the MCP SDK's
   `Transport` over these ops. It plugs into the existing client and client
   pool (`server/mcp/`), so a local server is an ordinary connector to the
   rest of the chat: per-chat toggles, tool approval cards, elicitation,
   delegated sub-agents and schedules.

4. **In the UI**, a machine's servers appear in the connector list as
   "<server> · on <machine>". Only the machine's owner sees them; they are
   listed per person, never deployment-wide. When the machine is offline,
   they show as unavailable and their tools are left out of the turn: a turn
   never fails or waits because a machine is away.

5. **Safety, because the chat is more exposed than the coding agent.** A
   chat reads web pages and documents that can carry prompt injection, and
   these tools run with the person's local privileges. So:
   - every local tool asks for approval by default, and "always allow" is
     per conversation, as for other connectors;
   - the machine keeps a per-server allow-list of tools (default: all tools
     the server lists, with an option to restrict). It is a ceiling Cerea
     cannot raise: galopin refuses a `tools/call` for a tool outside it,
     whatever Cerea sends;
   - galopin logs every call (server, tool, time, outcome; not the
     arguments) in its own log.

6. **Lifecycle.** galopin starts a server on first `mcp.open` and stops it
   after an idle period (default 10 minutes with no open channel). It
   supervises the process the way it supervises opencode (process group,
   parent-death signal). A crash closes the server's channels with an error,
   which the chat shows as the connector being unavailable, never a hung
   turn.

7. **A connectors-only mode is part of the first version.**
   `galopin run --backend none` runs no coding agent: it only serves the
   configured connectors. The machine announces an empty backend list, and
   the Agents panel shows it as "connectors only", with no sessions.
   This is the headless precursor of a desktop app: a small process left
   running on a laptop or home server to make local tools reachable from
   the chat.

8. **Capabilities.** A galopin that supports this announces
   `machine.capabilities.mcp` in `hello`. An older galopin does not, and
   Cerea shows no local connectors for it. The shared protocol fixtures
   (`agent/protocol-fixtures/`) gain the new ops and event.

## Owner decisions (2026-10-22)

- **Connectors-only mode** is the shape: such a machine **never appears in the Agents
  panel**. Its pairing is approved in a **Local connectors** tab of the workspace page.
- Its servers appear in the **MCP panel** as local connectors, with a green "on" when the
  machine is connected and the server is ready.
- **Full passthrough**: every MCP message in both directions, auth included. stdio secrets
  come from `env` on the machine; an http server's OAuth sign-in happens on the machine
  (`galopin connectors login`), since Cerea's server cannot reach the machine's localhost.
- The config is **JSON in the Claude format** (`mcpServers`), so an existing file can be
  copied.
- Changed from the draft above: traffic uses a bidirectional `mcp` frame rather than an
  `mcp.send` op and an event, and a stdio process lives as long as its channel (one process
  per channel, at most 4 per server).

## Consequences

- No inbound port and no VPN is needed to use a local MCP server from the
  chat. The server is reachable only through its owner's paired machine.
- The protocol grows by five ops and one event. They are generic MCP
  plumbing rather than one op per tool, so it should not need to grow again
  for MCP itself.
- A local tool is only usable while the machine is online. A schedule that
  needs it fails its run with "machine offline", as agent schedules do.
- The chat model can now act on the person's computer. The defaults (ask
  every time, a machine-side allow-list, local logging) are deliberate, and
  loosening them is the person's choice per conversation, never the
  deployment's.

## Open questions for the proof of concept

- How the client pool keys a machine connector (person, machine, server),
  and when it closes idle channels on the Cerea side.
- Whether server-to-client requests other than elicitation (sampling, roots)
  are answered or refused in the first version. The likely answer is
  "refused".
- Whether stdio servers that need a TTY or a desktop session behave when
  galopin runs as a service.
