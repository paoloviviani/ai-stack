# 73 — The browser runs Python; the model heals the rest; packages are served, not sockets

Date: 2026-09-16

## Status

Accepted. Amends [0072](0072-skills-phase-1.md): the "execution is Pyodide,
stdlib-Python-or-nothing, bundled `scripts/` inert" stance is superseded by the
package policy and the skill-asset ingestion below. Relates to
[0021](0021-code-sandbox.md), whose rejection of server-side untrusted execution
is reaffirmed, not touched. The client-side sandbox itself (worker, network gate,
file egress) is documented in `Cerea/docs/pyodide.md`.

## Context

The chat can run model-written Python in the person's own browser (Pyodide,
WebAssembly). The question this ADR settles came from wanting imported **agent
skills** — the open SKILL.md format of 0072, and specifically the Anthropic
office skills (docx, xlsx, pdf, pptx) — to actually *do their work*, not just
carry instructions. Two things stood in the way: those skills lean on packages
and on shell tools, and 0072 had recorded "stdlib only, no packages, `scripts/`
inert" as architecture without ever testing it against a real skill.

A full day was spent evaluating whether a different browser engine — **WASIX**
via `@wasmer/sdk` — should replace Pyodide, because WASIX has a real process
model (fork/exec/pipes) and a shell, which Pyodide does not. The friend's
decision notes framed the tiers; the orientation was, briefly, "WASIX-first".
Then the actual skills were read at source and a spike was run, and the
orientation reversed.

## What the skills actually need (verified at source, 2026-09-16)

The office skills are not "Python skills". Read from the real SKILL.md files:

- **docx** *creates* with npm `docx` (Node/JavaScript), *reads* with `pandoc`,
  *verifies* by rendering through LibreOffice (`soffice`) and `pdftoppm`
  (Poppler), and delegates edits to bundled Python scripts (`merge_runs.py`,
  `comment.py`, `accept_changes.py`).
- **xlsx** uses `openpyxl` + `pandas` + `markitdown`, and *mandates* a
  LibreOffice recalculation pass (`recalc.py`) before delivery.
- **pdf** uses `pypdf`/`pdfplumber` plus command-line tools.

None of `pandoc`, `soffice`, `pdftoppm`, `markitdown`, or a Node runtime exists
in **any** browser WebAssembly engine — Pyodide or WASIX. So the promise "run
imported skills as written" was never achievable in the browser for this class,
under either engine. WASIX's one genuine advantage — process composition —
does not reach the steps that give these skills their quality.

A Stage 0 spike (live gateway, `qwen3.8-flash-next`) confirmed the behaviour
that matters: told to use the docx skill under the *current* stdlib-only prompt,
the model correctly refuses docx-js/pandoc/soffice on its own and translates to
Python — but the hand-built OOXML it produces is **brittle** (one run raised a
fatal `NameError` and wrote no file at all, plus an XML well-formedness bug).
Told instead that `python-docx` is available, the model writes clean, idiomatic
`python-docx`. Packages are the difference between fragile and reliable.

## Decision

### The engine stays Pyodide; WASIX is considered and deferred

Pyodide is mature (MPL-2.0, used in JupyterLite/PyScript for years), needs no
special headers, and its host-side shape — stdout plus files — is already what
the chat consumes. WASIX buys real process composition we have just shown does
not reach the hard steps, and it costs: an **alpha** SDK we would co-develop, a
**single vendor**, a **modified-MIT** licence clause (products above 1M MAU or
$1M/mo must display "Wasmer" — no blocker at this scale, but re-users inherit
it), **mandatory COOP/COEP** cross-origin isolation, and — the decisive one — a
**WISP relay** for any guest networking, which is a network backend by another
name and would reintroduce the third-party egress the gateway rule forbids.

WASIX is **re-openable** on one condition: a demonstrated class of skills whose
work self-healing to Pyodide cannot serve and that a self-hosted relay plus the
alpha SDK would. The office class is not that condition — nothing browser-side
serves its `soffice`/`pandoc` steps.

### The model heals the skill (the self-healing doctrine)

Skills stay **verbatim** in storage. A skill's non-Python steps — bash, `unzip`,
`sed`, Node snippets, tool invocations that do not exist here — are translated
into Python **by the model, at execution time**, using the available packages or
the standard library. The composer is the model, not a port maintained per
skill: people import skills and do not adapt them, so the adaptation cannot live
in the stored text. The system prompt states what is available and instructs the
translation; it prefers the dedicated package (`python-docx`, `openpyxl`,
`pypdf`) over hand-built formats.

### Packages are served same-origin; the default is deny

The person is the principal and the data owner, and the code runs in their own
browser — so, as JupyterLite does, packages are allowed, default-off, in tiers:

- **Vendored wheels, served same-origin (the default enabler).** The wheels the
  office skills need are placed under the app's runtime directory and installed
  by micropip with its index still pinned there — **no third-party request, no
  gate change.** A pure-Python skill wheel is not enough on its own: `python-docx`
  and `python-pptx` pull in **compiled** `lxml` (and `python-pptx`, `Pillow`) —
  both are Pyodide-built packages in the lock, but their wasm wheels must be
  *served*, and today the deployment ships only the ~14 MB core. So enabling the
  docx class means serving `python-docx` + `typing_extensions` (pure) **and**
  `lxml` (compiled). `openpyxl` and `pypdf` are fully pure with no compiled deps.
- **A user opt-in to PyPI.** A per-user setting (default off) allows installing
  arbitrary **pure-Python** wheels from PyPI: it unpins micropip's index and
  opens the network gate to `pypi.org` + `files.pythonhosted.org` (https only,
  session credentials never sent cross-origin). An **admin kill-switch** env var
  overrides it off. micropip accepts pure wheels only, so a wrong-architecture
  install is impossible by construction.

The network gate (`gate.ts`) remains the single choke point and the enforcement
point — there is no relay, because Pyodide has no sockets. This is why the
network story here is a gate setting and not, as it would be under WASIX, a
proxy server to build and run.

### Skills carry their bundled files, loaded on demand, run client-side

0072 stored a skill as one SKILL.md string and left `scripts/`/`references/`/
`assets/` inert. They are ingested now: a skill may be imported as its folder
(SKILL.md plus the bundled directories), stored with path validation
(`scripts/|references/|assets/` only), and a `load_skill_file` tool returns a
bundled file's **content** on demand. The model reads a script and composes it
into a client-side `execute_code` call — **read-then-run, never a server-side
execution path.** A bundled script is text until the model chooses to run it in
the sandbox, exactly like the skill body itself.

### Server-side execution stays rejected; the seam is kept

0021 stands: no untrusted model-generated code runs on the multi-tenant box.
gVisor remains the sanctioned home for real compiled tools *if* server-side
execution ever becomes acceptable, behind an `exec(cmd, files) → {stdout,
stderr, files}` adapter so the chat layer never learns which backend answered.

## Cost, stated rather than hidden

- **The `pandoc`/`soffice` class is unreachable, permanently and regardless of
  engine.** The docx render-and-verify step, the mandatory xlsx recalculation,
  the pandoc read — self-healing to a lower-fidelity pure-Python approximation,
  or dropping the step, is the only answer. This is a limitation to document,
  not a bug to fix, and it is the same under WASIX.
- **Brittle generations can fail silently.** File-producing code in the auto-run
  code-fence channel executes where the model never sees stderr, so a broken
  script is claimed as a success over an empty result. The mitigation is to
  steer file work toward the `execute_code` tool, where the model reads the
  error and iterates.
- **The PyPI opt-in reintroduces a gated third-party egress.** It is off by
  default, per-user, admin-killable, and credential-free cross-origin — but it
  is a real hole in the "same-origin only" posture, opened deliberately and by
  the data owner's own choice.
- **A bundled script that shells out still cannot run.** `load_skill_file` makes
  the script *readable*; the `soffice`/`pandoc` calls inside it remain
  unavailable, and the model must heal them like any other non-Python step.

## Consequences

- The Pyodide packages work (serving wheels; the PyPI toggle) is un-held from
  0072's "packages later". The build vendors the **full** `pyodide-lock` set
  (~300 MB, all 357 built packages) same-origin — chosen over a selective set
  after live testing showed numpy/pandas (which the xlsx skill wants) missing:
  the wheels are lazy per-package downloads for the user, and the cost is image
  size and a longer `sync-pyodide` step, not per-session bandwidth.
- The execution system prompt loses its "stdlib only, never third-party" text
  and gains the available-package list and the self-healing instruction.
- WASIX leaves no code behind — it was evaluated, not adopted — but its findings
  and the modified-MIT clause are recorded here so a future adopter inherits the
  analysis rather than repeating the day.

## Amendment (2026-09-16): computed deliverables persist per-user, 30 days

Files a run *writes* (a generated `.docx`, an image) lived only in the browser
worker's in-memory FS: gone on reload, on the 20 s wall-clock terminate, or on
tab close, and the `execute_code` tool's resolved update deliberately carried no
file bytes — so a download card vanished the moment the turn finished. That is
right for scratch files and wrong for a deliverable the person explicitly asked
for. Two things change:

- **A card keeps its files for the whole session.** `CodeExecutionCard` now
  prefers the live settled run (whose RunsStore entry still holds the bytes)
  over the fileless resolved state, falling back to resolved only on true
  replay. This is a UI fix, not persistence — reload still loses the file.

- **Deliverables persist server-side, per-user, for 30 days.** When a run
  produces a file the model surfaces as a *deliverable* (the file-first case,
  not every scratch file), the browser uploads its bytes to the existing
  per-user output store (GridFS behind `authCondition`, the same machinery as
  message attachments), and the resolved update carries **file references**
  (url + size + sha256) rather than nothing — so a download card renders from
  the server on reload and on another device. Retention is a **30-day TTL**
  (a TTL index on the store), and deleting the conversation deletes its files.
  Only deliverables persist; scratch output a run writes stays session-only.

This does not weaken the execution security model — code still runs client-side,
nothing model-generated executes on the server. It only stores the user's own
output, per-user and access-controlled, exactly as an uploaded attachment
already is; the "data never leaves the browser" line was always about execution
isolation, not about the user's own saved deliverables. Considered and not
chosen: browser-local persistence (OPFS/IndexedDB) — purer on the posture but
per-device only, no cross-device or shared access; and auto-persisting *all* run
output — storage bloat for scratch nobody asked to keep.

## Amendment (2026-09-26): every produced file is a deliverable

The 2026-09-16 amendment kept only the `execute_code` tool's files and left an
auto-running chat code block's (and an artifact cell's) session-only, as
"scratch". In practice the line fell in the wrong place. The execution prompt
tells the model to answer "make me a file" with exactly such a code block, so
the most common request produced a file that was never kept, never became a
file artifact, and was gone on reload. Meanwhile the same bytes made through the
tool path were kept and previewed. The user's decision: "The point is not how
the file is created, the point is visualization." There is now one rule for
every produced file, whichever path produced it:

- **One retention rule.** Every file a run lists as output is uploaded to the
  same per-user store, whether it came from the tool, an auto-run or manually
  run code block, or an artifact cell. It gets the same per-file, per-
  conversation and total caps, the same 30-day TTL, and owner-only downloads.
  A tool run's references still ride on its resolved update. A block's or a
  cell's are recorded against their assistant message in a small record
  collection, which the conversation loader serves as an update on that
  message. That record is not written into the message itself, because a turn
  saves its messages wholesale and would overwrite it. The server rebuilds each
  reference from its own store rows and refuses anyone who isn't the owner, so
  the only thing it trusts from a request is a file's hash.
- **One way of showing a file.** Every stored file is a versioned file artifact
  with the same previews, and the card under a run, the artifact panel and the
  sidebar library all show the same thing. A replayed code block shows its
  stored file where the dead sandbox copy used to be.

The execution security model is unchanged: code still runs only in the
person's browser, and in every path the bytes come from that browser's own
sandbox. Shared-conversation viewers still cannot download the owner's files
(the user's decision), and a viewer's browser never uploads into the owner's
store. The storage-bloat concern that motivated the old line is bounded by the
caps and the TTL, which already applied per conversation. Out of scope: files
from MCP tools, and the person's own attachments.
