# Safe external directories — worker report (2026-10-09)

Branch `feat/safe-external-dirs`, worktree `../Cerea-safedirs`, commit `9e75bc9e`
"Safe external directories never ask (galopin + Permissions dialog)".
Owner-approved feature, built as specified (design parts 1–5).

## Protocol before / after

- `permission.rules` result gains one OPTIONAL field: `safeDirs: [dir, …]`
  (display form, home-relative entries shortened to `~`). Older galopins
  omit it; Cerea shows no line. No hello change was needed (the dialog
  already loads `permission.rules` itself), so `machineProtocol.ts`'s hello
  zod schema is untouched.
- `policy.json permission` gains `safeDirs`: absent = default list,
  `[]` = none, `[...]` = exactly those (tri-state via `*[]string`, so an
  empty list survives a save instead of collapsing to the default).
- Composition order (PROTOCOL §6): (1) machine rules, (2) mode block,
  coordination grant, machine tool rules, (3) exceptions, (4) safe dirs
  (`external_directory <dir>/* : allow`), (5) ceiling tail, last. The
  agent-level floor (§6 "(5)") gives general/explore the same allows only
  where the ceiling leaves `external_directory` alone.

## What changed and why

galopin: `Layers.SafeDirs` + `SafeDirRules` (permrules); floor allows for
general/explore (floor.go); `permission.safeDirs`, `DefaultSafeDirs`
(/tmp, $TMPDIR, cache, ~/go/pkg/mod, ~/.npm, ~/.local/share/pnpm —
existing only, never $HOME/~/.config/~/.ssh/~/.local/bin, even when
$TMPDIR lands there, as it does on this box), `Live` tighten-by-removal
(policy.go); `enroll --safe-dir/--no-safe-dirs`, `policy set
--no-safe-dir`, effective dirs in `permissionPolicySummary` (enroll
summary + `policy show` — there is no separate `galopin permission`
command); `safeDirs` in `permission.rules`; safe rules attributed
`machine` in RuleLayers. Cerea: `PermissionRulesResult.safeDirs` +
lenient parse, one line in the external_directory row
("Allowed: /tmp, ~/.cache, …; elsewhere asks/blocked"; hidden when the
ceiling holds the row). e2e harness: optional `safeDirs` /
`safeDirsUnderHome` policy inputs. Docs: PROTOCOL §4+§6, README,
agent-machines.md, kit/CHANGELOG Unreleased (says GALOPIN UPDATE NEEDED).

Live finding (probed, kept in the IT): for an outside path opencode asks
`external_directory` INSTEAD of `edit` when no rule matches; with a rule
that allows, the write falls through to the tool's own `edit` gate. So
under Ask a /tmp write still shows the session's own edit card (correct),
under Allow nothing, reads under Ask nothing. The shipped IT asserts
exactly this.

## Tests (fail-without-fix verified by stash for each)

- permrules unit (new `safedirs_test.go`, 7 tests): word × dirs × ceiling
  (Ask gets the allow; ceiling ask/deny still asks/refuses; Allow adds no
  duplicate; ChildRules carries them; floor shape + cap case). `go test
  ./internal/permrules/` ok.
- policy unit (4 new tests): absent/empty/custom, local-tighten-only
  (adds ignored, removals tighten, absent field leaves them),
  default-filter + conservative + TMPDIR-under-.config drop, tilde
  display, save round-trip of `[]`. `go test ./internal/policy/` ok.
- Real-opencode IT `TestSelectorS13SafeDirs` (2 subtests): fresh Ask reads
  /tmp with no card, /tmp writes raise only the edit card and never an
  external_directory ask, /etc/hostname still asks, Allow writes with no
  card, ceiling `external_directory=ask` still asks. Passes; fails without
  the fix (external_directory ask on the /tmp read).
- Cerea: PermissionsDialog spec 33/33 (4 new safe-dir tests; new one fails
  without the fix), machineProtocol.spec 10/10, permissionRules.spec 39/39,
  enrollFlags+codeEnrollPolicy 44/44, PairDeviceDialog 37/37. `npm run
  check` 0 errors, `npm run lint` clean, `mkdocs build --strict` clean.
- CLI smoke: `policy show` lists dirs; `policy set --no-safe-dir`
  removes/refuses-unknown; `enroll --safe-dir rel` and the
  `--safe-dir/--no-safe-dirs` conflict fail before sign-in.
- Screenshots (real app + real galopin binary, throwaway e2e spec since
  deleted): `ai-stack/reports/screenshots/2026-10-09-safe-dirs/` —
  dialog-desktop-light/dark.png, dialog-phone-light/dark.png. All four
  inspected: line reads "Allowed: /tmp, ~/.cache, ~/go/pkg/mod; elsewhere
  asks", wraps cleanly at 390, dark theme correct.

Not run: the six pre-existing failing code-* e2e specs (listed in
MAINTAINING §7; no existing e2e spec touches /tmp or stubs
external_directory rows, and the two stubbing specs return fixed payloads
without safeDirs, so nothing I changed can move them). Full client/server
suites: not run (only touched specs + gates, per box rules).

## Open / notes

- `kit/CHANGELOG.md` on main carried committed conflict markers
  (`=======`, `>>>>>>> feat/transcript-loading`, duplicated v0.9.4
  bullets) from the transcript-loading merge; removed the markers and the
  duplicates while adding the Unreleased entry (flag it to the transcript
  worker if they own that file's history).
- `session_send`/`session_list` are not in this worker's toolset, so this
  file + the session transcript is the report channel, not a message to
  the orchestrator session.
- Never touched: main checkout, galopin/opencode processes,
  ~/.config/galopin, opencode DB, the live stack, or the other worker's
  files (`internal/backend/opencode/http.go`, `dispatch.go`,
  machineTimeline/stream).
