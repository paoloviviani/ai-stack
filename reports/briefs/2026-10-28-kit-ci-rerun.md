# Brief: kit branch CI rerun + review (2026-10-28 evening)

## Task
Two jobs on branch `kit/maps-skill-tool-economy` (pushed at `eff9cf34`; worktree `/home/ubuntu/workspace/wt-maps-skill2` is clean — do not modify files):
1. Re-run the failed jobs of CI run **40760767750** (`gh run rerun 40760767750 --failed`, from the Cerea repo) and watch to completion.
2. Review the branch diff `origin/main..origin/kit/maps-skill-tool-economy` (one commit).

## Context
The branch makes the maps skills use fewer tools (the venue's address from the web, one `map_link` from known coordinates, labelled distances) and fixes the kit test regex so it accepts patch-pinned node images (e.g. `22.23.4`). Its kit workflow run (40760771759) is green, but the `ci` run failed on one `client` job test: `ToolUpdate.svelte.test.ts` — "the collapsed card's thumbnail strip > reserves each box before its image arrives: nothing moves when it loads" (~15.4 s). Main's ci on the same base (`5ff84be0`, run 40751352215) is green and the branch touches nothing near ToolUpdate — flake suspect. Main's kit.yml stays red until this branch merges; the orchestrator merges after your report.

## If the rerun
- **Green**: flake confirmed; say so in the report (the Cerea backlog may want a flake entry).
- **Same test fails again**: report it as possibly real; do NOT dig into ToolUpdate (out of scope); the orchestrator decides.

## Review scope
`git diff origin/main..origin/kit/maps-skill-tool-economy`:
- The maps skills: instructions coherent and self-contained (no dangling references to removed tools)? Compare against the owner's pasted Geoapify copy at `/home/ubuntu/workspace/skills/maps-routing/SKILL.md` — diff them and explain any differences.
- The regex fix in `kit/tests/test_mcp_example.py`: must accept `node:24.22.1-slim@sha256…` and `node:22.23.4-slim@sha256…`, still require the sha256 pin, and still reject floating `node:` tags.
- Nothing else snuck in.

## Report back
Rerun result (run id, conclusion); review findings as blocking / minor; verdict: merge, or fix first.

## Constraints
No file modifications, no merging, no pushing. `gh` and git read commands only, plus the one rerun.

## Outcome (W3, 2026-10-28 evening)

### 1. CI rerun — GREEN, flake confirmed
Reran the failed jobs of run **40760767750** (`gh run rerun 40760767750 --failed`, attempt 2, same commit `eff9cf34`). Only the `client` job re-ran (20:28:53Z–20:39:17Z, ~10.5 min); result: **success**. The exact test that failed in attempt 1 — `ToolUpdate.svelte.test.ts > the collapsed card's thumbnail strip > reserves each box before its image arrives: nothing moves when it loads` — passed in 10.56 s on the rerun; the whole client project is green (136 files / 1165 tests passed, 1 file + 2 tests skipped, unchanged). Combined with main's green `ci` on the same base (`5ff84be0`, run 40751352215) and the branch touching nothing near ToolUpdate: **confirmed flake** (attempt 1 took 15.4 s and failed on a screenshot comparison — image-load timing profile). Worth a flake entry in the Cerea backlog; no code change required.

### 2. Review of `origin/main..origin/kit/maps-skill-tool-economy` — clean
One linear commit (`eff9cf34`) directly on main's tip (`5ff84be0`); exactly three files, nothing else snuck in; worktree clean.

- **`kit/tools/mcp/skills/maps-routing-geoapify/SKILL.md`** — byte-identical to the owner's pasted copy at `/home/ubuntu/workspace/skills/maps-routing/SKILL.md` (verified with `diff`: zero differences). The delta vs main is exactly the paste's own delta: the map_link row now reads "with coordinates you already have" (dropping "(offline, always works)"), and the Rules section gains the venue-address rule (web/website first, geocode the address, never the venue's name), the no-cross-check rule, the map_link coordinates rule, and the labelled-distances rule.
- **`kit/tools/mcp/skills/maps-routing/SKILL.md`** (OSM-only variant) — the same rule set adapted to a single service; coherent and self-contained, no dangling references. Every tool it names is in the kit test's `OSM_TOOLS` set, and the guard tests (`test_maps_skill_names_only_tools_the_osm_server_has`, the geoapify one) passed in the green kit run **40760771759** on this commit (re-confirmed: `kit` workflow, success). Its differences from the paste are the variant's by design (no Geoapify inventory, category table, "Who does what" table, or cross-check rule — one service, no second to cross-check). One **pre-existing** minor: the OSM variant lacks the Geoapify rule's "if the address only resolved to its street, say so" caveat — it never had it on main either; optional follow-up, not this commit's.
- **`kit/tests/test_mcp_example.py`** — regex semantics verified directly: the new `^FROM node:\d+(?:\.\d+){0,2}-slim@sha256:[0-9a-f]{64} AS node$` accepts `node:24.22.1-slim@sha256:<64hex>` and `node:22.23.4-slim@sha256:<64hex>` (and the major-only pinned form), still requires the full 64-hex digest, and rejects floating `node:22-slim`, `latest`, missing digest, non-slim variants, four-component versions and a wrong stage name. The old regex demonstrably rejected the patch-pinned form (the bug). The actual Dockerfile line (`node:22.23.4-slim@sha256:4b15…7279da`) matches, and kit run 40760771759 is green.

**Blocking:** none. **Minor:** the flake backlog entry; the OSM variant's missing street caveat (pre-existing).

### Verdict: **merge**.
