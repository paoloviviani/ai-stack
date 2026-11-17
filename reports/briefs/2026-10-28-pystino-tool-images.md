# Brief: "Images in tool results" per model (Pystino 0.19.0, ships together with Cerea 0.32.3)

## Why
Cerea's new `look_doc` tool (v0.32.3) gives a vision model images of document pages through a tool call: the tool result, then a user message with the images. Some vision models or serving setups handle that badly. Live on Cortecs, mistral-small-2603 ignored images placed after a tool result in some placements, and some chat templates drop images in tool turns. The gateway already owns per-model capabilities (`input_modalities`, `supported_features`, editable in the console with audit), and Cerea reads them from `/v1/models` (`src/lib/server/models.ts` ~330-345 in Cerea). So whether a model can use images in tool results is a gateway capability too.

## What to build (branch `feat/tool-images` from origin/main)
1. **A new feature value `tool_images`** in the open `supported_features` set. Check `models.py` ~1166-1180, `pricing.py`, `admin_audit.py` and the console `CapabilityPicker.tsx`, then follow how the existing features are declared and validated (an enum? a known list for the picker?).
2. **Default on for vision models:**
   - a migration (alembic, next number, idempotent, following the repo's migration conventions and the bootstrap caveats in `bootstrap.py`) adds `tool_images` to every model whose `input_modalities` include `image` (or `vision`, if that alias exists), and doesn't touch others;
   - the provider catalogue sync and import (`providers.d/*.yaml` and whatever turns catalogue entries into model rows) also sets it by default for image-input models, unless the catalogue entry explicitly lists features without it, or an admin removed it (don't re-add on sync what an admin removed: check how the sync treats admin edits today and follow that rule);
   - a model created by an admin in the console with image input gets it pre-ticked.
3. **Console:** in the capability picker, show it as "Images in tool results", with a one-line help: "Lets the chat show this model page images from tools (for example a document's slides). Turn off if the model ignores or mishandles them." It's enabled only when the model accepts images (hidden or disabled otherwise). Changes are audited like the other capability edits.
4. **`/v1/models`:** `supported_features` includes `tool_images` for those models. Check the response schema and `api-schema.ts`, regenerated if it's generated.
5. **Docs:** the console docs for model capabilities, and the CHANGELOG entry (written at release, not now). Say "users", not "people", in new text.

## Tests (each fails without its fix)
- The migration: a vision model gains `tool_images`, a text model doesn't, and running it twice is a no-op.
- Catalogue sync: a new image-input model gets it, an admin-removed one stays removed after a sync.
- The API: `/v1/models` lists it for a vision model with it on, and not after it's turned off.
- The console: the picker shows the option only for image-input models; toggling it sends the right update (console test framework as the repo uses).
- The admin audit records the change.

## Rules
- Read Pystino's AGENTS.md and CLAUDE.md first. Worktree: `git -C /home/ubuntu/workspace/Pystino worktree add /home/ubuntu/workspace/Pystino-tool-images -b feat/tool-images origin/main`. `export TMPDIR=/var/tmp/pystino-tool-images-tmp && mkdir -p $TMPDIR`.
- Run the PG leg too if the repo's test setup expects it for migrations. Use the heavy lock for builds and Docker (`flock /tmp/heavy.lock`); never wrap a self-locking script in another flock. Bind to 127.0.0.1, and kill what you start.
- Never git stash, never --no-verify, never force-push, no AI attribution in commits. The repo is public.
- Checks: pytest (SQLite and PG as CI runs them), ruff, mypy, and the console's typecheck, lint and tests. Push and run CI once (the repo's CI workflow on the branch), and wait for it. Don't merge or release: this ships together with Cerea 0.32.3.
- Report: the feature name and where it's declared, the migration number, the sync rule, screenshots of the console picker (1440 and 412 px) in `/home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-28-pystino-tool-images/` (look at them yourself), the fails-without-fix evidence, the CI result, and a changelog line. No sub-agents.
