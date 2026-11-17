# Coordination follow-ups — worker T (tree provenance), Cerea-only

Branch feat/coord-tree off main. You own src/** for this task (CodeNavTree, codeSubagents, related specs). A sibling worker owns the approvals change (galopin + Cerea sender cards) on a separate branch — coordinate implicitly via the file boundary; never touch agent/**, ToolUpdate approval-card internals beyond what this spec needs, or dispatch/relay code.

Plan of record: the advisor's verdict, logged in /home/ubuntu/workspace/oc-orchestrator/STATE.md (2026-09-30 ~23:15 entry — read it FIRST; the tree section is your spec). You implement; ambiguity → stop and report.

## Spec (model iii refined: top-level truth, provenance marking, adjacency)

- **Mark spawned rows with provenance, not parentage.** In CodeNavTree.svelte:958–992 (fed by spawnedRow/subagentRow in codeSubagents.ts): replace spawned sessions' "↳ from ‹title›" with a chip — spawn icon (carbon/fork or add-alt), "**spawned by** ‹title›", same link + elsewhere fallback, at the row's own indent. Subagents KEEP "↳ from" (real parentage). The shared glyph was the confusion — verify no other place renders spawned rows with ↳.
- **Group by adjacency, not containment.** In the workspace list, sort each spawned session immediately after its spawner, recursing along the chain (≤2 deep, same workspace only), at the same indent. Spawner gone → sort by createdAt as today.
- **Spawner row:** a small "spawned N" count next to the subagent badge, INFORMATION only (hover/tap lists the spawned sessions as links — NOT a disclosure, NOT collapsible).
- **"Show subagents"** filters parentId children only (spawned = peers, always listed) — verify this is already the behavior; keep it.
- **Archive/delete/revoke:** deleting or archiving a spawner leaves spawned sessions untouched (no parentId — verify in code, don't assume); a gone spawner renders "spawned by ‹title› (gone)" muted (spawnedRow already falls back to marker.title — wire the muted rendering); revoke removes everything (unchanged).
- **Galopin IT (agent/** — exception to the file boundary, ONE test only, coordinate by reading): deleting the spawner keeps the spawned session and its spawnedBy marker survives. Put it in the existing agent test idiom; do NOT otherwise touch agent/**. If this proves awkward, report it as a follow-up for the galopin side instead of forcing it.

## Tests (codeSubagents + CodeNavTree specs)
- adjacency ordering incl. a two-level chain;
- the provenance chip vs the subagent ↳;
- the subagent toggle doesn't hide spawned sessions;
- the "gone" fallback;
- spawner delete/archive leaves spawned listed (client-level where possible; the galopin IT covers the backend truth).

## Rules (binding)
- NO sub-agents; foreground; every heavy command `timeout -s KILL <secs> flock /tmp/heavy.lock`; free -m ≥1500 / df ≥20% before heavy steps, WAIT rather than compete (the approvals worker shares the box). Never kill processes you did not start. Client vitest needs TEST_MONGODB_URL=mongodb://127.0.0.1:8801. npm run check baseline: 0 — 0 new. Prettier/eslint clean. NO npm install. Never ports near 5199, never /opt/cerea.
- GIT: Paolo Viviani (configured); NO AI trailers; coherent commits; push feat/coord-tree; NO merge to main.
- Report: design as built, files, commits, exact test commands + pass counts, deviations. Then STOP for review.
