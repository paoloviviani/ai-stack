# Brief: sandbox does not see conversation files — reproduce, fix, prove live (2026-10-29)

## Outcome

W2 (Sonnet worker, branch `fix/sandbox-mount`, head `a69d0ec41`, worktree `wt-sandbox-mount`). **Root cause: the mount path's fetches omitted the app's base path.** The kit serves the chat at `/chat` (`caddy/Caddyfile`: `handle /chat/*`), SvelteKit compiles the base in, and every other client caller builds its URLs through `base` (`runFiles.ts`, `CodeExecutionCard.svelte`) — but the four fetches that feed `/mnt/data` spelled bare `/conversation/...`:

- `src/lib/utils/execution/attachmentMounter.ts:354` (`fetchHash`) — the attachment download `GET /conversation/<id>/output/<sha>`, used by `sync()` for every attachment and for the extracted-text mount;
- `src/lib/utils/execution/attachmentMounter.ts:236` (`mountProduced`) — the produced download `GET /conversation/<id>/code-execution/output/<sha>`, used by `syncProduced()`;
- `src/lib/utils/execution/attachmentMounts.svelte.ts:103` (`listProduced`) — the produced-files list;
- `src/lib/utils/execution/files.ts:203` (`mountConversationFile`) — the manual mount action; plus the knowledge mounts beside them (`files.ts:135/146/180`).

On the deployment those requests reach the gateway (Caddy's `PROXY_DEFAULT=gateway` catch-all), fail, and every mount is skipped through `hooks.skipped` — so `/mnt/data` is empty for a plain attachment, for produced versions, and for knowledge files, on a fresh page load and a reopened conversation alike. "Re-attaching usually restores it" was invented and is now moot: the fix is in the URL, nothing about attachments changed. At the root (`base=""`) the same code is correct, which is why the whole unit suite and the default e2e were green while the bug lived — `tests/fixtures.ts` documents this exact trap ("the default e2e run never exercises a base path").

**Reproduction** (fresh worktree off `origin/main`, live Chromium e2e with the repo fixtures, built with `APP_BASE=/chat`, run with `E2E_APP_BASE=/chat`):
1. attach PDF → `doc_outline` turn → listing turn: **reproduced** — `os.listdir('/mnt/data')` → `[]`, before and after a reload; browser console: `[attachments] form.pdf was not fetched from /conversation/<id>/output/<sha> (status 404)`.
2. attach → `doc_edit` → listing turn: **reproduced** — `MOUNTLIST:[]` and `FileNotFoundError: '/mnt/data/<name>'` (the owner's own error), before and after a reload.
3. Both through a code fence and the live `execute_code` tool (parked turn; `CHAT_CODE_TOOL_ENABLED` added to the e2e env — it had never been enabled in e2e, which is why the tool path had no coverage). At the same `/chat` build **without** the fix all three failed; **with** the fix all three pass, listing the attachment (+ extracted `.md`) and the produced version with its produced bytes.

**Did C53 contribute? No.** The C53 guard (`530d987a1`, `attachmentMounter.ts:208-210`, skip a produced row when the attachment is the current version by stamped numbers) sits after the download and never ran on the owner's deployment; at the root the attach→`doc_edit`→list flow passes with the C53 code (attachment v1, produced row v2 → `1 > 2` false → mounts). `attachmentNamed` returning the newest attachment is server-side resolution and not on the mount path. The bug predates the versions work entirely (the Oct 28 19:35 transcript `07f27e0d` shows it on pre-versions code).

**Fix:** `base` from `$app/paths` prefixed on all four fetch sites (one commit). **Regression tests:** `src/lib/utils/execution/attachmentMountBase.svelte.spec.ts` pins every mount URL under a mocked `/chat` base (client project; fails 4/4 on the pre-fix code, verified by restoring the old files); `tests/chat-sandbox-mount-doc-turn.spec.ts` covers the doc-tool turn flow end to end (both cases, both load modes, fence and `execute_code` tool) — it fails at a `/chat` build pre-fix and passes post-fix. CI's suites run at the root, so the pinned-URL spec is what guards this in CI; the base-path e2e leg stays a documented manual mode (`E2E_APP_BASE=/chat` + a matching build).

**Gates:** `npm run check` clean; `npm run lint` clean on tracked files (one warn on an untracked gitignored paraglide cache file); server+ssr 4128 passed with one pre-existing environmental failure (`tokens.drift.test.ts`: compares `src/styles/tokens.css` against the sibling Pystino *working copy*, which is out of step on this machine — my diff touches no style file, and the same test passes in CI's `check` job); execution client specs and the new base spec pass; e2e at root: the two pre-existing mount/doc-edit specs and the three new ones pass, and all 15 `@smoke` specs pass. Pushed once; one CI dispatch: run [40880543374](https://github.com/paoloviviani/Cerea/actions/runs/40880543374) on `fix/sandbox-mount`.

**CI:** run [40880543374](https://github.com/paoloviviani/Cerea/actions/runs/40880543374) on `fix/sandbox-mount` — **green**: `check` (full server+ssr suite, 4121 passed), `e2e-smoke` (15 specs), `go`, `documents`, `changes` and `client` (1186 tests) all pass. The `client` job needed two reruns of the *same* dispatched run (`gh run rerun --failed`, never a second dispatch): attempt 1 failed `src/routes/admin/connectors/page.svelte.test.ts` (a pixel-snapshot assertion that passes 3/3 locally on this branch and on a pristine `origin/main` worktree, and passed in main's CI client job at 12:24), attempt 2 failed `src/lib/components/chat/ToolUpdate.svelte.test.ts` on a 15 s image-load timeout (that test fails identically on a pristine `origin/main` worktree on this machine, three times — pre-existing on main), and attempt 3 passed the whole project. Both are timing-sensitive layout tests unreachable from this diff (no shared imports; `renderWithApp` imports none of the changed files).

**Decisions taken:** enabled `CHAT_CODE_TOOL_ENABLED` in the e2e stack (the tool was otherwise untestable end to end); fixed the knowledge-mount fetches in the same commit (same bug class, same empty-`/mnt/data` symptom); left the base-path e2e as a manual mode rather than paying a second build in CI; did not merge (per the brief).

---


## Task
The owner's top-priority bug (handoff section 1.2, "Do this one first"): in the sandbox, `/mnt/data` is empty — a plain attachment is not mounted at all, and produced files are not mounted either. Reproduce on current main, find the cause, fix it, and prove the fix with a **live browser check** (unit tests passed before and the bug still existed, so a component test alone is not acceptance). Read the handoff first: /home/ubuntu/workspace/ai-stack/reports/2026-10-29-handoff-forms-artifacts-admin.md — section 1.2 is your task, its Rules section applies verbatim.

## The two reproductions to run first (on current main, in a fresh worktree off origin/main)
1. The owner's simpler case: a new chat with one attached PDF and one `doc_outline` call, then `execute_code` with `os.listdir('/mnt/data')` — expect (per the owner) empty `/mnt/data`, and `find /mnt -name '*.pdf'` empty. Fresh page load AND a conversation reopened later.
2. The original: attach a PDF, `doc_edit fill_form`, then `execute_code` listing `/mnt/data` — neither the attachment nor the produced version shows.

The owner's transcripts are in `~/.claude/uploads/ab09613d-fd72-4594-baa7-87d71d2ead82/` (`90fa4ca8-form-dummy-data-testing-9eb0da.md`, `d8c18568-form-contents-check-9eb3fd.md`) — read them for the exact symptoms (the model spent ~600 lines guessing because it could not see the file, and told the owner "re-attaching usually restores it", which is invented).

## Leads (from the handoff, plus one from the orchestrator)
- Mounting is driven from the chat page into the in-browser sandbox: `src/lib/utils/execution/attachmentMounter.ts` — `sync()` mounts attachments, `syncProduced()` mounts produced files. Every refusal goes through `hooks.skipped({name, reason})` — check whether a skipped note was shown (MountedChips) or only logged, and why.
- Check the doc-versions changes: the conversation registration with `$effect.pre` and `trackAttachmentSource`, the 5 s list and 30 s download timeouts, the per-conversation byte cap.
- Check whether a doc-tool turn (server-side) ever triggers a sync before the next `execute_code`.
- **Orchestrator's addition — check for a regression from today's merges:** `syncProduced`'s guard was changed today (C53, commit `6f380ebc7`, now merged at `a3ee1377b`): it skips mounting a row over an attachment that "is the current version" by a stamped-version comparison, and `attachmentNamed` now returns the newest attachment. If the reproduce shows nothing mounts at all, read those two functions first and diff them against `5ff84be05`'s behaviour. A regression here would be the whole bug.
- Client-side, so also check the browser console path: does `sync()` even run before the first `execute_code` (the chat page registers the conversation with `trackAttachmentSource` — `$effect.pre`)?

## Acceptance
- The fix with a regression test: attachment plus a doc_edit-produced version, both visible to the next `execute_code`.
- A live check in the browser (Playwright e2e with the repo fixtures, per AGENTS.md "Validating UI with screenshots" rules) proving the sandbox lists the attachment and the produced file after the fix — this is required, not optional.
- Remove the invented "re-attaching usually restores it" idea: after the fix that sentence must be unnecessary; make sure no skill or guidance suggests it.
- Full local gates (`npm run check`, lint, the execution specs), push once, dispatch exactly one CI run, watch it.

## Constraints
Heavy steps under `flock /tmp/heavy.lock`; `TMPDIR=/var/tmp/sandbox-mount-tmp`; mongod detached, never inside a flock; no stash/force-push/--no-verify. Do NOT merge — the orchestrator merges after review.

## Report back
The reproduction results (both cases, both load modes), the root cause (file:line), whether today's C53 change contributed, the fix, spec + live-check results, CI run id and conclusion.
