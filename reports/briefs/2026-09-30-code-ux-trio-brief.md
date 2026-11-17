# /code UX trio brief: collapse+rail, icon pills, Tasks view

Three items in the advisor's order (3 → 2 → 1): a bug, a quick fix, a
feature. Worktree: /home/ubuntu/workspace/Cerea on branch feat/code-ux-trio
off main. The advisor's full spec is recorded in
/home/ubuntu/workspace/oc-orchestrator/STATE.md (2026-09-30 ~07:30 entry) —
read that entry FIRST; it is your spec of record with file:line references.
You implement; ambiguity → stop and report.

## Item 3 first (the bug): collapsible devices and workspaces + the rail

- `CodeNavTree.svelte:192` (`isDeviceExpanded`) and `:195`
  (`isWorkspaceExpanded`) force-expand the SELECTED device/workspace, so the
  existing chevrons (`:462`, `:628`) do nothing on those rows. Collapse
  state is already stored and persisted (`readTreeCollapse`, `:136`).
- Fix: honour the stored state for every row. On address CHANGE (a new
  selectedDeviceId / selectedWorkspaceId), remove that device/workspace
  from the collapsed set ONCE (navigation still reveals it); after that the
  person can collapse it. A collapsed row containing the selection gets
  the active-row tint.
- The rail (chat's ProjectsBranch idiom, `ProjectsBranch.svelte:360`:
  `ml-[1.375rem] flex flex-col gap-px border-l border-gray-200 pl-2.5
  dark:border-gray-700`): wrap each device's children (workspaces) and each
  workspace's children (agents, subagents when shown) in
  `ml-3 border-l border-gray-200 pl-1.5 dark:border-gray-700` containers
  (`ml-3` = the centre of the `size-6` chevron slot). REMOVE the ad-hoc
  `pl-6`/`ml-4`/`pl-8` offsets (`:607`, `:625`, `:739`) — the nested rails
  now do the indenting. Rails only under expanded PAIRED rows; never under
  pending or revoked rows. Defaults unchanged (expanded unless collapsed,
  persisted across reloads).
- Tests (a NEW CodeNavTree component test): the selected device collapses
  on click and re-expands on navigating to a different agent; the collapsed
  state survives a remount; a collapsed row containing the selection gets
  the tint; rail containers exist only under expanded rows.

## Item 2 (quick): icon-only header pills on mobile

- `AgentView.svelte:906–952` has three hand-rolled `<button>`s (icon +
  "Changes"/"Files"/"Terminal", always full). Replace with
  `TogglePill.svelte` + `compact`: under `sm` it renders a `size-8`
  icon-only button with the label `max-sm:sr-only`; `aria-pressed` from
  `sidePane.open && sidePane.view === <view>`; `title` keeps the
  veto-explanation tooltips; `disabled` where present. The breakpoint is
  `sm`, matching the composer's pills. Desktop keeps icon+text.
- Add TogglePill's FIRST test: under `sm` the label is sr-only but exposed
  to assistive tech, and aria-pressed follows the state.

## Item 1 (the feature): the Tasks side-pane view

- **Two mapping fixes in `machineTimeline.ts:311` (`todoToUpdate`) first:**
  `cancelled` maps to `skipped` (PlanStepStatus has it; PlanCard renders it
  struck), NOT `pending`; and the module-level `planVersion` counter
  (shared across users/sessions!) is keyed per session or replaced with
  `agent-plan-<sessionId>`. Spec: `machineTimeline.spec` gains the
  cancelled→skipped case.
- **The view:** add `"tasks"` to `SidePaneView` and `toggleTasks()` in
  `sidePane.svelte.ts`; render in AgentView's pane switch (~`:1053`); a
  header TogglePill "Tasks" whose label carries the count ("3/7") so
  progress is visible without opening (this pill joins item 2's compact
  pattern).
- **Data:** `latestPlan = $derived(the last isMessagePlanUpdate across the
  session's messages)` in AgentView — no new store, no wire change; the
  snapshot and the live stream both flow through todoToUpdate so they stay
  in step, and a reload's snapshot maps to the same update.
- **Rendering:** extract `PlanSteps.svelte` (status glyphs + step rows) out
  of `PlanCard.svelte` so the card and the pane share one list. New
  `CodeTasks.svelte`: header "Tasks 3/7" with a thin progress bar;
  in_progress highlighted (PlanCard's class) and scrolled into view;
  pending normal; completed dimmed and grouped as "Completed (N)",
  collapsed once the list exceeds 8; cancelled struck through; a priority
  badge only for `high`; empty state "No task list yet — the agent makes
  one with its todo tool."
- **Scope:** the VIEWED session only (same as Changes/Terminal). A
  subagent's list shows when that child is opened. No child fan-out in v1.
- **Auto-open:** only when the pane is CLOSED, on desktop (`sm` and up),
  ONCE per list (keyed by session + the first item's content). Never
  replaces another open view; never on mobile; if the person closes the
  pane it stays closed. "Active" = the list has an in_progress item or the
  session is busy with unfinished items.
- **Tests:** CodeTasks component test (counts, in-progress highlight,
  completed group collapsing past 8, empty state); an AgentView auto-open
  test (opens once, never replaces an open view, never on a narrow
  viewport).

## Rules

- Commit per item (3 commits minimum), each with its tests green: item 3's
  CodeNavTree test, item 2's TogglePill test + the three buttons' behavior,
  item 1's mapping spec + CodeTasks + auto-open.
- `npm run check` baseline 0 errors — 0 new. Prettier/eslint clean on
  touched files.
- BOX: NO sub-agents; foreground; heavy commands under `timeout -s KILL
  <secs> flock /tmp/heavy.lock`; free -m ≥1500 before heavy steps, WAIT
  rather than compete; never kill processes you did not start; client
  vitest needs TEST_MONGODB_URL=mongodb://127.0.0.1:8801 (component specs
  run locally in Chromium as the recent waves did).
- GIT: Paolo Viviani (configured); NO AI trailers; push feat/code-ux-trio;
  no merges — the OC merges after review.
- Report per item: design as built, files, commits, exact test commands +
  pass counts, deviations. Then STOP for review.
