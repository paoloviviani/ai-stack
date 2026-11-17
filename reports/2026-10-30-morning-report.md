# Morning report — 2026-10-30

Overnight, both releases went out, each change reviewed by Opus before merge. Everything was verified after release.

## Released

| | Version | Verified |
|---|---|---|
| Pystino | **0.20.0** (tag `1b16dca`) | ci green on the release commit, images built, anonymous pull of gateway + redaction, stack test on the tag |
| Cerea | **0.33.0** (tag = `stable` = main `a2b211771`) | contract check against gateway 0.20.0, ci + kit green, fresh-kit `E2E_OK`, kit pins Cerea 0.33.0 / Pystino 0.20.0, contract pin 0.20.0, GitHub release published |

**To update the live box:** `cd ~/cerea/kit && git pull && docker compose pull && docker compose up -d`. No new settings are needed.

On its first start, 0.33.0 builds a text index over the conversations in the background. Until it is ready, `/chats` search matches titles only.

## What's in it

**Pystino 0.20.0: redaction now works through tools and reasoning**

- **Restoring placeholders in responses.** Placeholders are now restored in the assistant's reasoning text, in tool-call arguments (with JSON escaping) and on all three APIs (chat, Responses, Anthropic Messages), streamed and not.
  - Two of these were previously not restored at all: answers sent as a list of parts (Mistral style), and Responses API replies when not streamed.
  - Signed Anthropic thinking blocks are left untouched on purpose.
- **Screening on the way in.** What a follow-up request sends back is screened again before it reaches the provider: tool arguments, reasoning and tool results on all APIs, plus the Responses `instructions` field. A value caught once is replaced everywhere in the request.
- **Telling the model about placeholders.** The gateway adds a system note explaining what placeholders are, but only while a redaction rule is in force.
  - The note depends only on the policy, so it is byte-identical on every turn and doesn't break prompt caching.
  - It goes at the end of the system prompt; for Anthropic, as a separate final block.
- **Same-length placeholders** (`#K3QF…#`), as a per-entity option for fixed-width form fields.
  - Values under 8 characters fall back to the usual placeholder.
- **New setting `restore_in_tool_arguments`:** on by default, and only in effect when restore is on.

**Cerea 0.33.0**

- **File versions follow the conversation branch.**
  - After you edit a prompt or regenerate a reply, the doc tools and the sandbox no longer see files produced on the other branch.
  - Re-sending an attachment makes it current again.
  - While a reply streams, the sandbox identifies the turn by its generation ID.
- **The sandbox sees conversation files again,** with branch-correct swapping and release of mounted files.
- **Scanned PDFs:**
  - `doc_outline` reports a scan's tilt (`skew_deg`) and its blank lines (`rules`);
  - `place_text` gains `along`, `rotate` and `fit`;
  - `look_doc` gains `grid` and `region`.

  The worker estimates a scanned form now takes about 4–6 tool calls, down from 28. Decoding of very large embedded images is capped.
- **`fill_form` fits the text to the field's height,** and reports a value as clipped when it can't fit.
- **The PDF rules:** the doc tools come first. As a fallback, the sandbox may draw an overlay saved under the same name as the next version, for things the tools can't do. Signed PDFs, rebuilding a form and flattening when not asked are still forbidden. The wording no longer contradicts itself.
- **`/chats` searches message text,** not just titles:
  - a per-user text index;
  - whole words and quoted phrases;
  - highlighted snippets;
  - title-only search for visitors without an account.

  The search box stays pinned while the list scrolls.
- **Projects:**
  - the settings page is one column, grouped in the order the assistant reads things, with a section index on wide screens;
  - it is built from reusable `src/lib/components/settings/` components, meant to become the pattern for other settings pages;
  - clicking a project in the sidebar opens its chats.

## What the reviews caught (all fixed before merge)

- **Pystino, first review: blocker.** Restoring arguments and reasoning would have sent real values back to the provider on the next request in the same turn, because those echoed fields were never screened. Also fixed:
  - invalid JSON from unescaping;
  - escaped placeholders split across chunks not being restored;
  - two tool calls merging when the provider omits `index`.
- **Pystino, second review.**
  - A regression when only the first fragment of a tool call carries `index`.
  - `instructions` counted twice in the token estimate.
  - Plus the "value caught once is replaced everywhere" hardening.
- **Cerea forms and branch batch.**
  - The sandbox used the wrong branch while a turn streamed.
  - A changed attachment was never swapped in.
  - Memory use when decoding scans was unbounded.
  - The PDF guidance contradicted itself in five places.
- **Content search: blocker (performance, not privacy).** The text index had no user prefix, so every search scanned all users' chats. It is now a per-user compound index; the old one never shipped. Also fixed: the sort's memory limit and an unbounded snippet budget.
- **Projects.** A sideways-scroll bug, focus moves for the settings index, and Enter-to-save on two fields. These small fixes were made by me.

## Please check

1. **The fiscal-code test on the live box, after updating:** attach the form and ask "compila il campo con il mio CF RSSMRA80A01F205X".
   - **Expected:** the assistant uses the value, the PDF field holds the real code, and the reply shows the real code.
   - **Why it matters:** the original "placeholder visible in the answer" bug was never reproduced locally. The best explanation is "answer sent as a list of parts", which is now fixed, but only your instance can confirm it.
2. **A quick look at the project settings page and `/chats`.** The worker could not take screenshots, so the layout is verified only by component and e2e geometry tests.

## Open / next

- **Chat schedules (#51):** a worker started after the releases, on branch `feat/chat-schedules`. It gets an Opus review before merge, and there is no release until you say so.
- **Clicking a search result** opens the conversation, not the exact message. The message ID is already returned, so jumping to the message can come later.
- **Settings index:** no highlight for the active section.
- **Flaky tests:**
  - `chat-artifact-table` (the CSV download assertion) failed once on a branch run and passed on re-run;
  - the admin MCP page client test also failed once.

  Both are on top of C57.
- **The box's Node** is still v24.21.0, which lacks the CVE fix. No worker is running now: `nvm install 24.22.1 && nvm alias default 24.22.1`.
- **Backlog:** C58 (HTML artifact errors after a live preview) and C59 (parked: chat → /code bridge).

## Decision needed: how chat schedules get a gateway key

The Opus review of `feat/chat-schedules` found that my plan in #51 was wrong. I wrote that "the gateway needs no change", but:

- Pystino has no `/v1/me/keys`. Minting is `POST /api/me/keys`, which only accepts the **console session cookie**. That is the deliberate "key-mint wall": no bearer client can mint a key.
- So on a real deployment, no chat schedule can be created. The tests mocked the endpoint, which is why nothing caught it.

The branch is **not merged**. The worker is fixing the review's other items, none of which need this decision:

- unattended runs never use approval-gated tools, even under "always allow";
- keys expire after 180 days;
- account erasure and merge revoke keys;
- only a 401 counts as a dead key;
- races and pending revocations;
- project access is re-checked on every run;
- the `schedule` tool goes through the same gates as the API;
- late failures count.

The options for the key are below; this is your call.

1. **Pystino: a narrow bearer endpoint for Cerea** (recommended). For example, `POST /v1/me/schedule-keys`, with these limits:
   - it accepts the user's IdP access token;
   - it mints only keys that are chat-scoped, have a mandatory expiry (≤180 days), are tagged "minted by Cerea for schedule X", and are listed and revocable in the console;
   - it is rate-limited and audited;
   - an admin can switch it off.

   This widens the wall a little: a stolen access token, which is short-lived, could mint a long-lived key. The scope, expiry and audit limit that risk.
2. **The user mints a key in the console and pastes it into the schedule.** The wall stays intact, but every schedule needs a manual step.
3. **OIDC refresh tokens** (`offline_access`), which Authelia supports. This was rejected earlier because it varies by IdP.

The public issue #51 still says "the gateway needs no change". Once you've chosen, I'll correct it with a comment.

**Update:** review items 2–11 are fixed on `feat/chat-schedules` (head `c13aa5e90`, full CI `41003207651` green). The branch now waits only on the key decision above. Once that's made, the key client (isolated in `gatewayKeys.ts`) gets adapted, and the branch gets a final Opus pass before merge.
