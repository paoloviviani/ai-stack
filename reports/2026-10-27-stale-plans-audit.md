# Stale planning files audit, 2026-10-27

Read-only audit of the loose planning files in `/home/ubuntu/workspace/`. Nothing was changed, moved or committed.
Reference state: Cerea v0.31.1 / Pystino v0.18.1 released; Cerea 0.32.0 in progress (ADR 0104 = backlog C31, branch `feat/deployment-connector-modes`, plus the merged PowerPoint editing). Evidence: `git log origin/main`, tags, `kit/CHANGELOG.md`, `backlog.md`, `gh release list -R sst/opencode`.

## Summary table

| File | Asked for | Status | Still open (backlog ID) | Recommendation |
|---|---|---|---|---|
| HANDOFF.md (2026-10-09) | 11 Cerea/galopin tasks (spawn exceptions, fork button, transcript paging, permissions per session, safe dirs, retry detail, rules growth, provider errors, plan card, coordination switches); owner items | DONE (all 11 tasks shipped v0.9.4 to v0.10.2). The rest is process text, now OBSOLETE | GitLab first-test, reused login code 500, SCIM names held, kDrive backup confirm: untracked (probably old; ask owner). IdP access control "parked": superseded by Layer 1 (ADR 0095, shipped) | archive |
| BRIEF-auth-layer1.md | Join modes, invites, group gate, one mapping surface (ADR 0095, migration 0057) | DONE (migration 0057 to 0062, ADR 0095 exists, Pystino 0.5/0.6, Cerea 0.11 per memory). Its section 10 open questions were answered in the ADR | Layer 2 (replace Authelia) = C1 / C13 (Dex), parked | archive |
| BRIEF-c3-webfetch-cache.md | Cross-turn web_fetch extraction cache (C3, #12) | DONE (merge 0c4057ac, Cerea 0.17.0) | none | archive |
| BRIEF-c9-exclusive-modes.md | Pystino mode and standalone mode mutually exclusive (C9, #16) | DONE (merge 3cf78997, Cerea 0.17.0) | none | archive |
| BRIEF-continue-visibility-auth-usage.md | Billing group decides visible models; `galopin auth login`; personal-only usage page | DONE (Pystino 0.11.0, Cerea 0.16.0/0.16.1) | none | archive |
| BRIEF-model-visibility-and-galopin-login.md | Original of the above | OBSOLETE (replaced by the continuation brief) and DONE | none | archive |
| BRIEF-model-aliases.md | Implement ADR 0101 model aliases | DONE (Pystino 0.10.0) | Routing "designed for" part = P1, done in 0.14.0 | archive |
| BRIEF-model-aliases-release.md | Merge and release aliases (Pystino 0.10.0 + Cerea kit) | DONE (0.10.0, Cerea 0.15.13) | none | archive |
| BRIEF-release-pystino-0.11-cerea-0.16.md | Release Pystino 0.11.0 + Cerea 0.16.0 | DONE (tags v0.11.0, v0.16.0 exist) | none | archive |
| BRIEF-opencode-2-migration.md | Port galopin to opencode 2.x, gated on an upstream release | NOT DONE, still relevant, and the gate may have just opened (see below) | G1 (Cerea #19), parked | keep, update the gate and pin numbers |
| OVERNIGHT-PLAN.md (2026-10-20/21) | Block 1 queue then one release by 06:30 | DONE (Pystino 0.13.0 + Cerea 0.17.0 released 05:45). C10 was deferred, later shipped (backlog Done "Office previews") | NavMenu / CodeTerminal local-only flakes noted as follow-ups: untracked, likely fixed by the later test-reliability work (311ab9c9, 0.22.0) but unverified | archive |
| BLOCK2-PLAN.md (modified today) | Block 2 queue (2026-10-21), but in practice the orchestrator's running log through 2026-10-27 | PARTLY LIVE. Top "Queue" table (about 12 lines) is stale; everything after is a ledger that is current to today | see "Live items" below | keep, update (cut the stale table, or move the dated log into STATE) |
| oc-orchestrator/STATE.md (tail) | Ledger for the killed OC orchestrator; last entries 2026-10-10 to 2026-10-13 | OBSOLETE as a ledger (OC killed 2026-10-03; BLOCK2-PLAN.md has been the log since). Last two items (billing-banner collapse, agent-composer drop) are DONE: merges 93dd82bc and d38cd510 | none | archive (stop appending); memory still calls it "the ledger" |
| auth-briefs/STATE-15536003.md | Working state of a Sonnet worker, stage d (break-glass + e2e) | DONE and OBSOLETE (compaction scratch) | none | archive |
| auth-briefs/cerea-worker.md, stage-a.md, stage-b.md, stage-c.md, stage-d.md, stage-f.md | ADR 0093 stages: env-authoritative IdP, local accounts, link/merge/erasure, break-glass, docs | DONE (ADR 0093 shipped; Pystino 0.4+ / Cerea 0.10+ era). Remote branches `auth/*` no longer exist | none | archive |

## BLOCK2-PLAN.md: what is live

The file is not a plan. Lines 1-30 are a 2026-10-21 queue table whose states are all long finished. The rest is a timestamped log. Live as of today:

1. 0.32.0 = ADR 0104 (backlog C31) on `feat/deployment-connector-modes`, worktree `/home/ubuntu/workspace/wt-conn-modes`. Tracked as C31.
2. PowerPoint editing / fit (C30): merged (02423061), folded into 0.32.0. Tracked in C30.
3. Follow-ups recorded in the log with no backlog entry (untracked):
   - Pystino gateway `combine()` takes the redaction allowlist from the first applicable policy only; "consider union" (2026-10-26).
   - Cerea `files.*` ops are unimplemented in the machine-protocol spec (2026-10-22).
   - vitest client process takes 10 s to exit after runs (2026-10-21).
   - Pystino PG test conftest drops per-test databases only at exit, not at teardown (2026-10-21).
   - Briefs must forbid `--no-verify` and force-push (workers did both once, 2026-10-25/26). Memory has "no git stash" but not these.
   - Owner action: make GHCR package `cerea-documents` public after the first push (2026-10-26). Presumably done (0.30.0 released with documents healthy) but not recorded.
   - The `pystino_postgres-data` Docker volume deleted by mistake on 2026-10-21 (OVERNIGHT-PLAN log, 01:55). Owner was told; no follow-up recorded.
4. Already done or already tracked: Euro-Office spike (C12), ADR 0103 steps 1-3 (C30), P1/P7/P4/P2 (shipped), decision models live check (shipped 0.16.0), #3/P2 key blocker (resolved).

## opencode 2.x: the gate in BRIEF-opencode-2-migration.md may now be open

- Brief says "2.x is unreleased; npm latest 1.19.0; start condition = published 2.x release (npm and GitHub)".
- Today: `gh release list -R sst/opencode` shows **v2.2.0 published 2026-10-27**; npm `opencode-ai` `latest` is still 1.19.4. So the GitHub half of the gate is met, the npm half is not (check whether 2.x ships under another package name).
- Backlog G1 says "parked until opencode 2.x ships". The owner should be told. Pin is 1.19.3 (changelog line 738); 1.19.4 bump is G15; the brief still says 1.18.34.
- Brief cites a v1 DB migration risk (`experimental.migration.v1` may rewrite `~/.local/share/opencode/opencode.db`). Still a valid warning.

## Misleading statements (could mislead a future session)

HANDOFF.md
- "The owner's live stack is elsewhere (cerea.example.org)" is right, but "an opencode 'orchestrator' session ... on this box, working in /home/ubuntu/workspace/Cerea" and "Do not disturb what is running" refer to the OC orchestrator, killed 2026-10-03 (the file is dated 2026-10-09, so it was already partly wrong when written).
- "Workers are Sonnet; Opus only for orchestration and final review": consistent with today, but the file was written in the window when memory says workers were another model.
- "Feature freeze: fixes only": no longer true.
- Box rules say "4 cores, 5.8 GiB", "Heavy runs ... under flock" for everything; since 2026-10-23 heavy-lock is only for builds, full client project, Playwright and docker, and checks run in CI first.
- "Releasing" section describes `npm version` / `kit/tools/pin` manual flow and Pystino `AGENTS.md` flow; releases now use gated scripts (`tmp/rel-*.sh`, `release.sh`), CI full=true is the gate.
- References `Cerea-plan`, `Cerea-spawnx` worktrees and `BRIEF-plan-card-placement.md`: none exist.
- "Pystino: one stale cerea-deploy mention in deploy/cli.py" (cerea-deploy is archived; may or may not be fixed).
- Cerea tests "six code-* e2e specs fail on this box only; listed there": stale.

BRIEF-* files (all)
- Tell workers to use worktrees such as `Cerea-webfetch-cache`, `Cerea-modes`, `Pystino-aliases`. None exist now; existing worktrees are `Cerea-wt-merge`, `wt-conn-modes`, `wt-readme-shots`.
- "`TMPDIR` on this box points into a galopin directory" and "use `cerea-test-mongo` on port 8801" are box-specific and partly superseded (G14 fixed; in-memory Mongo libssl fix in database.ts since 0.17.0; CI-first rules).
- Say "At most 2 sub-agents" while the worker rule is now "no sub-agents" in worker briefs of auth-briefs.
- BRIEF-model-aliases-release / BRIEF-release-pystino: "the owner has authorised this merge and both releases" is one-shot authority, expired. A future session must not reuse it.
- BRIEF-model-aliases.md: "A release is running from the main checkouts right now" is a 2026-10-18 statement.
- BRIEF-auth-layer1.md: "Latest migration 0056, so this adds 0057 / ADR 0095": now 0070+ and ADR 0104.
- BRIEF-opencode-2-migration.md: "npm latest is 1.19.0, GitHub releases are all 1.x" (now 2.2.0 exists on GitHub; see above); "pin 1.18.34" (now 1.19.3).

OVERNIGHT-PLAN.md
- "At most 2 Sonnet workers", "Opus (me) reviews every branch": fine, but "Heartbeat", "OC" style wording and the 06:30 deadlines apply to one night only.
- Lists branches "finished, not merged": all merged and deleted.
- Mentions "Never touch ... `cerea-test-mongo`" which is still true.

BLOCK2-PLAN.md
- Top table: "#3 BLOCKED on a Cortecs key", "Cerea 0.21.0 awaiting", "#29 queued next", "ML Assistant queued": all done long ago.
- "Releases: ask the owner before merging/releasing a batch unless told otherwise": still the rule, but the log shows standing authorisations (overnight 2026-10-26) that have lapsed.
- Mixes two timestamp styles; "heartbeat" entries refer to cron heartbeats that no longer run.

oc-orchestrator/STATE.md
- Presents itself as the ledger ("STATE.md stays the ledger" in memory). It stopped on 2026-10-13; the live ledger is BLOCK2-PLAN.md.
- References "the free model's rate limit" and "task-tool subagents run a different model": old model setups.

auth-briefs/*
- Reference `/home/ubuntu/workspace/auth-*` worktrees (none exist), `cerea-deploy` repo and `/opt/cerea` (the live stack, not on this box since 2026-10-04), "orchestrator agent e5a26ebd", and branches `auth/*` that are gone from the remotes.
- The "NEVER wrap dev/build.sh in flock" rule is still valid; it is in memory.

backlog.md (found while auditing)
- Header says "Last updated 2026-10-24, at Pystino 0.17.1 and Cerea 0.23.1", but the file contains items up to 2026-10-27 (C30, C31). Misleading about freshness.
- IDs C18, C19, C20, C21, C22, C23 each appear twice (the Cerea feature list and the later "parked" chores): breaks the "stable IDs" rule.
- G1 text says "until opencode 2.x ships": see above.
- Memory and the CHANGELOG disagree on nothing material, but "Rejected / Filing plan" sections say filing is after owner review; most items are already filed.

## Untracked open items worth adding to the backlog

1. Check opencode v2.2.0 against the G1 start condition (new G1 status note).
2. Pystino gateway: redaction allowlist from several applicable policies should union, not first-wins.
3. Machine-protocol spec: `files.*` ops unimplemented in PROTOCOL (decide implement or delete from the spec).
4. Pystino PG test harness: drop per-test databases at teardown; vitest client exit delay (chore).
5. Worker briefs: add "no --no-verify, no force-push, even of your own branch" (process; goes in memory, not backlog).
6. HANDOFF owner items: GitLab real-deployment test and reused login code at `/chat/login/callback` giving 500 (verify whether still true).
7. NavMenu "draws the tree once sign-in fresh" and CodeTerminal "Ctrl+C SIGINT" flakes: confirm fixed (C25 covers the class, not these tests).
8. Close the loop on the 2026-10-21 deletion of the `pystino_postgres-data` volume (informational).
9. Dedupe backlog IDs C18-C23 and refresh its "Last updated" line.
