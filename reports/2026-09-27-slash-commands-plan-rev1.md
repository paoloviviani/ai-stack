# Slash commands for galopin/opencode — plan rev1

**Status: approved.** Supersedes §2 of `2026-09-26-agent-chat-features-plan.md`
(the rest of that report — steering, reasoning, permission cards, history
paging — stays as written there, unchanged and out of this wave's scope).
User go: 2026-09-27 ("go ahead with the plan as soon as the auth fixes are
ready"; execution in a separate worktree, one executor).

Written against Cerea `b422a40a` (worktree `slash-cerea`, branch
`feat/slash-commands`), agent/ at that same commit, opencode probed at
1.18.32 (see §3 for the version caveat).

## 1. Scope

Slash commands only, per the 2026-09-26 plan §0 and §2, as re-validated by
the advisor on 2026-09-27:

- galopin: the `commands` capability, `backend.commands` and
  `session.command` ops, the `commandShell` machine policy with all its
  gates, the transcript marker, audit.
- Cerea: the forwarder rows, `codeApi`, the command bubble, the `/` menu
  in the agent composer, panel commands, the first-run confirmation.
- Steering, reasoning blocks, permission-card polish and history paging are
  NOT in this wave (decisions 2026-09-26, re-confirmed: steer=yes is a
  follow-up scheduled after batch B; plan-mode flag stays off; reasoning
  collapsed-by-default is a separate 1-day item; history paging later).

## 2. What changed since the 2026-09-26 plan

The composer rework (mode pill back in the composer row; the model/effort
control below the composer as the shared `ModelEffortPicker` default
trigger; the usage ring trailing right; TogglePill restyle) does not break
§2.3: the `@` menu anchors absolutely at the caret, opening upwards, clear
of everything below the composer. Four things did change:

1. **The opencode version needs reconciling.** The plan probed 1.18.32;
   `agent/PROTOCOL.md` and every IT say 1.18.31; nothing pins what a
   machine's PATH has. galopin therefore advertises `commands` only when
   the server's `GET /doc` lists the `session.command` operation — never a
   version string. Batch A re-probes `/command` on whatever enroll
   actually installs and pins the IT to that.
2. **`/model` and `/mode` with no argument need bindable menus.**
   `ModelEffortPicker`'s `open` is internal `$state`; the mode
   `DropdownMenu.Root` has no `bind:open`. Both become `$bindable`
   (one-line each) in batch B.
3. **The fold is server-side**: `src/lib/server/code/machineTimeline.ts`.
   The command marker renders there (batch C).
4. **Stale copy**: the mode pill's tooltip says "paseo's modes"
   (`src/lib/components/code/AgentComposer.svelte:506`). Fixed in A0
   (freeze-allowed: it is wrong text about a shipped feature).

Menu interactions added to the design (batch B): dismiss the `/` menu when
the mode pill or model picker opens; keep the mobile send/stop overlay from
covering the menu; keep accept-over-send precedence identical to the hub
mention menu's.

## 3. Security delta (on top of 2026-09-26 §2.5, which holds as written)

1. **NEW: a command's `agent:` frontmatter can escalate out of plan mode.**
   A repo command can name `build` (or a permissive agent defined in the
   repo's own `opencode.json`) while the session is in `plan`. Rule: when
   the session's overlay mode is more restrictive than the command's
   agent, galopin sends the overlay mode and ignores the command's agent.
   A `subtask` command with a named agent refuses with `forbidden` in that
   case — it would run unsupervised in the other agent. The IT asserts
   plan mode cannot be escaped this way.
2. **`shell: null` stays denied by default** (MCP prompts, every ACP
   command). ACP commands and MCP prompts are effectively off until
   opted in — the docs say so. The IT records whether opencode applies
   `` !` `` expansion to MCP prompt text; if not, MCP is reclassified
   `shell: false` later.
3. **Accepted residual:** a template edited between galopin's scan and
   opencode's own read is a tiny race; anyone who can write the repo
   mid-run already has code execution. Documented, not fixed.
4. The 2026-09-26 §2.5 items all stand: `commandShell` policy default
   `denied` (enroll flag to allow; `policy set` tightens only), first-run
   confirmation with the exact shell snippets + `templateHash` conflict
   on change, `@path` refs checked against `fileDeny`, the command's
   `model:` frontmatter gated by `allowFreeModels`, audit rows that never
   carry arguments or expanded text.

## 4. Batch map

| # | Batch | Ships | Depends | Days |
|---|---|---|---|---|
| A0 | Freeze-allowed fixes: mint `messageID` for `prompt_async` (2026-09-26 §3.6), the ACP busy guard (§1.5), the "paseo" tooltip | exact client-message mapping; the minting helper A reuses | — | 0.5 |
| B | Composer `/` menu: `SlashCommandState`, `SlashCommandAutocomplete`, `ChatInput` props, panel commands (§2.4) over existing routes, bindable pickers, Vitest + Playwright | a working menu on every paired machine, old galopins included; doubles as the no-capability fallback UI | — | 3.0 |
| A | galopin: `/doc`-probed capability, `backend.commands`, `session.command`, overlay marker, `commandShell` policy + gates + audit, PROTOCOL.md §6/§7, unit tests + live ITs (opencode + ACP) | a machine that lists and runs commands safely | A0 | 3.0 |
| C | Cerea backend commands: forwarder rows, `codeApi`, audit, command bubble + collapsed expansion, menu backend groups + shell icon, confirmation sheet, 403/409 copy, hermetic specs | native/project/skill/MCP commands end to end | A + B | 2.5 |
| D | `docs/code-panel.md` with the residual risk, live check | release notes | C | 0.5 |

One executor at a time (user rule, 2026-09-27). Order: **A0 → B → A → C →
D**, each in the `slash-cerea` worktree on `feat/slash-commands`, one
commit per coherent piece, merged only when the whole feature is reviewed.

## 5. Test checklist (2026-09-26 §2.6, with the additions)

Additions over the 2026-09-26 list:

- **Live IT:** the plan-mode escape test (§3.1); the command-agent
  precedence result; whether MCP prompts expand `` !` ``; the `/doc`
  capability probe on the installed opencode version.
- **Playwright:** the menu closes when the mode pill or model picker
  opens; `/model` with no argument opens the picker below the composer;
  the menu stays usable on a narrow viewport with the send/stop overlay;
  slash commands can't be sent while a turn is running (send is hidden
  until steering ships).

## 6. Open items the IT settles

1. Command-agent precedence (§3.1) — **settled 2026-09-28, and the design
   changed**: opencode 1.18.32 runs the command's own `agent:` frontmatter
   whenever one is set — the agent sent alongside is ignored, so an
   overlay override is impossible. The gate now refuses `forbidden` for
   any command whose agent differs from the session's overlay mode
   (subtask or plain); the plan-mode-escape IT subtest is the acceptance
   test (`commands_opencode_it_test.go`, "a plan session refuses a
   build-naming command"). The live mode listing orders `[build, plan]`,
   so no restrictiveness ordering exists to read.
2. Whether opencode applies shell expansion to MCP prompt text (§3.2) —
   **settled 2026-09-28: it does not.** With `commandShell` allowed, an
   MCP prompt's text reached the LLM with the bang construct as literal
   text (IT: "the MCP prompt with commandShell allowed reaches the
   mock"). The `shell: null` gate for `source: "mcp"` is conservative and
   stays. Environmental notes, recorded: SDK 2.0's stdio transport
   requires CRLF framing (bare \n silently discarded), and 1.18.32's
   embedded MCP client cannot fetch prompts from an SDK 2.0 server
   ("typedCallback is not a function") — the IT ships a hand-written
   protocol server for exactly this reason.
3. Whether `@file` in a template honours opencode's own `read`
   permission (`*.env: ask`) — **settled 2026-09-28: it silently doesn't
   expand it.** Under opencode's read permission, @ expansion neither
   surfaced a permission ask nor leaked the file's content (IT: "records
   whether @ expansion honours opencode's read permission") — opencode
   does not bypass the read permission to expand the reference, but it
   does not ask through it either; the `@.env` reference is simply never
   substituted. galopin's `fileDeny` gate stays as the machine-side
   backstop.
4. **Added 2026-09-28 (from the advisor review):** a repo command can
   spoof a builtin/machine name — origin is now content-proven against
   the state directory's own listing (machine on template-hash match,
   builtin on frontmatter match), and the live IT records that on
   1.18.32 a repo `review.md` does NOT displace the builtin
   (first-writer wins; the frontmatter-mismatch rule stands for versions
   where an override wins).
