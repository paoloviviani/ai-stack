# Brief: move conversations in and out of projects (Cerea)

Repo /home/ubuntu/workspace/Cerea (public). Setup:
- `git fetch origin && git worktree add -b feat/move-to-project /home/ubuntu/workspace/Cerea-wt-move origin/main`; work only there.
- `export TMPDIR=/var/tmp/move-tmp && mkdir -p $TMPDIR`.
- NEVER `git stash`. No AI attribution trailers. Push the branch, no PR, never push main.
- `flock /tmp/heavy.lock` only around production builds / Playwright / full client project (never around dev/build.sh).
- No nested sub-agents. Real-mongo vitest: `TEST_MONGODB_URL`, `--no-file-parallelism`. Fix flakes at the cause.
- No private hostnames or private repo paths anywhere.

## Today
- Out: `DELETE /api/v2/projects/[id]/conversations/[conversationId]` clears `projectId` and calls
  `deleteDerived` (transcript leaves project memory). Only reachable from the project page
  ("Remove from project", ProjectPage.svelte ~967).
- In: nothing — a chat can only be born in a project.

## Want (owner: "move conversations in and out of a project")
1. Server: one operation to set a conversation's project: into a project, to another project, or
   out (null). Suggest `PATCH /api/v2/conversations/[id]` with `{ projectId: string | null }`
   (or a dedicated route — follow the codebase's conventions; keep the existing DELETE working,
   ideally delegating to the same helper).
   - Permissions: moving in requires access to the target project (`requireProjectAccess`);
     only the conversation's author may move a chat into a project or between projects; out keeps
     today's rule (author or project owner).
   - Memory: leaving a project → `deleteDerived` for that conversation (as today). Entering a
     project → its transcript becomes part of the project's memory/retrieval the same way a chat
     born in the project would (find how project transcripts are indexed — knowledge/service.ts,
     projects.ts — and reuse it; if indexing is per message at write time, backfill the existing
     messages). Moving between projects = out of A, into B.
   - Project-level effects a chat inherits (project instructions, documents, memory) must apply
     from the next message on; nothing to rewrite in history.
   - Tests: route spec covering in / between / out, forbidden cases (non-member target, someone
     else's chat), memory cleanup + indexing. Show they fail without the change.
2. UI entry points:
   - Sidebar conversation row menu (nav RowMenu): "Move to project…" opening a small picker
     (list of projects the user can access, search if many, "None (remove from project)" when in
     one, current one marked). Same on the chats list (ChatsList.svelte) row actions.
   - Chat page: the same action from the conversation header/title menu if one exists.
   - Desktop: drag a sidebar conversation onto a project in the Projects branch to move it in;
     drag a project chat out to the loose list to remove. Keyboard/phone users rely on the menu.
   - Project page: keep "Remove from project", but fix the phone layout defect: today the
     button squeezes chat titles to a few letters. Make it an icon/overflow menu with
     "Move to project…" and "Remove from project"; on a phone the top bar should show the
     project's name, not "New Chat".
   - After a move, the sidebar/project page update without reload; a toast confirms
     ("Moved to <project>" / "Removed from <project>") — use the app's existing toast if any.
   - Use the app's own dialog components, not native `confirm()`.
3. Checks: vitest for touched server/components, svelte-check on changed components, lint on
   changed files. Screenshots (desktop 1440 + phone 390, light + dark) of the menu, the picker,
   a drag in progress, and the fixed project page on a phone to
   /home/ubuntu/workspace/ai-stack/reports/screenshots/2026-10-24-move-to-project/ (don't commit
   in ai-stack). Look at them yourself.

Report: branch + commits, the API shape, the permission rules as implemented, how indexing on
move-in works, screenshot paths, open questions.
