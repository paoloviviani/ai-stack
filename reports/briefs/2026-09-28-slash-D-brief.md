# Batch D brief: e2e (sanctioned), docs, and the remaining live checks

Worktree: /home/ubuntu/workspace/slash-cerea (feat/slash-commands at 8c6bc293:
A0+B+A+C done). This closes the wave: the e2e debt, user/ops docs, and rev1
§6's open live checks. You implement/report; the merge+deploy decision is
NOT yours — report and stop.

## 0. SANCTIONED for this batch (user-approved 2026-09-28, this batch ONLY)

`npm install` in the MAIN checkout /home/ubuntu/workspace/Cerea is now
sanctioned, to install the missing modules (@xterm/*, @codemirror/* —
whatever `package.json` lists that the Sep 21 node_modules lacks). This was
previously forbidden; the user has approved it for this batch.

Procedure, in the main checkout:
1. `free -m` ≥1500 and `df` ≥20% free first.
2. `npm install --no-audit --no-fund` under
   `timeout -s KILL 1800 flock /tmp/heavy.lock` — foreground.
3. Verify nothing drifted: `npm run check` in slash-cerea still 13 = the
   baseline; `npx vitest run --project=server machine-forwarder.spec.ts`
   and `machineTimeline.spec.ts` still pass; if anything new appears,
   STOP and report (a dependency version shift is a report-worthy event,
   not something to fix silently).
4. This also un-breaks the build for slash-cerea (node_modules is the
   symlinked same tree) — the /tmp worktree trick is no longer needed.

## 1. The e2e (the debt: batch B's 7 panel cases + batch C's 4 backend cases)

- Build + run `tests/code-commands.spec.ts` from /home/ubuntu/workspace/
  slash-cerea directly, now that the build should resolve. Ports away
  from 5199 (and from the e2e-mongo-8801 if the harness wants Mongo);
  the harness env vars are in the spec's own header (E2E_APP_PORT,
  MOCK_* etc. — you wrote them).
- `npm run build` first under the lock (df/free first), then the run with
  E2E_SKIP_BUILD=1 (or per the harness's own build-skip idiom).
- If a case fails, fix it (the spec, the harness, or the feature — a real
  bug found by the e2e is the whole point; report which).
- Report exact pass counts per case.

## 2. Docs (user + ops)

Find the repo's docs idiom (the auth wave wrote docs — same conventions):
- User docs for /code slash commands: the `/` menu and its groups (Panel /
  Project / Machine / Skills / MCP), the shell icon meaning, the shadowed
  rule, the first-run confirmation sheet (snippets + @refs + the
  localStorage remembering per templateHash), the 403 (enroll
  --allow-command-shell) and 409 (template changed, review) copy, mid-turn
  refusal, panel-only fallback on old galopin.
- Ops docs (short): the commandShell policy (default denied, enroll flag,
  policy set tighten-only), the audit row shape (name/origin/shell, never
  args), the no-template-over-the-wire rule, and the confirm-sheet +
  templateHash 409 loop.
- Cross-check against agent/PROTOCOL.md §6/§7 (your batch A text) so the
  two documents agree on the Command shape and refusal codes.

## 3. Live checks (rev1 §6 leftovers) — galopin gated ITs

Both are extensions of the existing IT harness (GALOPIN_OPENCODE_IT=1):
a. **Agent precedence live** (owed from batch A): a plan-mode session
   issuing a command whose template names a build agent → assert the
   overlay mode is sent, not the agent. Extend the existing IT file with
   a subtest; run it live.
b. **MCP expansion** (open from batch A): attempt a minimal MCP server in
   the IT's opencode config (a trivial stdio server exposing one tool),
   one MCP-source command (shell: null → refused under default policy)
   and, if feasible, a command whose template calls the MCP tool → the
   expansion record. If this proves >2h or flaky, STOP the attempt, and
   report exactly what blocked it (config surface, version behavior) so
   it stays an honest open item. Do not hack around opencode's config.

## 4. Report + plan tick

- Report: install results (modules added, size), any drift found, e2e
  pass counts per case, docs files, live-check results, deviations.
- Append the settled §6 items' results to
  /home/ubuntu/workspace/ai-stack/reports/2026-09-27-slash-commands-plan-rev1.md
  §6 (mark each settled/open with one line + date).
- Then stop for review. NO merge, no main, no /opt/cerea.

## Box + git rules (binding)

NO sub-agents. Foreground; heavy under `timeout -s KILL <secs> flock
/tmp/heavy.lock`; free -m ≥1500 / df ≥20% before each heavy command (npm
install, build, e2e run — the trio is the heaviest sequence this box has
run; if RAM dips mid-sequence, stop between steps and let it recover).
Client vitest: TEST_MONGODB_URL=mongodb://127.0.0.1:8801. Git: configured
identity, NO AI trailers, coherent commits, push feat/slash-commands.
