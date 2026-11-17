# Batch A0 brief: three freeze-allowed fixes in agent/ (galopin)

Worktree: /home/ubuntu/workspace/slash-cerea (branch feat/slash-commands,
at Cerea b422a40a). The Go agent lives in `agent/`. This batch is three
small, freeze-allowed fixes that slash commands build on. You implement,
you don't redesign; ambiguity → stop and report.

## Fix 1 — mint a messageID for `prompt_async`

Today galopin's prompt path has no exact client-message mapping (the
2026-09-26 plan §3.6). opencode's `POST /session/:id/prompt_async` honours
a caller-minted `messageID` (verified in the plan's §1.2 probing of
`session.command`, same field). In `agent/internal/backend/opencode`
(find the prompt/prompt_async call):

- Mint an opencode-style ascending `msg…` id before the POST (a small
  helper in the package — batch A reuses it for `session.command`).
- Send it as `messageID`.
- Record it against galopin's `clientMessageId` if the caller gave one,
  so the transcript maps the client's id exactly (look at how session
  overlays/snapshots store per-message metadata today and follow that
  pattern).
- If the server ignores or rewrites the id (verify against your fake
  server test), keep the mapping from the RESPONSE instead and document
  which way won.

## Fix 2 — the ACP busy guard

In `agent/internal/backend/acp` (and `agent/*_dispatch*` if the op lives
there): `Prompt` on a busy session would overwrite the turn ids (the
2026-09-26 plan §1.5). Today it is unreachable because the composer hides
send while running; steering will make it reachable. Guard it: `Prompt`
while `st.busy` returns `invalid` (the same code other invalid-state
refusals use — find the existing pattern).

## Fix 3 — the stale "paseo" tooltip

`src/lib/components/code/AgentComposer.svelte` (~line 506, the mode
pill): the tooltip says "paseo's modes, as the daemon defines them". The
modes come from the machine's backend (opencode), not paseo. Change to
"How much the agent may do on its own — the machine's modes, as the
backend defines them" (keep the sentence shape; the exact wording is
yours as long as "paseo" is gone and it stays accurate).

## Tests

- Go: `agent/internal/backend/opencode` — the fake server asserts the
  minted ascending id and the exact `messageID` field; the ACP test
  asserts the `invalid` refusal while busy (and no prompt block sent).
- Cerea: the tooltip change is copy-only; run the AgentComposer-related
  client specs that exist (there is no AgentComposer spec — then any spec
  pinning the old tooltip text must be updated if one exists; grep first).
- Go build: from `agent/`, `go build ./...` and `go test ./...` — under
  the lock (`flock /tmp/heavy.lock timeout -s KILL <secs> <cmd>`), the Go
  build can be heavy on this box.

## Commit

One commit: "galopin: mint prompt ids, guard ACP busy, fix the modes
tooltip" — or three if the pieces are cleaner apart. Configured identity,
NO AI trailers, no push of main. Push `feat/slash-commands` at the end.
