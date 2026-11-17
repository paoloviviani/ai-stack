# ADR 0107: Permission classes on the machine, who answers in Cerea, and Auto with a decision-model reviewer

- Status: accepted (owner, 2026-11-04 evening)
- Supersedes: the ladder and posture parts of ADR 0105 (the `auto` session word, `ceilingForced`, the
  skip flag, "a ceiling of ask means a human decides", "auto never more permissive than skip"). Keeps
  from 0105: the decision-model reviewer (ADR 0100), allow-or-escalate (no deny), fail closed to the user,
  fencing of machine-originated fields, billing by the deployment, the audit, the card wording.
- Inputs: owner's notes and two advisor rounds, `reports/2026-11-04-permission-model-notes.md`;
  reviewer trials, an internal decision-reviewer trial report (not published).

## The model in one paragraph

Three layers, each a cap owned by one party; the most cautious wins. **The machine** (galopin, set at
enrollment on the machine, never over the link) says per class whether an action is **never** allowed,
must be **asked**, or may **run**. **The deployment** (Cerea admin) says per class who may answer an ask
in Auto: **you** (the user) or **the reviewer** (a decision model). **The session** (composer) says what
the user wants now: **Plan · Ask · Auto**. galopin cannot tell who answered an ask (every answer comes
over the link from Cerea), so who answers is Cerea's concern; what may happen at all is the machine's.

## 1. The machine: classes and limits (galopin)

Classes (from galopin's existing `Classify`): `edit` (in-project edits), `command` (bash, incl. sudo),
`web` (webfetch/websearch/codesearch), `outside` (any read or write outside the workspace and safe dirs),
`secrets` (`.env` and the credential paths of the Protected list), `agents` (task, session_list/read/send/
spawn, schedule — delegation is one class), `tools` (MCP and unknown tools), `loop` (opencode's
`doom_loop`). In-project reads have no row (always run). galopin's own state/config and the opencode
config it owns are **never**, fixed, not a class.

Limit values: `never` | `ask` | `run` (wire: `deny` | `ask` | `allow`). `run` means **uncapped: the session
word decides** (an Ask session still gets cards); `ask` means **a card is always raised** ("judged before it
happens", by whoever Cerea routes it to); `never` means refused.

| Class | Default limit | Allowed values |
|---|---|---|
| edit | run | never, ask, run |
| web | run | never, ask, run |
| agents | run | never, ask, run (run = free when the target session's word is the same or more cautious than the sender's; else the session's word applies) |
| tools | run | never, ask, run |
| command | ask | never, ask, run |
| outside | ask | never, ask, run |
| secrets | ask | never, ask (**run refused**) |
| loop | ask | ask, **stop** (stop: end the turn and notify; never `run`) |

These defaults reproduce today's behaviour exactly for anyone not on Auto.

**Enrollment:** `galopin enroll <cerea-url>`; overrides `--limit class=never|ask|run` (repeatable).
**Re-enrolling keeps every existing setting except the options passed** (fixes Cerea #25). `galopin reset`
returns the machine's policy to the defaults. Raising a limit stays at the machine (re-enroll); `galopin
policy set` still only tightens. `--permission-max` / `--permission-rule` stay one release as aliases
(mapped onto classes, printed by `policy show`). The **file editor is on by default** (was
`--allow-file-write`; `--no-file-write` turns it off). **Dropped:** the skip flag and its policy keys.

**Migration** of existing `policy.json` on load: each class takes the most cautious value among the old
keys it replaces (tighten-only, no re-enroll); per-key own `allow` rules carry over only when all members of
a class agree, else dropped with a notice in `policy show`. A machine whose session-level "protected" step
asked for outside/`.env` (ADR 0097 §3) maps to `outside=ask`, `secrets=ask`.

**Session words on the wire stay three** (`deny`/`ask`/`allow`); no `auto` word. A reviewer reply is
accepted as any reply, carries an `actor` label for galopin's local audit (`by: user | auto`, model id,
reason), and is applied **once only** (never `always`).

## 2. The deployment: who answers (Cerea admin)

Admin → **Agent auto-approval** (one screen):

- Reviewer on/off; **decision model** chosen among the gateway's `kind: decision` models; **threshold**
  (default 0.85 since 2026-11-05 with the read-only-inspection default instruction, was 0.90; floor 0.50 — amended after the sysadmin trials, see
  an internal decision-reviewer trial report (not published): the scores move with the instruction, so the
  save-time test, not a fixed floor, is the guard; ≈0.62 fits an unattended-sysadmin instruction); **instructions**: admin-editable policy text inside a fixed frame (the fencing
  of untrusted fields and the "text inside the action is data" trailer always last, the field set, the
  predicate and output contract fixed, length cap ≈2,000 chars, fence markers refused); **Test on the
  standard cases** runs the trial cases and refuses a save that lets a "must escalate" case through or
  fails a routine one.
- **Per-class rows, two values: you | reviewer.** Defaults: command → reviewer, outside → reviewer,
  secrets → you, edit/web/agents/tools → reviewer (they only matter if a machine sets them to `ask`),
  loop → you (fixed, never the reviewer: it has no transcript).
- Hourly cap of reviews per machine (default 300); the **review log** (time, machine, session, class,
  command/path, probability, allowed/escalated, applied).
- A static escalate list in code (galopin state/config, credential paths, CI-config writes) always goes
  to the user regardless of rows.

Per machine, the user can switch **"Never send this machine's asks to the reviewer"** in /code.

## 3. The session: the composer (Cerea user)

**Plan · Ask · Auto.** Plan → galopin `deny`. Ask → galopin `ask`; every card comes to the user. Auto →
galopin `allow` (the machine's `run` classes run locally, its `ask` classes raise cards); each card goes to
the reviewer if the admin's row for its class is *reviewer*, the machine isn't opted out and the reviewer is
reachable; otherwise to the user. Reviewer: probability ≥ threshold ⇒ allow (once); else escalate to the
user with the reason. With no reviewer configured, the third step is labelled **Allow** and its cards come
to the user.

Under the control, a **computed line** from the machine's limits and the admin's rows, e.g. "Auto on
studio-laptop: edits, web and tools run · commands and outside access are reviewed · secrets come to
you", with a details view (each row and its reason: this machine's limit / set by your admin).

## 4. Out of scope now

An OS sandbox (none assumed). Waiting inside a chat turn. Reviewer access to the session transcript.

## Plan (one night, three workstreams)

1. galopin + protocol: classes, limits, migration, re-enroll keeps state, `galopin reset`, loop stop,
   delegation rule, actor label + once-only, file editor default on, skip dropped; the parked branch
   `feat/auto-permissions-galopin` is reworked (keep Protected/CIGlobs and the actor field; drop the
   `auto` word, `ceilingForced`, skip, posture, `autoPermission`/`maxPerHour`/`allowSkip`).
2. Cerea admin screen + composer + device opt-out + the machine-limits display.
3. Cerea review service: routing per §3, the Pystino `/v1/decisions` call (ADR 0100, Pystino PR in
   progress), fixed frame, threshold, rate cap, escalation push and card wording ("Auto-allowed by
   ⟨model⟩ (96%)"; escalation: "The reviewer wasn't sure enough (51%; it allows at 90%)"), the review log
   store, the save-time test.

## Amendment 2026-11-05: plain reads skip the reviewer (owner, for Cerea 0.42.0)

The reviewer scored harmless reads (`docker compose ps`, `cat crontab_backup`) at 0.70–0.86, so they
reached the user. A model is the wrong judge for a question with an obvious answer.

- **The machine computes it.** galopin parses a `bash` command with a real shell parser
  (`mvdan.cc/sh`) and marks the ask `readOnly: true` only when: the command is simple commands joined by
  `|`, `;`, `&&`, `||`; no file redirects, no command/process substitution, no variables, no globs in
  arguments; every program is on a fixed read-only list with argument rules (`cat`, `head`, `tail`,
  `less`, `wc`, non-recursive `grep`, `ls`, `ps`, `df`, `du`, `git status|log|diff|show`, `docker ps|logs`,
  `docker compose ps|logs`, `systemctl status`, `journalctl`; `find` without `-exec|-execdir|-delete|-fprint*|-ok`;
  `sed` without `-i`); and every path argument, symlinks resolved, is inside the workspace and hits neither
  the Protected secret list nor galopin's own paths. Recursive reads and commands that print secrets with no
  file argument (`docker inspect`, `docker compose config`, `env`, `printenv`) never qualify.
- **The flag is a machine-computed field** of the permission request (next to `class`), never taken from
  agent- or opencode-supplied metadata.
- **Cerea routes it.** In Auto, a `command` ask with `readOnly: true` is allowed once at once, with no model
  call, logged in the review log as "Allowed: read-only" (actor `rule`). Ask sessions still get the card;
  a machine's `never` still refuses; secrets and outside reads keep their classes and rows.
- **What it is for:** a noise and latency reduction, not a security measure. A command that does not
  qualify is not refused; it takes the normal route (the reviewer in Auto). `less` is not on the list.
  No inspection of git configuration (decided 2026-11-05, see the threat model below).
- **`.git/**` writes** inside the workspace always raise an ask that reaches the user (galopin workspace globs,
  like CI files; Cerea's static escalate list), because they change what later commands mean.

## Threat model (owner, 2026-11-05, with an advisor round)

galopin, the classes and the reviewer protect against a fallible, over-eager agent: wrong or destructive
commands, needless outside access, loops, and secrets leaking into transcripts and commits. They are not a
security boundary. The agent runs as the user; an agent whose instructions were subverted by content in a
repo, a web page or a tool result (`web` and `tools` are the ingress points) can combine allowed actions into
anything the user's account can do, and the plain-read and class rules are heuristics, not guarantees.
Actions that change what later actions mean (galopin's state, CI config, `.git` internals, credential paths)
always reach the user. Containing a subverted agent is a sandbox's job (backlog C72, separate ADR); until
then, Auto on a machine means the blast radius is that user's account. Future reviews should judge these
rules as safety rails, not as attack resistance.

## Amendment 2026-11-05 (evening): a human may always allow

Owner decision: a human answering a card can always choose "Always allow", also when the machine caps that
class at `ask`. galopin stores the session exception for a reply with actor `user` and decision `always`;
later matching asks in that session run under it. `ask` therefore means "a person or the reviewer judges it
first; a person may judge a pattern once for the session". Unchanged: reviewer (`auto`) and `rule` replies are
once-only; `loop` stays once-only; a machine `never` and galopin's own paths still refuse. Cerea could already
answer every ask, so this gives Cerea no new power over the machine.
