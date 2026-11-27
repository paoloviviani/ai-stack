# Parked designs: Auto "Secret rules" (C175) and the `session_archive` agent tool (C176)

Status: **parked** by the owner on 2026-11-27 (no tokens to build now). This page is the starting
point when either is picked up. Nothing here is built; both are proposals the owner agreed in
principle, with the open points listed at the end of each section.

Context: Cerea v0.67.0 (2026-11-27) shipped the new **Allow**: a session on Allow never gets a
permission card. Only galopin's own state and configuration, and classes the computer's owner
refused with `--deny`, are refused; a call to another of the user's computers (ADR 0121 relay)
keeps its card. Ask and Plan are unchanged. Auto is unchanged from v0.66.0 apart from the `.env`
rule below, and is what C175 redesigns.

---

## C175: Auto, a fourth option "Secret rules" on the outside-access row

### What the owner decided (2026-11-26/27)

- Workspace → Agents → **"On Auto, per kind of action"** has one row per kind of action (edits,
  commands, web, outside access, secrets, agents, tools, loops), each with **Runs / Reviewer /
  You**.
- Only the **outside access** row gets a fourth option, **Secret rules**, an alternative to
  Reviewer. That row becomes **You · Reviewer · Secret rules · Runs**. The other rows stay as they
  are.
- Auto's policies live in **Workspace → Agents only** (not in project files).
- Threat model: a **careless agent, not a hostile one** (ADR 0107). Containment of what an agent
  can reach is the job of the future sandbox, not of name-based guards. **Reading is not the harm;
  a secret leaving the computer is.**
- "Not covered" by the rules means "not a dangerous match", and it **runs with no card**.

### What "Secret rules" means (to confirm with the owner before building)

The rule set worked out on 2026-11-26 while building PR #388 (most of it is already in galopin's
decide package, used today by Ask's labels and by Auto):

1. **Reading is free.** Reading or editing any file runs, `.env` files included, wherever they are.
2. **A card only when a secret would leave the computer**, in any of these forms:
   - an outbound command (galopin's `outbound()`: curl, wget, scp, rsync, ssh, nc, git push,
     gh, cloud CLIs, rclone, gsutil, s3cmd, mail tools, croc, deploy CLIs such as fly, vercel,
     netlify, heroku, …) that **names a `.env` or credential file** anywhere in the line: as a
     word, an `@file` or `<file` argument (including curl's `name=@file;type=…`,
     `--data-urlencode name@file`, httpie's `field@file`), a redirect source, the left side of a
     pipe into the outbound command, or `--env-file`;
   - sending a **folder that holds a non-placeholder `.env`** (rsync -a DIR, scp -r, tar|ssh,
     aws s3 sync, rclone/gsutil sync; the folder and one level below are searched);
   - an outbound call that carries a **secret's value written literally** in its text (C73, the
     secret-value guard).
3. **Computed words.** A word galopin cannot resolve (a variable, `$(…)`) counts only where it
   could be a file being sent: after `@` or `<`, as a redirect source, as a file operand of a
   file-sending tool, as the value of a file option (curl -T, wget --post-file, gh --body-file,
   mail -a), or on the left of a pipe into an outbound command when the left command reads files.
   `git push origin $BRANCH`, `gh pr view $n` and `curl https://x/$id` run. This narrowing is
   written and tested on the local branch **`wip/env-blind-narrowing`** (Cerea repo, not pushed;
   in worktree `Cerea-wt-envallow` as of 2026-11-27).
4. **Credential stores** (`~/.ssh`, `~/.aws`, gcloud, kube, `/proc/*/environ`) are **free to read** like any file (owner, 2026-11-27); sending one off the computer is a card (rule 2).
5. Everything else on outside access **runs**.

### Known limits (to state in the docs, as #388 already does)

- A program that reads the file and sends it itself is not seen: a script, interpreter code
  (`python -c`, `node -e`), `npm publish` or `docker build` of a folder holding a `.env`, `git push`
  of a repository that committed one.
- `find -exec` / `xargs` with `{}` on an outbound line is treated as a computed word (a card).
- A computed file read into an argument (`curl -d "$(cat $F)"`) is not caught (Low, per the last
  review).
- The check runs before the command; a symlink swapped between the decision and the run is not
  seen.
- Pystino's redaction is a third layer for model traffic only, off until an administrator sets a
  policy, and only for the patterns it lists.

### Where the code is

- `agent/internal/decide/` (decide.go, bashwords.go, secretvalue.go, `outbound()`,
  `outboundFileLeak`): the rules, used today by Ask (labels) and Auto.
- The Auto row settings: Cerea's Workspace → Agents screen and galopin's per-session Auto map
  (`AutoHost`, `AutoClasses`). The new option needs a value in that map (e.g. `rules`) for the
  outside-access class, read by `modeAnswer`.
- Review history: Opus reviews of PR #388 on 2026-11-26/27 (four rounds); the High criteria must
  be derived from the threat model above. Lesson recorded: a review brief that counted reading an
  outside `.env` as High contradicted the model and cost two rounds.

### Decided (owner, 2026-11-27)

1. Credential stores under Secret rules: **free to read**; a card only when sent.
2. Secret rules applies its outgoing checks **only on the outside-access row** (only when that row is set to Secret rules).
3. Open: the value the outside-access row starts with before a user ever changes it (today Reviewer); to confirm.

---

## C176: a `session_archive` agent tool

### Why

An orchestrating session can start sessions (`session_spawn`, `session_committee`) and task
subagents, but cannot tidy up after them. A long orchestration leaves a trail of finished workers
and reviews (on 2026-11-26/27: 4 workers, 12 review subagents) that the owner then archives by
hand in the Agents panel.

### What exists

- The machine protocol already has `session.archive` / `session.delete` (`agent/PROTOCOL.md`, the
  session ops table), called by Cerea (`src/lib/server/code/machines.ts`) from the Agents panel's
  ⋯ menu.
- **Both ops do the same thing today:** `agent/dispatch.go` routes `session.archive` and
  `session.delete` to `opSessionDelete`, which calls the backend's `DeleteSession`. So "archive" is
  not reversible yet; check before building whether opencode 2.4 offers a real archive.
- Agent tools today: `session_list`, `session_read`, `session_send`, `session_spawn`,
  `session_committee`, `session_profiles` (agent/agenttools*.go). None removes a session.

### Proposal

- A new agent tool **`session_archive {target}`**.
- **Scope:** only sessions **this session spawned** (its delegates, via `spawnedBy`, and its own
  task subagents), the same rule that makes `session_send` to one's own delegates card-free. Never
  another root's session, never the session itself, never a session on another computer.
- **Permissions:** an agent-tools ask like the others: Allow runs it, Ask shows a card, Plan
  refuses. Under Auto it falls in the "agents (coordination)" row.
- **Refused while busy:** a session that is still running (busy, or with a pending card) is
  refused with a plain message; the agent stops it first (`session_send` asking it to finish) or
  leaves it.
- **Archive, not delete,** if the backend can archive (reversible, hidden from lists). If it
  cannot, the tool is named `session_delete`, and its description says the session and its
  transcript are gone for good; the owner decides which before building.
- **Report-back bookkeeping:** archiving a delegate drops it from the report-back queue
  (`agenttools_report.go` `prune` already forgets deleted or archived delegates).
- **Audit:** one `codeAudit` row per archive, with the session id and the asking session.
- **Docs:** agent/PROTOCOL.md (agent tools), docs/code-panel.md, the delegation skill in
  `agent/internal/backend/opencode/skill.go` (it describes the agent tools: add "archive your
  finished delegates when you are done").

### Tests to write

- Archive own delegate: runs on Allow, card on Ask, refused on Plan.
- Another root's session, the session itself, an unknown id, a session on another computer:
  refused.
- A busy delegate: refused.
- The report-back queue forgets the archived delegate.

### Open points for the owner

1. Archive (reversible) or delete (final), given that today both ops delete?
2. Should an orchestrator also be able to archive its own task subagents' sessions in bulk
   (`session_archive {all_finished: true}`)?

---

## Related backlog rows

- **C174** (agreed, after v0.67.0): galopin stops sending "X is waiting for approval" notices to
  the parent session; the card reaches the owner anyway, and the parent reads the child with
  `session_read` when it needs to.
- **Delegate profiles** (owner action): this machine has none, so `session_spawn` without a
  profile runs on the orchestrator's own model (Opus). Define `sonnet` (default) and `opus`.
