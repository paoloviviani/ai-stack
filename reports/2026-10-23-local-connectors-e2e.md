# Local connectors end-to-end check, 2026-10-23

Result: PASS on every step except one sub-check (direct -32001 JSON-RPC code visibility, see 4c).
Screenshots and support files: `2026-10-23-local-connectors-e2e-shots/` (not committed; `support/` has galopin.log, audit.log, mcp.json, the mini MCP server, the Playwright scripts, the patched fake upstream).

## Versions
- Cerea image `local/cerea:sha-d43ade5` (sha256:aa99fd8daab7...), built from origin/main d43ade53 (includes the 3 GB Node heap fix). Kit and `agent/` taken from 9f5c8aee; `agent/` and `kit/` do not differ between 9f5c8aee and d43ade53 (checked with git diff --stat).
- Pystino image `local/pystino-gateway:sha-caab8aa` (sha256:d4bcb79cca58...), origin/main caab8aa.
- galopin: `go build` of agent/ at 9f5c8aee (no `version` subcommand exists; `galopin version` answers "unknown command").
- Stack: scratch kit, compose project `lce2e`, ports 80/443 (nothing else bound), origin https://192.0.2.10, bundled Authelia, TLS internal, `homelab` preset with the `documents` profile dropped (see notes), `-f dev/smoke.yaml`, user `lcuser` (non-admin). `GATEWAY_CHAT__ENABLED=true` confirmed in the gateway env; chat env `LOCAL_CONNECTORS_ENABLED=true`.
- Scratch HOME/XDG under /var/tmp/lce2e/home; ~/.config/galopin, ~/.local/share/opencode and the real galopin untouched. galopin trusted Caddy's root via SSL_CERT_FILE.

## Steps
1. Stack from mains: PASS. Build, configure, up --wait all healthy. Seeded a chat model `scripted/chat` (supported_features=[tools]) on the fake upstream.
2. Enroll: PASS. `galopin enroll --connectors-only --device --issuer $O/authelia --cerea $O/chat`; device flow completed with Playwright against Authelia (login + ACCEPT). Shots 01-03. `galopin run` then connected (status pending), after the first-sign-in issue below.
3. mcp.json: PASS. Stdio server `mini` (my own newline-delimited JSON-RPC Python server with echo, add, secret), `allowedTools: [echo, add]`. `galopin connectors list/test` showed ready, 2 tools of 3 offered.
4. Browser:
   - 4a Local connectors tab (shots 05, 05b, 06): capability granted, machine "fortifying-moray" listed pending, Approve clicked, shows Connected, server `mini` Ready. PASS.
   - 4b MCP panel (shot 07, 08): "mini · on fortifying-moray", green "on" pill, "2 tools allowed", enabled for new chats. PASS.
   - 4c Chat turn (shots 10-a/b, 12): fake upstream scripted with `CALLTOOL echo {...}`; approval card "wants to call mini · on fortifying-moray:echo" appeared first, Allow once, result in the conversation "tool result: ECHOED:hello-e2e"; `add` gave the sum likewise. PASS.
   - Ceiling: the upstream's tools list contained echo and add, not secret (tools/list filter, PASS). A call for secret that is not offered is refused by the chat itself ("Unknown MCP function", shot 11). To reach galopin's refusal I allowed secret, sent the call, and removed secret from mcp.json while the approval card was open; after Allow, the conversation shows "this tool is not allowed on this machine" (shot 14) and audit.log has `outcome: refused, tool: secret`. PASS for the refusal and message; the numeric -32001 code is not shown by the chat UI, so I did not observe the code itself.
   - audit.log (support/audit.log): ok echo, ok add, refused secret, ok echo; lines carry action/at/outcome/server/tool, no arguments. PASS.
5. Lifecycle:
   - Stop galopin (shots 15): MCP panel "Unavailable / Offline ... not connected. Start galopin there to use it."; tab shows Offline. A new turn proceeded without the MCP tools (scripted reply listing only built-in tools), no hang. PASS.
   - Restart (shot 17, 18): Ready again, tool call worked after restart ("ECHOED:after-restart"). PASS.
   - Revoke (shot 19, 20): machine gone from the tab, MCP panel "0 servers configured"; galopin logged "revoked this machine's refresh token at the IdP" and "error: link: this machine was revoked (4403)" and exited. PASS.
6. Teardown: compose down -v (project lce2e), both local images removed, worktree and scratch tmp removed, no galopin or scratch browser process left. Disk: before 10G free (48G used), at the lowest 0.77G free during the Cerea build, after 5.0G free (53G used). Other agents' volumes and cache untouched, except `docker builder prune -f` (unreferenced build cache, 2.2 GB, once during the build and once at the end).

## Findings (reported, none fixed)
1. `kit/dev/build.sh --cerea-ref main` builds a STALE commit on a reused `dev/src/cerea` clone: the script runs `git checkout --detach main`, which resolves the local branch `main` (stale) before `origin/main`. Evidence: with origin/main at d43ade53 it printed "Cerea main = 7ec1d7c637d4". Workaround used: `--cerea-ref origin/main`. Fix idea: try `origin/$ref` first, or `git fetch` then `checkout origin/$ref` for branch names.
2. First build exit 134 (Node OOM in `npm run build`, 5 GB box); fixed on main by d43ade53 (BUILD_HEAP_MB). Noted per coordinator.
3. UX: `galopin run` right after `enroll` got HTTP 403 on the WebSocket until the user had signed in to Cerea once (resolveMachineUser: "Sign in to Cerea once before connecting a machine", plus a 60 s cache). galopin only prints "got 403", not the reason body. The tab's how-to does not say to sign in to the chat first. Suggest: show the 403 body in galopin's log and add the sentence to step 3 of the tab.
4. Default-on state of a local connector for new chats is browser-local (a fresh browser context shows the chip off and the switch is disabled while the machine is offline); not a bug, but an E2E must keep storage state.
5. Kit: with the `homelab` preset the `documents` profile needs the `local/pystino-redaction` image, which `build.sh` does not build for that profile set ("ERROR ... run dev/build.sh" from configure --check; `up` tried to pull it). I dropped `documents` via `./configure --set COMPOSE_PROFILES=gateway,chat,authelia`. Not investigated further.

## Test infrastructure
The smoke upstream (`Pystino/scripts/_fake_upstream.py`) had no tool-call mode. I used a patched copy mounted through `PYSTINO_SRC=/var/tmp/lce2e/fakesrc` (no repo change, no branch): a user message `CALLTOOL <substring> <json>` answers with a tool call to the first offered tool whose name contains the substring (`RAW:<name>` calls a tool that was not offered); a trailing tool message answers "tool result: <content>". The patched file is in `support/_fake_upstream.py`; the patch is about 55 lines and could be committed to Pystino if wanted.
