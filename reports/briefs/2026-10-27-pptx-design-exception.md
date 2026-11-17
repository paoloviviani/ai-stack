# Brief: a design exception for PowerPoint (Cerea, small)

## Owner decision (2026-10-27)
When the document service is running, the PowerPoint skill makes the `doc_*` tools the ONLY way to make a deck. This rule stays the default. The owner wants one exception: when the person **explicitly asks** for a custom visual design that the tools can't express, the assistant may build the deck in the sandbox with python-pptx. Examples: free-placed shapes or cards, coloured or picture backgrounds, an infographic, a timeline drawn from shapes, a "designed" or "creative" deck.

The tools stay the default. Asking for "a deck about X" still goes through `doc_create`. The exception is opt-in by the person's own words, or applies when the person has asked for something the tool rejected as not expressible. A plain "make it nice" is not an opt-in.

**PowerPoint only.** Word, Excel and PDF keep the strict rule.

## What to change (branch `feat/pptx-design-exception` from origin/main)
1. **`src/lib/server/skills/builtin/powerpoint/SKILL.md`:**
   - "One rule" keeps the ONLY-way sentence and gains the exception in one short paragraph. It covers when the exception applies (above), and requires the assistant to say in one line that it is building a custom design in the sandbox. It also says that within one deck the two ways are never mixed, and that a later edit of a sandbox-built deck may use `doc_edit` normally.
   - The fallback section's heading and intro now cover two cases: the tools are absent, or the design exception applies. Then give the fallback some design guidance for the exception case:
     - stay on a 16:9 slide;
     - keep every shape inside the slide (check bounds with the bundled `validate.py`);
     - use a consistent palette and fonts, text at least 14 pt, and enough contrast;
     - save under `/mnt/output/`.
     Keep it short.
2. **`src/lib/server/skills/officeSkills.spec.ts`** pins the wording for all four skills. Keep the pins for word, excel and pdf exactly. For powerpoint, pin the new heading and the exception wording ("explicitly asks", the one-line notice, never mixed in one deck). The test "names no way of writing documents in Python outside the fallback, except to forbid it" must still hold: phrase the exception without naming libraries or scripts above the fallback.
3. **`src/lib/server/textGeneration/executionPrompt.ts`:** two sentences say that with `doc_create` on offer, Office files are never made with code. Add the PowerPoint design exception there in a few words, so the two texts don't contradict each other. Check its spec (`executionPrompt.spec.ts`) for pinned wording.
4. Built-in skills re-seed on boot when unedited (`seedHash`), so no migration is needed.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-pptx-exc -b feat/pptx-design-exception origin/main`. `export TMPDIR=/var/tmp/pptx-exc-tmp && mkdir -p $TMPDIR`.
- Never `git stash`, never `--no-verify`, never force-push. No AI attribution in commits. The repo is public: no private hostnames or paths.
- Another worker is changing `documents/` and may add bullets under "Creating a deck" in the same SKILL.md. **Edit only the "One rule" section and the fallback section.**
- Checks: `npm run check`, eslint and prettier on every changed file, and the server tests `src/lib/server/skills` and `src/lib/server/textGeneration/executionPrompt.spec.ts`. Show that the new pins fail on the old text.
- Push and run CI once: `gh workflow run ci.yml --ref feat/pptx-design-exception`. Wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report: the changed files, the new SKILL.md "One rule" text verbatim, the CI run id and result, and one changelog line.
- No sub-agents.
