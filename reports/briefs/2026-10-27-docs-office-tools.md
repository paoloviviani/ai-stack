# Brief: documentation pass for the document tools (Cerea, for 0.31.1)

## Goal
Bring every document page up to date with what has shipped:
- the document tools from 0.30.0 (ADR 0103; cite by number only, the repo is public);
- the slide-layout fixes from 0.30.1;
- backgrounds, shapes and the custom-design route from 0.31.0;
- the fixes landing in 0.31.1.

The docs must say what a person can ask for, what they get, and the limits. Operators must know how the service is deployed and configured. Write user text by `docs/writing.md`: plain language, sentence case, its term list. Read it first.

## What has shipped (verify each point against the code before writing it)
- **Service:** the `cerea-documents` service (`documents/`, image `ghcr.io/paoloviviani/cerea-documents`, versioned with the chat). The kit runs it on an internal network; the chat reaches it at `CHAT_DOCUMENTS_URL` with `CHAT_DOCUMENTS_SECRET`, and existing installs had to run `./configure` once in 0.30.0.
- **Tools:** `doc_outline`, `doc_read`, `doc_edit`, `doc_create`, `doc_create_from_template` (see AGENTS.md "Document tools", `src/lib/server/textGeneration/builtinTools/documentTools.ts`, and `documents/src/cerea_documents/`).
- **Formats:** Word, Excel and PowerPoint creation and editing, and PDF creation by the spec path (reportlab). Each edit is saved as a new version under the same name; the original is kept.
- **Style:** a neutral default style; styling from the prompt (`theme`: fonts from a fixed list, colours, accent, sizes, spacing, table style); templates only when the person uploads one in the chat. There is no admin template.
- **Charts and images:** native charts (editable in Office) or image charts; images everywhere.
- **Decks:**
  - six built-in 16:9 layouts (title, title and content, section, two columns, title only, blank);
  - text 20–24 pt, shrinking no further than 14 pt;
  - content kept below the title;
  - speaker notes.
- **0.31.0:**
  - slide backgrounds (colour, two-colour gradient, picture cropped to cover);
  - up to 30 shapes per slide (rect, rounded rect, ellipse, line, arrow, chevron, text box);
  - warnings for overflow, overlap and contrast.
- **0.31.1 (branch `fix/shapes-bleed`, about to merge):**
  - decorative shapes without text may run off the slide edge, as long as at least 0.5 cm stays visible; text shapes stay fully inside;
  - range errors state the field, the value and the allowed range;
  - the tool card's Input shows object arguments such as the spec, pretty-printed and cut with a visible note when very long.

  Read the branch: `git -C /home/ubuntu/workspace/Cerea show origin/fix/shapes-bleed --stat`.
- **The PowerPoint skill:**
  - the tools are the default;
  - the person may explicitly ask for a custom design, which the assistant builds in the sandbox and says so;
  - when it's unclear which the person wants, the assistant asks with two choices.

  Word, Excel and PDF use only the tools when the service runs. Without the service, the skills fall back to the sandbox method.
- **Previews:** Office previews and `convert_document` through optional Gotenberg (`CHAT_GOTENBERG_URL`, the kit's `office` profile); without it, decks are drawn in the browser. `doc_convert` is not built yet: don't document it as available.
- **Limits:** size caps, timeouts, and what can't be done (for example, adding native charts to an existing deck, or chart data edits). Take them from the code and the skill texts.

## Pages to check and update
- `docs/office.md` (the user page): the main rewrite. Cover:
  - what to ask for;
  - creating, editing and templates;
  - styling by asking;
  - designed slides;
  - the custom-design question;
  - versions;
  - previews;
  - limits;
  - what happens when the deployment has no document service.

  Add a short "for administrators" part, or link to the operator page.
- `docs/configuration.md`: `CHAT_DOCUMENTS_URL`, `CHAT_DOCUMENTS_SECRET`, `CHAT_GOTENBERG_URL`, and any other documents variable; also `CHAT_STREAM_IDLE_TIMEOUT_MS` and `CHAT_TURN_MAX_MINUTES` if missing. Check `.env` and `kit/.env.example` for each.
- `docs/deploy-kit.md` and `kit/README.md`: the documents service (what it is, its resources, the secret, upgrading from 0.29.x), and the office profile. Keep these consistent with each other.
- `docs/skills.md`: the word, excel, powerpoint and pdf skill descriptions (the one rule, the PowerPoint exception).
- `docs/index.md`: the feature table row, if documents are missing or out of date.
- `AGENTS.md`, "Document tools" section (developer reference): add shapes and backgrounds, bleed, `toolParams.ts` (object arguments on the tool card), and the error-message shape. Keep its style and density.
- `MAINTAINING.md`: only if it has a documents section that's now wrong.

Screenshots aren't required. If a page already embeds images from `docs/assets`, leave them unless they're wrong.

## Rules
- Worktree: `git -C /home/ubuntu/workspace/Cerea worktree add /home/ubuntu/workspace/wt-docs-office -b docs/office-tools origin/main`. `export TMPDIR=/var/tmp/docs-office-tmp && mkdir -p $TMPDIR`. Never `git stash`, never `--no-verify`, never force-push. No AI attribution in commits. No private hostnames or paths; cite ADRs by number only.
- Checks:
  - `uv run --with-requirements docs/requirements.txt mkdocs build --strict` passes;
  - prettier on every changed markdown file;
  - `npm run i18n:check` is unaffected (docs aren't scanned, but run lint if you touch anything under `src`; you shouldn't need to).
  - The kit's README is covered by kit tests (`cd kit && python3 -m unittest discover -s tests -q`): run the README-related ones at least.
- Push and run CI once: `gh workflow run ci.yml --ref docs/office-tools`. Wait with `until [ "$(gh run view $id --json status -q .status)" = completed ]; do sleep 60; done`. Don't merge.
- Report: the pages changed, with one line each on what changed; anything you found the code does differently from what the docs or the skills say; and the CI run and result.
- No sub-agents.
