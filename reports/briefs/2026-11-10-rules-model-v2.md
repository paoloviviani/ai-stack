# Brief: privacy rules model v2 (Pystino), end to end, then deploy to the dev stack

You are a Sonnet worker. Implement completely ("no half results", no prototype). Do not spawn sub-agents. The owner approved this design on 2026-11-10.

## Where
- Worktree `/home/ubuntu/workspace/Pystino-wt-rules2`, branch `feat/rules-model-v2`, created from origin/main (Pystino 0.32.1).
- Read `AGENTS.md` first. Then read:
  - `docs/privacy-routing.md`, the current model;
  - `docs/redaction.md`;
  - the code:
    - `apps/gateway/src/gateway/privacy/` (rules.py, evaluate.py, service.py, pipelines validation);
    - `apps/gateway/src/gateway/routers/admin_privacy.py` and `me_redaction.py`;
    - `apps/gateway/src/gateway/redaction/resolver.py`;
    - `apps/gateway/src/gateway/models.py` (PrivacyPipeline, RedactionPolicyRecord, UserPolicy);
    - migrations 0082–0085;
  - the console:
    - `apps/console/src/components/PipelineEditor.tsx` and `PipelineCard.tsx`;
    - `routes/AdminPrivacy.tsx`, `AdminPolicy.tsx`, `MyPrivacy.tsx`, `MyRedactions.tsx`;
    - `lib/privacy.ts`, `types.ts`, `api-schema.ts`.
  - Find the ADR that ADR 0113 lives in and add the next-numbered ADR beside it.

## The new model (the specification)

**Kinds: two, `read` and `content`.**
- `content` replaces `chat` and `embed`. It covers chat completions, responses, messages and the other chat surfaces, plus embeddings and rerank.
- A pipeline's target gets an optional **model type** filter: any (the default), chat, embedding, or rerank. It is part of the scope.
- What a condition judges is unchanged: chat judges messages and tool results; embedding judges each input.

**Pipeline.** A scope (who + target, as today) plus an ordered list of rules. There is no "otherwise" / "everything else"; that field is removed.

**Rule: "When ‹policies› + ‹conditions› → ‹mode›".**
- **policies:** one or more policies (admin policy ids, or for a user pipeline its allowed policies, as today). They are what the rule looks for, and what it hides.
- **conditions:** optional, with a selectable **match: all | any** (default all). Each condition can be negated.
  - `finds`: the threshold, "at least N items". It counts distinct items found by the rule's own policies combined. It no longer names a policy.
  - `classified` (admin only): unchanged.
  - read kind: `filetype`, `scan`, `filename`, unchanged.
  - With no conditions, the rule fires when its policies find at least one item.
    - In the content kind, a rule must have at least one policy.
    - In the read kind, a rule needs no policy (see below).
- **mode:** `off` < `detect_only` < `anonymise_restore` < `anonymise` < `redact` < `block`.
  - Optional **overrides by entity type** (`{TYPE: mode}`) apply to the rule's policies.
  - `block` refuses the request. Keep the existing `RoutingRefusedError` / `code="routing_refused"` and the refusal body. Cerea depends on that code.
  - `off` does nothing. `detect_only` logs (this replaces the `observe_only` flag; remove that flag).

**Policies keep only what to look for:**
- items: patterns, keywords, formats, entities, custom entities;
- engine, thresholds, allow-list, placeholder style.

Per-item `mode` and `default_mode` move to rules. The policy editor loses its mode selectors and keeps detection settings. User policies (`user_policies`) lose their per-entry `mode` the same way. Check how a user pipeline names a user policy, and keep users' pipelines working with the same rule shape.

**Evaluation (stateless, per request):**
1. Collect every pipeline in scope, in this order: **administrator pipelines in console order (`position`), then the user's own pipelines**. Rules within a pipeline go top to bottom. Every rule is evaluated; there is no first match.
2. **All conditions are judged on the original text.**
3. **Block first:** if any matching rule's mode is `block` (or an override sets `block` for a type that was found), refuse the request. Name that rule in the error, as today.
4. Otherwise, apply hiding **in order**: each matching rule hides what its policies find, using its mode and overrides. **The first rule to hide a span decides how.** Later rules only see text not already claimed.
   - `off` and `detect_only` never claim a span.
   - Implement this as one detection pass over the original text per request, then resolve overlaps by rule order. Do not re-detect on placeholder text. Placeholders stay HMAC-stable (`placeholder_for`), and restore works for `anonymise_restore` spans.
5. **An undecidable condition never fails open:** keep today's behaviour, adapted.
6. **The trace / Test tab:** list every pipeline and every rule with matched or not, the items found, and which rule claimed which span.

**Read kind:**
- Actions: `default reader` < `read with <reader>` < `block`.
- Between two `read with` rules, the first in the order above wins.
- Hiding on the text a reader returns uses the same rule shape (policies + mode), applied in the same order, and is optional on a read rule.
- Keep the read conditions unchanged.

**Migration (alembic, next number). It must preserve behaviour as closely as possible:**
- Merge each `chat` and `embed` pipeline into `content`:
  - two pipelines with identical name, scope and rules become one with model type any;
  - otherwise convert each separately, with model type chat (for chat) or embedding+rerank (for embed). If the filter must allow a set, make it a set.
- Each old rule (conditions → level, plus optional "redact with" P):
  - `finds` conditions name policies; those become the rule's policies;
  - `refuse` becomes `block`;
  - `pass` + redact with P becomes a rule whose policies are P, with mode and overrides derived from P's per-item modes (the most common mode as the default, the rest as overrides);
  - a rule that both decides on X and hides with a different P becomes two rules in sequence: X + threshold → … and P → modes, preserving the intent as closely as possible. Document every lossy case in the ADR.
  - `observe_only` becomes `detect_only`.
  - `otherwise` with a "redact with" becomes a final rule with those policies and no condition; `otherwise: pass` is dropped.
- Strip `mode` / `default_mode` from policies only after converting.
- Write a downgrade if feasible; otherwise state in the ADR why it is irreversible.
- Test the migration on a copy of the dev-stack data (below).

**API and console:**
- Update the schemas (`schemas.py`), the admin and me routers, the OpenAPI export (`scripts/export_openapi.py`) and `api-schema.ts`.
- The pipeline editor shows each rule as one sentence: "When [policies ▾] [+ conditions, all/any] → [mode ▾] (overrides, collapsed)".
- Say once, above the rules: "Rules apply top to bottom. A rule that blocks refuses the request; otherwise every matching rule hides what it finds, and the first rule to hide a piece of text decides how."
- No pass/refuse wording anywhere.
- Remove the policy editor's mode columns.
- Use "users", not "people", in UI strings.
- **Topic-generic:** no medical or other subject defaults or examples in seeds or UI.

**Docs:**
- Rewrite `docs/privacy-routing.md` for the new model. Update `docs/redaction.md` where it talks about policy modes.
- Add one line: rotating `GATEWAY_REDACTION__PLACEHOLDER_KEY` invalidates embeddings indexed with old placeholders, so knowledge bases must be re-embedded.
- Write the new ADR (it supersedes the relevant parts of 0113).
- Add a CHANGELOG entry under Unreleased.

## Checks
- Run the pytest suite for the gateway and the console's `pnpm` typecheck, lint and tests (see AGENTS.md).
- Add tests:
  - the evaluator: order, the first claim wins, block first, detect_only and off claim nothing, admin before user, read reader precedence;
  - the migration: each conversion case;
  - the API validation.
- Update `scripts/test_privacy_routing_live.py` to the new model.
- Use `export TMPDIR=/var/tmp/rules2-tmp` (mkdir it).
- Never `git stash`; use temporary local commits.
- Commit as you go, with messages ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push the branch (`git push -u origin feat/rules-model-v2`).
- Do NOT open a PR, merge, tag or release.

## Box rules (mandatory)
- 5 cores / 20 GB, shared.
- **Heavy jobs** (docker image builds, `pnpm build`, e2e): `flock -n /tmp/heavy.lock.a CMD || flock /tmp/heavy.lock.b CMD`.
- **Never nest locks:** `kit/dev/build.sh` locks itself, so point its `BUILD_LOCK` at a slot rather than wrapping it in flock.
- **Stacks:** run `docker compose ls` before any `up`. Take `flock /tmp/heavy.lock.x` for compose up/down and live checks.
- **The live stack** `/home/ubuntu/cerea/` (project `cerea`) serves real users. Never touch it, its `.env`, containers, volumes or networks. Allowed prunes: `docker image prune` (dangling only) and `docker builder prune -f`.
- **No sudo.**
- **Secrets:** never print secrets or `.env` key values. Use grep with values masked.

## Final step: deploy the branch to the dev stack and show it
The dev stack is `/home/ubuntu/cerea-test/kit`, compose project `cerea-test`, gateway on port 8100. It runs Pystino `PYSTINO_VERSION='sha-fdaf9b0'` (local images).
1. **Back up its postgres first:** `docker exec cerea-test-postgres-1 sh -c 'pg_dump -U "$POSTGRES_USER" "${POSTGRES_DB:-$POSTGRES_USER}"' | gzip > /home/ubuntu/cerea-test/backup-pre-rules2-$(date +%F-%H%M).sql.gz`.
2. **Build your branch's gateway image:**
   - with `/home/ubuntu/cerea-test/kit/dev/build.sh --pystino-ref <your pushed sha>` (read its header first; keep the current Cerea ref `285e201` and the extractor and redaction images unchanged);
   - use `--no-env` if needed, and set only `PYSTINO_VERSION` in its `.env` yourself;
   - check that the build doesn't replace `EXTRACTOR_IMAGE` or the redaction image override in `compose.override.yaml`.
3. **Bring the stack up:** `flock /tmp/heavy.lock.x docker compose -p cerea-test up -d gateway` (plus whatever must restart). Confirm the migration ran and the gateway is healthy. Confirm the running image is your sha.
4. **Check the migrated data:** today it has one pipeline "Medical condition blocker", saved twice (chat and embed), with rule `Advanced PII finds >= 1 -> refuse`, and three policies: Advanced PII, Basic tax PII, Leaking secrets.
   - The pipelines should now be one content pipeline: "When Advanced PII + finds ≥ 1 → block".
   - Then add, through the API as the admin, an example pipeline "Remote providers example" (target all, model type any) with these rules:
     - Leaking secrets → anonymise;
     - Basic tax PII → anonymise_restore, IT_VAT_CODE → redact;
     - leave it disabled if enabling it would change behaviour for the owner's tests. Ask nothing; disabled is fine.
5. **Screenshots** with Playwright, of the dev stack only (never external sites), saved to `/home/ubuntu/workspace/ai-stack/reports/screenshots/rules2/`:
   - the pipeline list;
   - the pipeline editor for both pipelines;
   - a policy editor (no modes);
   - a Test-tab run that shows block, and one that shows hiding.

   Admin credentials are in `/var/tmp/uireview/creds.txt`; never print them.
6. **Report:** the final message must list:
   - commits;
   - test results, with counts;
   - the migration outcome on dev data;
   - lossy cases;
   - screenshot paths;
   - anything not done.
