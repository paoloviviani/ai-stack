# 0084 — Bundled identity providers: Authelia and Keycloak ship with the installer

- Status: accepted, built, verified live
- Date: 2026-09-20
- Related: [0068](0068-minimal-idp.md) (the house IdP this sits beside —
  still the default everywhere, still the fallback behind every sign-in
  menu), [0051](0051-settings-identity-and-email.md) (the identity
  providers registry that makes a second issuer a row, not a second config
  schema), [0040](0040-bearer-tokens-on-v1.md) (the audience on `/v1` — what
  makes per-user billing work against an external issuer),
  [0082](0082-satellite-and-generic-profiles.md) (the satellite profile whose
  local-IdP shape this extends).

## Context

The installer offers three sign-in shapes and none of them fits a fresh box
whose operator has no directory yet:

- the **house IdP** signs the chat in and nothing else — the gateway console
  still lives on local passwords, and there is no OIDC server a second
  application could trust;
- a **single external IdP** needs a directory before the first login, which
  is precisely what the deployment was supposed to provide;
- the **custom split** is for operators who already have one.

Two streams built the providers as compose overlays (Authelia 4.39.20,
Keycloak 26.7.3 — both licence-checked in the overlay headers) and proved
them live against a scripted OIDC flow. This decision records the wiring
rules both streams converged on and one the live run forced.

The operator asked for one thing explicitly: **the audience is never
prompted for when the provider is bundled.** Everything about the pairing is
deterministic — issuer from the public origin, client ids fixed, audience
`pystino-api` granted implicitly to both clients — so the installer writes
the whole OIDC half of `deploy/.env` from values it already minted.

## Decision

**Bundled providers join the sign-in menus, not the profile list.** Team
gains bundled Authelia/Keycloak beside its house default; enterprise's menu
grows to five (external, house, custom, bundled Authelia, bundled Keycloak);
satellite gains a sign-in choice — central provider (today's shape) or a
bundled local Authelia. The satellite deliberately gets **Authelia only**:
no gateway means no console client, and Keycloak's ~730 MB RSS is aimed at
directory-shaped deployments. Homelab and generic stay as they are.

**Audience and issuer are derived, never asked.** `pystino-api` for both
providers, written into `GATEWAY_OIDC__ACCESS_TOKEN_AUDIENCE` and
`CHAT_OIDC_*` with no prompt. The chat's scopes for every bundled shape are
`openid profile email groups` — `/v1` access tokens are validated locally
with no userinfo round trip, so whatever is not *in* the token is not seen,
and without `groups` the ledger bills nobody.

**The satellite-local shape flips the billing mode, and the installer
enforces the pairing.** Central's `/v1` will never accept a local issuer's
token (wrong `iss`), so a satellite with a local Authelia runs shared-key
mode: `OPENAI_API_KEY` from central (required — the guard refuses an
otherwise-legal empty key), `USE_USER_TOKEN=false`, Usage tab hidden (it
reads central's ledger with the signer's own token, which no longer exists
here). Both guards are fail-closed in `validate_values`, against the built
file on fresh installs and resumes alike.

**Bare IP plus bundled Authelia is refused.** Authelia requires a Domain
cookie, and browsers refuse a Domain cookie on an IP — nobody could stay
signed in. The generator enforces a dotted domain; the installer refuses
earlier, before anything is written. Keycloak has no such constraint.

**The provider ships in phase 1.** The gateway reads OIDC discovery once at
startup, so the issuer must answer before the gateway that reads it is
restarted. Phase 1 therefore starts base + exposure + the IdP overlay
(services by name), waits for discovery over the public origin, runs the CA
dance (proxy's local CA root appended to a public-roots bundle, de-duplicated
— `SSL_CERT_FILE` *replaces* the trust store, so a bundle of only the local
root would blind the gateway to its upstream), and restarts the gateway —
the restart the OIDC configuration needs anyway is the one that picks the
trust up. The edge shape skips the dance (plain HTTP behind the edge) and
instead appends the IdP route to `Caddyfile.netbird`, whose sites share one
snippet both import — the proxy shape needs nothing beyond the overlay's
conf.d mount.

**Secrets are minted, passwords are asked.** Everything generatable
(`openssl`) is generated; the first human's password is *typed* (memorable,
used daily), lives only in the rendered IdP files, never in `deploy/.env`.
Keycloak's bootstrap admin is the one minted exception — shown once at the
end of the install, resettable in the Admin Console after. Regenerating the
generated files is refused (a realm re-import or a JWKS rotation
re-provisions every user; users are keyed on `(issuer, subject)`), so
starting over means deleting them deliberately.

**The chat container speaks the same dialect as its deployment.** The chat
overlay now interpolates `OPENAI_BASE_URL`, `OPENAI_API_KEY` and
`USE_USER_TOKEN` from `deploy/.env` (gateway defaults when unset), because
the satellite-local shape's chat must point at central with a shared key —
the same image, one set of variables, no per-shape overlay.

## Consequences, and what the live runs found

Two full installs (enterprise + Authelia, enterprise + Keycloak, proxy
exposure, both with the chat built and a real scripted chat login) carried
these findings, each fixed where it lives:

- **Phase 1 needed the redaction overlay** even on a bundled install whose
  engine is not `noop`: the gateway refuses `engine='http'` without an
  endpoint, and only the redaction overlay names one. A fresh team/enterprise
  install of any kind died in phase 1 with `redaction.endpoint is required`;
  the overlay joins the phase-1 set for its variables (containers still start
  by name).
- **The chat route did not exist on the proxy shape.** The chat overlay's
  header claimed it mounts `conf.d-chat/20-chat.caddy` into the proxy; no
  such mount existed, and only the edge shape (which routes `/chat` in
  `Caddyfile.netbird` itself) ever served `/chat`. Every proxy-shape
  deployment 404'd the chat with nothing in any log. The overlay carries the
  mount now.
- **Keycloak's realm import refuses unknown JSON fields** — the realm
  template's documentation-as-`_comment` killed the import
  (`Unrecognized field "_comment"`). The template is bare JSON now; the
  knowledge moved to the docs page.
- **An explicit `clientScopes` key replaces the auto-created built-ins.** A
  realm defining one must define everything the clients request, including
  `basic` — whose `oidc-sub-mapper` puts `sub` in the access token. Without
  it every token failed validation with `Missing claim: 'sub'`. The template
  defines `basic`, `profile`, `email` and `groups` with mapper shapes copied
  from the live server, not from memory.
- **A probe is not the client.** The issuer-wait probe first used a loopback
  URL inside the proxy — which Caddy answers with a TLS internal error,
  because it serves by SNI and a loopback probe carries no hostname. The
  probe uses the public origin, exactly what the gateway and the chat fetch.

Unchanged on purpose: the house IdP remains the default on every menu it
appears on (no new dependency for deployments that need nothing more), the
`GATEWAY_IDP__CLIENTS=[]` crash fix keeps covering every shape where the
house IdP is off, and no overlay carries a hardcoded secret.

## Verification

- Dry runs (`--dry-run`, `docker compose config --quiet`) green for: team
  house/Authelia/Keycloak, enterprise external/house/custom/Authelia/
  Keycloak, satellite central/local, generic, homelab — proxy and edge
  exposures; phase-1 sets checked separately; both fail-closed guards
  (satellite-central stored key, generic user-token) plus the new pairing
  rules re-verified against crafted `deploy/.env` files.
- Live, against real issuers over the public TLS origin: discovery byte-exact
  (`iss` compared to the configured issuer), chat-client PKCE flows with
  `aud=['pystino-api']` / `aud='pystino-api'` and group claims (`users`,
  `research`), `/v1/me` 401 without / 401 bad / 200 with the token, console
  SSO through the gateway landing on the same user row, then the chat's own
  browser-shaped login → session → conversation → streamed turn → usage
  tab, with the ledger attributing every row to the IdP identity
  (`testadmin@example.net` under Authelia, `owner@example.org` under
  Keycloak). Both stacks torn down to nothing afterwards.
