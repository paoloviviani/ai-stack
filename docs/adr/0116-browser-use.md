# ADR 0116: Browser use: a `browse` tool backed by a sub-agent, a wrapped browser runtime, and approvals by action class

- Status: accepted 2026-11-12. The owner gave the go; building started 2026-11-12 at 14:00 CET.
- Builds on ADR 0115 (server sandboxes: the later hosted mode), ADR 0097/0099 (Plan · Ask · Allow; delegate and report-back), Cerea #193 (privacy-withheld files).
- Runtime engine decided 2026-11-12 by the evaluation (§7): **Playwright's AI snapshot core, wrapped in our own runtime**.

## Context

`web_fetch` (with the optional headless browser) reads one URL as it loads. Users want an agent that *acts* in a browser: search and filter forms, pagination, multi-step flows, downloads behind buttons, and above all logged-in sites. A user can already expose Playwright MCP through `galopin --connectors-only`, but then:
- every step lands in the main chat context, with full snapshots of thousands of tokens;
- the chat model runs every click itself;
- approvals are per tool, not per kind of action;
- there is no live view away from the laptop.

## Decision

### 1. Where the browser runs (in order)

- **B: on a galopin machine first** (the user's own or a dev server). It uses a persistent profile, the user logs in there by hand, and sessions stay on the user's machine.
- **A: the server sandbox** as an ADR 0115 workload class, later. It is the same runtime in a sandbox image.
- **C: the user's real browser through an extension**, last, if ever.

### 2. The browser runtime: wrapped, not written

A small Node package beside the browser, built on a library chosen by a time-boxed evaluation (§7).

**It exposes one compact protocol as an MCP server**, which the relay already carries:

| Tool | Contract |
|---|---|
| `snapshot()` | pruned accessibility tree of what is visible: interactive elements, headings, short text. Every element has a **stable ref** and the metadata needed to classify actions (role, name, input type, form membership, link target domain). Repetition is collapsed ("… and 37 more rows like this; use extract"). |
| `diff()` | only what changed since the last snapshot (added, removed or changed nodes; URL and title). A full snapshot is sent only after navigation. |
| `act(actions[], approvals?)` | a batch of `click`, `fill`, `select`, `press`, `scroll`, `wait_for`, `navigate`. It auto-waits, stops at the first failure and reports per action. **It refuses a commit-class action (§4) that has no matching approval id.** |
| `extract(schema)` | structured data from the page (JSON Schema). |
| `screenshot(ref?)` | the page or one element (for vision models and approval cards). |
| `download()` | captured files, returned for upload to the attachment store. |
| `screencast`, `input` | phase 2: live view and takeover. |

**Target size:** about 1–1.5k tokens per step in the common case.

### 3. The `browse` tool and its sub-agent (Cerea server)

The chat model sees one tool:
`browse(goal, start_url?, output_schema?, machine?)` returns `{ result, data?, files?, final_url, steps, stopped_reason? }`.

Cerea runs the loop on a **browser model**, an administrator setting called through Pystino with the user's token. The sub-agent:
- has **only** the runtime's tools: no connectors, files or email;
- has budgets for steps, tokens and wall time, and stops with a partial result;
- streams progress into a collapsible chat card;
- returns only the outcome to the chat model.

Page text is marked as untrusted content in the sub-agent's prompt, and it passes through Pystino's privacy pipelines like any tool result.

### 4. Approvals by action class

Cerea classifies each action from the snapshot metadata before calling `act`:
- **read:** navigate within the current site, scroll, extract, open;
- **input:** typing into fields;
- **commit:**
  - submitting a form, or clicking a submit control;
  - clicking a control whose name means pay, buy, order, send, delete, remove, confirm, publish or sign;
  - starting a download;
  - navigating to a new domain.

The classes map onto Plan · Ask · Allow. The defaults: read and input allowed, commit asks. Administrators can add per-site allow- or deny-lists. An approval card shows a screenshot of the element and a plain sentence ("Click 'Pay €120' on shop.example.com") and lands in the Needs-you inbox.

**Defence in depth:** the runtime itself refuses a commit-class action without an approval id that Cerea issued for that exact action.

### 5. Files and privacy

Downloads go to the attachment store, so the privacy pipelines apply and withheld files (#193) stay withheld.

### 6. Phases

1. The runtime on galopin (`galopin browser` manages it and its persistent profile), plus the `browse` tool, sub-agent, approvals and card.
2. Live view and takeover. The agent is paused and receives no snapshots during takeover. Amended 2026-11-12 after studying Open WebUI Computer (`cptr`) and OpenChamber:
   - **Two stream modes over the existing relay:**
     - *watching* uses CDP screencast, which sends frames only when the page repaints and uses almost nothing when idle;
     - *takeover* uses H.264 encoded by WebCodecs inside Chrome (a capture page auto-selected with `--auto-select-tab-capture-source-by-title`), sent as binary WebSocket frames and decoded with WebCodecs onto a canvas, at about 1–2 Mbit/s and 15 fps. It falls back to screencast where WebCodecs isn't available.
   - **Input:** CDP `Input.dispatchMouseEvent`, `dispatchTouchEvent` for phones, and `Input.insertText` for typing (mobile keyboards and IME).
   - **Later, small:** annotations. The user marks an element or area in the live view and sends it to the browse sub-agent.
   - **A banner in the headed window** ("Cerea is using this window · Take over") pauses the agent like takeover does.
   - **Owner UX decisions 2026-11-13:**
     - *Agents:* the machine's browser behaves like the agent terminal. The user opens it on request and browses with it directly (like `cptr`); there is no browse task and no pause.
     - *Chat:* the live view opens when the agent needs the user (an approval, a challenge, a sign-in or a handover). There is no streaming by default.
     - *Everywhere:* the UI always says where the browser runs (the computer's name and the site). Every stream carries the machine, the origin and its kind (chat task, lent tab or agent browser).
     - The scaffolding (stream, input, pause, banner isolation) is built first; the final UI follows once the UX is settled.
3. Replay of known tasks (action caching).
4. The server sandbox class (ADR 0115).

### 7. Runtime evaluation (decides §2's engine)

**Candidates:**
- Stagehand (MIT, TypeScript): observe, act, extract, action caching, CDP;
- Playwright's AI snapshot core (Apache-2.0, as used by Playwright MCP).

**Method:** run both against a local fixture suite and **never external sites**. Fixtures: forms, pagination, a login wall, a prompt-injection page and a long table.

**Measures:** success rate, tokens per step, latency, and whether non-vision models work.

**Hard requirement:** every action can be intercepted before it runs (§4).

**Not adopted:**
- browser-use (Python, owns its own loop): reference only;
- Skyvern: AGPL;
- hosted browser services: against the self-hosted model.

Steel Browser is noted for phase 4.

### 7a. Evaluation result (2026-11-12)

Evaluated on Cerea branch `spike/browser-runtime-eval`, `eval/browser-runtime/REPORT.md`, with 5 local fixtures and 3 models (qwen3-235b non-vision, ministral-8b, gemma-4-31b vision), for about €0.06:

| | Playwright snapshot + our loop | Stagehand 4.4 |
|---|---|---|
| Success | **15/15** (the 8B model included) | 10/15 |
| Prompt / completion tokens | 101k / 1.5k | 204k / 19.3k |
| Wall time | 91 s | 694 s |

**Why Playwright:**
- Stagehand's `act()` cannot be intercepted before it runs, which §4 needs. Its action cache requires Browserbase's cloud.
- Playwright is Apache-2.0, about 20 MB, with no telemetry.
- Refs are stable within a page, and CDP screencast and input work.
- Vision added tokens without improving accuracy.

**Risks:**
- The AI snapshot API is in an alpha line, so the version is pinned.
- `extract` and row collapsing are ours to write. Collapsing cut a 200-row table from about 11.9k to 230 tokens.
- Refs reset on navigation.
- Weak models sometimes emit malformed tool calls, so the loop must recover.
- The injection fixture was weak: a harder one is required before phase 1 is signed off.

## Consequences

- One protocol serves every placement (laptop, dev server, sandbox). The engine behind it can change without touching Cerea.
- The chat context pays one tool call per browse task, not one per click.
- Commit actions need an approval, by default, even under Allow for other tools; an administrator can relax this per site.
