# GLiNER as an opt-in redaction engine: spike report (2026-11-08)

Branch: `spike/gliner-engine` (Pystino worktree `~/workspace/Pystino-wt-gliner`), pushed for reference. No PR opened.
All text used is synthetic. Everything below was measured on this box (5 cores, pinned with `taskset`), except the N5105 figures, which are estimates.

## Verdict

**Ship it as an opt-in engine, but position it as the slow, high-recall option, not a spaCy replacement.** Reasons:

- Quality is much better than spaCy md for this use case (recall 0.90 vs 0.49 on the synthetic medical set), and it detects medical conditions, medications and Tessera Sanitaria numbers, which spaCy cannot.
- The weights are **Apache-2.0**, so unlike the Italian spaCy models (CC BY-NC-SA 3.0) it is shippable in the kit. This is a real argument for it independent of speed.
- Latency is the problem: about **10 ms per token on one core here, 4 ms per token on four cores**, against 0.18 ms per token for spaCy md. That is roughly 50 times slower. On the N5105 expect 10-20 ms/token on four cores. A 4,500-token document takes 40-90 s. It is workable for 1-2 users only if redaction is scoped to attachments or new messages and the detection cache does its job.
- int8 quantisation does not work for this model family (see below), so there is no cheap speed-up.
- Memory: fits an 8 GB host only barely, and not safely. It fits a 10-12 GB VM comfortably.

## 1. Licences (checked against the Hub API and model cards, 2026-11-08)

| Artefact | Licence | Notes |
|---|---|---|
| `gliner` Python package 0.2.30 | Apache-2.0 | PyPI metadata |
| `urchade/gliner_multi_pii-v1` | **Apache-2.0** | Multilingual (en, fr, de, es, pt, it). Fine-tuned from `gliner_multi-v2.1` on `urchade/synthetic-pii-ner-mistral-v1` (dataset Apache-2.0). Encoder `microsoft/mdeberta-v3-base` is MIT. 1.16 GB `pytorch_model.bin`, no safetensors. |
| `E3-JSI/gliner-multi-pii-domains-v1` | **Apache-2.0** | Fine-tune of the above on `E3-JSI/synthetic-multi-pii-ner-v1` (MIT). en, fr, de, es, pt, it, sl, el, nl. Has safetensors. Slightly better here. |
| `urchade/gliner_multi-v2.1`, `gliner-community/gliner_*-v2.5` | Apache-2.0 | General NER, not PII-tuned |
| `knowledgator/gliner-pii-{edge,small,base,large}-v1.0` | Apache-2.0 | **English only** per the card; small ONNX int8 files exist, but useless for Italian |
| `knowledgator/gliner-x-{small,base,large}` | Apache-2.0 | Multilingual incl. Italian. mT5 encoder, int8 ONNX published. Needs `stanza` + `langdetect` and runtime downloads of stanza models for tokenising (not offline-friendly) |
| `DeepMount00/GLiNER_PII_ITA` | Apache-2.0 | Italian PII, 1.16 GB, own Italian label set. **Not benchmarked** (training data undocumented) |
| `fastino/gliner2-privacy-filter-PII-multi` | Apache-2.0 | GLiNER2 is a different package (`gliner2`); not tried |
| `onnx-community/gliner_multi_pii-v1` | **no licence field** | Derivative ONNX export of the Apache-2.0 weights. Use only as a reference; for the kit, export ourselves at build time |
| `urchade/gliner_multi` (v1), `gliner_base`, `gliner_small-v1` | **CC-BY-NC-4.0** | Non-commercial: personal use only |
| `nvidia/gliner-PII` | `other` (NVIDIA open model licence) | English only. Not OSI. Do not ship |
| `tknika/gliner2-PII-basque*` | CC-BY-NC-SA-4.0 | Irrelevant, non-commercial |
| Italian spaCy models (`it_core_news_*`) for comparison | CC BY-NC-SA 3.0 | per the existing Dockerfile notice |

Conclusion: `urchade/gliner_multi_pii-v1` and the E3-JSI fine-tune are shippable. Nothing non-commercial is needed.

## 2. What was built

- `REDACTION_NLP_ENGINE=gliner` runs Presidio with a no-op NLP engine plus Presidio's own `GLiNERRecognizer`. All pattern and checksum recognisers stay active, including the Italian ones.
- `REDACTION_GLINER_MODEL` (default `urchade/gliner_multi_pii-v1`), `REDACTION_GLINER_LABELS` (`label` or `label=ENTITY`, comma separated), `REDACTION_GLINER_THRESHOLD` (default 0.5), `REDACTION_GLINER_CHUNK_CHARS` (default 1200), `REDACTION_GLINER_ONNX_FILE` (loads an ONNX file with ONNX Runtime).
- Default label map: person to PERSON; address and city to LOCATION; organization to ORGANIZATION; date of birth to DATE_TIME; health insurance number to HEALTH_INSURANCE_ID; medical condition to MEDICAL_CONDITION; medication to MEDICATION. The three new types are registered as model-backed, so `/healthz` and the gateway's family toggle treat them as NER.
- **Hybrid**: with `REDACTION_NLP_ENGINE=spacy` plus `REDACTION_GLINER_MODEL` set, GLiNER is added next to spaCy and both run on every request.
- One GLiNER model is shared across all configured languages (the checkpoint is multilingual).
- Dockerfile: `--build-arg GLINER_MODEL=... GLINER_REVISION=<sha>` adds CPU PyTorch, `gliner`, the pinned weights and the mdeberta tokenizer files (GLiNER fetches the tokenizer from the base encoder repo, so offline mode would otherwise fail). `HF_HUB_OFFLINE=1` at runtime. Built and run end to end: `/healthz` and `/detect` work.
- Unit tests for label parsing and engine validation pass (45 passed with the existing detector tests); ruff clean. Two mypy errors on `app.py` are in the Presidio typing (`NlpEngine` vs `NoOpNlpEngine`, `AnalyzerEngine` vs the `Analyzer` protocol); I did not check whether they predate the branch.

### Quantisation did not work

The mDeBERTa-based GLiNER collapses under int8:

| Variant | Result |
|---|---|
| `onnx-community` int8, uint8 and quantized files | recall 0.10 overall (every NER entity lost) |
| Our own `onnxruntime` dynamic int8, per-channel, all MatMul | no entities at any threshold |
| Same, attention score matmuls excluded | no entities |
| Same, only the FFN matmuls | no entities |
| `torch.quantization.quantize_dynamic` on `nn.Linear` | no entities |

The fp32 ONNX model reproduces the torch results exactly, but is no faster (9.5 vs 10.2 ms/token on one thread). So the only speed lever is cores. A static int8 with calibration, or a distilled/smaller encoder, would be research work, outside this spike. The 4x smaller `gliner-x-small` int8 ONNX exists but needs the stanza dependency and was not tested for speed.

## 3. Benchmark

Single process, `detector.analyse_one` (no HTTP, no gateway), Italian synthetic prompts of about 56, 313, 1,110 and 4,503 tokens (`\w+|punct` tokens), unique per request, 8 labels. p50 of 12/8/5/3 reps for spaCy, 5/3/2/1 for GLiNER (4,500-token GLiNER rows are a single run). cpu_s is process CPU for one request. Pinned with `taskset`; the ONNX session thread count is forced because ONNX Runtime otherwise ignores `taskset`.

| Engine, threads | 56 tok p50 | 313 tok p50 | 1,110 tok p50 | 4,503 tok p50 | ms/token (large) | cpu_s at 4,500 | RSS loaded | RSS peak |
|---|---|---|---|---|---|---|---|---|
| spaCy md, 1 core | 14 ms | 57 ms | 194 ms | 838 ms | 0.185 | 0.84 | 711 MB | 784 MB |
| spaCy lg, 1 core | 14 ms | 59 ms | 195 ms | 838 ms | 0.185 | 0.84 | 1,278 MB | 1,350 MB |
| GLiNER fp32 torch, 1 core | 816 ms | 3.33 s | 10.97 s | 46.0 s | 10.2 | 45.8 | 2,481 MB | 4,218 MB |
| GLiNER fp32 torch, 4 cores | 366 ms | 1.45 s | 4.59 s | 18.8 s | 4.18 | 68.0 | 2,482 MB | 4,218 MB |
| GLiNER fp32 ONNX, 1 thread | 627 ms | 2.98 s | 10.13 s | 42.6 s | 9.5 | 42.5 | 2,927 MB | 3,953 MB |
| GLiNER fp32 ONNX, 4 threads | 236 ms | 1.16 s | 4.15 s | 17.3 s | 3.8 | 65.5 | 2,934 MB | 3,956 MB |
| Hybrid spaCy md + GLiNER (medical labels only), 1 core | 858 ms | 3.46 s | 11.27 s | 47.3 s | 10.5 | 47.3 | 2,941 MB | 4,444 MB |

Notes:

- spaCy md and lg have the same latency here. The cost of the spaCy path is Presidio's pattern recognisers, not the model, so md saves memory (about 570 MB) but not time. (Our spaCy figure of 0.185 ms/token is higher than the 0.116 in docs/performance.md, which was measured through the gateway on all cores with a different token count; the ratio to GLiNER is what matters.)
- Fewer labels did not help: the hybrid with 3 labels is as slow as the 8-label run. The encoder dominates.
- Four threads give only a 2.4-2.7x speed-up and cost about 1.5x the CPU-seconds.
- Load time: 6 s for spaCy md, about 18-20 s for GLiNER. RSS **peak 4.2 GB at load** (the `.bin` pickle is read in full, then copied); steady state about 2.5 GB. The container reads 2.3 GiB idle and 2.33 GiB after a request; cgroup peak was 4.28 GB. A safetensors checkpoint (E3-JSI has one) would probably lower the load peak; not measured.
- Image size (`docker images`, SPACY_MODELS `en_core_web_md it_core_news_md`): **1.27 GB without GLiNER, 4.81 GB with it.** Net payload is about 2.1 GB (torch 809 MB, transformers, onnxruntime, weights 1.1 GB); the rest looks like layer duplication from the `COPY --chown` of the venv, which could be trimmed.

### N5105 estimate (assumption stated)

Assumption: the N5105 (Tremont core, 4 cores, no AVX2) runs at **0.4-0.5x of one of this box's cores**. It has no AVX or AVX2, so dense fp32 matrix work is probably worse than that ratio, 0.25-0.35x, and I could not measure that: forcing `ATEN_CPU_CAPABILITY=default MKL_ENABLE_INSTRUCTIONS=SSE4_2 ONEDNN_MAX_CPU_ISA=SSE41` here only cost 17%, which probably does not emulate the hardware. Treat the pessimistic column as a guess.

| Prompt | spaCy md (1 core) | GLiNER 4 cores, optimistic (0.45x) | GLiNER 4 cores, pessimistic (0.3x) |
|---|---|---|---|
| about 300 tokens | 130 ms | 3.2 s | 4.8 s |
| about 1,100 tokens | 430 ms | 10 s | 15 s |
| about 4,500 tokens (a long PDF) | 1.9 s | 42 s | 63 s |

On the whole box a 10-page PDF of roughly 6,000 tokens would take 1-1.5 minutes of all four cores, during which the other services on the box are starved. This is acceptable for a one-off document upload, painful for chat, and the opposite of free.

## 4. Quality

30 synthetic sentences (28 Italian, 2-3 English), 69 gold spans: names with compound surnames and De/Di/Da/Lo prefixes, "Dott.ssa"/"Prof." titles, addresses, dates of birth and visit dates, valid-checksum fiscal codes, 20-digit Tessera Sanitaria numbers, diagnoses, drugs with dosages, hospitals, departments and ASLs. Score threshold 0.5 for all engines. A gold span counts as caught if any predicted span of the same type overlaps it (a boundary-exact count is in the JSON files). A prediction is a false positive if it overlaps no gold span of its type. All DATE_TIME gold spans are included, not only dates of birth. Set sizes per type (6-15) are small: read differences under about 0.15 as noise.

Cells are recall / precision (gold count in the header).

| Type | spaCy md | GLiNER urchade pii-v1 | GLiNER E3-JSI | Hybrid (md + urchade medical labels) |
|---|---|---|---|---|
| PERSON (15) | 0.93 / 0.76 | 1.00 / 0.79 | 1.00 / 0.88 | 1.00 / 0.62 |
| LOCATION (10) | 1.00 / 0.61 | 0.70 / 1.00 | 0.90 / 1.00 | 1.00 / 0.61 |
| ORGANIZATION (12) | 0.25 / 0.75 | 0.92 / 1.00 | 0.83 / 1.00 | 0.92 / 0.92 |
| DATE_TIME (6) | 0.50 / 1.00 | 0.67 / 1.00 | 0.67 / 1.00 | 0.67 / 1.00 |
| IT_FISCAL_CODE (4) | 1.00 / 1.00 | 1.00 / 1.00 | 1.00 / 1.00 | 1.00 / 1.00 |
| HEALTH_INSURANCE_ID (2) | 0.00 / - | 1.00 / 1.00 | 1.00 / 1.00 | 1.00 / 1.00 |
| MEDICAL_CONDITION (10) | 0.00 / - | 1.00 / 0.77 | 0.90 / 0.69 | 1.00 / 0.77 |
| MEDICATION (10) | 0.00 / - | 0.90 / 1.00 | 0.90 / 1.00 | 0.90 / 1.00 |
| **Total (69)** | **0.49 / 0.73** | **0.90 / 0.90** | **0.90 / 0.92** | **0.94 / 0.76** |

`knowledgator/gliner-x-small` (mT5, needs stanza; its stanza Italian model failed to load and it fell back) got 0.86 / 0.82, with Tessera missed and 12 medical false positives. Not a good candidate.

Notable misses and false positives:

- **spaCy md**: hospitals tagged as LOCATION instead of ORGANIZATION; "Gentile" (greeting), "Eseguito" (verb), "Neurologia" and "Tessera" tagged as PERSON/LOCATION; fiscal codes also returned as LOCATION/PERSON/ORGANIZATION (a trailing full stop swallowed into the span); "Vittorio Emanuele II" as a PERSON (street name); and no medical content at all. Misses "3 novembre 2025" (Italian month names are not handled by the date pattern) and "Mr John Smith".
- **GLiNER (urchade)**: false positives are mostly common words, not verbs: "paziente", "Il paziente", "He", "Gentile collega" as PERSON (these are harmless over-redaction, but they will make redacted text read oddly and cost placeholder quality), and "Ecografia addominale" and "dolore toracico" as MEDICAL_CONDITION. Part of the medical precision loss is my gold set not labelling symptoms: "dolore toracico" is arguably a correct hit. Misses: "Roma", "Parma" typed as ORGANIZATION (redacted but with the wrong type; this is why LOCATION recall is 0.70), "Firenze" missed, "Diabetologia" (department) missed, "penicillina" typed as MEDICAL_CONDITION, dates with month names ("3 novembre 2025", "2 October 2025") missed because the only date label is "date of birth". Adding a plain "date" label would likely fix this, not tested. Names with De/Di/Da/Lo prefixes were all caught, with exact boundaries.
- Only drugs with a generic name were used; brand names and dosage spans were not tested separately (dosages stayed outside the gold span).

Per-run details are in `services/redaction/spike/quality-*.json` and `bench-*.json` on the branch.

## 5. Memory fit

Baseline from the earlier estimate: about 5.5 GB idle with spaCy md and Gotenberg (no local embedder). The redaction service is part of that figure at about 0.7-0.9 GB (spaCy md en+it).

| Configuration | Redaction service steady | Whole stack idle (estimate) | Transient at startup |
|---|---|---|---|
| spaCy md (baseline) | about 0.8 GB | 5.5 GB | about 0.9 GB |
| GLiNER fp32, replacing spaCy | about 2.4 GB (container reads 2.3 GiB) | **about 7.1 GB** | **4.2-4.3 GB**, so about 8.9 GB peak |
| spaCy md + GLiNER side by side | about 3.0 GB | **about 7.7 GB** | 4.4 GB, so about 9.2 GB peak |

- **8 GB host**: GLiNER alone leaves under 1 GB headroom with a 8.9 GB startup peak. It would swap or OOM-kill at startup unless the host has swap and the other services are stopped or not yet started. Not recommended. The side-by-side setup does not fit at all.
- **10-12 GB VM**: GLiNER alone fits with 3 GB or more spare; the side-by-side hybrid fits with 2.3-4.3 GB spare. Startup peak is fine if services start in sequence. Activation memory per request is small (RSS grew only 20-150 MB across a 4,500-token request).
- The VM has 4 cores; a single long redaction pass with four threads takes the whole machine.

## 6. Options at 10-12 GB

- **GLiNER alone** (recommended if the opt-in ships): best precision for names (0.79-0.88) and the right types for hospitals, drugs and conditions. It misses some city names (Roma/Parma tagged as organisations) and month-name dates; pattern recognisers can complement the latter.
- **spaCy md + GLiNER medical labels** (hybrid): highest recall (0.94) but spaCy's false positives stay (PERSON precision 0.62, LOCATION 0.61), and it costs about 0.5 GB for little extra recall: GLiNER alone already gets 1.00 on persons. Use it only if cities matter more than precision. A better hybrid is probably GLiNER for people/organisations/medical and a cheap city gazetteer, not tried.
- **Larger GLiNER**: only `gliner_multi*` is multilingual and the family has only the one mdeberta-base size for Italian; `gliner_large-v2.1` and knowledgator `large` are English. Nothing larger to try for Italian within an Apache-2.0 constraint, and a larger encoder would be proportionally slower. Not evaluated.

## 7. What productising would take

1. **Config and code**: the engine selection, labels, threshold and chunk size env vars already exist on the branch. Still to do: `REDACTION_GLINER_LABELS` validation (a typo currently becomes a new entity type), a `date` label default, and a warning when the engine is `gliner` and a chunk exceeds the model's 384-word window. Consider a request-time guard (maximum characters per request, or return early for very long texts) because a 4,500-token request ties up all four cores for 20-60 s on the VM, and the service handles one batch at a time per thread pool.
2. **Gateway side**: confirm that the console's entity list and policies handle the three new types (`HEALTH_INSURANCE_ID`, `MEDICAL_CONDITION`, `MEDICATION`) as plain strings. Not checked in this spike.
3. **Scoping**: the economics only work if redaction is scoped (documents only, or user-selected conversations), because the detection cost is paid for every uncached token. docs/redaction.md already describes scoping; add a GLiNER section recommending it, with the numbers above.
4. **Tests**: config parsing tests exist. Add a model-gated integration test (skipped without the weights, in line with how the spaCy models are handled) that runs three or four of the synthetic sentences, and a Dockerfile smoke test in CI for the build arg.
5. **Image**: 4.8 GB with GLiNER (1.27 GB without). Reduce by dropping `onnxruntime` and `sympy` from the image if ONNX stays unused, avoiding the duplicated venv layer, and switching to a safetensors checkpoint (E3-JSI has one; the urchade `.bin` also drives the 4.2 GB load peak). Pin both the model and the tokenizer base by revision; the spike pins the model only.
6. **Kit**: a `build.sh` option such as `REDACTION_ENGINE=gliner` mapping to the Docker build arg, plus the compose environment variables, a default memory limit (about 5 GB to leave room for the load peak) and a `start_period` of at least 120 s in the health check (already 120 s). Add docs for the 8 GB versus 10-12 GB guidance. A pin bump in the Cerea kit is required for it to reach users (per the release chain).
7. **Docs**: `docs/redaction.md` engine section, `docs/performance.md` table, the licence table above, and ADR 0026's list of pluggable engines (the ADR file is not in the repository's `docs/adr` directory in this checkout, so I could not read or update it).
8. **Open question, cheap to try next**: whether a smaller multilingual GLiNER (e.g. a distilled or `gliner_small` multilingual with safetensors) at 2-3x the speed keeps most of the quality; none exists under Apache-2.0 for Italian that I found, besides `gliner-x-small` with its stanza dependency. Also whether `DeepMount00/GLiNER_PII_ITA` is better on Italian.

## 8. Caveats

- 30 sentences, one author, synthetic, labelled by me; precision depends on what I chose to label (symptoms, departments).
- Timings are detector-only (no gateway, no HTTP), on pinned cores of this shared box while other jobs were running at low load; N5105 numbers are extrapolated, not measured, and the AVX question could shift them by 1.5x.
- Single-run 4,500-token GLiNER figures; the 1,100-token rows had two reps.
