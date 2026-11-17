# Spike: DocumentDB (own gateway) as Cerea's database, FerretDB as comparison

Date 2026-10-20. Box: Intel Celeron N5105, no AVX, ~5.9 GB RAM, kernel 7.0. Baseline: `cerea-test-mongo` (mongo:4.4, port 8801, untouched apart from a throwaway `mig_sample` db that was dropped).

## Verdict

**Viable with listed gaps, but not as shipped on a no-AVX CPU.** The data plane (PostgreSQL + DocumentDB extension) runs fine without AVX, and Cerea's whole server suite gives identical results on it and on mongo 4.4. The official DocumentDB v1.0 *gateway* binary does not run here: it is compiled for x86-64-v3 / AVX2 and dies with SIGILL. Rebuilding the gateway from source with `target-cpu=x86-64-v2` works (7m38s on this box) and passed everything below. So adoption on AVX-less hardware means we build and publish our own gateway binary or image, or the project fixes it upstream. On any AVX2 host the stock image should work as is (not tested here).

## 1. Runs here? AVX

- Image tested: `ghcr.io/documentdb/documentdb/documentdb-local:pg18-1.0.0` (1.16 GB; Debian 13, PostgreSQL 18.6, pgvector 0.8.7, PostGIS 3.6.4, pg_cron 1.6.8, DocumentDB `1.0-0`). Tags `pg15-1.0.0`..`pg18-1.0.0` exist; `latest` is pg17.
- PostgreSQL + extension: start and work on this CPU. No AVX needed.
- Gateway (`pg_documentdb_gw`, Rust): stock binary exits with `Illegal instruction (core dumped)`. Cause confirmed at source: `pg_documentdb_gw/.cargo/config.toml` sets `rustflags = ["-C","target-cpu=x86-64-v3","-C","target_feature=+avx2"]` (comment: the `scc` crate wants avx2). The shipped binary has about 46,000 `ymm` instructions (objdump), so it is compile-time, not runtime-dispatched.
- Fix tried: edit that line to `target-cpu=x86-64-v2`, build in `rust:1-bookworm` with `cargo build --profile release-with-symbols -p documentdb_gateway` (needs whole repo checkout, because build.rs reads `error_mappings.csv` from the repo root; toolchain pinned 1.95). The binary still contains ~900 ymm instructions (dependencies, evidently runtime-guarded), never executed here. Bind-mounted over `/home/documentdb/gateway/pg_documentdb_gw/target/release-with-symbols/documentdb_gateway` in the image, it ran the entire suite. The binary is kept at `/var/tmp/ferret-tmp/gateway-x86-64-v2` (42 MB, not committed anywhere).
- Idle RAM: DocumentDB container (PG + gateway) 59 MB right after start, about 150 MB after the test run; mongo:4.4 about 100-135 MB. Image sizes: documentdb-local 1.16 GB vs mongo:4.4 594 MB.
- Behaviour notes: TLS on by default (`tls=true&tlsAllowInvalidCertificates=true`, self-signed cert; `TLS_MODE=allowTLS` default, so plain may be possible, not tested); SCRAM-SHA-256 auth required (we passed `authMechanism=SCRAM-SHA-256`); reports itself as MongoDB 7.0.0; **usage telemetry to Scarf is on by default** in documentdb-local (hourly, source IP visible to Scarf): disable with `DOCUMENTDB_USAGE_TELEMETRY=false` (we did). Native packages have no telemetry. Startup takes about 60 s (readiness loop logs "Gateway not ready yet").

## 2. Licences (from the repos)

- DocumentDB (github.com/documentdb/documentdb): MIT (GitHub SPDX `MIT`; LICENSE file starts "MIT License"). Linux Foundation project (technical charter "DocumentDB a Series of LF Projects, LLC", adopted 2025-08-21). Contributions need DCO sign-off only, no CLA found. Gateway crates: MIT per workspace manifest, with Apache-2.0 deps (`licenses/` dir). Bundled third-party: PostgreSQL licence (postgres, RUM, pg_cron, pgvector), PCRE2, libbson, CRoaring (Apache/MIT), Intel rdfpmath. PostGIS is a required dependency of the extension (Debian package `postgresql-18-postgis-3`); its licence file in the repo (`licenses/LICENSE-postgis`) is a multi-licence summary, and I believe the core is GPL-2.0-or-later (from memory, not verified at source). It is a separate package loaded by Postgres, but worth a legal look given the Apache-2.0 policy.
- FerretDB v2.7.0: Apache-2.0 (GitHub SPDX). Its postgres-documentdb image wraps DocumentDB (MIT) on Postgres (PostgreSQL licence). No CLA text found in CONTRIBUTING.md (not checked exhaustively). Company-run (FerretDB Inc.), but the code is Apache-2.0.
- No SSPL anywhere in either stack.

## 3. Can it share the kit's Postgres (`pgvector/pgvector:pg18`)?

Not as a drop-in. Tried: `FROM pgvector/pgvector:pg18-trixie`, apt `postgresql-18-cron` + `postgresql-18-postgis-3`, then `dpkg -i` of the release's `ubuntu24.04-postgresql-18-documentdb_1.0-0_amd64.deb`. Postgres refused to start with `shared_preload_libraries=pg_cron,pg_documentdb_core,pg_documentdb`: `undefined symbol: ucol_getSortKey_74`. The release debs target Ubuntu 24.04 (glibc >= 2.38, ICU 74), only Ubuntu 24.04 and RHEL 9 packages are published, and the kit's pgvector image is Debian (bookworm for `pg18`). So adding the extension to that image needs one of:
- build the extension from source on our base image (the documentdb-local image itself is Debian 13 and does exactly that), or
- use the DocumentDB-built PG18 image as the kit's single Postgres: it already contains pgvector 0.8.7 and PG 18.6, the same major as the kit. Not tested: the gateway DB living next to Cerea's docs in the same instance, preload settings (pg_cron, documentdb libs) affecting the gateway workload, and mounting the kit's existing `postgres-data` volume (initdb flags, locale, PG minor).
- Extension prerequisites: pg_cron, pgvector, PostGIS installed; `shared_preload_libraries` must include pg_cron, pg_documentdb_core, pg_documentdb; a background worker runs index builds through pg_cron (`build_index_concurrently` ticks every 2 s in the log, harmless but noisy).
- Practical minimum for "fewer moving parts": still one extra container (the gateway), but no mongo image. Gateway can run in its own container or in the same one.

## 4. Compatibility with Cerea

### Inventory (src/lib, non-test; counts are call sites)
- Indexes (`database.ts`): ~97 `createIndex`; unique (26), partial filter (16: `$exists`, `$type:"string"`, equality), sparse, compound, TTL `expireAfterSeconds` (19, incl. TTL+partial and a migration that drops/recreates indexes when TTL changes). No text indexes, no collation indexes.
- GridFS: `GridFSBucket` x2 buckets (`files`, `codeOutputs`) + knowledge service.
- Transactions: `session.withTransaction` in the migration runner (`migrations.ts`). Change streams: none. `collation`: none in code (a comment only). `bulkWrite` (unordered) in two migrations.
- Updates: `$set` (130), `$setOnInsert`, `$unset`, `$inc`, `$push`, `$pull`, `$addToSet`; `findOneAndUpdate` (14, upsert) / `findOneAndDelete`.
- Queries: `$in`, `$exists`, `$or`, `$ne`, `$nin`, `$and`, `$elemMatch`, `$regex`, `$expr`, `distinct` (22), `countDocuments` (141).
- Aggregation: used only in `jobs/refresh-conversation-stats.ts`: `$group`, `$project`, `$concatArrays`, `$unwind`, `$replaceRoot`, `$set`, `$ifNull`, `$cond`, `$sum`, `$mergeObjects`, `$map`, `$size`, **`$merge` into a collection on a compound key (`on: [...]`, replace/insert)**, `allowDiskUse`. No `$lookup`, `$facet`, `$text`, `$vectorSearch`.

### Probe script (`/var/tmp/ferret-tmp/scripts/probe.cjs`, run against DocumentDB with the rebuilt gateway)
Everything in the inventory worked: unique, partial (`$exists`, `$type`, equality), sparse, TTL, TTL+partial, `findOneAndUpdate` upsert/arrayFilters, unordered `bulkWrite`, `$push/$pull/$addToSet`, `$elemMatch`, `$regex`, `distinct`, `countDocuments`, `$expr`, the aggregation stages above, **`$merge` on a compound key**, `$lookup`, `$facet`, `$unionWith`, text index, **transaction commit and abort-with-rollback**, change-stream open/close, **GridFS 3 MB write/read/delete**. Three "FAIL" lines are probe mistakes (my own duplicate-key and `$size` on a missing field, which mongo rejects too; a JSON print of `rename`'s return). The one real gap: **collation** is "not implemented yet" for `createIndex` and `find` (v1.0). Cerea does not use collation, so no impact today.

### Cerea server test suite (`npx vitest run --project=server --no-file-parallelism`, 1046 suites, 3402 tests, under `flock /tmp/heavy.lock`)
| target | passed | failed | skipped | wall | sum of per-file time |
|---|---|---|---|---|---|
| mongo:4.4 (baseline, :8801) | 3361 | 2 | 39 | 8m52s | ~100 s |
| DocumentDB 1.0, rebuilt gateway (:8803, `TEST_MONGODB_URL=mongodb://u:p@127.0.0.1:8803/?tls=true&tlsAllowInvalidCertificates=true&authMechanism=SCRAM-SHA-256`) | 3361 | 2 | 39 | 8m53s | ~141 s |

The two failures are **identical on both** (so not attributable to DocumentDB): `gatewaySession.spec.ts` ("folds a merged identity in the background...", expected null) and `textGeneration/__tests__/replayRoundTrip.spec.ts` ("model switching still replays tool calls..."). **FerretDB-only / DocumentDB-only failures: zero.** I confirmed the tests really hit DocumentDB (database `chat-ui-test` present there afterwards). Not run: `ssr`, `client` projects, Playwright e2e, the kit's own tests, the app against a long-running DocumentDB with real load.

## 5. Rough performance (same box, same moment, other agents occasionally running; indicative only)
| op | mongo 4.4 | DocumentDB |
|---|---|---|
| 2000 sequential insertOne | 4.1 s | 10.6 s |
| 20000 insertMany (20 batches) | 1.1 s | 2.6 s |
| 2000 findOne by indexed key | 5.1 s | 6.4 s |
| 200 find+sort+limit | 0.82 s | 0.79 s |
| 2000 updateOne $set | 4.4 s | 10.8 s |
| 10 aggregate $group | 1.0 s | 0.6 s |
| GridFS write 3x20 MB | 1.5 s | 2.3 s |
| GridFS read 3x20 MB | 0.54 s | 1.8 s |
Writes about 2.5x slower per round trip, reads similar, large GridFS reads about 3x slower. Test suite per-file time +40%. Acceptable for a chat app's access pattern; not benchmarked at scale or concurrently.

## 6. Migration
`mongodump` (tools in the `mongo:4.4` image, run with `--user $(id -u)`) from mongo 4.4 and `mongorestore --ssl --sslAllowInvalidCertificates -u .. --authenticationMechanism SCRAM-SHA-256` into DocumentDB worked on a sample (500 conversations, a 5 MB GridFS file): 521 docs restored, 0 failures; unique+sparse, compound and TTL indexes recreated; GridFS file read back byte-exact. (The 4.4 tools use `--ssl`, not `--tls`.) Untested: full-size data, partial-filter indexes via restore (they were fine via the driver), downtime procedure.

## FerretDB comparison (short, per instruction not pursued further)
- Latest release v2.7.0 (2025-11-10). Official images: `ghcr.io/ferretdb/ferretdb:2.7.0` (53.6 MB) + `ghcr.io/ferretdb/postgres-documentdb:17-0.107.0-ferretdb-2.7.0` (2.31 GB; PG 17.6, DocumentDB 0.107, includes pgvector 0.8.1/PostGIS/rum/pg_cron). Runs on this no-AVX box: Go gateway and PG extension both started; idle RAM FerretDB 36 MB + Postgres 98 MB. Reports MongoDB 7.0.77. Requires auth with the Postgres user. So FerretDB *is* a working no-AVX gateway today for the 0.107 extension line. I did not run the Cerea suite on it (the DocumentDB probe results apply to the same engine, but FerretDB's own translation layer was not tested) and did not test pairing FerretDB 2.7.0 with the DocumentDB 1.0 extension (unknown).
- Fallback idea: FerretDB on the DocumentDB extension avoids the AVX2 gateway, at the cost of an engine that is behind v1.0 and a project whose release cadence has slowed (per orchestrator).

## What a real adoption would need
1. A gateway for non-AVX2 CPUs: either our own CI-built `x86-64-v2` gateway artefact (one-line config change, 8-minute build) or an upstream issue/PR asking for a baseline build or runtime dispatch. Decide whether we support non-AVX2 hosts at all.
2. A Postgres image for the kit with the extension: build from the documentdb repo on Debian (as documentdb-local does) or consume `documentdb-local` split into postgres + gateway; verify it can replace `pgvector/pgvector:pg18` (same volume, pgvector present).
3. Kit changes: new service(s), `MONGODB_URL` with TLS + SCRAM-SHA-256 (or plain if `allowTLS` permits), credentials in `.env`, telemetry off, healthcheck (mongosh replacement), startup-time allowance (~60 s), volume migration step (dump/restore) in the upgrade path, docs.
4. Cerea: nothing needed for the server tests. Still to verify: `ssr`/`client`/e2e projects (Playwright starts its own Mongo via `E2E_MONGO_URL`), the app under real use, the 2.5x write latency on hot paths, `mongodb-memory-server` in CI stays as is (CI uses mongo 8.2).
5. Legal: confirm PostGIS licence stance (required by extension); note DocumentDB-local telemetry default.

## Cleanup
All `ferret-spike-*` containers, networks and the images I pulled or built (FerretDB, DocumentDB, rust, alpine) removed; `cerea-test-mongo` untouched (still running). Worktree `Cerea-ferretdb` and branch `spike/ferretdb` removed; nothing committed or pushed. Scratch (logs, JSON results, probe/bench scripts, the rebuilt gateway) in `/var/tmp/ferret-tmp/`.
