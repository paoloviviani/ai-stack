# SGLang + DeepSeek V4 compliance (2026-11-16)

Read: SGLang main (shallow clone, `python/sglang/srt/...`), SGLang V4 cookbook, DeepSeek thinking-mode doc, Pystino and Cerea source. Nothing run live. Paths below are relative to `srt/entrypoints/openai/` unless noted.

**Headline: no code fix is needed on either side for correctness.** Two config or live-test items matter: thinking is off by default, and `reasoning_effort` low/medium may be rejected.

Key finding: with `--tool-call-parser deepseekv4` and `--reasoning-parser deepseek-v4`, SGLang uses the `dsv4` chat-encoding adapter (`serving_deepseek_recipe.py`). That adapter renders prompts and parses output with the `deepseek-recipe` package, not the Jinja template or the text detectors (`function_call/deepseekv4_detector.py` only supplies the structural tag). I could not install `deepseek-recipe` (denied), so its exact rules are unverified.

| Concern | SGLang behaviour (evidence) | Pystino / Cerea | Verdict |
|---|---|---|---|
| Tool-call deltas | One chunk per call piece (`chat_encoding_adapters.py:354-368`). `id` is set only on the piece that carries `name` (`serving_deepseek_recipe.py:~208`). `index` is always set. `type` defaults to `function`. Parallel calls come as separate indices. | Cerea `runMcpFlow.ts:1160-1170` keys on `index`, sets `id` and `name` only when present, and appends `arguments`. Pystino `recorder.py:104-120` does the same. The redaction slot key is `args:<index>` (`protocols.py:388`). | OK |
| Finish reason | Rewritten to `tool_calls` when calls were seen and the stop was natural (`serving_chat.py:2453-2460`; non-stream `serving_deepseek_recipe.py:~163`). | Cerea records `finish_reason` and acts on `sawToolCall`. | OK |
| Usage | With `include_usage`, a separate final chunk has `choices: []` after the `finish_reason` chunk (`serving_chat.py:2757-2790`). `continuous_usage_stats` is opt-in. `prompt_tokens_details.cached_tokens` appears only if the server runs `--enable-cache-report` (`usage_processor.py:39`). `reasoning_tokens` is reported. | Pystino `generic.py:75` forces `include_usage`. `recorder.py:352` reads `usage` from any frame. Frames with no choices are handled. `cost.py:119-154` reads cached and reasoning tokens. Cerea also sends `include_usage` (`endpointOai.ts:243`, `runMcpFlow.ts:957`). | OK. Cached tokens are missing without `--enable-cache-report`, so billing shows 0 cache reads (operator flag). |
| Reasoning field | `reasoning_content` in deltas (`build_sse_content(reasoning_content=...)`), absent from content-only deltas. Reasoning and content chunks are emitted in order, with tool-call chunks after them. | `REASONING_FIELDS` includes `reasoning_content` (`protocols.py:78`). Cerea reads it (`openAIChatToTextGenerationStream.ts:84`). | OK |
| Thinking toggle | Off by default (`environ.py:1958`, `SGLANG_DEFAULT_THINKING=False`). On only with `chat_template_kwargs: {"thinking": true}` (cookbook). The dsv4 path reads only `thinking`, not `enable_thinking` (`serving_chat.py:3591`). | Neither side sends `chat_template_kwargs`. Cerea has a per-endpoint `extraBody` (`endpointOai.ts:40`), and Pystino passes unknown fields through (`schemas.py:73`, `extra=allow`). | Config. Set Cerea `extraBody={"chat_template_kwargs":{"thinking":true}}` or the server default. |
| Multi-turn reasoning replay | DeepSeek API: with `tools`, `reasoning_content` must be passed back or the API returns 400. Without tools it is ignored. SGLang accepts `reasoning_content` on messages (`protocol.py:842`), and the dsv4 spec owns reasoning history (`chat_encoding.py:68-79`). What the recipe does if it is missing is unverified. | Pystino forwards messages unchanged. Redaction only edits the text (`redaction/http.py:333`). Cerea echoes `reasoning_content` on tool-call assistant messages (`runMcpFlow.ts:1482-1493`) and on replayed turns (`prepareFiles.ts:230,356`). It is on by default, off for gemma only. | OK, and this is the correct behaviour. |
| `strict` on tools | Accepted (`protocol.py:908`). It only adds a structural-tag constraint (`serving_chat.py:1778`). | Cerea sets no `strict`. Pystino passes it through. | OK |
| `parallel_tool_calls` | Accepted, default true (`protocol.py:1091`). | Not sent. | OK |
| `tool_choice` | `auto`, `none`, `required` and named are accepted. | Cerea sends `auto`. | OK |
| `response_format` | Accepted. The recipe does the JSON constraint (`serving_deepseek_recipe.py:JSON_RESPONSE_FORMATS`). | Not sent. | OK |
| `max_tokens` / `max_completion_tokens` | Both accepted (`protocol.py:1055-1061`). | Cerea chooses by the `useCompletionTokens` flag (`endpointOai.ts:245`). | OK |
| `stream_options` | Accepted. Unknown keys are ignored, because the request model is not `extra=forbid`. | Sent as `{include_usage: true}`. | OK |
| `reasoning_effort` | The dsv4 spec requires a named tier. A number raises ValueError (`serving_deepseek_recipe.py:_encode`). The docs list only High and Max. | Cerea sends `low`, `medium` or `high` (`runMcpFlow.ts:844,862`; `endpointOai.ts:253`). | Unverified. `low` and `medium` may give 400. Test live. |
| `cache_control` in parts | Extra keys are ignored by the pydantic part models. | Pystino strips or forwards what the client wrote (`config.py:1881`). Cerea sends none. | OK |
| Image parts | The dsv4 spec renders images via recipe. DSV4 itself is text-only, so this is unverified. | Cerea sends images only when the model is flagged multimodal. | Config: keep the model non-multimodal. |
| `name` on messages | Accepted (`protocol.py:840`). | Not used. | OK |
| Tool message, array content | Accepted by the model (`protocol.py:836`). Recipe handling is unverified. | Cerea sends tool results as strings (`prepareFiles.ts:379`). | OK |
| Assistant `content: null` with `tool_calls` | Turned into `""` (`_null_content_as_empty`). | Cerea sends null on purpose (`runMcpFlow.ts:1480`). | OK |
| Context overflow | `ValueError` becomes HTTP 400 `BadRequest`: "The input (N tokens) is longer than the model's context length (M tokens)." (`tokenizer_manager.py:1419-1427`; `serving_base.py:125`). | Cerea budgets history by estimate (`prepareFiles.ts`) and does not match this text. Pystino relays the 400. | OK, but there is no automatic recovery. |

## Fixes, ranked

1. **Config, high impact:** enable thinking, or users get no reasoning. Use Cerea `extraBody` or the server flag. If you want it everywhere, a Pystino per-model param injection would be the code option, but only if one already exists. I did not check.
2. **Verify, medium:** `reasoning_effort` low and medium on dsv4. If SGLang returns 400, either hide the effort selector for this model in Cerea or map it to `high` or `max` for this provider in a Pystino plugin (`prepare_payload`).
3. **Operator, low:** add `--enable-cache-report` so cached tokens reach billing.
4. No fix is needed for tool deltas, usage-after-finish, `reasoning_content` echo, null content or the `strict` and `parallel_tool_calls` fields.

## Not established, and how to test

Use `$B`, `$K` and `$M` for the user's base URL, key and model.

- **Streaming tool call with usage:**
  `curl -sN $B/v1/chat/completions -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d '{"model":"'$M'","stream":true,"stream_options":{"include_usage":true},"chat_template_kwargs":{"thinking":true},"tools":[{"type":"function","function":{"name":"f","parameters":{"type":"object","properties":{"x":{"type":"string"}}}}}],"messages":[{"role":"user","content":"call f with x=a and f with x=b"}]}'`
  Check: `id` only on the first delta of each index, `finish_reason` is `tool_calls`, and the last frame has `choices: []` and `usage`.
- **Tool loop without `reasoning_content`:** resend that conversation with an assistant message carrying `tool_calls` and no `reasoning_content`, plus a `tool` message. Then repeat with `reasoning_content` set. Compare: 400, or degraded output?
- **Effort:** repeat the first request with `"reasoning_effort":"low"`, `"medium"`, `"high"` and `"max"`.
- **Cached tokens:** send the same long prompt twice (non-stream) and look for `usage.prompt_tokens_details.cached_tokens`.
- **Overflow:** send a prompt above the context limit and look for the 400 text above.
- **Through the gateway:** run the same tool-call request via Pystino, with the usage row and the redaction on.
