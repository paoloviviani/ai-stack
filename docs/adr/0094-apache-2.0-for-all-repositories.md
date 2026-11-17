# 0094 — Apache-2.0 for every repository

- Date: 2026-10-04
- Status: **accepted**. The owner took the decision on 2026-10-04.
- Restates: 0001 decision 1 (first-party code is under an OSI-approved licence) by naming the licence for every repository; extends 0092 from Cerea to the rest. Decisions 2 to 5 of 0001 (the inbound dependency policy) stand.
- Related: 0001, 0092.

## Context

0092 put Cerea under Apache-2.0, like its upstream. The owner's reason for moving the rest of the projects to the same licence: "AI-generated code is harder to protect" under the licence they carried before, and one licence across the projects is simpler to state and apply than two.

Pystino, cerea-deploy and this repository have a single author (every commit is by Paolo Viviani), so the owner can relicense them without anyone else's consent. Cerea, which has many upstream contributors, was already Apache-2.0 and is unchanged.

## Decision

1. Pystino, cerea-deploy and ai-stack are licensed **Apache-2.0**. Each repository's licence file is `LICENSE`, the verbatim text from apache.org, and `NOTICE` carries the copyright line.
2. Licence fields are the SPDX id `Apache-2.0` (`pyproject.toml`, `package.json`, the image label `org.opencontainers.image.licenses`).
3. Dependency policy: 0001 decisions 2 to 5 stand. Permissive licences are free to use; MPL-2.0 used unmodified is fine; AGPL and GPL only as separate processes; non-OSI licences need approval.
4. Releases already published stay under the licence they carried. No history is rewritten; each repository's changelog records the change.
