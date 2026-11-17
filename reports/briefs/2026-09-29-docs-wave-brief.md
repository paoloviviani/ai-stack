# Documentation wave brief: Cerea mkdocs site + Pystino coverage pass

Two repos, one worker, ~2.5d. The advisor's structure spec is binding (recorded
verbatim in /home/ubuntu/workspace/oc-orchestrator/STATE.md, 2026-09-29 ~11:30
entry — read that entry FIRST; the tables below summarize, the STATE entry is
the spec of record). You write docs and config; you do NOT touch /opt/cerea,
the compose stack, or any serving infrastructure — the OC handles hosting
after review.

## Rules of engagement

- REPO LAYOUTS: Cerea /home/ubuntu/workspace/Cerea (branch feat/docs-site off
  main b734f911); Pystino /home/ubuntu/workspace/Pystino (branch feat/docs-
  coverage off its main). NEVER edit docs/source/** in Cerea (upstream
  chat-ui's doc-builder docs, carried close-to-upstream by design — a fork
  merge discipline; also would fail strict mode). NEVER edit upstream docs
  meaning; the fork's flat pages in docs/ are yours to update where the spec
  says.
- STYLE: match Pystino's existing pages (read docs/getting-started.md and
  docs/operations.md first for voice, heading depth, admonition style).
  Material admonitions (`!!! info "For operators"`) per the spec's audience
  banners. One-line audience admonition at the top of each page.
- TRUTH: every page you write must be verified against the code/docs it
  describes — cite nothing you haven't read. The recent waves' behavior
  (slash commands, image rendering, enroll checkboxes) is documented in
  docs/code-panel.md, docs/agent-machines.md, agent/PROTOCOL.md, CLAUDE.md,
  README.md — read them. Where CLAUDE.md and a page disagree, CLAUDE.md wins
  (it is kept current by the waves) — fix the page.
- BUILD: Pystino's mkdocs pattern is the template (mkdocs.yml header comments
  explain the licence posture, ADR 0001). Cerea gets docs/requirements.txt
  (mkdocs, mkdocs-material, pymdown-extensions, pinned, with the same licence
  comment header) and builds with `uv run --with-requirements docs/requirements.txt
  mkdocs build --strict` — NO Python project files in the Node repo (no
  pyproject.toml changes). Prettier must not touch mkdocs.yml (add to
  .prettierignore if needed); verify `!!!` admonitions survive prettier on
  the .md files you touch (tabs-vs-spaces: match existing pages).
- GIT: Paolo Viviani (configured); NO AI trailers; coherent commits per
  numbered task below; push both branches; no merges.
- BOX: another opencode serve may be running — never kill processes you did
  not start. Heavy commands under `timeout -s KILL <secs> flock /tmp/heavy.lock`;
  check free -m ≥1500 / df ≥20% before each; WAIT rather than compete.

## Cerea (feat/docs-site)

1. **Site skeleton (0.25d).** mkdocs.yml at repo root: docs_dir: docs,
   exclude_docs: source/**, strict, material theme mirroring Pystino's
   features/palette (read Pystino's mkdocs.yml and copy the shape; site_name
   Cerea; repo_url https://github.com/paoloviviani/Cerea; copyright "LINKS
   Foundation — Apache-2.0" in Pystino's shape), the nav EXACTLY as the spec
   (Home / Using Cerea / Operating Cerea / Reference), docs/requirements.txt.
   New pages as flat files in docs/. index.md: what Cerea is, the stack
   (Cerea + Pystino + cerea-deploy), which section each audience reads,
   upstream credit (huggingface/chat-ui, Apache-2.0). `uv run --with-requirements
   docs/requirements.txt mkdocs build --strict` green with the pages that
   exist so far (unwritten pages: add them to nav only when written — the
   spec's cut-line: nav lists only pages that exist, growing as you go).
2. **agent-machines.md update (0.3d).** Add: the THREE enroll checkboxes
   (install opencode, allow terminal, allow auto-accept — read
   src/lib/components/code/PairDeviceDialog.svelte and
   src/lib/codeEnrollCommand.ts for the exact behavior/copy); THE MACHINE
   POLICY TABLE (one home: this page — files read-only + redactions,
   terminals behind a veto + max, auto-accept machine gate incl. handoffs/
   questions never auto-accepted, commandShell default denied +
   tighten-only, allowFreeModels — source agent/policy.go +
   agent/PROTOCOL.md §4); slash commands (the / menu groups Panel/Project/
   Machine/Skills/MCP, shell icon, shadowed names, the confirmation sheet
   keyed per (device,name,templateHash), 403 = enroll flag needed, 409 =
   template changed, mid-turn refusal, panel-only fallback on old galopin);
   agent images (tool-output images render inline; screenshots from
   Playwright-MCP; "N images not shown"). Cross-link see-also to
   code-panel.md at the top.
3. **chat.md (0.3d).** Conversations, models + effort pills, attachments
   (extracted ONCE at upload — billing rationale; unreadable-text sentence),
   web search/fetch, tool approvals, memory, skills. Sources: README,
   CLAUDE.md (§attachments, §models), the UI components where needed.
4. **artifacts.md + pyodide.md refresh (0.3d).** artifacts.md: text
   artifacts, inline file-artifact cards, versioning (sha-matched),
   library panel, raster-only inline images. pyodide.md refresh: the
   sandbox, auto-install, MATPLOTLIB FIGURES CAPTURED AUTOMATICALLY
   (plt.show saves figure-<n>.png; changed-files-only listing; savefig
   explicitly to reuse; 20-cap), limits.
5. **configuration.md + deploy.md (0.3d).** configuration.md: FORK-OWNED
   env vars ONLY (grouped by feature: CODE_AGENTS_ENABLED, CHAT_OCR_*,
   CHAT_PG_URL, CHAT_ERASURE_TOKEN, MCP_SERVERS, ... — source: .env.example
   + src/lib/server/config.ts; verify each against the code that reads it);
   upstream vars link to upstream docs (absolute GitHub URLs). deploy.md:
   thin pointer to cerea-deploy (three commands + link to its README;
   DO NOT duplicate the runbook).
6. **knowledge.md (0.2d).** Absorbs rag.md (keep rag.md? NO — the spec
   absorbs it: delete rag.md, fold content into knowledge.md, fix any
   inbound links). Projects (a shared project is a shared workspace),
   knowledge bases, sharing semantics (decided against the viewer's own
   identity), the memory base (an ordinary base, visible, deletable),
   retrieval never fails a turn.
7. **chat-admin.md + connectors.md + reference.md (0.2d).** chat-admin.md:
   the gatewayIsAdmin-gated chat surfaces (Admin row, knowledge/extractor
   settings, fetch status) — everything else links to the Pystino console.
   connectors.md: MCP connectors (OAuth or static token, per-call
   approvals). reference.md: LINKS ONLY — agent/PROTOCOL.md (repo URL, not
   included — its relative links would break strict), upstream chat-ui
   docs, the Pystino site (full GitHub URLs per the spec; cross-site links
   live HERE, few elsewhere; site_url stays unset).

## Pystino (feat/docs-coverage)

8. **Identity restructure (0.4d).** Promote identity to a section: NEW
   identity.md (one IdP from .env; admin rules OIDC_ADMIN_EMAIL/_CLAIM;
   rules only revoke what rules granted; the LAST-ADMIN GUARD serialized —
   read the code: the pg_advisory_xact_lock; link-by-email off by default,
   never admins; merge/erasure; identity_events audit; "need MFA →
   Keycloak"); NEW bundled-accounts.md (the Users page: Add user, the
   sign-in name, Create sign-in only for users with no login, Reset
   password, disable/enable/delete, OTP notice, SMTP self-service);
   TRIM oidc-generic-provider.md to its title's scope (external IdP
   registration, GitLab example, Keycloak audience mapper + the WARNING
   log, sign-out, User sync) — keep its path so inbound links survive;
   consolidate BREAK-GLASS into identity.md (preconditions; rotate
   SESSION_SECRET on suspected compromise) with deployment.md keeping a
   link. Sources: gateway/directory/*, the ADR 0093 series, docs/deployment.md.
9. **console.md + coding-agents.md delta + Versions (0.25d).** console.md:
   a task map of the console (users, groups, models, providers, quotas,
   redaction, the identity-provider card, activity) linking to each
   explaining page. coding-agents.md: machine credentials (long-lived
   refresh token, revocation on revalidation, disable ends access ~1 min);
   link to Cerea's agent-machines.md (full GitHub URL). index.md: a
   "Versions" section — one paragraph pointing at cerea-deploy's CHANGELOG.
   No mike/versioned docs.

## Verification (both repos)

- `uv run mkdocs build --strict` (Pystino) and `uv run --with-requirements
  docs/requirements.txt mkdocs build --strict` (Cerea) GREEN at the end of
  every numbered task, not just at the end.
- Every internal link resolves (strict enforces it); cross-site links are
  full GitHub URLs (strict does not check them — YOU verify each by curl
  -fsI once and note the status in your report).
- Prettier/eslint untouched-green on Cerea (the docs are .md — check the
  prettier ignore situation for mkdocs.yml at least).
- Report: per task, pages written/updated, what code/docs you verified each
  claim against, cross-site link check results, build outputs. Then STOP
  for review. The OC builds and hosts both sites after review — not you.
