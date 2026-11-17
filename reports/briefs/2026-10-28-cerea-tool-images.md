# Brief: Cerea honours "Images in tool results" and never breaks a turn over them (Cerea 0.32.3)

## Context
- `look_doc` (on main) returns page images. They go to the model as a user picture message right after the round's tool messages (`textGeneration/mcp/pictureMessages.ts`, `toolInvocation.ts`), labelled and footed (`textGeneration/untrusted.ts`, the tool-output guard, also on main).
- Live trials: some vision models mishandle images in tool turns, and some chat templates reject or drop them.
- Pystino is adding a per-model capability `tool_images` in `supported_features` on `/v1/models` (branch `feat/tool-images` in Pystino, not merged yet). It is on by default for image-input models; an admin turns it off per model in the console.

## What to build (branch `feat/tool-images-gate` from origin/main)
1. **Read the capability:** in `src/lib/server/models.ts` (where `supported_features` and `input_modalities` are read, ~330-372), add a per-model `toolImages: boolean`:
   - **Pystino mode:** true only if the model accepts images **and** the gateway lists `tool_images`;
   - **a gateway that doesn't list the feature for any model at all** (an older Pystino): fall back to "accepts images", so nothing changes until Pystino 0.19 is deployed. Detect "the gateway knows the feature" as "at least one model lists `tool_images`", or a version or capability flag if Pystino exposes one; pick the robust option and explain it;
   - **standalone or a generic endpoint:** "accepts images", with an override in Cerea's model config (the `MODELS` env JSON or wherever per-model overrides live; follow the existing pattern) to set `toolImages: false`.
2. **The gate:** `look_doc` is offered only when `toolImages` is true (replacing the plain `modelSeesImages` gate). Other image paths (user attachments) are unaffected.
3. **Never break a turn over pictures:** if a model request that carries a look_doc picture message fails with an HTTP 4xx from the endpoint (400 or 422, the shape the provider rejects), retry the same request once without any picture messages. Replace them with the text "[the images could not be sent to this model; describe what you can from the text, or tell the user]". Remember it for the rest of the turn (no more pictures, and look_doc answers that images aren't available on this model this turn). Log it at warn with the model id. Don't retry on 5xx, timeouts or 401/403/429.
4. **Docs:** `docs/office.md` (`look_doc`: when it's offered, the per-model switch in Pystino, the standalone override) and the admin docs. "users", not "people".

## Tests (each fails without its fix)
- `models.ts`: the three cases (Pystino with the feature on or off, Pystino that never lists it, standalone with and without the override).
- Gate: look_doc absent when `toolImages` is false, even for a vision model.
- Retry:
  - a mocked endpoint returns 400 to a request containing a picture message and 200 to the same request without it: the turn completes, the replacement text is present, and later look_doc calls in the turn report images unavailable;
  - a 500 isn't retried;
  - a 400 on a request without pictures isn't retried by this path.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-tool-images -b feat/tool-images-gate origin/main`. `export TMPDIR=/var/tmp/tool-images-tmp && mkdir -p $TMPDIR`. Read AGENTS.md first.
- Another branch, `fix/sandbox-reportlab-flat-forms`, touches `executionPrompt.ts`, `executeCodeTool.ts`, `documentTools.ts` and the pdf skills. Avoid those files.
- `npm ci`, builds and containers run under `flock /tmp/heavy.lock`; never wrap a self-locking script in another flock. If a build runs out of memory, use `NODE_OPTIONS=--max-old-space-size=4096`. Bind to 127.0.0.1, and kill what you start.
- Never git stash, never --no-verify, never force-push, no AI attribution in commits. Don't commit generated files (`.svelte-kit`); run `npm run check` from the repo root.
- Checks: `npm run check`, eslint and prettier on the changed files, and the server specs for models, textGeneration (mcp, builtinTools) and generation.
- Merge origin/main (merge commit) before CI. Push, run CI once (`gh workflow run ci.yml --ref feat/tool-images-gate`), and wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report: the detection rule as built, the retry behaviour, the fails-without-fix evidence, the CI result, and a changelog line. No sub-agents.
