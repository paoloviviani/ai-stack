# 0083 — OCR is one shape across Pystino, Mistral and Cortecs; a gateway-less chat calls it directly

- Status: accepted, built
- Date: 2026-09-19
- Amends [0055](0055-ocr-surface.md), whose surface is unchanged but whose
  `pages` field now accepts a second form, and whose `usage_info.credits`
  question is answered here — by declining to read it, on the record.
- Related: [0082](0082-satellite-and-generic-profiles.md) (the generic profile,
  which without this decision cannot read a document at all),
  [0070](0070-the-vector-store-belongs-to-the-chat.md) (the knowledge pipeline
  that consumes extraction), [0053](0053-model-pricing-sources.md) (where a
  billing figure is allowed to come from).

## Context

`POST /v1/ocr` is the one Pystino-specific limb in the chat's request path.
Everything else the chat needs from a gateway is either standard OpenAI shape
(`/v1/chat/completions`, `/v1/embeddings`) or degrades gracefully when absent
(the usage tab hides itself). Extraction does not degrade gracefully: without
it an attached PDF arrives with no text, `preprocessMessages` puts "no readable
text" in its place, and knowledge ingestion cannot read documents at all.

0082 introduced a profile with no gateway anywhere. That made the question
urgent rather than theoretical: either a gateway-less chat reads documents some
other way, or it is a chat that cannot read a PDF.

The obvious fear was that reading documents elsewhere means writing an adapter
per vendor. It does not. Mistral and Cortecs both serve `POST {base}/v1/ocr`
with the same body and the same response, and Pystino's surface was
deliberately built to that shape in 0055 — its Cortecs path is a verbatim
forward with the model name swapped, because no translation was ever needed.
The three already agree.

## Decision

### The shape, stated explicitly so it can be relied on

```json
// request
{"model": "<string>",
 "document": {"type": "document_url | image_url",
              "document_url?": "<https: or data: URI>",
              "image_url?":    "<https: or data: URI>"},
 "pages?": [0, 1] | "0-5",
 "include_image_base64?": false}
// response
{"pages": [{"index": 0, "markdown": "<string>"}],
 "model": "<echo>", "usage_info": {"pages_processed": 1}}
```

Unknown request fields forward upstream; unknown response fields are ignored or
proxied verbatim. Both were already true of Pystino (`extra="allow"`), which is
how Cortecs' router knobs reach it today.

### Three changes on the gateway, to meet the rest of that shape

**`pages` accepts an inclusive range string** (`"0-5"`) as well as a list, which
is what Mistral and Cortecs both document. This was not only a compatibility
gap: the quota reservation called `len()` on the field, so a range string
reserved one page per *character* — `"0-100"` reserved 7 pages for 101. The
count is now parsed at the schema boundary, and a malformed or reversed range is
refused there with a plain message instead of becoming arithmetic nobody
questions.

**`include_image_base64` is declared** rather than riding through on
`extra="allow"`. The local extractor accepts it and always answers with no
images: a known behaviour is worth more than a silently ignored field.

**`usage_info.credits` is explicitly never read.** Cortecs reports it on OCR
responses. Credits are not money, and no published rate says what one is worth —
folding it into `TokenCounts` would hand `compute_cost` a number it multiplies
by a EUR rate, producing a wrong invoice that looks precise. Billing on this
surface stays on `pages_processed` alone. This makes explicit, with its reason,
what was previously an absence; if a verified credit-to-currency rate ever
appears it belongs on `ReportedCost`, not in this reader.

### In the chat: an env-configured endpoint, for the profile that has no gateway

`CHAT_OCR_BASE_URL` and `CHAT_OCR_API_KEY` join the existing `CHAT_OCR_MODEL`.
When a base URL is set the chat posts to `{base}/ocr` directly with the shared
key as a bearer; when it is not, nothing changes and extraction goes through the
gateway with the signed-in person's own token exactly as before. The request and
response handling are the same code: there is no second protocol, only a second
destination.

Four decisions inside that, each of which could reasonably have gone the other
way:

- **A configured endpoint overrides a resolved gateway model**, rather than
  serving as a fallback behind it. On `generic` there is no catalogue to resolve
  against so the question never arises; the case that decides it is a hybrid box
  with both, where an operator who names an endpoint means it.
- **A base URL requires a model name, enforced at boot.** There is no catalogue
  to discover a reader from, so the two are meaningless apart. The server
  refuses to start rather than failing at somebody's first upload.
- **Direct mode reads PDFs only.** Our allowlist is much broader — doc, xls,
  ppt, odt, epub — but neither vendor's published schema documents Office
  formats, and OpenWebUI, which ships the same integration, sends only PDFs and
  routes everything else to loaders we do not have. An unsupported type gets the
  existing spelled-out 422, never a silent empty result.
- **A 10 MB ceiling, which is not a new number** — it is the chat-attachment
  limit already enforced elsewhere. It does real work here: knowledge uploads
  allow 20 MB, and a 20 MB PDF base64-encodes into a ~27 MB JSON body that
  nobody has ever sent to these vendors. Better our own actionable message than
  an opaque 413.

The `data:` URI posture stays the default, as 0055 set it. The honest version of
why, in direct mode: the URL form has the *provider* fetch the document, so the
deployment never holds it; sending bytes means we choose what is sent. In direct
mode the bytes reach a third party either way — what is preserved is the choice,
not the locality.

## Consequences

- **The generic profile can read documents**, which closes the last functional
  gap 0082 left open. It needs a second vendor and a second bill, which is why
  the installer offers it rather than assuming it.
- **Pystino keeps a Mistral-compatible face.** A client written against Mistral
  works against Pystino unchanged — including the range form, which it did not
  before.
- **Error envelopes are undocumented on both vendors** (their OpenAPI documents
  show only 200s), and Cortecs' OCR is labelled BETA with no versioning policy.
  The direct client parses failures defensively and degrades to the existing
  "reader could not be reached" path with the status preserved.

## Verified

The gateway changes carry tests for each case: list-form `pages`, range-string
`pages` reserving the true count, a malformed range, `include_image_base64`
accepted, and a Cortecs-shaped response whose `credits` do not move the cost.
The chat's direct path carries 16 new tests — boot validation, routing and
override, PDF-only rejection, the size guard, a quoted vendor error, a malformed
error body, a network failure, an unparseable 200, and an empty-text response —
with the file at 20/20 and `npm run check` clean.

**What is not verified: no live call was made to Mistral or to Cortecs.** We
hold no key for either. Conformance rests entirely on their published schemas
and on OpenWebUI's precedent for the PDF-only decision. The first real call
against either vendor is the test this has not had — and it is also the thing
that would settle whether Office formats are genuinely unsupported or merely
undocumented.
