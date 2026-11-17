# Provider-override check: can a cloned repo redirect every prompt? (SPIKE FIRST)

Branch feat/provider-override off main (/home/ubuntu/workspace/Cerea, on
main).galopin-focused investigation with a fix ONLY if the hole is real.
You investigate, then report facts BEFORE any fix. You implement a fix
only if you can demonstrate the redirect live; ambiguity → stop and report.

## The question (advisor-flagged, highest-stakes before public)

A person clones a hostile repo as a workspace and runs an agent in it. The
repo contains its own `opencode.json` (project config: providers, models,
`enabled_providers`?). Can it:
(a) override the gateway provider's `baseURL` (or equivalent) so prompts —
    including expanded `@file` contents — go to an attacker's endpoint?
(b) re-enable providers galopin disabled (`enabled_providers`, the
    --allow-opencode-provider gate)?
(c) shadow a model id the gateway serves with a same-named local model
    pointing elsewhere (model-identity confusion at the picker or the
    setModel gate)?

## How to probe (live, opencode 1.18.32 installed)

1. Read how galopin launches opencode: what config it passes
   (OPENCODE_CONFIG? OPENCODE_CONFIG_DIR? per-backend config content?),
   what env (OPENCODE_SERVER_PASSWORD pattern), and what stops a repo
   config from merging (opencode's own config-layering: global → project
   → ? — verify against the INSTALLED binary's behavior, not docs).
2. Build a hostile fixture workspace: an `opencode.json` attempting each of
   (a)/(b)/(c). Run galopin against it (the IT harness idiom — mockllm +
   GALOPIN_OPENCODE_IT=1) and observe: where do prompts actually go (assert
   on the mock's received requests, the established pattern)? Which
   provider/model serves them?
3. Also check the reverse: does galopin PASS any repo-controlled config
   through to opencode verbatim (config overlays, `--config` flags,
   env passthrough like OPENCODE_* that a repo's .envrc/direnv could set
   — though direnv is out of scope, note it)?

## Report FIRST, then fix policy

- If NOT exploitable: report the facts (which layer stops each of a/b/c,
  with the observed behavior) and STOP — no code change, branch pushed
  empty-or-tests-only.
- If exploitable (any of a/b/c demonstrably redirects): report the
  minimal fix shape for OC approval BEFORE implementing (likely: galopin
  pins or strips repo-level provider settings — decide from evidence),
  then implement + live IT proving the redirect REFUSED + regression run.
  Do NOT freelance a broad config-lockdown beyond the demonstrated hole.

## Rules (binding)
- NO sub-agents; foreground; every heavy command `timeout -s KILL <secs>
  flock /tmp/heavy.lock`; free/available ≥1500MB / df ≥20% before heavy
  steps, WAIT rather than compete (a second worker shares the box). Never
  kill processes you did not start (exact PID only after ps confirms an
  orphaned probe/IT instance). Go live ITs: GALOPIN_OPENCODE_IT=1. npm run
  check baseline: 0 — 0 new. NO npm install. Never ports near 5199, never
  /opt/cerea.
- GIT: Paolo Viviani (configured); NO AI trailers; coherent commits; push
  feat/provider-override; NO merge to main.
- Report: facts first (exploitable? which of a/b/c, observed behavior),
  then fix-or-no-fix with evidence. Then STOP for review.
