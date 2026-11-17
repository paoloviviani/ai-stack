# Brief: minimal file editor for Cerea's /code panel (issue #69)

Repository: `paoloviviani/Cerea` (public). Work on a new branch `feat/file-editor` from `main`.
Read `AGENTS.md` and `agent/PROTOCOL.md` (§4 policy, §9.3 file ops, §9.4 deny list,
audit) first and follow them. The full spec is GitHub issue #69, so read it.

## What exists

- `/code` shows a machine's workspace files read-only in CodeMirror
  (`src/lib/components/code/CodeFileViewer.svelte`, with `readOnly` and `editable: false`).
- galopin (the Go machine agent in `agent/`) implements `files.list`, `files.stat`,
  `files.read` and `files.status` (`agent/internal/files/`, `agent/dispatch.go`).
- `files.write` is **specified but not built**. Today it answers `unsupported`.
- The policy field `fileWrite`, the enroll flag `--allow-file-write`, the deployment switch
  `CODE_FILE_WRITE_ENABLED` and the capability `hello.machine.capabilities.fileWrite`
  are also specified but not built.

## Build

### 1. galopin (Go)

- **`files.write`, exactly as specified:**
  - request: `{workspaceId, path, content, encoding: "utf-8"|"base64", baseRevision: string|null}`;
  - written atomically: a temp file in the same directory, then rename, keeping the file mode;
  - at most 1 MiB, otherwise `too_large`;
  - `baseRevision: null` means the file must not exist yet;
  - a revision mismatch answers `conflict` with `error.details = {revision}`;
  - answer: `{entry}`.
- **Reuse the read side's rules:** the same path resolution, workspace containment and symlink handling, and the `fileDeny` deny list. A denied path is `forbidden`, as for reads.
- **Policy:**
  - `fileWrite` (`allowed`|`denied`), **default denied**;
  - `enroll --allow-file-write`, and `policy set --no-file-write` to tighten;
  - loosening only through enroll, matching how the terminal and other powers work (read `policy_cmd.go` and `enroll.go`).
- **Capability:** report `fileWrite: true` in `hello.machine.capabilities` when built in. The policy is reported separately, as the other powers are.
- **Audit:** one line per write in galopin's audit log (path, size, outcome), never the content.
- **Tests:** atomic write, mode kept, create-only, conflict, too large, forbidden (deny list), path escape and symlink escape, policy denied.

### 2. Cerea server

- Forward `files.write` from the code API route (`src/routes/api/v2/code/[...path]/+server.ts`, next to the `content`/`raw` file cases). Allow it only when all three hold:
  - the deployment switch `CODE_FILE_WRITE_ENABLED` (default on, the machine policy is the real gate; add it to the config and docs like `CODE_FILES_ENABLED`);
  - the machine's policy;
  - the machine's capability.
- On refusal, answer 403 naming the exact enroll/policy flag, exactly as the terminal and files powers do.
- Record the write in `codeAudit`, path and bytes only.

### 3. Cerea UI, in `CodeFileViewer`

- An **Edit** button on text files, only when writing is allowed.
- CodeMirror becomes editable, with a dirty marker, **Save** (also Ctrl/Cmd-S) and **Discard**.
- On `conflict`, a "Changed on disk" choice:
  - **Reload**, which drops the user's edits;
  - **Overwrite**, which saves again against the new revision.
- Over 1 MiB, binary and image files stay read-only, with a short reason.
- Leaving with unsaved edits asks first.
- Strings go in `messages/en.json`. Regenerate the pseudo-locale with `npm run i18n:pseudo` and pass `npm run i18n:check`. Say "users", not "people".

### 4. Docs

- `docs/agent-machines.md` and `docs/agent-machines-reference.md`: the policy flag, the switch and the conflict behaviour.
- The "Implemented" list in `agent/PROTOCOL.md`.
- `kit/CHANGELOG.md` under `## Unreleased`, creating the heading at the top of the entries if absent.

## Checks

- **galopin:** `cd agent && go vet ./... && go test ./...`. The opencode integration tests need opencode and are optional; CI runs them.
- **Cerea:** run the affected specs only.
  - `npx vitest run --no-file-parallelism <files>`, plus `--project=client` for component tests (needs Chromium: `npx playwright install chromium --with-deps`).
  - `npx svelte-check`.
  - `npx eslint` and `npx prettier --check` on every changed file, tests included.
- **Real-galopin e2e:** the panel has end-to-end tests against a real galopin (`tests/code-machine-parity.spec.ts`). Add one for edit, save and conflict there. You don't need to run Playwright locally; CI's full run does it (see below).

## Rules

- **Git:**
  - never `git stash`, never `--no-verify`, never force-push;
  - commit with real messages that explain *why*, ending with
    `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or your own model's line) and this session's link;
  - no other AI attribution.
- **Publishing:**
  - push the branch and open a PR to `main` titled "Code panel: a minimal file editor (files.write behind the fileWrite policy)", referencing #69;
  - start the full CI on the branch: `gh workflow run ci.yml --ref feat/file-editor -f full=true`;
  - also start `gh workflow run opencode.yml --ref feat/file-editor` (galopin integration).
- **Do not merge.** Report the PR link, what was built, the tests run with results, both CI results, and anything uncertain.
- **The repository is public:** no private hostnames or credentials in code, tests or commits.
