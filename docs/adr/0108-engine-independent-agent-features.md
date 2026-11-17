# ADR 0108: Engine-independent coding-agent features in galopin and Cerea

- Status: accepted (owner, 2026-11-06); its "no second engine yet" is superseded by ADR 0110 (goose opt-in, same day)
- Context: the ACP spike (Cerea PR #122) showed goose (`goose acp`) and pi (`pi-acp`) run behind galopin's
  ACP backend with small fixes, but Cerea's view would be poorer than with opencode (no diffs, empty history
  after resume, no usage, connectors only where the engine speaks MCP). No user asks for another engine now.
  Owner decision: no second engine yet; build the pieces that make any engine a configuration choice and
  improve opencode today. When goose ships, galopin hides its `auto` mode and forces `approve` (owner,
  2026-11-06).

## Decision

Three features live in galopin/Cerea/Pystino, not in the engine:

1. **Diffs from galopin.** For every edit-class ask (and for edits that run without an ask), galopin
   snapshots the file(s) before the tool runs and after it completes, and emits the unified diff on the
   existing tool/file-change events. Engine diffs, where present, are not needed. Bounded: text files under a
   size cap, binary noted as changed; snapshots kept per turn only (memory or galopin's state dir, cleaned).
   This also lays the ground for a per-turn undo later.
2. **History and usage that don't depend on the engine.** (a) On resume, galopin captures the history the
   engine replays (ACP `session/load` updates; opencode's own API as today) so Cerea's transcript is never
   empty. (b) Cost and token usage per session/turn come from Pystino's usage records for the requests galopin's
   gateway proxy forwarded (tagged with the session), not from the engine's own counters.
3. **The MCP reverse path.** galopin serves one local MCP endpoint to the engine with:
   - the user's **Cerea connectors** (deployment connectors and their own, with their own keys/OAuth):
     galopin lists them and forwards each call up the MachineLink; Cerea executes it with the user's
     credentials, which never reach the machine;
   - the machine's **local connectors** (already managed by galopin), served locally without the round trip.
   Every call goes through galopin's `tools` class and the review log. Which connectors a session gets is
   opt-in per session or project (default: none), mirroring "load only what's needed". Engines without MCP
   (pi) get the same tools through a small galopin-shipped extension.

ACP stays the protocol for non-opencode engines; extensions go in ACP `_meta`, never a private protocol.

## Plan

Three workstreams, each its own PR: (1) galopin diffs; (2) history capture + usage from Pystino;
(3) the MCP reverse path (protocol ops on the MachineLink, Cerea execution, galopin endpoint, per-session
opt-in UI, pi extension later).
