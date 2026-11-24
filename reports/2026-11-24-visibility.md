# Cerea visibility plan (2026-11-24)

Starting point: Cerea 4 stars / 1 fork, Pystino 2 stars. Fundamentals fine (README with screenshot, docs site, Discussions, public images); missing: reach and a sharp pitch. Show HN already done by the owner (worked to some extent).

## Status

| Item | Status |
|---|---|
| README first screen (pitch, demo, 5-minute install, badges, "Why Cerea"), comparison table | **Done**: merged as #353 (2026-11-24) |
| Demo animation (27 s, fake data via the docs-screenshots harness) + MP4 | **Done** in #353; re-record: docs/dev/ui-screenshots.md |
| Social preview 1280×640 | In #353 (`docs/assets/social-preview.png`); owner uploads in Settings → General → Social preview (no API) |
| Topics | Done 2026-11-24 (Cerea 17, Pystino 13) |
| `good first issue` | #43 labelled |
| Weekly "what's new" Discussion | Offered |
| r/selfhosted, r/LocalLLaMA | Owner created the account 2026-11-24; **catch up ~late January 2027** (together with awesome-selfhosted): read sidebar rules (self-promotion days, AI-built disclosure), post with the demo, stay in the thread |
| awesome-selfhosted | **Owner submits by hand** (rules: "done by a human, not a machine/LLM", ban otherwise). Eligible from **2027-02-02** (first GitHub release v0.2.0 on 2026-10-02; 4-month rule). PR per entry to awesome-selfhosted/awesome-selfhosted-data, file `software/<name>.yml`. Drafts below |
| awesome-mcp-clients | **PR opened** 2026-11-24: punkpeye/awesome-mcp-clients#433 (fork paoloviviani/awesome-mcp-clients can be deleted after merge) |
| awesome-llm-apps | Skip: no external submission path |
| GitHub organisation for Cerea + Pystino | Owner decision (visibility change) |
| One-click templates (Coolify, Dokploy, CasaOS, Umbrel, Unraid), Helm | Not started |

## awesome-selfhosted drafts (verify tag/platform names against `tags/*.yml` and `platforms/*.yml` before submitting)

`software/cerea.yml`
```yaml
name: "Cerea"
website_url: "https://paoloviviani.github.io/Cerea/"
source_code_url: "https://github.com/paoloviviani/Cerea"
description: "Chat for the models your gateway serves, with knowledge bases, artifacts, Python in the browser and coding agents on your own computers (alternative to Open WebUI)."
licenses:
  - Apache-2.0
platforms:
  - Docker
  - Nodejs
tags:
  - Generative Artificial Intelligence (GenAI)
```

`software/pystino.yml`
```yaml
name: "Pystino"
website_url: "https://paoloviviani.github.io/Pystino/"
source_code_url: "https://github.com/paoloviviani/Pystino"
description: "OpenAI- and Anthropic-compatible model gateway with per-user and per-group accounting, quotas, PII redaction, OIDC sign-in and an admin console (alternative to LiteLLM)."
licenses:
  - Apache-2.0
platforms:
  - Docker
  - Python
tags:
  - Generative Artificial Intelligence (GenAI)
  - Proxy
```
(Check that Pystino's docs site URL exists; otherwise use the repository URL.)

## awesome-mcp-clients draft (README, alphabetical in "Clients"; mirror the neighbouring entries' block format)

- Name: Cerea — https://github.com/paoloviviani/Cerea — Website https://paoloviviani.github.io/Cerea/
- License Apache-2.0 · Type: Web app · Platforms: Web, Docker · Pricing: Free · Languages: TypeScript, Go
- Description: Self-hosted chat (a fork of Hugging Face chat-ui) where remote MCP servers are connectors shared by the chat and by coding agents on users' own computers, with per-user approvals for tool calls; also local MCP servers on those computers.
