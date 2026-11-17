# 72 — Skills, phase 1: SKILL.md in the open format, loaded in stages

Date: 2026-09-16

## Status

Accepted. Supersedes the discovery half of the "Plan skill support" session
(agent `31a81568`): its exact-keyword matching plan is replaced by the
description-preload design below, for the evidence stated. Decisions 1, 2, 5
and 6 of that session stand as decided and are recorded here.

## Context

The chat needs reusable procedural knowledge — "reshape this CSV the way we
always do", "write the report in our shape" — that today lives in repeated
prompting. The industry has converged on the SKILL.md shape for exactly this:
YAML frontmatter with required `name` + `description`, a markdown body, and
optional `scripts/`, `references/` and `assets/` directories, with
progressive disclosure (frontmatter always, body on trigger, deeper files on
demand). The open agentskills.io spec (Apache-2.0) and the Anthropic and
OpenAI/Codex implementations agree on the format and on the loading pattern,
so there is a standard to follow rather than one to invent — portability in
and out is the point.

The planning session locked six decisions. A state-of-the-art check against
that spec and those implementations confirmed five and corrected one: the
session's "Phase 1 stays exact-keyword" matching. Keyword matching is more
code for worse triggering — a matcher the chat owns, tuned per skill,
misfiring on prose that happens to contain a keyword — while the standard
needs no matcher code at all: preload every enabled skill's frontmatter into
the system prompt every turn (~100 tokens each, which IS progressive
disclosure stage 1), let the model match by description semantics and load
the body (implicit activation), and let an explicit `@skill-name` mention in
a user message force that skill's body load. Simpler, standard, and strictly
less code than the thing it replaces.

## Decision

Phase 1 implements skills in the open SKILL.md format verbatim, with staged
loading as the budget mechanism:

- **Execution: Pyodide only.** Skills never execute on the chat backend or
  gateway; code runs client-side in the browser through the existing
  execution paths (`execute_code` tool / fences, model-driven). Portable
  skills with shell scripts do NOT transfer here — Cerea skills are
  **instructions + stdlib-Python-or-nothing**. A skill whose workflow needs
  bash is out of scope by architecture (multi-tenant box, no server
  isolation), not by omission.
- **Sharing: owner-only + minimal admin catalogue.** No user-to-user
  sharing, no publish flow. Admin skills are read-only shared definitions
  shaped like an `McpConnector` of scope `deployment`: the definition is
  shared, and the sharing is trivially safe because a skill holds no
  secrets. (Repo/project scope exists in the standard and the chat has
  projects — a later thought, not Phase 1.)
- **Discovery: frontmatter always, body on trigger, no matcher.**
  Every turn carries the frontmatter list (`name` + `description`) of every
  enabled skill in the system prompt. The model matches by description
  semantics and loads a body mid-turn through a `load_skill` builtin tool;
  a `@name` mention in the latest user message loads that body up front. A
  mention of an unknown or disabled skill is ignored silently, never an
  error. Full bodies for all skills are never injected; there is nothing
  deeper in Phase 1.
- **Budget: staged loading IS the mechanism**, plus the normal guards and
  truncate-and-log beyond them. Frontmatter is capped in shape (name and
  description length limits); bodies past 500 lines (the spec's guidance)
  are truncated with a logged warning, not rejected.
- **Versioning: none.** Admin skills are single-version; user skills are
  user-managed and live-read.
- **Admin catalogue: minimal, seeded definitions, no admin editor in v1.**
  Two to three boring, high-value procedural skills fitting Pyodide-only
  execution (CSV shaping, report writing, JSON shaping) — nothing needing
  network, packages, or shell. A per-skill global kill-switch
  (`CHAT_SKILLS_DISABLED`) costs nothing and exists.
- **Storage: Mongo, following the knowledge-base pattern of ADR 0070.**
  One document per user skill (raw SKILL.md plus denormalized
  name/description for the every-turn listing, per-skill enabled flag
  defaulting on), beside its owner like a `user`-scoped connector — not
  files, because there is no versioning to keep and live-read documents are
  "files = git" without a filesystem to synchronize. Admin seeds live in
  code, not in the store: read-only definitions with no v1 editor.
- **UI: minimal, in the Workspace idiom.** A fourth workspace tab beside
  models, MCP servers and knowledge: list with enable/disable, body view,
  create/edit/delete for user skills; a read-only admin section. Plumbing
  with a face, not a showcase.
- **Export: nothing needed.** Skill activation produces no transcript
  artifact — frontmatter and bodies live in the system prompt, and
  `load_skill` calls summarize to their names like every other tool — so
  the Markdown export already handles turns that used skills.

## Consequences

- The session's original exact-keyword plan is superseded and must not be
  built: any future matching work starts from description-preload, not from
  a keyword index.
- Every turn with skills available runs the tool flow (as enabling
  `execute_code` already does), carrying one extra tool definition. The
  frontmatter section is the visible per-turn cost, ~100 tokens per skill.
- A skill can never become a server-side execution path: the only
  model-facing surfaces are prompt text and the `load_skill` result text,
  and Python runs only where the model puts the procedure — client-side,
  through the existing sandbox tools.
- The next phases, explicitly not this one: `scripts/` execution policy
  beyond stdlib-Python-via-sandbox, `references/`/`assets/` depth loading,
  project-scoped skills, and any sharing or publishing flow.

## Amendment

2026-09-16: the "no admin editor in v1" statement above is superseded — admin
skills now live in the same `skills` collection with deployment scope
(readable by all users, writable only by an administrator through the
existing skills routes), the three code seeds are bootstrap rows inserted on
first read with the code kept as the fallback source of truth, and the admin
panel manages DB rows thereafter behind the gateway's admin gate.
