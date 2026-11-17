# Backlog audit, 2026-11-06

**Scope.** Every P, C and G row in `backlog.md` (last updated 2026-10-27, with later edits up to C75).

**How verified.** Read-only. `git fetch` on Cerea and Pystino, then `origin/main` and release tags (Cerea v0.42.2, Pystino v0.27.0). For each item I found the commit and ran `git tag --contains` for the first release that holds it. Where it mattered I grepped the code on `origin/main`. I also checked GitHub issue states (`gh issue list`) and CI history (`gh run list`, last 200 runs, 2026-11-04 to 11-05 only). Nothing was built or run.

**Limits.** "Open" means the code on main still shows the problem, or no fix commit exists. The flake window is short (about 1.5 days), so "no recurrence" means only that none was seen in that window. In-progress rows follow the owner's statement. Branches `fix/small-ui-bugs`, `fix/edit-always-scope` and `fix/small-server-bugs` exist locally or on origin, and there are no open PRs yet. No sandbox ADR exists: the ADR dir ends at 0107.

Counts are approximate (some IDs appear in more than one table); see the end.

---

## 1. Open

### Pystino
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| P2 [#3](https://github.com/paoloviviani/Pystino/issues/3) | Decision models as a routing selection | Only the metered kind shipped (0.16.0). `docs/decision-models.md` says routing belongs to the deployment; no decider-picks-target rule exists. Issue open. | Build it on P1's selection interface, or park explicitly. |
| P3 [#4](https://github.com/paoloviviani/Pystino/issues/4) | vLLM semantic-router spike | Issue open, no code, no spike. | Stays long-term; needs heavier hardware. |
| P8 [#8](https://github.com/paoloviviani/Pystino/issues/8) | Multi-tenancy | Idea stage, no code, issue open. | Owner to schedule or park. |
| P13 [#14](https://github.com/paoloviviani/Pystino/issues/14) | Console language picker | No second language exists, issue open. | Wait for the first translation. |
| P19 | Redaction allow-list combine | `RedactionPolicy.combine` takes the allow_list from the first policy on purpose (docstring, ADR 0038: union lets a user exempt what the admin redacts). The row's "should be the union" contradicts the design. | Owner to drop the row, or open a design question. |
| P21 | `pystino_postgres-data` volume check | Cannot be verified from git; no host inspection done. | Owner to confirm or drop. |

### Cerea bugs
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| C20 [#31](https://github.com/paoloviviani/Cerea/issues/31) | Ask card resets a pick | Marked parked, but `fix/ask-question-reset` merged in v0.24.0 and issue #31 is closed; I did not confirm that it fixes the app race. | Confirm it fixes the race, then mark Done. |
| C34 | Reused login code gives 500 | `/login/callback` retries once on a state or PKCE mismatch. A genuinely reused code (valid state) path is not visibly handled. GitLab sign-in test unverified. | Owner to test or drop. |
| C36 [#41](https://github.com/paoloviviani/Cerea/issues/41) | Composer draft edge cases | 0.32.1 fixed the main cases (2e2fc45c). The three leftovers are unfixed and the issue is open. | Keep parked. |
| C39 [#43](https://github.com/paoloviviani/Cerea/issues/43) | Pill leftovers on the code panel | `NeedsYouInbox` and others still do not use the shared PILL. 0.32.1 moved only some pills (c8fdf926). | Low priority. |
| C41 [#40](https://github.com/paoloviviani/Cerea/issues/40) | Skills-first before connector tools | No `tools:` frontmatter field in the skills code. Issue open. | Parked. |
| C50 | mrl-truncate low items | `mrl.ts:66` still has the "cut to fit" wording, and the source is still `mixedbread.ai`. | Batch with the next knowledge change. |
| C54 | Sandbox mount "current" exceptions | The row's own fix plan is unchanged on main. The text "mounts the current version of every name" no longer appears in AGENTS.md (grep), so the wording half may be done. The row is in `fix/small-server-bugs`. | Confirm the mounter's number guard in that branch. |
| C61 | Assistant creates and fills KBs | `kb_create`, `kb_list` and `kb_add` are not on main. | Owner to schedule. |

### Cerea features
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| C1 [#9](https://github.com/paoloviviani/Cerea/issues/9) | Kit: Dex in front of Authelia | Only the spike branch `feat/kit-dex-authelia` exists; no Dex in `kit/configure`. Blocked on Pystino groups-from-claim. | Stays parked. |
| C13 [#10](https://github.com/paoloviviani/Cerea/issues/10) | Kit: Dex alone with break-glass | Not started, issue open. | After C1. |
| C12 [#18](https://github.com/paoloviviani/Cerea/issues/18) | Euro-Office backend | Not on main (no references in docs, kit or src). | Long-term. |
| C17 [#28](https://github.com/paoloviviani/Cerea/issues/28) | Open Design / CoDesign | No references on main, issue open. | The spike is not done. |
| C30 | Office docs step 4 (`doc_convert`) | Steps 1-3 shipped (0.30.0 to 0.32.x). No `doc_convert`; `convert_document` exists. Step 5 depends on C12. | Decide whether step 4 is still wanted. |
| C40 [#39](https://github.com/paoloviviani/Cerea/issues/39) | PDF forms, step 3 | Steps 1-2 shipped (0.32.2). Step 3 needs `look_doc` (shipped 0.32.3). | Schedule step 3. |
| C42 [#44](https://github.com/paoloviviani/Cerea/issues/44) | MCP Apps | No `ui://` rendering in src. Needs an ADR first. | Stays parked. |
| C63 | M365 / Google connector reference | Parked, no tenant to test. | Parked. |
| C59 | Chat to /code bridge | Idea only. | Parked. |
| C71 | OpenTelemetry for agent activity | No OTel in src, kit or docs. Interim: review log page (#104). Cerea issue #50 (observability) is open. | Needs a pipeline in the kit first. |
| C72 | Sandbox ADR for coding agents | No sandbox ADR; the last ADR is 0107. G3 is the same area. | Write the ADR and merge it with G3. |
| C73 [#113](https://github.com/paoloviviani/Cerea/issues/113) | Secret value in an outbound command | Issue open, no commit. Owner says "next release". | Queued. |
| C75 [#115](https://github.com/paoloviviani/Cerea/issues/115) | Provenance note on repeated text | Issue open, no commit. Owner says "later". | Later. |

### Cerea tests/CI
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| C25 | Audit of sliding-panel and leaky tests | A class of work; no completion marker. | Fold into per-flake fixes. |
| C32 [#32](https://github.com/paoloviviani/Cerea/issues/32) | Client harness noise and hangs | `wrapDynamicImport` TypeError is still in the failing client run of 2026-11-05 (42026034710). | Parked. |
| C37 [#42](https://github.com/paoloviviani/Cerea/issues/42) | CodeNavTree flake | No fix commit; no recurrence in the last 200 runs. | Fix at the cause. |
| C43 | ChatInput cascade-submenu flake | No fix commit; no recurrence in the window. | Fix at the cause. |
| C45 / C57 | ToolUpdate thumbnail flake | No fix commit; no recurrence in the window. | Fix at the cause. |
| C49 | `TEST_DATABASE_URL` specs never run in CI | `deleteDerived.spec.ts` still skips without it; no workflow supplies it (grep). | Add a pgvector service container, or document. |
| C56 | Pin `listKnowledgeFiles` URLs | `attachmentMountBase.svelte.spec.ts` exists. Whether it has the fifth case is not verified (only 2 hits for "knowledge"). | Check, then add the case. |
| C60 | Client flakes | The connectors "tapped on a phone" snapshot failed again on 2026-11-05 (run 42026034710, `feat/read-only-fast-path`), after the v0.37.0 fix. The KB submenu was fixed in v0.38.0. OfficePreviewWiring is local-only and unverified. | Re-open the connectors snapshot; see the correction list. |
| C66 | code-machine-parity timeout | Recurred in the 2026-11-05 runs. 41947602648 and 42008000219 were on main, 42069030503 on a branch, at `:674`, `:136` and `:172`. The sibling `code-stop-permission` and `code-auto-review` specs failed in the same runs. | Fix at the cause; it is no longer rare. |
| C68 | V8 start-up crash in CI | Mitigation shipped (f52bc052, v0.41.0: a retry only on exit 133). No exit-133 failure in the window. | Mitigated; keep watching. |
| C69 | CSV download carries a partial artifact | `chat-artifact-table.spec.ts:26` failed on main (42015100418) and in 42015426072 on 2026-11-05. The 3daf5e7f revoke change is in v0.42.0, and the failures came before that release; no run after the release is available to check. | Cause unknown; wait for another run. |
| (new) | Galopin `opencode` workflow failed on main | `TestPassthroughP3CeilingWinsAndAlwaysBecomesOnce` failed in run 42076436648 on `eeb5a72e`. The later commit 413ee66b ("Always allow over ask limit") may be the cause. It is not in the backlog. | Check against 413ee66b and give it a row. |

### Cerea chores
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| C19 [#36](https://github.com/paoloviviani/Cerea/issues/36) (Pystino [#20](https://github.com/paoloviviani/Pystino/issues/20)) | Coverage gaps; users API capability flags | Pystino #20 open. No WebKit run exists. | Parked. |
| C21 [#33](https://github.com/paoloviviani/Cerea/issues/33) | Shrink AGENTS.md | It is 1595 lines against a ~400 target. | Parked. |
| C22 [#34](https://github.com/paoloviviani/Cerea/issues/34) (Pystino [#21](https://github.com/paoloviviani/Pystino/issues/21)) | Split the largest modules | Pystino `routers/admin.py` is still 7414 lines. | Parked. |
| C23 [#35](https://github.com/paoloviviani/Cerea/issues/35) | Shrink the chat image | Not done (issue open). | Needs the owner's package list. |
| C46 | OSM maps skill caveat | No "street" caveat in the OSM skill (grep). | Optional. |
| C51 | "users" vs "people" wording | `docs/writing.md` still says "people" and is unchanged. | Owner decision. |
| C52 | Sidebar folder delete on others' chats | In progress (see below); the other half is open (error paths without specs). | Finish in `fix/small-ui-bugs`. |

### galopin
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| G1 [#19](https://github.com/paoloviviani/Cerea/issues/19) | opencode 2.x | The pin is still 1.19.3 (`agent/packaging/opencode-version`). Issue open. | Parked. |
| G3 [#21](https://github.com/paoloviviani/Cerea/issues/21) | OS sandbox | Not built. Overlaps C72. | Merge with C72. |
| G12 [#24](https://github.com/paoloviviani/Cerea/issues/24) | Machines show offline after a restart | Issue open; not investigated in git. | Low priority. |
| G14 | `TMPDIR` inside the galopin tree | Still the case; per memory, `TMPDIR` points to `~/.config/galopin/opencode-tmp`. | Low priority. |
| G15 [#30](https://github.com/paoloviviani/Cerea/issues/30) | Pin to 1.19.4 | The pin is still 1.19.3. Issue #30 ("passes") is closed; #37 ("1.19.4 breaks") is open; #49 ("1.19.5 passes") is open. | Settle which of 1.19.4 and 1.19.5 to take, close the stale CI issues. |
| G16 [Pystino #19](https://github.com/paoloviviani/Pystino/issues/19) | Spurious ERROR on standalone Pystino | Issue open. | Parked. |
| G7 | Document machine-installed skills | `docs/agent-machines-reference.md:176` documents it, so the docs half is Done (v0.17.0). | Move to Done. |

### Design / long term
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| P1 follow-ups | Routing | P1 itself is done; P2/P3 hold the rest. | See P2/P3. |
| C71, C72 | OTel and sandbox | See above. | ADR first. |

### Owner decisions
| ID | Title | Status + evidence | Next step |
|---|---|---|---|
| C51 | users vs people | Open (see above). | Owner. |
| C34 | Reused login code | Open. | Owner to confirm or drop. |
| P19 | Allow-list union | Open. | Owner to drop. |
| P21 | postgres-data volume | Open. | Owner. |
| C63, C59, C42, C41 | Parked ideas | Owner has parked them. | Leave parked. |

---

## 2. In progress

| ID | Title | Branch / evidence |
|---|---|---|
| G11 | "Always allow" on a file edit covers the whole session | `fix/edit-always-scope`. The relabel "Always allow edits (this session)" is already on main (`messages/en.json`). The branch changes the scope. |
| C27 | Slash command echo monospaced | `fix/small-ui-bugs` (main still has `font-mono` at ChatMessage `:1335`). |
| C28 | Message actions vanish mid-turn | `fix/small-ui-bugs` (not yet pushed on origin, per the owner). |
| C29 | "Something else" shown twice | `fix/small-ui-bugs`. |
| C65 | Refused 410 shows nothing | `fix/small-ui-bugs`; origin has commit 2588d28d. |
| C52 | Sidebar folder delete | `fix/small-ui-bugs`; origin has commit faf9e084. |
| C48 | `search` 500 on an unreachable width | `fix/small-server-bugs`. The MRL half shipped in 0.32.4 (31a33bc0); the non-MRL width case is the remaining part. |
| C54 | Sandbox mount "current" exceptions | `fix/small-server-bugs`. |
| C38 | `look_doc` | **Done**: v0.32.3. Remove "in progress". |
| C73 | Secret value in outbound command | Issue #113, queued for the next release; no branch yet. |

---

## 3. Done since the backlog was written (or never marked)

### Pystino
| ID | Title | Release |
|---|---|---|
| P1 | Routing policies, stickiness, fallback | v0.14.0 |
| P4 | YAML provider catalogue | v0.15.0 |
| P5 | Chat completions over native Messages | v0.23.0 (issue #6 is still open) |
| P7 | Per-user quota ceiling | v0.14.0 |
| P9 | Admin audit log | v0.13.0 |
| P10 | Empty `/v1/models` on a scoped key | v0.13.0 (not reproduced) |
| P11 | Quota admission race | v0.13.0 |
| P12 | `packages/ui` i18n | v0.13.0 |
| P14 | Live checks with a non-admin | v0.13.0 |
| P15 | AGENTS.md open items | v0.13.0 |
| P16 | Per-size image pricing | v0.13.0 |
| P17 | Request log | v0.13.0 |
| P18 | Usage charts, per-provider | v0.15.0 |
| P20 | PG test conftest drops per-test databases | v0.15.0 (e57137c) |

### Cerea
| ID | Title | Release |
|---|---|---|
| C2 | Chat i18n foundation | v0.25.0 |
| C3 | web_fetch cross-turn cache | v0.17.0 |
| C4 | gatewaySession fold race | v0.17.0 |
| C5 | MongoDB 8 default (4.4 fallback) | v0.17.0, kit follow-up v0.24.0 |
| C7 | Keep the fresh-kit log | v0.17.0 |
| C8 | `as unknown as` audit | v0.17.0 |
| C9 | Exclusive model-access modes | v0.17.0 |
| C10 | Office previews (Gotenberg, pptx-glimpse) | v0.18.0 |
| C15 | Voice input (browser speech recognition) | v0.21.0 |
| C16 | Push notifications | v0.21.0 |
| C18 | Opt-in location | v0.21.0 |
| C24 | Playwright 1.64.1 | v0.25.0 |
| C31 | Connector modes and `load_tools` | v0.32.0 |
| C33 | NavMenu and CodeTerminal flakes | v0.18.0 / v0.21.0 |
| C35 | Admin connector description | v0.32.1 |
| C38 | `look_doc` | v0.32.3 |
| C44 | Delete in the chats-list row menu | v0.32.4 |
| C47 | Docs nav tabs | v0.32.4 |
| C53 | Attachment "current" version | v0.32.4 |
| C55 | Dead `draftEmitAt` store | `draftEmitAt` is now used (`runMcpFlow.ts:1139`); the other two notes are unverified |
| C58 | HTML artifact load errors | v0.35.0 |
| C62 | Mobile keyboard/PWA | v0.37.0 |
| C64 | /code file editor (#78, #69) | v0.39.0 |
| C67 | Chat drives coding-agent sessions | v0.40.0 |
| C70 | Shared projects list own chats | v0.41.0 |

### galopin
| ID | Title | Release |
|---|---|---|
| G2 | Coordination over MCP | v0.19.0 |
| G4 | Delegate profiles and recipes | v0.19.0 |
| G6 | opencode pin 1.19.3 | merged (d8f71a87) |
| G7 | Machine-skills docs | v0.17.0 |
| G8 | Cancelled background tasks reported | v0.17.0 |
| G13 | Re-enroll keeps policy flags (ADR 0107) | v0.41.0 |
| G17 | `files.*` ops (list, stat, read, status, write) | v0.39.0; `fileSearch` and `fileWatch` stay reserved |
| G11 (relabel half) | "Always allow edits (this session)" | on main |

---

## 4. Dropped / Parked

| ID | Item | Decision |
|---|---|---|
| C26 | Move-to-project on the open chat page | Dropped 2026-10-25 |
| C74 | Workspace config that runs code on open | Dropped by the owner 2026-11-06; issue #114 is closed |
| P6 | Refuse Anthropic server tools on `/v1/messages` | Rejected |
| G5 | Billing group per session | Rejected |
| G9 | Report to opencode upstream | Rejected |
| G10 | Free-model sessions | Not a leak |
| C6, C14 | MongoDB EOL plan; DocumentDB/FerretDB | Rejected or merged into C5 |
| C1 | Dex in front of Authelia | Parked; spike branch only |
| C42, C41, C59, C63 | MCP Apps, skills-first, chat/code bridge, M365 reference | Parked |
| G1, G3 | opencode 2.x, OS sandbox | Parked or long-term |

---

## 5. Rows whose old status text was wrong

1. **C38 `look_doc`**: "in progress". It shipped in v0.32.3.
2. **C64 file editor**: "unreleased". It is in v0.39.0.
3. **C58 HTML artifact errors**: "merged, unreleased". It is in v0.35.0.
4. **C60 flakes**: "mostly done". The connectors snapshot flake recurred on 2026-11-05 (42026034710), so it is not fixed.
5. **C66 code-machine-parity**: "rare, allowed to wait". It failed in 3 of the 8 failed runs of 2026-11-05, two of them on main; it is not rare.
6. **C69 CSV download**: "reopened; revoke deferred". It failed again on 2026-11-05 on main (42015100418); the 3daf5e7f revoke change shipped in v0.42.0, so a recheck is needed.
7. **C20 ask card**: "parked, app race remains". `fix/ask-question-reset` merged (v0.24.0) and #31 is closed.
8. **C5**: described as an upgrade path plus the CI pin removal; AVX detection and the default shipped (v0.17.0 and v0.24.0). I did not check the guided 4.4 to 8 upgrade or the pin removal.
9. **C30**: "steps 1-3 shipped". The row did not say step 4 would not be built; no `doc_convert` exists on main.
10. **G11**: "being done on `fix/always-allow-edits-label`". The relabel is on main. The in-progress branch is a different one (`fix/edit-always-scope`).
11. **P19**: framed as a bug. The first-policy-only allow-list is by design (ADR 0038).
12. **G17**: "files.* not implemented". `files.list`, `stat`, `read`, `status` and `write` are all implemented; only search and watch are reserved.
13. **G7**: marked "docs, pushed, not merged". It is merged and in v0.17.0.
14. **P5**: marked long-term/open. It shipped in v0.23.0 (issue #6 still open).
15. **P2**: its Done entry ("decision models, routing by decision model is still #3") is right, and the row stays open.
16. **P7**: P7 was listed as "nothing in the code". Shipped v0.14.0.
17. **C3, C4, C7, C8, C24, C35, C44, C47, C53**: stale "not merged" or "pushed" text. All are merged and released (see section 3).
18. **C2**: "done on main 2026-10-25". Released v0.25.0.
19. **G6, G15**: G6 says "pin is still 1.18.34"; the pin is 1.19.3. G15's "1.19.4 passes" is stale: #37 reports it breaking.

### Issues with no backlog row
- Pystino #18 (speech-to-text models), #20 (= C19), #21 (= C22).
- Cerea #48 (unattended permission asks), #50 (observability), #113 and #115 (= C73, C75; filed).
- The opencode CI issues #37, #49 (open).

---

## Counts (approximate)
- Open: about 50 distinct IDs (Pystino 6, Cerea about 38, galopin 6; C32/C60/C66/C69 etc. are flakes; G7 appears in the galopin table but is Done).
- In progress: 8 (G11, C27, C28, C29, C65, C52, C48, C54); C73 is queued; C38 is a correction (it is Done).
- Done: 14 Pystino + 25 Cerea + 8 galopin = 47.
- Dropped/Parked: 14 lines in section 4.
- Wrong old status: 19 corrections.
