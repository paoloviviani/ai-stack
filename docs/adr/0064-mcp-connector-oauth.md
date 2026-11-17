# 0064 — MCP connectors: the chat is the OAuth client

- Date: 2026-09-11
- Status: **accepted, being built.**
- Asked directly, after [ADR 0063](0063-connectors-through-toolhive.md) was
  reversed: *"what I honestly need: MCP with browser friendly oauth support
  within the chat (now it supports only header auth). we already considered to
  go the MCP gateway way, but that's an overkill probably. or at least, it
  makes sense if we host MCP servers... now the target are remote connectors,
  either with oauth or with tokens."*
- Supersedes 0063's *deployment* premise and keeps its analysis. Depends on
  [ADR 0040](0040-bearer-tokens-on-v1.md) for who the caller is.

## The decision

**The chat is the OAuth client for MCP connectors**, and the credential lives
server-side, per user. No gateway: we host no MCP servers, so the half of a
gateway worth having — container isolation, a registry, policies — is the half
we would not use.

Two things make this the right place rather than a compromise. The chat *is*
the MCP client; the gateway does not speak MCP at all, so putting connector
OAuth there would mean a component holding credentials for a protocol it never
sends. And **the redirect URI becomes ours to choose**, which is what removes
every difficulty 0063 ran into: a callback on our own published origin is a
route we already serve, so there is no `localhost`, no tunnel, and no
externally-reachable-redirect problem to solve.

## What is wrong today

Custom MCP servers and their `Authorization` headers are kept in browser
`localStorage` (`src/lib/stores/mcpServers.ts`), so a long-lived third-party
bearer token sits where any XSS on the origin can read it. `authRequired` on
the server record is derived by **string-matching an error message** for
"unauthorized", "forbidden", "401" or "403"
(`src/routes/api/mcp/health/+server.ts`) and leads nowhere: the interface's
only answer is "provide appropriate Authorization headers".

Both are fixed here. The token moves to the server and the detection becomes
the protocol's own.

## The shape

Per the MCP authorization specification, which is OAuth 2.1 with the
discovery documents:

1. **Probe.** A 401 from the server carries `WWW-Authenticate` naming its
   protected-resource metadata. Fetch `/.well-known/oauth-protected-resource`
   for `authorization_servers`, then that server's
   `/.well-known/oauth-authorization-server`. This replaces the string match:
   a connector either advertises an authorization server or it does not.
2. **Register**, once per connector, by RFC 7591 dynamic client registration
   against the `registration_endpoint`, with our callback as the redirect URI.
   The client id and secret are stored encrypted.
   *Not* by client-ID metadata document: CIMD would have the provider fetch a
   document from us, and this deployment serves `tls internal` — a CA nothing
   has heard of. DCR is us posting to them, so it works either way. 0063
   measured this.
3. **Authorize** with PKCE S256 and the RFC 8707 `resource` indicator, state
   bound to the signed-in user's session, and redirect the browser.
4. **Call back** to a route on our own origin, exchange the code, and store
   the access and refresh tokens **per user, per connector**, encrypted.
5. **Use.** The server side attaches the caller's own token when it opens the
   connector, refreshing when expired. Nothing reaches the browser.

## Three rules, each for a failure it prevents

**Per user, never per deployment.** One shared connector credential would mean
every person in the chat reading the same Notion workspace as one identity,
which is an access-control defect dressed as a convenience — and it is exactly
what 0063's rejected shape would have given us. A token row is keyed on
`(userId, connectorId)`.

**A static token is a connector too.** The requirement names both. A
token-authenticated connector takes the same shape minus the flow: the secret
goes to the same encrypted server-side store, and the headers editor stops
writing to `localStorage`. The point is where the credential lives, not how it
was obtained.

**The state parameter is bound to the session, and the callback trusts
nothing else.** An authorization code arriving with a state we did not issue to
*this* session is discarded. Without that, a callback is a way to attach an
attacker's connector authorisation to somebody else's account.

## What building it measured, and the bug it found

The flow was driven against Notion's own remote server
(`https://mcp.notion.com/mcp`) from the deployment behind the proxy overlay,
and every machine-checkable step of it passes —
`scripts/test_connectors_live.py`, 20 assertions. What that proves is the
thing 0063 could not deliver: discovery finds the authorization server,
RFC 7591 registration returns a client id, and the authorize URL comes back
with PKCE S256 and a `redirect_uri` **on our own origin**. Approving the
consent screen is the one step no script can do, and the check says so rather
than reporting green over a gap.

Two corrections came out of it.

**The RFC 8707 resource indicator is the MCP server's canonical URI, not its
issuer's origin.** One authorization server can front several resources, and
the indicator names the one the token is *for* — `https://mcp.notion.com/mcp`,
not `https://mcp.notion.com`. Getting it the wrong way round is invisible
until a provider starts checking the audience, at which point every stored
token is worthless.

**A connector-only turn arrived with no tools at all.** `runMcpFlow` narrows
the merged server list to `selectedServerNames`, and the client built that
list from its *servers* alone. Enable one connector and no servers and it sent
`[]` — an array, so the filter ran and matched nothing. No error anywhere: the
model simply answered without the capability, which is the worst shape a
failure can take. The client now names connectors in that list too, and the
name filter has a test of its own.

A third thing was ordered deliberately rather than found broken: connectors go
**last** in the merged list, because the merge deduplicates by name and the
later entry wins. Somebody with a stale `localStorage` server called "Notion"
beside a connector of the same name must end up using the connector — the one
whose credential this browser never held.

## Two OAuth modes, after checking what Open WebUI does

Checked at source on 2026-09-11, because it is the most-deployed comparable
product and the question "are we holding user credentials for a good reason"
deserves an answer from outside our own head. It is the same architecture:
an admin registers an MCP server, each user authorises individually, and the
tokens go **encrypted into the database** — an `oauth_session` table, with the
browser holding only an `httponly` cookie carrying a session id.
`WEBUI_SECRET_KEY` encrypts them, and a second key,
`OAUTH_CLIENT_INFO_ENCRYPTION_KEY`, covers the client registration.

One thing they have that we did not, and it closes a real gap: **two modes**.
`oauth_2.1` is dynamic client registration; `oauth_2.1_static` uses credentials
an operator already holds, with metadata discovery but no DCR. Ours required
DCR, so a provider that does not offer a `registration_endpoint` left
`canAuthorize` false and the Sign in button disabled **permanently** — a dead
end, not an inconvenience. `McpRegistration.source` is now `dcr | static`, and
a static registration is never replaced by a re-probe, because those
credentials are somebody else's to manage.

The registration can also be supplied *after the fact*, which is the recovery
path: the connector whose DCR failed keeps its row, and pasting a client id
turns it into one that works. Replacing a registration deletes every token held
under the old client id — they were issued to a different client, and keeping
them would show a connector as connected while every call returned 401.

One thing we have that they do not, and it is worth keeping deliberately rather
than by accident: **a credential we cannot decrypt fails that connector, not
the application.** Their [issue #18092] is a changed `WEBUI_SECRET_KEY`, a
restored backup or a redeploy raising `InvalidToken` *at startup* and locking
every user out, with no re-encryption path and a workaround that involves
editing SQLite by hand. Key rotation is unsolved in both; only the blast radius
differs. [issue #18092]: open-webui/open-webui#18092

## A bug this work introduced, and the guard it was missing

The first version called plain `fetch` for discovery and the token exchange.
That is wrong, and the reason is the shape of the chain rather than anything
exotic: a URL somebody typed produces a `WWW-Authenticate` naming a metadata
document, that document names an authorization server, and we then post a
client registration and later an authorization *code* to whatever it named.
Plain `fetch` makes adding a connector a way to reach anything the container
can. `https://` in the schema stops none of it, because a hostname is free to
resolve into the compose network.

Everything outbound now goes through `ssrfSafeFetch`, which is what the
upstream health route had been using all along — the new code simply did not
adopt it. Worth recording because it is the failure mode of writing a client
beside an existing one rather than on top of it: the safety lived one import
away and was not reached for.

## What this does not do

**No connector sharing, yet.** A connector's *definition* (name, URL, how it
authenticates) is worth sharing; a token never is. Sharing definitions can
reuse the pattern projects use, and is deliberately out of this ADR — the
first version is one person's connectors, because the alternative is designing
a sharing model before the flow works once.

**No local MCP servers.** That is what a gateway is for, and 0063 records why
we do not have one. If that changes, this decision does not have to: an OAuth
client is orthogonal to who runs the server.
