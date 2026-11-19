# ADR 0112: Redaction visibility for users (own rules, a log without values, a per-response summary)

- Status: accepted (owner, 2026-11-08)
- Builds on: Pystino ADR 0038 (scoped rules, the fold), ADR 0039 (no default policy), ADR 0059 (restoring and offsets).
  Cerea reads the summary defined here; the two repositories implement it in parallel against the contract below.

## Decision

Users can see what the gateway hid from a provider, and can only ever make it hide more.

### 1. User rules fold in last, and can only tighten

- Each user keeps their own rules: custom patterns (same RE2 engine, validation and limits as admin custom
  patterns) and a stricter mode per entity type (the existing modes).
- The gateway computes the admin effective policy exactly as before, then applies the user's rules as the narrowest
  scope: patterns are unioned; per type the stricter mode wins, with
  `off < anonymise_restore < anonymise < redact < block`.
- A user rule cannot loosen anything: no `off`, no thresholds, no exceptions or allowlists (the request model has no
  such fields and refuses them). A rule that is not stricter than the admin's is inert, and the console says so; a tie
  goes to the admin.
- It applies to requests whose principal is that user: OIDC tokens and the user's own API keys. A user's rules never
  reach another user's requests.
- Stored in `user_redaction_rules` (one row per rule). Workers load them on the resolver's existing ten-second poll,
  so the request path stays query-free. If the engine is `noop` nothing runs, so user rules have nothing to act on;
  the console says so.
- A user's pattern is add-only in overlap resolution too: a pattern span overlapping a detected or administrator span is dropped, so the administrator's span stands whole in its mode.
- A user rule that blocks makes the user's own request fail with the usual 403; that is the mode they asked for.

### 2. The redaction log keeps no values

- For a request where redaction found something, or blocked, the usage row carries `redaction_detail` (JSON): per
  entity type the count, the mode, the deciding rule (id, name, owner `admin|user`) and the sources (`message`,
  `tool_result`; `document` for `/v1/ocr`, where the extracted document is the screened text). Plus `blocked`.
- **Never the original or the matched value, and no character offsets** (offsets into a prompt the user may have
  deleted are not worth a column, and they are a step towards reconstructing the text).
- It lives on the usage row rather than in a new table: it is written by the `begin` insert the request already makes
  (and by the blocked row), so it costs no extra statement, and its retention is the request log's, which is the
  usage row's. (Today that means rows are kept; only the reply text has a sweep.) With accounting disabled there is no
  request log and so no redaction log.
- A request where redaction ran and found nothing leaves no entry; the per-response summary says `applied: false`.
- BYOK: logged, flagged, and visible to the owner only. A user's own-key requests are theirs, so the user view shows
  them; the admin view leaves them out, as every other administrator read of the ledger does.
- `GET /api/me/redaction/events` (the repo's `Page` envelope, filter `request_id`) and an admin view,
  `GET /api/admin/redaction/events`.
- No path writes values anywhere: not this log, not the application log. The test box returns spans (type, offsets,
  rule), never the text, and is not logged.

### 3. The per-response summary (contract with Cerea)

Opt in with request header `x-pystino-redaction-summary: 1`; without it responses are byte for byte unchanged.
With it, `/v1/chat/completions` carries a top-level `pystino_redaction` object: in the JSON body when not streaming,
on the final chunk (the one that carries `usage`, else the last chunk before `[DONE]`) when streaming. No separate
event. Not on `/v1/responses` or `/v1/messages` yet.

```json
{
  "applied": true,
  "request_id": "...",
  "blocked": false,
  "entities": [
    {"type": "PERSON", "count": 2, "mode": "anonymise_restore",
     "rule": {"id": "...", "name": "Cloud providers", "owner": "admin"},
     "sources": ["message", "tool_result"]}
  ],
  "values": [{"type": "PERSON", "original": "Mario Rossi", "placeholder": "<PERSON_AB12CD34EF>"}]
}
```

- Absent when redaction is off for the request (engine `noop`, or no rule applies). `applied: false` with empty
  arrays when redaction ran and found nothing.
- A blocked request is a 403 whose body also carries the object (`blocked: true`) when the header is sent.
- `values` only when the request also sends `x-pystino-redaction-values: 1` AND the caller authenticates with the user's own sign-in: an external IdP access token, or the
  bundled IdP's session token (a key row minted at login, `minted_by` set). Never a standing key
  (`minted_by` null), which a user, group or script may hold. They are put in that one response and never written to a log or database.
- `pystino_cost` is not sent: cost is settled after the response (the ledger write is after the answer), so it is
  not known at that point. Cerea reads cost from `GET /v1/pystino/usage`.

## Consequences

- One more column on `usage_records` (nullable JSON) and one new table; forward-only migration, SQLite-safe.
- The fold gains attribution (`EffectivePolicy.contributors`), used only after detection, for the log and summary.
- A merge of two accounts keeps the surviving account's user rules and drops the merged-away account's.
