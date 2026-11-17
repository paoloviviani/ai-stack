# 0075 — Tool-calling permission framework: per-tool policy, composer override, conversation grants

- Status: proposed (discussed 2026-09-17; not implemented)
- Date: 2026-09-17

## Context

The web-fetch policies (`ask-domain` / `auto-verified`, built 2026-09-17) failed
in practice within a day. Three compounding causes, all verified against the
live system:

1. **Per-domain approval confused everyone it touched.** `github.com` and
   `raw.githubusercontent.com` are different domains to the policy but the same
   place to the person; the model burned thinking budget on the distinction too.
   Domains do not generalize to any other tool, so the concept was web_fetch-only
   weight.
2. **The setting never saved.** The client store persists through the legacy
   `POST /settings` route, but the field was added only to the v2 settings
   schema; zod stripped it silently and both users' docs stayed empty. The UI
   showed a selection the server never received.
3. **A select dropdown is the wrong control for approvals.** An approval needs
   exactly three buttons — accept once, accept for the conversation, deny —
   not a generic form.

State of the art, checked 2026-09-17: **OpenWebUI** offers Full access vs Ask
for approval per chat (behind an admin experimental flag, off by default); in
approval mode the reply stops at the tool call and an inline card names the
tool, unfolds its exact arguments, and waits for Allow/Deny — deny feeds the
refusal back to the model, several calls are approved one at a time, approval
state persists on the message, and unattended paths (automations, channel
replies) always run full access. **LibreChat** governs approval operator-side
(`toolApproval` config, off by default; ask-by-default for agents with a Code
environment). Nobody does per-domain approval.

## Decision

One framework for model-initiated tool calls with external reach or side
effects. Five points, all agreed with the user:

1. **Gated set: `web_fetch` and MCP tools.** Web search carries its own
   explicit button and stays out. `execute_code` runs client-side in the
   person's own browser — no server side effects, no gate. `ask_user_question`
   is itself a prompt, not a call to gate.
2. **One policy for the whole gated set, in Settings: `always-allow` or
   `manual`.** A single row, not per-tool settings — per-tool configuration
   UI is where a 20-tool server would turn into 20 rows, and nothing in the
   framework needs it. Default is `manual`; the user opts into always-allow
   once, globally. No global deny policy exists: denying a tool entirely is
   done by disabling it where tools are enabled/disabled today.
3. **Chat-local override at composer level.** Resolution per call: chat
   override, else the user's per-tool setting, else the `manual` default.
   Settings hold defaults, a chat holds state — the existing pattern.
4. **Under `manual`, every gated call parks on a dedicated approval card**
   with exactly three buttons: accept once, accept for the conversation, deny
   the call. Deny feeds the refusal back to the model (OpenWebUI behavior);
   several calls in one block queue one at a time rather than refusing the
   second. "For the conversation" grants are recorded per tool (server-
   qualified name for MCP calls), so approving `web_fetch` never blanket-
   approves an MCP writer in the same chat — the granularity lives in the
   grant, not in Settings. Grants live no longer than the conversation (the
   existing `$addToSet` pattern). Unanswered approvals fail closed through
   the existing park deadline — the sweeper denies, never approves; nobody
   watching means no approval, never auto-approval.
5. **The web-fetch-specific machinery is removed**, not extended:
   `webFetchPolicy`, the domain concept, the auto-verified search check, and
   `approvedFetchDomains` all go. The domain idea caused the github/raw
   confusion; the verification check added theater risk for a case the
   approval card now covers directly. (Migration is a no-op in practice: no
   settings doc ever persisted the field — cause 2 above.)

## Consequences

- The MCP call path needs a pre-call checkpoint beside the existing
  post-call elicitation handling; the `fetch-approval` elicitation kind
  generalizes into a tool-approval kind carrying tool name plus unfolded
  arguments (the OpenWebUI card pattern).
- The approval card is its own component, not the generic elicitation form.
- MCP tools change default behavior: today they auto-run; under this decision
  they park under `manual` until the user says otherwise. That is the point
  of the framework, but it is a visible behavior change to call out at
  deploy.
- No per-tool settings UI exists anywhere: one global row in Settings, one
  toggle at the composer, per-tool grants that the user never configures
  directly — they accumulate by tapping "accept for the conversation."
- No "always allow across chats" grant exists beyond the setting itself —
  the setting IS the standing grant. Nothing to audit beyond it.
