# ADR 0120: Share links for artifacts

- Status: **accepted** (owner 2026-11-17). Backlog C146.

## Decision

- **What a link shares:** a snapshot of one artifact version. "Update to latest" re-points the link on request. It never includes the conversation, the prompt or other files.
- **Link and token:** `/<prefix>/<token>` with a random 128-bit token.
- **Audience,** chosen per link:
  - anyone with the link;
  - signed-in users of this deployment (the default).
- **Expiry:** 7, 30 or 90 days, or never. Links can be revoked, and views are counted.
- **Management:** users see and revoke their own links in Settings → Shared links; admins see all links and can revoke any of them.
- **Switches:** sharing is on by default (an env var). The admin panel has a deployment-wide on/off toggle that overrides the env default. There are no per-group switches (first stage).
- **Signed-in links** always use the path prefix on the app origin (`/s/<token>`) with the normal session, whatever the public prefix (owner 2026-11-17; no one-time ticket across hosts).
- **Public prefix** (for "anyone" links): the operator sets it with `./configure`, either as a subdomain (`share.<host>`, recommended) or as a path (`/s`). Choosing a path prints a warning: shared HTML would run on the app's own origin, protected only by the CSP sandbox. That is weaker isolation and a phishing risk under the deployment's domain.
- **How each kind is served:**
  - markdown, tables, documents and files go through a read-only public viewer (download included);
  - HTML, slides and interactive artifacts are served with `Content-Security-Policy: sandbox allow-scripts` (no same-origin), no cookies, `noindex` and `no-referrer`, with a fixed band "Shared from Cerea by <name>: not an official page";
  - all public routes are rate-limited.
- **Privacy:** the share dialog shows a preview and says plainly that anyone with the link sees exactly this content. Every share is audited (who, what, when, views); content is never logged.
