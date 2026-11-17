# Brief: earlier versions in the doc tools, and the sandbox attachment mount (Cerea 0.32.4)

## Why
In a real session the model flattened a PDF form by mistake. Every doc tool then resolved the file name to the latest (flattened) version, so it couldn't get back to the fillable one, and the model fell back to rebuilding an official form as a lookalike. Separately, in the same session the sandbox's `/mnt/data` was **empty**: the attached PDF wasn't there, although the execution prompt says attachments are mounted at `/mnt/data/<name>`. So the model couldn't read the file with pypdf either.

## What to build (branch `feat/doc-versions` from origin/main)
1. **Address an earlier version:**
   - find how doc tool outputs are versioned (the "saved as a new version under the same name" logic in `src/lib/server/textGeneration/builtinTools/documentTools.ts`, `conversationFiles.ts`, and the conversation files store);
   - add an optional `version` (1 = the original attachment or first output, then 2, 3…; or "previous") to `doc_outline`, `doc_read`, `look_doc` and `convert_document`, and as the **source** of `doc_edit`, so an edit can start from an earlier version and save a new latest version;
   - add a small built-in or doc_edit-level way to **list a file's versions** (version number, when, which tool made it, a one-line summary): either a `doc_versions({file})` tool or a `versions` field in `doc_outline`. Pick the smaller design and justify it;
   - a "restore" is then `doc_edit` from version N with no operations, or a dedicated `restore_version` op. Make the result say plainly which version it started from;
   - tool descriptions stay within their budgets; strings say "the user".
2. **The sandbox attachment mount:** find why `/mnt/data` can be empty while the conversation has an attachment. Look at how attachments are synced into the browser sandbox (client side: the code-execution or Pyodide file mount, `src/routes/conversation/[id]/code-execution`, and the stores):
   - is it only files from the current message?
   - is it only some MIME types?
   - is a doc-tool output version mounted?
   - is there a race on the first execute_code?

   Reproduce it with a test (a conversation with an attached PDF, execute_code listing `/mnt/data`), fix the cause, and make the sandbox prompt's statement true: every file in the conversation is readable at `/mnt/data/<name>`, the latest version, and earlier versions too if cheap (e.g. `/mnt/data/.versions/<name>/<n>`, or say they aren't).
3. **Docs:** `docs/office.md` (versions), and the execution prompt if the mount rule changes.

## Coordination
- Another worker is on `feat/pdf-forms-round2`. It owns `documents/` (the Python service), the PDF skills and the PDF parts of the doc tool descriptions. If you need to touch `documentTools.ts`, keep to version resolution and the shared parameters.
- Another is on `fix/brotli-hardening` (playwright.ts, Dockerfiles); stay out of those files.

## Tests (each fails without its fix)
- Versions: create a file, edit it twice, outline version 1, edit from version 1 producing version 4 whose content derives from version 1, list the versions; a bad version number gives a clear error.
- Mount: the reproduction above fails before the fix and passes after.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-doc-versions -b feat/doc-versions origin/main`. `export TMPDIR=/var/tmp/doc-versions-tmp && mkdir -p $TMPDIR`. Read AGENTS.md first.
- Heavy steps under `flock /tmp/heavy.lock`; never wrap a self-locking script in another flock. If a build runs out of memory, use `NODE_OPTIONS=--max-old-space-size=4096`. The Playwright container runs as root: chown back what it leaves. Bind to 127.0.0.1, and kill what you start.
- Never git stash, never --no-verify, never force-push, no AI attribution in commits, no generated files.
- Checks: `npm run check`, eslint and prettier on the changed files, the server specs for builtinTools, files and documents, and the client tests for the code-execution and sandbox mount.
- Merge origin/main (merge commit) before CI. Push, run CI once (`gh workflow run ci.yml --ref feat/doc-versions`), and wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report: the design, the mount root cause, the fails-without-fix evidence, the CI result and changelog lines. No sub-agents.
