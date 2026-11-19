# ADR 0119: Large content reaches the model as a file it reads with code

- Status: **accepted** (owner 2026-11-15); shipped in Cerea v0.54.0 (C138): large text reaches the model as a file it reads with code. Supersedes this ADR's first draft (pre-flight card plus coded chunking), which was dropped.

## Context

A large text attachment, extracted document text or paste was inlined whole into the prompt. 20 MB of JSON (millions of tokens) overflows any model. Providers refuse such requests without charging, and the refusal is clear, but the content is still unusable. Attachments are already available to code at `/mnt/data/<name>`.

## Decision

- **Estimate, no parsing:** characters ÷ 4.
- **Pointer instead of inline:** content above **25% of the model's context window** is not inlined, largest first. The model gets:
  - the name, size and line count;
  - a sample (head ~3k characters, tail ~500);
  - a note that the full content is at `/mnt/data/<name>`, to be read with code as far as needed.
- **Structured data** is filtered or queried with code, never printed whole.
- **Prose that must be read in full:** the note tells the model to ask the user first. If they agree, the model splits the content with code and runs sub-agents in sequence, each with the user's instruction, the running notes and its chunk. The strategy is prompted, not coded.
- **No code available:** sample plus a plain statement that the content is too large for this model; never silent truncation.
- **No setting, no new UI.**

## Consequences

- Big data files become usable; tokens are spent only on what the code reads.
- The behaviour depends on code execution being available; without it the user gets a clear limit message.
