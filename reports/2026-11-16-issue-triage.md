# Open-issue triage, 2026-11-16 (read-only; origin/main of Cerea at v0.54.2, Pystino at v0.33.4)

Backlog rows for #184-#191 are stale: they still read "open" for work that is on main. Update them when closing.

## Cerea
| # | Title | Verdict | Evidence / what's left | Backlog |
|---|---|---|---|---|
| 191 | Show details collapses on id swap | DONE | commit 96c20876 (C98) | C98 |
| 190 | Postgres knowledge specs, no poll after reindex | DONE | 47009cf7 (specs), e827afd2 (CI pgvector service), polling in `KnowledgeManager.svelte` pollOnce | C96 |
| 189 | Flaky tests, e2e OOM | PARTLY | a4e244d6 raised the slides PDF wait; CI heap is 6144 MB (was 4 GB). The route.fulfill teardown rejection is not shown to be fixed; the issue says it recurs | C93 |
| 188 | Phone density, Panels sheet | DONE | 04d6f35c (C92), v0.53.0 top bar; `AgentHeaderRow.svelte` Panels button and sheet | C92 |
| 187 | Stale re-enroll note | DONE | c0f5cb5b (PR #145); `isLegacyMachine` and `legacy_title` are gone from main | C89 |
| 186 | Project TOC scroll, Save bar | DONE | c0f5cb5b (PR #145); "Unsaved changes" bar and its spec in `ProjectPage.svelte(.test.ts)` | C88 |
| 185 | Sidebar redesign | DONE | PR #143, #208; `NavMenu.svelte` has the Chats, Recent and Agents switch, quota summary in the user menu, `CommandPalette.svelte` | C87 |
| 184 | Sandbox ADR | DONE | ADR 0115 (accepted 2026-11-12), steps 1-2 shipped in v0.52.1 (#225, #231). Its follow-ups are C116-C119 | C72 |
| 115 | Provenance note on repeated text | STILL RELEVANT | No provenance code in `agent/` | C75 |
| 113 | Local secret value in an outbound command | STILL RELEVANT | No value-matching in `agent/` (`decide.go` only has the secrets class) | C73 |
| 56 | Assistant creates and fills KBs | STILL RELEVANT | No `kb_create`, `kb_add` or `kb_list` in src. The decisions are written in the issue | C61 |
| 50 | Observability, OTel | STILL RELEVANT | No OTel export in src or kit. Review log is the interim view | C71 |
| 44 | MCP Apps (ui://) | STILL RELEVANT (parked) | No `ui://` rendering. Needs an ADR first | C42 |
| 43 | Pill leftovers | PARTLY | 93e6105c moved MountedChips, CodeNavTree, EnrollPolicyControls and NeedsYouInbox onto PILL. Left: `ContextMeter.svelte` and `AgentComposer.svelte` still use their own pill classes | C39 |
| 42 | Flaky CodeNavTree "tints a folded row" | STILL RELEVANT (parked) | Test still exists. Unknown whether it still flakes | none (C32-style flake) |
| 41 | Composer draft cases | PARTLY | 93e6105c fixed cases 2 and 3. Case 1 (saved, then 502, so the text returns and the message also shows) has no fix in `composerDraft.ts` | C36 |
| 40 | Skills-first before connector tools | STILL RELEVANT (parked) | ADR 0104 connector catalogue shipped, but nothing loads the skill first | C41 |
| 39 | PDF forms | PARTLY | Steps 1-2 in v0.32.2 (`doc_outline`, `fill_form`), fitting and `look_doc` later. Left: step 3 | C40 |
| 36 | WebKit and real phone tests | STILL RELEVANT (parked) | The e2e smoke subset now runs per PR (be01ae8c), nightly full. WebKit and real phones still uncovered | C19 |
| 35 | Shrink chat image, Pyodide allowlist | STILL RELEVANT (parked) | `sync_pyodide_wheels.mjs` still vendors every lock package | C23 |
| 34 | Split big modules | STILL RELEVANT (parked) | `code/[...path]/+server.ts` 1644 lines, `AgentView.svelte` 1769, `dispatch.go` 2037 | C22 |
| 33 | Shrink AGENTS.md | DONE | 7dada3c4: 477 lines, subsystem reference moved to `docs/dev/` | C21 |
| 32 | Client test harness noise | PARTLY / unproven | `wrapDynamicImport` is not mentioned in the repo. Noise status unverified and not reproduced here | C32 |
| 28 | Open Design, CoDesign | STILL RELEVANT (parked) | Investigated 2026-10-22, owner parked it | C17 |
| 24 | Machines offline after restart | STILL RELEVANT | Only the token-refresh drop is fixed (885ecacf, C103). Reconnect gap and shutdown announce unmeasured | G12 |
| 21 | OS sandbox for agent commands | PARTLY | ADR 0115 covers the server side (E and P classes). The local OS sandbox for galopin on user machines is not built, and no runsc on the box | G3, C72, C116 |
| 19 | galopin on opencode 2.x | DONE | #239, opencode 2.3.0, v0.53.0 | G1 |
| 18 | Euro-Office backend | STILL RELEVANT (long term) | Not on main | C12 |
| 10 | Dex alone mode | STILL RELEVANT (low) | Needs #9 first. No Dex in `kit/configure` | C13 |
| 9 | Dex in front of Authelia | STILL RELEVANT / OBSOLETE-leaning | Only spike branch `feat/kit-dex-authelia`. See below: it contradicts the single-IdP, no-broker decision | C1 |

## Pystino
| # | Title | Verdict | Evidence / what's left | Backlog |
|---|---|---|---|---|
| 60 | Live checks fail on a fresh stack | STILL RELEVANT | Live scripts were repaired for the rules v2 (f0f9ce8, fa14116), but the 3 named failures are not shown fixed. `test_reporting_live.py` still asserts a "research" group. Needs a run on a fresh stack | P30 |
| 21 | Split routers/admin.py | PARTLY (parked) | `admin_audit`, `admin_byok` and `admin_privacy` already split out; `admin.py` is still about 7,300 lines | none (P21 is a different row) |
| 20 | Users API shows chat flags without chat | STILL RELEVANT | `_require_chat` guards writes (`admin.py:3376`), but the user responses are not gated on `chat.enabled` | none |
| 19 | Standalone logs a machine-client ERROR | STILL RELEVANT | `oidc_policy.py:~499-525` has no `chat.enabled` check; it logs at ERROR | none |
| 14 | Console language picker | STILL RELEVANT | No second language | P13 |
| 8 | Multi-tenancy | STILL RELEVANT | No code | P8 |
| 4 | vLLM semantic-router spike | STILL RELEVANT | No code; needs heavy hardware | P3 |
| 3 | Decision models as routing selection | PARTLY | The model kind and `/v1/decisions` shipped (0.16.0, ADR 0100). Left: a `SelectionRule` (`routing.py`) that uses one to pick a route | none |

Open issues not in the request list: Cerea #267-270 (new: upload to agent, workspace isolation, clone a repo, Claude subscription) have no backlog rows. #49, #196-#258 are pipeline bot issues for opencode and goose bumps (#49 and #206 are stale since the pin is now 2.3.0).

## Recommend closing
- Cerea #191: "Fixed in 96c20876 (C98); Show details now survives the message re-key."
- #190: "Fixed in 47009cf7 and e827afd2: specs pass, CI runs the Postgres knowledge specs, and the Knowledge screen polls after a reindex."
- #188: "Shipped in v0.53.0 (C92): one-row agent header, Panels sheet, denser phone sidebar."
- #187: "Removed in PR #145; `isLegacyMachine` and its message are gone."
- #186: "Shipped in PR #145: the TOC scrolls the content column and the Save bar is a compact floating unsaved bar."
- #185: "Shipped in PR #143 and #208: Chats, Recent and Agents switch, user menu with quota, command palette."
- #184: "Answered by ADR 0115; steps 1-2 shipped in v0.52.1. Follow-ups are C116-C119."
- #33: "Done in 7dada3c4: AGENTS.md is 477 lines with the reference moved to docs/dev/."
- #19: "Shipped in v0.53.0 (opencode 2.3.0, #239)."
- #9 (and #10 with it), the owner's call: "Superseded by the single-IdP, no-broker decision (auth-design); Dex-in-front would add a second issuer path. Spike branch kept for reference." The memory says the owner rejected a custom OIDC broker, not Dex. The Dex spike was parked on gateway work, so this is OBSOLETE only if the owner agrees.
- #49, #206 (bot): "Stale: the pin is opencode 2.3.0."

## Top 5 still worth doing
1. Pystino #19 and #20: both are small, no row exists, and standalone Pystino logs an ERROR that looks like a fault.
2. Cerea #113: block a secret value in an outbound command (C73). It is the most common real leak and an easy rule on top of the permission classes.
3. Cerea #56: the assistant adds to knowledge bases (C61). The decisions are already recorded.
4. Cerea #39 step 3 (C40), then #41 case 1, a user-visible duplicate message.
5. Pystino #60: get live checks green on a fresh stack before the next request-path release; Cerea #189 shares the flaky-test theme.
