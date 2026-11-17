# Rules model v2: fix round after the Opus review (continuation)

The previous worker was stopped. Its commit 850c256 on feat/rules-model-v2 (pushed) covers part of this list. Verify each item against the code, finish whatever is missing, and do every step from "Docs and ADR" on. The main brief, with box rules and the dev-stack details, is `2026-11-10-rules-model-v2.md` in this folder.

## The fix list

**Model change, approved: a content rule may have no policy when its mode is `block` or `detect_only` AND it has at least one condition.** A no-policy rule hides nothing.
- Classifier-only and other policy-less refuse rules migrate ENABLED, as no-policy block rules.
- A truly unconditional refuse (refuse everything in scope) migrates ENABLED as a no-policy block that blocks everything in scope. Document it.

**Migration 0086**
1. **Several `finds` conditions with mixed negation.** Merge only when none is negated. Otherwise represent the rule faithfully where possible (e.g. split it). If that's impossible, keep the rule off with a note, counted in the log.
2. **`otherwise: refuse` / `read_with X`** (extract and content). When every earlier rule has a single condition, synthesise "block when NOT(rule1) AND NOT(rule2)…" with match all. Otherwise add the rule switched off with a note. NEVER enabled without a condition.
3. **`default_mode`** expands to every format and entity type the engine supports. The log must state accurately what is lost.
4. **A name in two tables** keeps the strictest mode.
5. **Twin chat/embed pipelines** are paired independently of row order.
6. **A missing policy** keeps a hiding mode, so the request fails closed with a 503.
7. **Split rule names** are truncated to 120 characters.
8. **The hiding part of a migrated extract rule** is never `block`; clamp it to `redact`.

**Claim order.** A partly overlapped later span is trimmed to its unclaimed remainder(s) and claimed. Test: "Mario Rossi" with Rossi claimed as LOCATION → "Mario" is hidden too.

**Block counting.** Override types set to `off` are excluded from the count.

**Console**
- No static "Pipeline is on" / "Rule is on" labels: show On/Off from the checked state (see PipelineCard:80).
- `conditions_tip`: say match is all or any, and spell out the no-condition behaviour.
- Pluralise "(1 overrides)" and "finds at least 1 items".
- The sticky Save/Back bar must not cover the Policies field while a rule is open.

## Remaining steps (do all of them)

**Docs and ADR**
- Update ADR 0114 (`/home/ubuntu/workspace/ai-stack/docs/adr/0114-privacy-rules-model-v2.md`, do not commit in ai-stack):
  - make the lossy list match the behaviour;
  - add that cross-pipeline order now decides (the first admin pipeline by position claims), which can be less strict than the old fold.
- Update `docs/privacy-routing.md` the same way.

**Checks**
- Run the FULL gateway suite, `mkdocs build --strict` (heavy lock) and the console checks.
- Add a migration test for every case above.

**Dev stack**
1. With the gateway stopped (`-p cerea-test` only, never the live `cerea`), drop and recreate the gateway DB in cerea-test-postgres-1, then restore `/home/ubuntu/cerea-test/backup-pre-rules2-2026-11-10-1052.sql.gz`.
2. Rebuild for the new sha and deploy. Confirm alembic 0086, a healthy gateway and the running image's sha.
3. Re-create the disabled "Remote providers example" pipeline (Leaking secrets → anonymise; Basic tax PII → anonymise_restore with IT_VAT_CODE → redact).
4. Run `scripts/test_privacy_routing_live.py` against the dev gateway if you can do it without printing secrets. Otherwise say why not.
5. Re-take the 6 screenshots into `ai-stack/reports/screenshots/rules2/`, as before, and open all 6 yourself.

**Report:** commits, full test counts, the migration result on dev data, the remaining lossy cases, and anything not done.
