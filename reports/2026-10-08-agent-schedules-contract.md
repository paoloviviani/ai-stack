# Agent-created schedules: the contract both sides build to (2026-10-08)

Goal: coding agents (opencode sessions run by galopin) can list, create, update,
pause and delete the owner's scheduled actions, through new galopin agent tools.
Schedules live in Cerea (`src/lib/server/schedules/`, executor
`src/lib/server/code/scheduleAgentExecutor.ts`), so this adds the first
machine→Cerea request.

## 1. Frames (agent/PROTOCOL.md §5)

M→C `{"type":"call","id":"<galopin-unique>","op":"schedule.<x>","sessionId":"<caller session>","rootSessionId":"<its root>","caller":Caller,"args":{…}}`
C→M `{"type":"callres","id":"<same>","ok":true,"result":{…}}` or
`{"type":"callres","id":"…","ok":false,"error":{"code":"invalid"|"forbidden"|"not_found"|"limit"|"unavailable"|"unsupported","message":"<human sentence the model can read>"}}`

`Caller = {"workspaceId":"…","permissionMode":"deny"|"ask"|"allow","coordination":["session_list",…]}`
— the calling session's facts as galopin knows them (root's selector: mode word and
coordination grant; workspace = the session's workspace id as `workspace.list` reports it).

Galopin times a call out after 20 s (`unavailable`). A call is only sent while the link is up
and paired; otherwise the tool answers that Cerea is unreachable. Cerea answers an unknown op
`unsupported`. A Cerea that predates this ignores the unknown frame type, so galopin must
also time out cleanly.

Capability: Cerea's `welcome` frame gains `"features":{"machineCalls":["schedule"]}`.
Galopin installs the schedule tools whenever it installs agent tools, and a tool called
against a Cerea without the feature answers "this Cerea does not support schedules from
agents; update it". Galopin's hello backend capabilities gain `"scheduleTools":true`.

## 2. Ops (Cerea acts as the device's owner; every rule of the store applies: 15-min floor, per-user cap, timezone, kill switch `CHAT_SCHEDULES_ENABLED`)

- `schedule.context {}` → `{"scheduledRunOf": "<scheduleId>"|null, "enabled": bool}` — whether
  the caller's session (or its root) is a session a schedule's run created or targeted (look
  up the run records by device + sessionId/rootSessionId).
- `schedule.list {}` → `{"schedules":[{id,name,recurrenceText,timezone,paused,status,
  nextRunAt,lastRunAt,workspace,session:"new"|"<sessionId>",permissionMode,coordination,
  createdBy:{kind:"person"}|{kind:"agent",sessionId,title},self:bool}]}` — only this
  device's schedules of the owner. `self` = the caller's session is a run of it. Prompts are
  included (the owner's own data, same machine).
- `schedule.create {name, prompt, recurrence, timezone?, workspaceId?, session:"new"|"this",
  permissionMode, coordination?:[keys]}` → `{schedule: <list item>}`.
  `recurrence` uses the store's `recurrenceSchema` as is. Defaults: timezone = the owner's
  saved timezone if one exists else UTC; workspaceId = caller.workspaceId; `session:"this"`
  = the caller's ROOT session as the existing target.
- `schedule.update {id, …any create field except session…, paused?: bool}` → `{schedule}`.
- `schedule.delete {id}` → `{}`.

Cerea-side rules (refuse with `forbidden`/`limit`/`invalid` and a clear sentence):
- target device is ALWAYS the calling device; workspaceId must exist on it (`workspace.list`).
- permissionMode no looser than caller.permissionMode (deny < ask < allow).
- coordination ⊆ caller.coordination.
- at most 5 active (not paused/disabled) agent-created schedules per device; at most 10
  create/update/delete calls per device per hour.
- update/delete only of this device's schedules.
- created schedules record `createdBy: {kind:"agent", deviceId, sessionId, title}`; the
  Schedules list/editor shows "Created by an agent in ‹session title›" linking the session.
- audit like other schedule changes, with the creator.

## 3. Galopin-side permission (decided by the user)

New rule-gated permission key `schedule` for all four mutating tools, and a ceiling key
`schedule` (default uncapped). `schedule_list` asks nothing.
- `schedule_create`: follows the session's Deny/Ask/Allow word like an ordinary tool —
  **the blanket Allow DOES cover it** (user's choice), Ask gives a card, Deny refuses —
  EXCEPT when the caller is a scheduled run (`schedule.context.scheduledRunOf != null`):
  then it always asks, even under Allow or a machine allow rule (runaway guard).
- `schedule_update` / `schedule_delete` on a schedule with `self:true` that only pauses it
  (`{paused:true}`) or deletes it: no card ("stop when done").
- any other update/delete: always asks (card), even under Allow.
- The ceiling capping `schedule` at ask/deny wins over all of the above.
- Card shows the full schedule (name, timetable text, timezone, workspace, session,
  mode, coordination, full prompt) or for update the changed fields, for delete the name.
- Audit row `agent_tool {tool, from, decision, reason, schedule: id|name}`, no prompt text.
- The `delegation` skill gains a short "Scheduling work" section: when to schedule, list
  first and update instead of duplicating, prefer `session:"this"` for follow-ups, pause or
  delete your own schedule when the job is done, schedules outlive you so name them clearly.
