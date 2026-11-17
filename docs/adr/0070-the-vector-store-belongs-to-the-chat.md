# 70. The vector store belongs to the chat

Date: 2026-09-12

## Status

Accepted. Supersedes the *placement* decided in
[ADR 0062](0062-knowledge-bases.md) — knowledge bases move from the gateway to
the chat — and keeps 0062's decisions that were never about placement: the
document-to-passage pipeline (markdown-aware chunking, heading paths, overlap),
retrieval as a per-base search with the reader's authorisation, and
reindexing as the feature that makes a configurable embedding model honest.

## Context

ADR 0062 placed the whole knowledge pipeline in the gateway: files, extraction,
chunking, embeddings, the vector store and its retrieval, behind
`/v1/vector_stores/…`. That put the *store* — the corpus, its chunks, its
vectors, and the right to read them — in the same component that meters and
bills inference. It worked, and the chat consumed it through its forwarder.

Two things were wrong with the placement, and both got worse as the chat grew
its own features around retrieval (project memory, agent knowledge):

1. **Ownership.** The store holds the user's documents and their transcripts.
   That is application data, not platform plumbing: it has the chat's users'
   ids on it, it is shared in the chat's vocabulary, its retrieval happens
   inside the chat's generation, and its admin screen lives in the chat. Every
   one of those crossings cost a proxy, an allowlist entry, and a second
   place to reason about authorisation. The gateway was keeping a database on
   behalf of an application that could not touch it directly.

2. **The gateway's actual job.** What the pipeline genuinely needs from the
   gateway is two *inference* services, and nothing else: an embedding model
   endpoint, and a document-reading service. Both are metered, priced,
   catalogue-managed — gateway work by every ADR so far. Chunking, storing,
   ranking and sharing are not.

A move is cheap now and will not stay cheap: the deployment's knowledge tables
are empty, so there is nothing to migrate.

## Decision

The chat owns the vector store.

- **Chat side.** The pipeline — file storage, extraction calls, chunking,
  embedding calls, persistence, retrieval, sharing, reindexing — lives in the
  chat. The store is pgvector in a Postgres database the chat owns (a separate
  `chat` database from the gateway's), reached with the chat's own
  credentials. Bases, documents and their status live in the chat's Mongo;
  only passages and vectors live in Postgres, because ranking is a
  database query and that database should hold nothing but ranking.

- **Gateway side.** The gateway keeps what the pipeline consumes and drops the
  rest:
  - `POST /v1/embeddings` — embedding models, catalogue-managed, metered and
    billed to the caller. This is the endpoint the user asked for by name.
  - `POST /v1/ocr` and the extractor — document *reading*, priced per page,
    unchanged. Reading a PDF is inference on a file; it is not storage.
  - The `/v1/vector_stores/…` and `/v1/files` surfaces, the knowledge package,
    the knowledge tables and `GATEWAY_KNOWLEDGE__ENABLED` are removed. The
    gateway no longer stores documents or vectors.

- **Embedding calls carry the acting user's token.** As 0062 decided for
  retrieval, embedding the query and the chunks is metered to a person. The
  chat sends the acting user's OIDC token to `/v1/embeddings`: indexing spend
  lands on the person whose document is being indexed, and a search's query
  embedding on whoever asked — visible in the ledger, never a hidden cost on
  a shared base's owner. The chat holds no other credential, by design.

- **Sharing moves with the store.** A base's shares live beside it, in the
  chat: owner, per-user shares resolved by email against the chat's own
  users, and per-group shares checked against the caller's groups — a fact
  the gateway already answers in `/v1/me` (ADR 0069). The reach check is
  unchanged in kind: unreachable bases are 404, read-only edits are 403.

## Consequences

- One proxy disappears from every retrieval: generation calls an in-process
  function, not its own forwarder aimed at another service.
- The forwarder's allowlist keeps its `vector_stores` paths, but they now
  authorise chat-internal handling, not a second hop. Nothing else about the
  browser's paths changes, so the Knowledge, Projects and Agents screens do
  not move.
- The gateway's Postgres keeps pgvector installed (the extension image is
  shared) but no knowledge tables; the chat's database gets its own HNSW
  indexes. Neither component can read the other's store, which is the point.
- An embedding model change still requires reindexing, still costs one
  embedding call per batch, and still never re-extracts — the text is kept on
  the document for exactly that reason, and 0062's accounting survives the
  move.
- The gateway's console loses the knowledge-pipeline screen; the chat's admin
  Knowledge screen becomes the only one, backed by the chat's own config.
