# Backlog notes, 2026-11-06 (moved out of backlog.md)

**Owner decisions, 2026-11-06:** P19 dropped (first-policy allowlist is by design, ADR 0038). P21 dropped (no volume or config on this box depends on `pystino_postgres-data`; only the `.env.example` comment names it). C34 dropped unless it reproduces. C51 decided: the writing guide says "users" (PR to follow). Issues: Cerea #48 closed (shipped as ADR 0107 Auto), Cerea #50 linked to C71, Pystino #18 closed (transcription shipped in v0.21.0). G15 and G1: not decided (owner reconsidering opencode itself vs a lighter engine).

**2026-11-06 merges:** C27, C28, C29 were already fixed on main (39631fa3) — done. C65 and C52 fixed (PR #118), C48 and C54 fixed (PR #119), quota messages (PR #117): all on main, unreleased (0.42.3). C53 merged earlier (6f380ebc7).

**Released 2026-11-06: Cerea 0.43.0 + Pystino 0.28.0** (ADR 0108, ADR 0109, G11, C69, quota messages, schedules on expiry, Playwright 1.65.0 / Chromium 158). C60 recurred again (admin connectors phone-tap snapshot failed the release-commit CI; passed on rerun): fix at the cause next.

**ADR 0109 (owner, 2026-11-06), was in progress for 0.43.0:** no machine limits (fixed floor + optional local `--deny`), auto-approval per user in Workspace → Agents, admin only enables, Test button non-blocking — `feat/0109-no-machine-limits` (galopin), `feat/0109-user-auto-approval` (Cerea). Next big item after 0.43.0: C72 sandbox ADR. Deferred: optional admin caps.

**ADR 0108 (owner, 2026-11-06): all three merged** — diffs/history (#123), usage from the gateway (Cerea #127 + Pystino #37), MCP reverse path (#124: `connector_list`/`connector_call`, opt-in per session and project default). Follow-ups: pi extension for connectors; per-turn usage after reload (`x-pystino-turn`); a real-opencode end-to-end test of `connector_*`; a connector picker at session creation. Earlier note: (1) galopin diffs + (2a) history on resume — `feat/galopin-diffs-history`; (3) MCP reverse path — `feat/mcp-reverse-path`; (2b) usage/cost from Pystino — starts when a worker slot frees. goose/pi: no second engine now; ACP fixes merged (#122); when goose ships, hide `auto` and force `approve`.

**2026-11-06, more merges:** G11 + C76 (PR #120), ADR 0108 items 1 and 2a (PR #123), C69 fixed at the cause (PR #126: download/copy read the truncated version prefix while the preview showed the finished draft; now both export what the preview shows; guard test 30/30 fail before, 60/60 pass after under stress).

| ID | Title | Status | Next step |
|---|---|---|---|
| C78 | `code-tree-collapse.spec.ts:91` flake: machine B's `opencode serve` exits 1 on every restart, never pairs (run 42137909043 attempt 2) | Open. Hypothesis: both test machines share `XDG_CACHE_HOME` (machineHarness.ts) and race the first provider install. | Capture opencode stderr in the galopin log in `startMachine`; start B after A pairs or give each its own cache. |

| C79 | Session sharing: `galopin attach` (opencode TUI/VS Code live on galopin's server); goose shared history | Owner thinking (2026-11-06); report `2026-11-06-session-sharing-goose-opencode.md` | Owner decision. |

| G18 | `galopin opencode [args…]`: run the user's own opencode with galopin's config and proxy (starts the proxy if needed; pinned-version check; "not supervised by Cerea" notice) | Owner request 2026-11-06, after 0.43.0 | About half a day; shares proxy discovery with C79's `galopin attach`. |

**New since the audit**
| ID | Title | Status | Next step |
|---|---|---|---|
| C76 | galopin `opencode` workflow red on main since #111 | `TestPassthroughP3CeilingWinsAndAlwaysBecomesOnce` asserts the pre-amendment rule (run 42076436648). The suite is path-filtered, so full CI didn't run it. | In progress on `fix/edit-always-scope` (G11): update the test to the new rule, run the workflow. |
| C77 | Quota errors shown as "rate limited" | Fixed by PR #117 | On main, unreleased (0.42.3). |
| G1 | opencode 2.x | v2 is the official line (v2.2.5, npm `@opencode/cli`, `bash` tool renamed `shell`); v1 still maintained as `opencode-ai` 1.19.5. | Spike: galopin suites against 2.2.5, list API/config/tool differences, decide. |
| — | Issues with no row | Cerea #48 (skip flag / review-model auto mode): shipped as ADR 0107 Auto, close it. Cerea #50 (observability): same area as C71. Pystino #18 (speech-to-text models): check whether the transcription work covers it. | Tidy the issues. |

