# 0087 — Two repositories; Pystino is the distribution and pins Cerea by digest

- Status: **accepted**, 2026-09-24
- Amended by: 0091 (a code-free deploy repository, cerea-deploy, pins Pystino, which pins Cerea; option 4 is taken in that narrower form)
- Related: [0086](0086-one-stack-two-image-sources.md); the 2026-09-23 review's §3.1 (which recommended a monorepo)
- Design: `reports/2026-09-24-deployment-rearchitecture.md` §7

## Context

The review found that cross-repo seams cause many bugs. It recommended merging the repos while keeping the services separate. The operator prefers two repos for brand recognition. Most seams the review listed were **deployment** seams:
- Cerea's installer drives Pystino's compose files and edits Pystino's tracked files;
- chat IdP clients are generated in Pystino;
- there are two installers.

ADR 0086 moves all of them into Pystino. What stays cross-repo is the runtime contract: `/v1`, `/v1/me`, `/v1/pystino/*` capabilities and the OIDC client ids.

## Options considered

1. Two independent repos plus a pinned manifest.
2. Git submodules. They pin sources while the artefact is an image, and bring detached-HEAD and recursive-clone friction.
3. Git subtree. It gives two histories to reconcile and makes one repo a mirror.
4. A thin third deploy repo. It adds a third owner for what Pystino already owns, and recreates the two-owners problem.
5. A monorepo with two published products. It is the best engineering, but costs the repo-level brand.

## Decision

**Option 1.**
- Pystino owns the stack (compose, proxy, `pystino` CLI, IdP config), and `deploy/stack/release.env` pins `cerea` by tag and digest. A Pystino release names one tested pair.
- Cerea owns its Dockerfile and app, and has no stack deployment.
- Lockstep comes from three guards:
  - Cerea CI runs contract tests against `pystino-gateway` at the pinned version and at `edge`;
  - Pystino CI runs a fresh-install job with the pinned `cerea` and, non-blocking, with `cerea:edge`;
  - the gateway API is additive within a minor, and Cerea detects features via `/v1/pystino/capabilities`.
- Paired features become a Pystino PR whose manifest pins the Cerea branch's image by digest, merged Cerea first.

## Revisit when

Over a quarter, more than about a third of features still need paired PRs, or a manifest bump breaks the pair twice. Then import Cerea with `git subtree add --prefix apps/chat`. Image names don't change, so users see no difference.

## Amendment 2026-09-24 (acceptance)

Accepted (D1). Digest pinning is implemented as `pystino release-pin`, and the image workflow checks it on tags. Cerea keeps its brand at the entry point: `cerea init` (a console script in the gateway image, plus `scripts/cerea` in the Cerea repo).
