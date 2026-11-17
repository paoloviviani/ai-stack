# Brief for the OC orchestrator: the permission selector (Deny / Ask / Allow) replaces auto-accept

To be filed as `ai-stack/reports/briefs/2026-10-03-permission-selector-brief.md`. Then notify OC (a4ed059a) and record it in `oc-orchestrator/STATE.md`.

## Context
- The permission pass-through is live (Cerea `sha-7f801b7`).
- It still carries a client-side **auto-accept responder**: galopin clicks "once" on every ask for sessions whose toggle is on. The user judged this a brittle over-complication.
  - "Auto" should mean a real per-call judgment. That comes later, possibly with a different harness.
  - Until then the user wants a plain **blanket selector**.

**User decisions (2026-10-03), final:**
1. The composer gets a selector **Deny / Ask / Allow**. It covers the whole session until changed. New sessions start on **Ask**.
2. **"Always allow"** on a card adds a **per-session exception** for that specific command or pattern, on top of the blanket.
3. **Reading stays allowed** under all three settings.
4. **Under Allow, two asks survive:** writing outside the project folder (`external_directory`) and the stuck-agent brake (`doom_loop`).
5. The auto-accept responder, its toggle, the `responders` policy and `--allow-auto-accept` all **go away**. The machine's ceiling (set at enroll) stays the only thing Cerea cannot raise.

**This is user-ordered work.** The feature freeze is waived for it.

## Process
- **Two "Claude handoff" workers**, the same profile as the pass-through (claude-sonnet-5-5, auto, thinking high). Each gets an isolated worktree from `origin/main` (`7f801b79`):
  - **Worker G:** galopin, branch `feat/permission-selector-agent`.
  - **Worker P:** panel, branch `feat/permission-selector-panel`.
- **Box rules:** at most 2 heavy jobs at once; `flock /tmp/heavy.lock` for builds and live ITs; never wrap `dev/build.sh` in another flock.
- **The contract below is frozen.** Either worker *flags* a change instead of inventing one.
- **Reviewable commits:** stop and report when done.
- **After both finish:** an Opus advisor verification review, then the joint merge (`--no-ff`, real messages). **No deploy without the user's order.**
- **Commit trailers:** none from Claude in Cerea (`no-public-no-claude-trailer` memory).

## Exact semantics (G implements, P displays)

**The rule list galopin composes for a top-level session.** It is appended after the agent's own ruleset; opencode takes the last matching rule. Sources are shown in brackets.
1. The machine's own rules from `policy.json` (`machine`). Unchanged.
2. The **mode block** (`cerea`):
   - **Allow:** `{* : allow}`.
   - **Ask:** `{* : ask}`.
   - **Deny:** `{* : deny}`.
   - Then, in every mode, the agent's own rules for the **untouched set** are re-appended verbatim, so they keep their normal behaviour: `read` (including its `*.env` asks), `glob`, `grep`, `list`, `lsp`, `question`, `todowrite`, `todoread`, `plan_enter`, `plan_exit`, `skill`, `external_directory` (including opencode's own safe-dir allows) and `doom_loop`.
   - Everything else follows the blanket: `edit` (write and patch), `bash`, `webfetch`, `websearch`, `codesearch`, `task`, every MCP tool and every custom tool.
   - **G must check the untouched set against 1.18.32's real permission names** (see canary S12).
3. **Exceptions** (`cerea`): one `allow` rule per pattern. Placement:
   - **Ask:** after the mode block, so exceptions win.
   - **Allow:** after the mode block (redundant but harmless).
   - **Deny:** *before* the mode block, so Deny wins.
   - Exceptions are kept even while blocked; switching back to Ask restores them.
4. **The ceiling's tail** (`ceiling`), last. Unchanged: the ceiling caps everything above.

**Default:** a session with no mode set is **Ask**. That covers existing sessions on upgrade, new sessions, spawned sessions, and machines whose `policy.json` predates permissions.
- So `composeFor` must **always** compose; today it returns nil when there are no layers. This makes legacy machines ask before writing **without a re-enroll**, which fixes the silent hello-world write. Call it out in the release notes.

**"Always allow" on a card:**
- galopin answers opencode with **"once"**. It never forwards "always" to opencode again, so opencode's invisible workspace-wide approvals stop being created.
- It then stores an exception `{id: "ex_…", permission, patterns: request.always (fall back to request.patterns), grantedAt}` on the **root** session, persisted in the overlay so it survives restarts.
- **If the ceiling caps that key below allow:** store nothing, answer once, and audit `capped: true` (as `capDecision` does today).
- **`gp_` asks:** never "always" (unchanged).

**Subagents:**
- They have no selector of their own. Their rules are the **root session's** mode block plus the root's exceptions, capped. Never the machine's own allows (as today).
- They are applied when the child appears (`ApplyChildRules`), and re-applied to every tracked descendant whenever the root's mode or exceptions change.
- The agent-level floor still covers the moment before the rules land.

**Spawned sessions** (`session_spawn`) are top-level and start on **Ask**, whatever the caller's mode.

## Frozen contract
- **New op `session.setPermissionMode {sessionId, mode: "deny"|"ask"|"allow"}` → `{}`.**
  - An unknown session answers `not_found`.
  - A bad mode answers `invalid`.
  - A subagent's id answers `invalid` ("a subagent follows its root").
  - Audited as `permission.mode {session, mode}`.
- **Session objects** (list, get, snapshot) gain `permissionMode`. A child reports its root's.
- **`permission.rules`:**
  - The shape is unchanged, plus a top-level `mode`.
  - The mode block and exceptions carry source `cerea`.
  - `savedApprovals` now lists the root's **exceptions** as `{id, sessionId, permission, patterns, removable: true, grantedAt}`.
- **`permission.saved.remove {sessionId, id}` → `{}`.** It now really removes an exception (re-applying the rules to the root and its descendants). An unknown id answers `not_found`. Audited with no patterns.
- **`permission.reply`:** the wire is unchanged. The "always" handling is the one described above.
- **Retired:**
  - `session.setAutoAccept` and `session.setRules` answer `unsupported` for one release, then are deleted.
  - Hello `policy.permission.responders` is gone. `policy.autoAccept` is sent as the constant `"denied"` for one release.
- **Forwarder:**
  - Add `POST v1/agents/:id/permission-mode {mode}` → `session.setPermissionMode`. It is already covered by the stale-session guard on `/api/v2/code/`.
  - Audit `permission.mode` there too.
  - Remove `POST v1/agents/:id/permission-rules` and the `auto_accept` feature path.

## Worker G (galopin, `agent/`): deletions and changes
- **Delete the responder:**
  - in `internal/sessions/sessions.go`: the `autoAccept` field, `autoAcceptEffectiveLocked`, the responder branch in the `EventPermissionAsked` case, `autoRepliedIDs`, `SetAutoAccept`, `AutoAcceptInEffect`, `OnResponder`;
  - the audit hook in `agent/permissions.go` `installPermissions`.
- **Policy and enroll:**
  - Remove `Permission.Responders` and the legacy `autoAccept` carryover (`internal/policy/policy.go`), plus `RespondersAllowed`.
  - `enroll --allow-auto-accept` prints a no-op warning for one release.
  - Fix the `policy show` and enroll summaries.
- **Remove `opSessionSetRules`** and the Panel rules/touched machinery in `permrules` (`Panel.With`, the touched block in `ComposeParts`). Replace it with a `Mode` plus `Exceptions` session state and its composition, per the semantics above.
- **Replace `savedLedger`** (opencode's own approvals) with exceptions. Keep `capDecision` for the capped case. Keep restart-on-tighten.
- **Implement:**
  - `opSessionSetPermissionMode`;
  - `permissionMode` on sessions;
  - exceptions in `permission.rules` and `permission.saved.remove`;
  - root-to-descendant re-application.
- **`agent/PROTOCOL.md`:** update §5–§7 (remove auto-accept, the responder and `setRules`; add the selector and exceptions). Also the README and the enroll help text.
- **Live specs** against real opencode 1.18.32, using `permission_rig_it_test.go`:
  - **S1 Allow:** an edit runs with no ask; bash still asks under the default `bash` ceiling of ask; a write outside the workspace asks; reading `.env` asks.
  - **S2 Ask:** an edit asks; read and grep don't; the question tool works without a permission ask.
  - **S3 Deny:** edit, bash and task are refused with no card; read works.
  - **S4 Always under Ask** (rig ceiling `bash=allow`): after "always" on `git status`, the next `git status` runs; `git log` asks; **a second session in the same workspace still asks for `git status`**, proving nothing was forwarded to opencode as "always".
  - **S5:** with an exception present, switching to Deny blocks it, and switching back to Ask restores it.
  - **S6:** removing an exception makes the command ask again.
  - **S7:** "always" on a capped key stores nothing, and the next call asks.
  - **S8 Subagents:**
    - root on Allow, a `general` child's edit runs;
    - root on Deny, the child's edit is refused;
    - a root change is re-applied to a live child;
    - the root's exception reaches the child.
  - **S9 Legacy machine** (no permission block anywhere): a new session's write asks. This is the hello-world regression test.
  - **S10:** a spawned child starts on Ask regardless of its caller.
  - **S11:** `setAutoAccept` and `setRules` answer unsupported; `permission.rules` lists exceptions as removable.
  - **S12 canary:** list 1.18.32's permission names and assert each one is classified as either untouched or following the blanket. The test fails on any unknown name.
- **Keep:** P1–P7, the four upgrade canaries and the floor canary green. Delete the responder tests (`permission_responder_it_test.go`, the responder cases in `subagent_test.go` and `sessions_test.go`).

## Worker P (panel, `src/` + `tests/` + docs)
- **Delete:**
  - the Auto-accept toggle in `AgentComposer.svelte` and the `auto_accept` feature handling;
  - the forwarder's `autoAcceptCatalog`, `autoAcceptLive`, `respondersAllowed`, the veto note and the feature-POST path;
  - the "Allow auto-accept" checkbox in `PairDeviceDialog.svelte` and `codeEnrollCommand.ts`, which were restored in `7f801b79`;
  - the free-form rules editor in `PermissionsLine.svelte` and `setSessionRules` in `codeApi.ts`;
  - `AgentComposerAutoAccept.svelte.test.ts`.
- **Add:**
  - a **three-segment selector** (Deny · Ask · Allow) in the composer pill row. It shows the machine's word (`permissionMode` from the snapshot), never an optimistic guess.
    - Under Allow, it names what the ceiling still caps, e.g. "Allow · bash asks (machine limit)", from `permission.rules.ceiling`.
    - It is disabled with an explanation on a subagent view ("follows the main session").
  - `codeApi.setPermissionMode` and the forwarder route, plus a code audit row.
  - **The Permissions line, read-only:** the rule list plus an **Exceptions** list with Remove.
  - **The card's Always button:** labelled "Always allow (this session)", and hidden when the ask's key is capped by the ceiling.
- **Stale sessions:** the selector and Remove are hidden while stale (`codeReauth`); the server guard refuses them anyway.
- **Docs:** rewrite the Permissions section of `docs/agent-machines.md` (the three settings, the untouched set, exceptions, subagents follow the root, the ceiling still caps, the default is Ask). Update the rows in `docs/code-panel.md`. Remove every mention of auto-accept or responders.
- **Specs:**
  - client specs (Playwright container): the selector reflects the machine, sends the op, and shows the ceiling note; exceptions are removed by id; Always is hidden on capped keys; no auto-accept anywhere;
  - forwarder spec: the route maps to the op and is refused while stale;
  - update `tests/code-machine-parity.spec.ts`: auto-accept cases become selector cases, plus an "Always allow" exception case;
  - update `tests/machineHarness.ts` (no `responders`).

## Release note (OC drafts it at merge)
- Sessions now default to **Ask**: machines ask before editing or running commands, **including machines enrolled earlier, with no re-enroll needed**.
- Auto-accept is replaced by the Deny / Ask / Allow selector.
- "Always allow" now applies to this session only, and can be removed.
- Re-enrolling is still needed only to change a machine's ceiling.

## Addendum (user, 2026-10-03): the enroll dialog exposes every machine-policy option
The Pair-a-machine dialog (`PairDeviceDialog.svelte`, `codeEnrollCommand.ts`) must offer **every enroll flag that sets machine policy**, so nobody has to hand-edit the printed command. Today it offers only Install opencode, Trust repos, Allow auto-accept and Allow terminal.

**Rules for the dialog**
- Every control's default matches enroll's own default, and a default emits no flag.
- The command preview updates live, with correct shell quoting for paths and globs.
- One short honest sentence per control, and a warning tone on the risky ones (terminal, command shell, trusting repo configs, any ceiling set to allow on bash).
- The dialog says once, plainly: "These are fixed when the machine enrolls. Loosening one later means enrolling again; `galopin policy set` on the machine can only tighten."
- Common options sit at the top; the rest go under an **Advanced** disclosure.

**Controls (flag → control)**
- **Common:**
  - `--allow-terminal` and `--max-terminals N`: checkbox, plus a number shown when the box is checked.
  - **The ceiling, `--permission-max KEY=ACTION`:** a small table, "the most this machine will ever allow". One row each for `edit`, `bash`, `webfetch`, `task`, `session_spawn` and `session_send`, each with an Allow / Ask / Deny select. Defaults are `bash=ask` and `session_spawn=ask`; every other row is Allow.
    - The flag REPLACES the default set when given. So if any row differs from the default, the dialog must emit the **full** set (including `bash=ask` and `session_spawn=ask` unless changed). If nothing changed, it emits nothing.
  - `--allow-project-config`: the existing "Trust the repos" box.
  - Install opencode: existing.
- **Advanced:**
  - `--allow-command-shell`, `--allow-background-subagents`, `--no-agent-tools`, `--allow-free-models`, `--allow-opencode-provider`;
  - `--workspace-root PATH`: a repeatable list;
  - `--no-files`, `--file-deny GLOB` (repeatable), `--no-default-file-deny`;
  - `--permission-rule KEY=ACTION`: a repeatable key/action list labelled "this machine's own rules (below Cerea's selector)".
- **Removed:** `--allow-auto-accept` (as above).
- **Deliberately not exposed** (connection plumbing): `--cerea`, `--client-id`, `--creds`, `--device`, `--discover`, `--gateway`, `--group`, `--issuer`, `--loopback`, `--output`, `--shim-port`, `--yes`.

**Keeping the dialog and enroll in sync (G and P share this)**
- G adds `agent/packaging/enroll-flags.json`: every enroll flag with `{flag, kind: bool|int|string|list|keyAction, default, exposed: true|false}`.
- G adds a Go test asserting that the flag set `enroll` registers equals that file, so adding a flag without classifying it fails the build.
- P imports the JSON (or a generated TS copy, checked by a spec) and adds a spec asserting that every `exposed: true` flag has a dialog control and that the defaults emit nothing.

**Specs (P)**
- **Each control** emits exactly its flag. Defaults emit an empty policy section.
- **The ceiling table:**
  - one changed row emits the full set;
  - an unchanged table emits nothing.
- **Quoting:** a path with spaces, and a glob with `*`.
- **Advanced:** collapsed by default, but its non-default values still show in the preview.
- **The parity spec:** enrolling through the dialog-built command yields the `policy.json` the dialog promised (`tests/code-enrollment.spec.ts` / the harness).
- Also update the `docs/agent-machines.md` dialog table.

**Effort:** about 1 extra day for P (the dialog), and about 0.25 day for G (the JSON and its test).

## Effort
About 3 days (G about 1.5–2, P about 1), plus review. OC records the commissioning, each worker report and the verdicts in STATE.md as usual.
