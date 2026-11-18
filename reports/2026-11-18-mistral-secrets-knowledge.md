# Mistral: secrets and knowledge (research 2026-11-18), lessons for Cerea + Pystino

The full research was done from Mistral's public docs (sources at the end). Items marked UNCONFIRMED could not be verified in primary sources.

## Mistral, in short
- **Studio Secrets Manager** (Public Preview, 14 Oct 2026):
  - workspace-scoped, with role-based write access;
  - values are **write-only** in the console and API (never shown again);
  - versions, soft delete and restore, an audit event on every read;
  - deployments hold a reference (`secret:workspace:<name>`) resolved at workload start to the latest version;
  - rotation means set a new value, then restart;
  - the MCP tools list secrets and read their metadata, never values.
- **Connector credentials** (GA, Jun 2026):
  - user, workspace and org scopes; named credentials with a default (`credentials_name`), and several accounts per connector;
  - rotation by promoting a new credential, then deleting the old one;
  - scoped API keys, service accounts;
  - per-tool allow, restrict or block by admins; org-level apps.
- **Knowledge Base** (Vibe Work, Public Preview, Sep 2026):
  - per-user memory entries saved explicitly or implicitly, with inline read/write pills;
  - entries are edited by asking the model;
  - sensitive categories are off by default, and credentials and IDs are never saved; admins can switch it off.
- **Libraries:**
  - files and URLs (100 MB per file), a monthly processing allowance;
  - footnote citations;
  - Viewer/Collaborator sharing with users, workspace or org;
  - a re-index schedule for websites;
  - a `document_library` tool for agents.

## Ideas for us (prioritised)
1. **A workspace secret store**, about 1–2 weeks:
   - write-only values, versions, audit on read, `secret:<name>` references;
   - encrypted with an operator-held key;
   - used by galopin and cloud workspaces, which fixes the manual `gh auth login`.
2. **Credential injection at the egress proxy** for cloud workspaces, about 2–3 weeks on top of 1: the agent holds a placeholder, and the proxy substitutes the real value per host. This goes further than Mistral (which resolves secrets at start); it is our own design idea.
3. **Named, multi-account connector credentials** with user/workspace/org scope and a default, plus service accounts for scheduled runs, about 1 week.
4. **Per-tool allow/restrict/block** for admins, and **scoped API keys** (connector or secret allow-lists), about 3–5 days.
5. **Knowledge UX:**
   - read/write pills when memory is used;
   - editing memory through the model;
   - an explicit never-store list enforced by the privacy pipeline;
   - Viewer/Collaborator sharing;
   - re-index schedules for web sources;
   - an explicit library tool for agents.
6. **Connector sync kept opt-in:** live fetch by default, with source-permission mirroring as the open risk.

## Conflicts with a self-hosted, privacy-first design
- Secrets and libraries stay in our own database, encrypted with an operator-held key.
- Prefer pinned secret versions over "latest at start".
- Implicit memory saving should be opt-in, with redaction before storing.
- Resolve-at-start leaves the plaintext in the workload; injection at egress closes that gap.

## Sources
- https://docs.mistral.ai/studio/secrets
- https://docs.mistral.ai/resources/release-notes
- https://docs.mistral.ai/resources/mcp
- https://docs.mistral.ai/resources/cookbooks/mistral-connectors-06-multiple-authentication
- https://mistral.ai/news/more-control-over-connectors/
- https://docs.mistral.ai/admin/identity-access/connectors
- https://docs.mistral.ai/en/vibe/work/knowledge
- https://docs.mistral.ai/vibe/work/libraries
- https://docs.mistral.ai/studio-api/libraries
- https://docs.mistral.ai/le-chat/knowledge-integrations/connectors/knowledge-connectors
