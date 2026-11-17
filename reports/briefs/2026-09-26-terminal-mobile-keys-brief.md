# Brief: the /code terminal on mobile. View mode, a Type button and an extra-keys bar

Repo: Cerea. The orchestrator gives you the worktree, branch, base SHA, ports and Mongo in the launch message. Run `npm ci` first.

The spec is §2.4 of `/home/ubuntu/workspace/reports/2026-09-24-code-files-and-terminal-plan.md` (the Terminal bullets). The terminal UI is `src/lib/components/code/CodeTerminal.svelte` (the xterm viewport, the socket, binary frames) and `CodeTerminals.svelte` (tabs). Input goes to the machine as binary `term.input` frames; see how CodeTerminal sends typed data today and reuse that path.

## Needed
Below the mobile breakpoint the composer and side pane use; match what they do, e.g. `max-sm` or a MediaQuery of `(max-width: 639px)`. Desktop is unchanged.
- **View mode by default:** no keyboard, touch-scroll only, so an accidental tap never types into a shell. Tapping the terminal must not focus xterm's textarea in view mode.
- **A Type button** focuses xterm's textarea (that opens the soft keyboard) and switches to typing mode. There's a way back to view mode ("Done"), and blurring the textarea returns to view mode too.
- **An extra-keys bar while typing,** above the keyboard: Esc, Tab, **Ctrl (sticky:** tap once, and the next key is sent as its control character, then Ctrl releases; the active state is shown), Alt (sticky, sending an ESC prefix), the four arrows, `|` `~` `/` `-`.
  - Keys send the right byte sequences: Esc `\x1b`; Tab `\t`; arrows `\x1b[A`/`B`/`C`/`D`, or their application-cursor-mode forms when xterm is in that mode (read xterm's state rather than guessing).
  - Ctrl+letter is the letter's code & 0x1f. Tapping a bar key must NOT blur the textarea (prevent default on pointerdown, or equivalent), or the keyboard closes on every tap.
- **A−/A+ font buttons** change xterm's fontSize within sensible bounds, refit (the fit addon) and send the resize as today.
- **Nice to have:** dedicated Ctrl+C and Ctrl+D keys.
- **Don't** add visualViewport resize handling; the prompt already stays visible above the keyboard, per the user.
- **Accessibility:** every bar key is a real button with an accessible name ("Escape", "Control", "Arrow up"…), and the sticky ones expose `aria-pressed`.

## Tests
- A Playwright mobile spec at 390×844 (in the style of `tests/code-dialogs-mobile.spec.ts`, on the hermetic fake machine used by `tests/code-terminal.spec.ts`), at root AND under `E2E_APP_BASE=/chat`:
  - the terminal opens in view mode (the textarea isn't focused after a tap);
  - Type focuses it and shows the bar;
  - Esc and Ctrl+C reach the machine as the right bytes (the fake machine echoes or records input);
  - sticky Ctrl applies to one key only;
  - an arrow sends the right sequence;
  - A+ increases the font size;
  - Done returns to view mode.
- A desktop check that nothing changed (no bar, typing as before).
- `npm run check` (0 errors); eslint and prettier on the changed files. Run the terminal specs (hermetic and real-machine) at both bases, after an explicit build per base (`APP_BASE='' npm run build`, then `APP_BASE=/chat npm run build`), with `E2E_SKIP_BUILD=1 … --project=chromium`.

## Box rules (mandatory)
- Wrap EVERY heavy command in `timeout -s KILL <secs> flock /tmp/heavy.lock …`, in the foreground.
- Always pass `TEST_MONGODB_URL` to vitest and the `E2E_*` exports to Playwright, on the same command line.
- If `free -m` shows under 1.5 GB available, wait. Pause heavy jobs whenever the orchestrator says so.
- Kill only the processes you start, by recorded PID. Never `pkill -f` with a pattern. Never kill an `opencode serve` whose parent is "Paseo Daemon". Never use port 5199. Write nothing to `/tmp`.
- No sub-agents. Never deploy. No live checks.
- Don't touch sign-in, OIDC or user identity; the terminal's ticket and step-up path is out of scope.
- No new dependencies without asking (Cerea is Apache-2.0).
- **Commits:** as the repo owner identity from git config (never override it), with no `Co-Authored-By` trailer. Before pushing, run `git fetch origin` and check that `git log origin/main..HEAD` lists only your commits. Push the branch; DON'T merge.
- **The disk is tight:** when you're done, delete the worktree's `build/`, `test-results/` and `playwright-report/`.

## Report
Reply with:
- the commits;
- what you built, and the byte sequences per key;
- the test commands and pass counts at both bases;
- screenshot paths under `/home/ubuntu/workspace/reports/screens-terminal-mobile/` (outside the repo; don't commit them): view mode, typing with the bar, and Ctrl active.
