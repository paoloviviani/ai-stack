# Plain-language pass over the interface (2026-10-25)

Branch `feat/plain-language` (Cerea, pushed, no PR). Owner's rule: "It should not be technical as much as possible."
The rules and the term list are in `docs/writing.md`, linked from `AGENTS.md`, so the i18n extraction follows them.
Strings stay inline where they were written; only the words changed.

## Owner requests

- "Provided by this deployment" is now **Built-in** (Workspace → Connectors heading "Built-in connectors (n)", composer menu heading "Built-in", tests updated). Description: "Ready to use for everyone here. Turn one on to use it in your chats; some ask you to sign in first."
- Connector cards no longer change colour with their state. `ServerCardFrame` always draws the neutral card, so a connected connector, a signed-out connector and a `.env` base server look the same. Status colour lives only in the pills (Connected, Not signed in, Problem...). A test pins that the group's cards share one class list.
- The "from .env" pill (admins only, as before) now reads "Set up by the administrator" (the tooltip still names `MCP_SERVERS`). The admin connectors page keeps a technical wording on purpose: "Set in the .env file".

## Glossary decisions

| Technical | Interface says | Notes |
| --- | --- | --- |
| MCP server | connector | "MCP" survives on the admin page and in the add-connector help only. Tab "MCP Servers" is now "Connectors"; "Local connectors" keeps its name. |
| deployment, instance, gateway, Pystino | "here", "this service", "your administrator" | no ordinary page names the gateway product any more. |
| OAuth | sign in | the add form offers "Automatic (recommended) / No sign-in needed / Access key / Sign in with my own app details (advanced)". |
| token, API key | access key | only where needed (the add form, notification set-up) and explained. Context "tokens" are not shown on the project files meter any more, just characters. |
| health check | Check | button and result. |
| elicitation | question | "Your reply is needed", "Question". |
| artifact | file | panel "Files", cards say what they are (Document, Diagram, Web app, Interactive page, Image, Table, Code). |
| system prompt | instructions | "Instructions for every chat", "Original model" for the base model of a custom model. |
| sandbox / Pyodide | "in your browser" | |
| sub-agent, delegate | helper agent / helper | admin page keeps "sub-agent". |
| Code area: machine, device, daemon, enroll, pair | kept | Owner decision: the agent area is for power users and keeps its technical words. Local connectors and "Pair a machine" also stay. |
| Code area: workspace, posture, ceiling, policy | kept | Same reason. |
| agent, session, worktree | kept | agent is the product word; session and worktree are what the thing is. |
| Code area: workspace, posture, ceiling, policy | kept | Same reason. |
| "Request failed (500)", "Failed to ..." | "Something went wrong. Try again." / "Could not ... Try again." | what happened, then what to do. |

## Before to after, the most visible changes

| # | Where | Before | After |
| --- | --- | --- | --- |
| 1 | Workspace → Connectors, group heading | Provided by this deployment (n) | Built-in connectors (n) |
| 2 | same, description | Offered to every account. Turn one on and, where it asks, sign in to it as yourself; they are managed by whoever runs this deployment, not from here. | Ready to use for everyone here. Turn one on to use it in your chats; some ask you to sign in first. |
| 3 | Composer connector menu heading | Provided by this deployment | Built-in |
| 4 | Admin-only pill | from .env | Set up by the administrator |
| 5 | Workspace tab | MCP Servers | Connectors |
| 6 | Workspace tab | Local connectors | Local connectors (unchanged, owner decision) |
| 7 | Connectors page header | Manage MCP servers to extend Cerea with external tools. | Connect Cerea to other apps and services so the assistant can use them. |
| 8 | Add connector form | Authentication / Detect automatically / Token / OAuth — credentials I already have | How to sign in / Automatic (recommended) / Access key / Sign in with my own app details (advanced) |
| 9 | Connector card hint | OAuth / token / no auth | sign-in / access key / no sign-in |
| 10 | Connector status | Error / Unknown | Problem / Not checked |
| 11 | Composer menu | MCP Servers / Manage MCP Servers | Connectors / Manage connectors |
| 12 | Composer pill | MCP (2) | Connectors (2) |
| 13 | Composer pill | Tools auto-approved / Tools ask first | Runs without asking / Asks first |
| 14 | Its tooltip | web_fetch and MCP tools run without asking in this chat. Click to ask again. | The assistant can open web pages and use connectors in this chat without asking. Select to be asked first again. |
| 15 | Web search tooltip | Search the web through this deployment's search backends (this chat only) | Let the assistant search the web (this chat only) |
| 16 | Attach menu | Add image(s) / Fetch from URL | Add images / Add from a web address |
| 17 | Files panel | Artifacts / No artifacts yet | Files / No files yet |
| 18 | Files panel empty state | Things the model makes for this chat — documents, diagrams... land here. Generated files stay available for 30 days, across reloads and devices. | Documents, diagrams, tables, reports and images the assistant makes in this chat show up here. They stay available for 30 days. |
| 19 | Export | Export conversation | Save this chat |
| 20 | Preview errors | Error caught (2) — ask to fix | Problem found (2): ask for a fix |
| 21 | Code block | Run this code in the browser sandbox | Run this code here in your browser |
| 22 | Project section | Context documents | Project files |
| 23 | Project section | Standing instructions / Project memory | Instructions / Project notes |
| 24 | Project files meter | 9,000 of 100,000 characters / ≈ 2,250 tokens | 9,000 of 100,000 characters |
| 25 | Project files warning | Large context makes every message in this project slower and more expensive. | That is a lot to read each time. Replies in this project will be slower and cost more. |
| 26 | Project page | What every chat here is given. In that order. The first three are sent whole... | What every chat here starts with. The first three are read in full every time, so they add to the cost of each reply. The last two are searched... |
| 27 | Project settings | MCPs on by default | Connectors on by default |
| 28 | Knowledge | No embedding model is configured, so documents cannot be indexed yet. | Documents cannot be made searchable yet: no search model is set up. |
| 29 | Knowledge | 3 documents indexed / Reindex | 3 documents ready / Update |
| 30 | Memory | Never keep a password, key or token here: it would ride along in every prompt. | Never keep a password or key here: every chat would see it. |
| 31 | Custom models | Global system prompt / Base model / System prompt | Instructions for every chat / Original model / Instructions |
| 32 | Skills | Valid SKILL.md: YAML frontmatter with name and description, then the procedure as markdown. | A SKILL.md file starts with a header with name and description, then the steps in plain text. |
| 33 | Skills tip | Skills run standard-library Python in the browser — never shell or packages | Skills can run simple Python in your browser. They can't run shell commands or install packages. |
| 34 | Settings | Streaming mode: Smooth stream / Raw stream | How replies appear: Smooth / As it arrives |
| 35 | Settings | Tool approvals: Whether the assistant may call web_fetch and MCP tools... | Asking before acting: Whether the assistant may open web pages and use connectors on its own... |
| 36 | Settings | Install packages from PyPI in code execution | Let code install extra Python packages |
| 37 | Settings | Haptic feedback | Vibration |
| 38 | Errors | Oops, something went wrong. / You have to be logged in. | Something went wrong. Try again. / Please sign in first. |
| 39 | Errors | The request failed (500). | Something went wrong (500). Try again. |
| 40 | Notifications | Push needs a key pair that the operator creates once. | Notifications need a one-time set-up by whoever runs this service. |
| 46 | Delete all dialog | Are you sure you want to delete all conversations? ... This action cannot be undone. | Delete all your chats, including the ones inside projects? This cannot be undone. |
| 47 | Location | ...your location is sent to the model provider with every message. | ...your location is sent along with every message to the company that runs the model. |

## What was left alone on purpose

- Server-side text the model reads (system prompts, tool descriptions), server logs, API error strings that tests or other code match on, the stored "New Chat" placeholder title.
- Code area power-user words kept where they are the thing itself: session, worktree, branch, HEAD, opencode, galopin (in commands), cron.
- `src/routes/settings` was done last and kept small, to merge with `feat/i18n-foundation` (only descriptions and labels on the Application and Usage pages and the one "Delete all chats" button changed; no string moved).

## Checks

- eslint and prettier on every changed file: clean.
- svelte-check: 3 errors, all `pdfjs-dist` not installed in the shared `node_modules` (`src/lib/utils/pdfRender.ts`); none from this change.
- Component tests run for every touched component (48 client test files): all pass except the three files that fail to import for the same missing `pdfjs-dist` reason (ChatWindow, FileArtifactView, PreviewPane); CI has the dependency. Their text assertions were updated by search and are unverified locally.
- `src/lib/utils` and `src/lib/stores` unit tests: pass (759).
- Playwright specs in `tests/` had their text locators updated mechanically (33 files); not run here, CI runs them. Watch for strict-mode label collisions, for example `getByLabel("Instructions")` on the project page.

## After merging feat/i18n-foundation (6a48d0d7)

Settings, Notifications, Location, Usage and the delete-all dialog were taken from main as is, and my wording was written into `messages/en.json` values (32 messages); `messages/en-XA.json` regenerated with `npm run i18n:pseudo`. Not run after the merge: `npm run i18n:check` and the client tests, because the shared `node_modules` has no `@inlang/paraglide-js`. Client tests were green before the merge (45 files, 535 tests); CI must confirm the merged state. Server specs for the touched server messages pass (1169).

Extra changes since the table: server messages people see ("not enabled in this deployment" is now "not turned on here", gateway wording), the connectors summary strip ("1 connector set up"), and "Open" is now "Ready" on a connector with no sign-in.

## Screenshots (phone 390, light)

`reports/screenshots/2026-10-25-plain-language/`: 01-workspace-connectors (tall), 02-composer-connector-menu, 03-settings (tall, taken before the merge), 04-empty-chat, 05-project-page (Settings tab). Taken from a dev server against the hermetic e2e stack, with the connector list stubbed (one own, one admin OAuth connector) plus one `MCP_SERVERS` base server "Web docs".


## Update after owner feedback and CI

- Reverted all Code-area terminology (machine, pair, device, workspace, daemon stay) and the "Local connectors" name; `docs/writing.md` now has a "Kept terms" section saying so. The Code area files, the Local connectors page and the approval and tool cards are back to main's text.
- CI fixes: an extra space I had put in the file card label ("Open file:  x") broke the artifact specs; stale locators updated (Files panel, Limits, Asks first / Runs without asking, Connectors, Instructions made exact to avoid strict-mode collisions with "Instructions for every chat"); prettier on docs/writing.md; "Add image(s)" kept as it was.
- i18n:check, lint, and the whole client project (84 files) pass locally with a real `npm ci`.
