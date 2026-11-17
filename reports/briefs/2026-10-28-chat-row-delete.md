# Brief: C44 — delete in the chat row `⋯` menu (2026-10-28 evening)

## Task
Owner-approved pull-in for 0.32.4. On branch `feat/chat-row-delete` (worktree `/home/ubuntu/workspace/wt-delete-menu`, based on `origin/main` `5ff84be0`): add Delete to the row `⋯` menu that today offers only "Move to project…" and "Remove from project". Implement, run the relevant specs, push once, exactly one CI run. Do not merge — the orchestrator merges before the release step.

## What to build
- `src/lib/components/MoveMenu.svelte`: add an optional `ondelete?: () => void` prop beside `onmove`/`onremove`; when given, render a Delete item styled like the other items, with a trash icon (`~icons/lucide/trash-2` or whatever the sidebar uses) and the destructive tint the sidebar's delete uses.
- Wire it at both call sites: `src/lib/components/projects/ProjectPage.svelte` (~line 975) and `src/lib/components/chats/ChatsList.svelte` (~line 280), reusing the **same delete flow the sidebar uses** — find how `NavConversationItem.svelte` deletes a conversation, including any confirmation dialog, and reuse it (do not invent a bare destructive action).
- Label: reuse an existing Paraglide message key if one fits (search `messages/` for the sidebar delete label); add a new key only if none fits — and then in every locale file present, plus whatever the i18n check requires (there is an i18n check; find the script, likely in package.json; en-XA counts).

## Verify
- Existing specs touching MoveMenu / ChatsList / ProjectPage (search `*.test.ts`); add or extend a MoveMenu spec so the new item is covered (offered only when `ondelete` is given, calls it on select).
- Run the relevant vitest specs locally (`--project=client` for component tests). Heavy steps under `flock /tmp/heavy.lock` — the box has 4 cores/6 GB.
- Commit: one descriptive line matching repo style, no AI trailers (hooks reject them). New user-facing text says "users", not "people". Push once, no force. One CI run, watched to completion.

## Report back
Files changed with a one-line why each; which message key was reused or added; spec results; CI run id and conclusion; anything decided yourself.

## Outcome (W4, 2026-10-28)

Branch `feat/chat-row-delete`, one commit `9a3266804` on top of `origin/main` `5ff84be0`; pushed once; PR [#47](https://github.com/paoloviviani/Cerea/pull/47) (opened so CI would run; not merged).

**Files changed**
- `src/lib/components/MoveMenu.svelte` — optional `ondelete` prop beside `onmove`/`onremove`; when given, a last Delete item with the sidebar's `CarbonTrashCan` icon and its exact destructive tint (`DELETE_ITEM`, copied from NavConversationItem's item).
- `src/lib/components/chats/ChatsList.svelte` — wired `ondelete`; the sidebar's `DeleteConversationModal` confirms, then `DELETE /api/v2/conversations/<id>` (same endpoint the layout's delete uses), row dropped, the conversations store told (`remove`), `projectsChanged()` for the Projects tree, failures toast (`useNotificationsStore`).
- `src/lib/components/projects/ProjectPage.svelte` — wired `ondelete` for `conversation.mine` only (the server's delete is `authCondition`, the caller's own; same gate as Move); same modal, then the page's `api` helper DELETE, `leftProject()` drops the row and count, `projectsChanged()`; failures land on the page's failure line.
- `src/lib/components/MoveMenu.svelte.test.ts` (new) — Delete offered only when `ondelete` is given; last item, `text-red-500` tint; calls `ondelete` alone on select; offered alone when it is the only action. Verified to fail with the old MoveMenu restored (2 of 3 fail, as designed).
- `src/lib/components/chats/ChatsList.svelte.test.ts` (new) — delete from the row menu after the confirmation (nothing sent before it), row gone, sidebar store told; cancel leaves everything alone.
- `src/lib/components/projects/ProjectPage.svelte.test.ts` — extended "ProjectPage chats": author's chat deletes after the same confirmation; a chat someone else started offers no Delete (menu is exactly "Remove from project"). Stub learned `DELETE /api/v2/conversations/<id>`.
- `src/lib/components/__tests__/sharedComponents.i18n.svelte.test.ts` — MoveMenu render now passes `ondelete` so the pseudo-locale suite knows the shape.
- `docs/chat.md`, `docs/knowledge.md` — the row menus' Delete documented (chats page and project page) in the same change.

**Message key**: reused `app.nav_item.delete` ("Delete") — the sidebar's own label; no new keys, no locale/en-XA changes. Error text reuses `nav.projects.delete_chat_failed`.

**Specs (local, `--project=client`)**: MoveMenu 3/3; ChatsList 2/2; ChatsList.i18n 1/1; ProjectPage 21/21 (incl. the two new); ProjectPage.pseudo 3/3; sharedComponents.i18n 4/4. A six-file batch run once hit the documented under-load loader failure; each file run alone passes (trap in MAINTAINING.md). Gates: `npm run check` 0 errors; eslint clean; `i18n:check` passed (2424 messages, 2424 used). Prettier clean on all touched files (a generated untracked `project.inlang/cache/*.json` trips `prettier --check .` locally only; CI's lint orders prettier before the compile, so it never sees it — pre-existing wart, not touched).

**CI**: run `40771806355` (the only run for the branch), concluded **success** in 12m15s — check, client (the PR touches `src/lib/components`), go and e2e-smoke green; e2e-full/documents skipped by design.

**Decided myself**: (1) Delete on the project page is offered for the author's chats only — the delete endpoint is author-only, and the sidebar's project folder currently offers it on colleagues' chats and eats a 404; not replicated. (2) ChatsList errors toast, ProjectPage errors use its existing failure line — each surface's own idiom, same message key. (3) Sidebar flat list updated via `conversationsStore.remove` from the chats page; project page relies on `projectsChanged()` (project chats are not in the flat list). (4) PR opened by me (the branch push alone triggers no workflow) so exactly one CI run exists.
