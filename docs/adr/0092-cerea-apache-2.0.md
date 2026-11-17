# 0092 — Cerea (including galopin) is Apache-2.0; ADR 0001 no longer applies to it

- Date: 2026-09-25
- Status: **accepted**. The user took the decision on 2026-09-25.
- Names the licence under 0001 decision 1 for the Cerea repository. The other repositories followed in 0094.
- Related: 0087 (two repositories), 0089 (galopin).

## Context

Cerea is a fork of huggingface/chat-ui, which is Apache-2.0. Under 0001 it carried two licence files: `LICENSE` (Apache-2.0, upstream's code) and `LICENCE` (a different OSI-approved licence, for first-party additions), including galopin in `agent/`. For an open-source release that split is hard to explain and harder to apply. Most files mix upstream and first-party lines, so a reader cannot tell which licence covers what, and the combination was never signed off.

Cerea and Pystino talk only over HTTP (`/v1`, `/v1/me`) and share no code, so their licences are independent.

## Decision

1. The whole Cerea repository, `agent/` (galopin) included, is licensed **Apache-2.0**. the second licence file (`LICENCE`) is removed, `LICENSE` (Apache-2.0) stays, and a `NOTICE` names Cerea, its author, and that it is based on huggingface/chat-ui, © Hugging Face, Apache-2.0.
2. `package.json` declares `"license": "Apache-2.0"`, and every mention of the previous licence in the repository's docs and comments goes.
3. Dependency policy for Cerea: permissive licences, and MPL-2.0 used unmodified, are fine. Anything GPL, AGPL, LGPL, unlicensed or non-OSI needs the user's approval. The first audit (2026-09-25) raised two items for that approval: sharp's LGPL-3.0 libvips binaries, and `object-stream`, which declares no licence.
4. The other repositories followed on 2026-10-04 (0094).

## Consequences

- One licence for the whole Cerea tree, the same as upstream's, so merging from upstream raises no licensing question.
- First-party contributions to Cerea are Apache-2.0 from now on. Earlier first-party commits were made by the same author, who relicenses them; no history rewrite is needed. The other authors in the history are upstream chat-ui contributors, whose code was Apache-2.0 already.
- galopin is Apache-2.0. It moved from Pystino's repository with its history; its earlier commits were by the same author.
