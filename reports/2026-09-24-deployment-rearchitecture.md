# Deployment re-architecture and OIDC-only identity — Pystino + Cerea (2026-09-24)

Status: **draft for review**. Branch `deploy/rearch` in both repos.
Inputs: the 2026-09-23 code and architecture review (§3.1, §3.4, §3.6; O4, O5, X5, X6), both repos' git logs for 09-16…09-24, and ADRs 0010, 0035, 0040, 0043, 0048, 0051, 0057, 0061, 0068, 0069, 0076, 0082, 0084.

## 0. Summary

- **One compose project, one static `compose.yaml`, one `.env`.** The compose file lives in Pystino (`deploy/stack/`) and carries **no** `build:` sections. Every service names an image through `${…_IMAGE}` variables with versioned defaults. Add-ons are compose **profiles**, selected by `COMPOSE_PROFILES` in `.env`. Nothing derives an overlay list any more.
- **The two modes differ by one line.** Development sets `COMPOSE_FILE=…/compose.yaml:…/compose.build.yaml`. The second file only adds `build:` contexts that point at the local checkouts. Distributed mode sets `COMPOSE_FILE=compose.yaml`. The file comes out of the gateway image of the version you run, and images are pulled from the registry. Either way the bring-up is `docker compose up -d --wait`, and an upgrade is a version bump followed by the same command.
- **Delete shapes before porting anything.** That means:
  - the edge Caddyfile, which becomes a `TLS_MODE=upstream` setting of the single Caddyfile;
  - conf.d splicing, replaced by static routes baked into a small `pystino-proxy` image;
  - the CA trust bundle, replaced by server-to-server OIDC over internal URLs;
  - the house IdP;
  - bundled Keycloak (proposed; it stays a first-class *external* IdP);
  - the two-phase bring-up and its resume memory;
  - `profiles/overlays.sh`;
  - Cerea's `installer/`.
- **`pystino` CLI in the gateway image replaces about 6,000 lines of shell.** `init` writes `.env` and mints its secrets. `bootstrap` is an idempotent one-shot service that runs on every `up`: it creates the chat database, creates the Authelia key and first-user file if absent, and seeds the first admin. The Authelia config itself is a static template baked into a `pystino-authelia` image; it reads every secret from the environment, so nothing is rendered and nothing drifts. `upgrade` swaps in the new `compose.yaml` and bumps the version. `doctor` checks the install. The host needs Docker plus a 20-line shim.
- **Images:** GitHub Actions build `pystino-gateway`, `pystino-proxy`, `pystino-redaction` and `cerea`. Every `main` commit gets `sha-<short>` and `edge` tags; every git tag gets `vX.Y.Z` and `X.Y`. All images carry OCI labels and provenance. Pushing stays switched off until you approve the registry.
- **Repos:** keep two repos. **Pystino is the distribution**, and its `deploy/stack/release.env` pins the Cerea image by digest. A fresh-install CI job tests exactly that pair. Submodules, subtree and a meta repo are compared in §7 and rejected.
- **Identity is OIDC-only.**
  - Authelia stays as the bundled IdP; any OIDC issuer can be brought instead.
  - The house IdP is deleted. Local passwords are demoted to a CLI break-glass (a decision for you).
  - Each provider row gains a **capability model** and console-configurable policy:
    - where groups come from (which claim, a directory pull, or console only);
    - how often the IdP's answer is refreshed (every login, first login, or never);
    - where admin comes from (console or a claim), with provenance, so the IdP can only revoke what it granted;
    - **batch directory sync** through adapters (Authelia users file, Keycloak admin REST, and an inbound SCIM 2.0 endpoint for Entra, Okta and Authentik).
  - Cerea stays consistent by never deciding authorisation itself: it asks the gateway's `/v1/me`, with a short cache.
- **Implementation order:** the config and bring-up core (dev mode, verified on this box under a throwaway project), then the image pipeline, then auth and the console. See §13 for status.

## 1. What goes wrong today, and why

Every pain point found live this week traces to a *shape*, not to a bug in the code that handles the shape. Commit ids are from `main` in each repo.

| Pain point | Mechanism | Evidence | Root cause (shape) |
|---|---|---|---|
| The CA trust bundle decays on the edge shape | The gateway and chat reach the IdP through the **public** hostname. On the edge shape that name is a compose network alias (`cerea.example.org`) pointing at Caddy's `tls internal` site. Recreating `caddy-data` mints a new root, and the bundle in `deploy/tls/` goes stale | Cerea 15ab5dc1, 3b85ea08; Pystino 3d8572e (`ca-bundle` service); review O5 | Server-to-server OIDC hairpins through the browser-facing TLS listener |
| Caddy bind-mount inode staleness after route appends | The installer rewrites Pystino's *tracked* `Caddyfile.netbird` with sed/awk and swaps it in with `mv`. The single-file bind mount keeps the old inode | Cerea 79adc029, 9e9130ad, 29b4e7c0 (and 791c76d3, where snippet order mattered); review O4 | The edge Caddyfile has no `conf.d` import, and host files are edited at run time |
| `--phase2` resumes don't persist overrides | Phase 2 recomputes the component set from "recorded shape" memory, and overrides given on the command line weren't written back | Cerea e8c22dca, f6d8fbc5 | Two-phase bring-up with resume state, needed only because three values "cannot exist before the stack runs" (ADR 0076) |
| The Authelia YAML drifts from the generator, and can't be safely regenerated | `generate-authelia-config.sh` runs once. Regeneration is refused because it would rotate the JWKS key and the storage key, and users are keyed on `(issuer, subject)` with Authelia's *opaque* subject stored in its sqlite. New clients (`opencode-enrollment`, 1e58add, f88048f) never reach existing installs | ADR 0084 "Regenerating the generated files is refused" | Config (clients, policy) and state (keys, users) live in one generated file |
| Chat images are built from mutable local checkouts | `build.context: ${CHAT_REPO}` builds whatever the working copy holds. Nothing records which commit is running, and a dirty tree ships | `docker-compose.chat.yml`; the live chat image is `llm-platform-chat:latest` with no label | No published artefact exists for either product |

Two structural observations sit underneath the table:

1. **Cerea's installer drives Pystino's compose files and edits Pystino's tree.** It is 4,500 lines plus 1,860 lines of tests; Pystino's own `install.sh` adds 537, `overlays.sh` 121 and the profile fragments 585. So the deployment has two owners, and every seam is a place where the owners disagreed: the client id `cerea` versus `pystino-chat`, the relay overlay living in Cerea but composable only from Pystino's `deploy/`, and so on.
2. **The config has no single source.** Values live in:
   - `deploy/.env`;
   - the installer's recorded metadata;
   - generated files under `deploy/idp/` and `deploy/tls/`;
   - the chat's `DOTENV_LOCAL` block (JSON-carrying, hence the `SCRUB` environment dance);
   - build args baked into images (`APP_BASE`, `PUBLIC_APP_NAME`, `SPACY_MODELS`, `INCLUDE_CONSOLE`);
   - database rows (`identity_providers`, `oidc_config`).

   Three of those can disagree without anything noticing.

## 2. Target architecture (both modes)

```
                 browser / opencode / scripts
                          │  https://<origin>
                ┌─────────▼─────────┐   TLS_MODE = acme | internal | upstream
                │  proxy            │   (pystino-proxy image: caddy + baked Caddyfile)
                │  /chat/*   → chat:3000
                │  /authelia/* → authelia:9091
                │  /*        → gateway:8000
                │  import /etc/caddy/extra/*.caddy  (component hook, dir mount)
                └──┬──────────┬─────┘
       ┌───────────▼──┐   ┌───▼──────────┐
       │ gateway      │   │ chat (cerea) │──► gateway:8000/v1 (user token)
       │ + console    │   └───┬──────────┘
       └──┬───────┬───┘       │ chat-mongo
          │       │ back-channel OIDC (discovery, token, JWKS, userinfo)
          │       └──────────►┌──────────────┐  http://authelia:9091  — never via proxy
          │                   │ authelia     │  (or an external issuer's public URL)
    postgres  valkey          └──────────────┘
    (gateway + chat DBs)
    one-shots:  migrate (alembic)  →  bootstrap (pystino bootstrap: chat DB, authelia config, first admin)
    add-ons:    redaction/extractor (profile redaction), playwright (profile fetch)
```

**Services and profiles** (`compose.yaml`):

| Service | Profile | Image | Notes |
|---|---|---|---|
| `postgres`, `proxy`, `bootstrap` | always | upstream pgvector, `pystino-proxy`, `pystino-gateway` | `bootstrap` is a one-shot that runs `pystino bootstrap` |
| `valkey`, `migrate`, `gateway` | `gateway` | upstream valkey, `pystino-gateway` ×2 | Off only for the Cerea-without-gateway presets (ADR 0082) |
| `chat`, `chat-mongo` | `chat` | `cerea`, mongo | |
| `authelia` | `authelia` | `pystino-authelia` (pinned upstream + a baked `configuration.yml` using Authelia's `template` filter) | Secrets come from env, the JWKS key and users file from the `authelia-config` volume that `bootstrap` seeds |
| `redaction`, `extractor` | `redaction` | `pystino-redaction` (pattern or NER variant) | |
| `playwright` | `fetch` | upstream playwright | Moves from Cerea's overlay into the stack file |

All cross-profile `depends_on` entries use `required: false`, so a profile that is off never breaks the graph. That needs Compose ≥ 2.20; this box has v5.5.1, and `doctor` checks the version.

**The two modes, concretely:**

| | Development | Distributed |
|---|---|---|
| Where the deploy dir lives | anywhere, e.g. `~/pystino-dev/` (never inside a checkout) | anywhere, e.g. `/opt/pystino/` |
| `compose.yaml` | referenced in place in the Pystino checkout | copied out of `pystino-gateway:<version>` by `pystino init` / `upgrade` |
| `COMPOSE_FILE` | `<pystino>/deploy/stack/compose.yaml:<pystino>/deploy/stack/compose.build.yaml` | `compose.yaml` |
| Images | built locally from `PYSTINO_SRC` / `CEREA_SRC` and tagged `:dev`. Each carries `org.opencontainers.image.revision=<sha>[-dirty]` | pulled: `${PYSTINO_REGISTRY}/pystino-gateway:${PYSTINO_VERSION}` etc. |
| Bring-up | `docker compose up -d --build --wait` | `docker compose up -d --wait` |
| Upgrade | `git pull`, then the same command | `./pystino upgrade 1.5.0` (swaps `compose.yaml`, bumps the pins), then the same command |

It is the same compose file and the same `.env` schema. Dev mode is distributed mode plus one file that adds `build:`, so anything that works in dev works when pulled, apart from the image origin. Mixing is legal and useful: build the gateway locally while pulling a released Cerea, by putting only the gateway's build stanza in play (`compose.build.yaml` has one service per product, and `CEREA_SRC` unset means "pull").

**The back-channel rule (it deletes the CA dance).** Each identity provider has an optional `internal_base_url`. When it is set, the gateway fetches discovery, token, JWKS and userinfo from that URL. It rewrites the discovery document's endpoints from the public issuer prefix to the internal one, and sends `X-Forwarded-Proto/Host` for the public origin so the IdP mints tokens whose `iss` is the public issuer. The browser still sees only public URLs (`authorization_endpoint`, `end_session_endpoint`). The bundled Authelia gets `internal_base_url=http://authelia:9091/authelia` automatically, and Cerea gains the same `OPENID_INTERNAL_URL` knob. The result is no `tls internal` hairpin site, no network alias of the public name, no `SSL_CERT_FILE`, no `NODE_EXTRA_CA_CERTS` and no `ca-bundle` job. An external IdP with a publicly trusted certificate needs no internal URL at all.

**TLS modes (one Caddyfile, three settings).** All three are set in `.env`:
- `acme`: `SITE_ADDRESS=https://llm.example.org`, and Caddy obtains a certificate.
- `internal`: `SITE_ADDRESS=https://10.0.0.5`, `tls internal`. Dev only, and the only place Caddy's own CA survives. Browsers click through it, and no server ever needs to trust it (back-channel rule).
- `upstream`: `SITE_ADDRESS=http://:8443`, with a trusted-proxy range. This is the NetBird edge. TLS terminates upstream, and Caddy forwards `X-Forwarded-Proto: https`.

The routes are identical in every mode because they are baked into the image. A route whose upstream isn't running (say `/authelia` with the profile off) answers 502 rather than failing Caddy's start, since Caddy resolves upstream names per request.

**The component hook.** The proxy imports `/etc/caddy/extra/*.caddy` from a directory mount (`${DEPLOY_DIR}/proxy.d/`, empty by default). A **directory** mount sees new and renamed files, which closes the inode class for good. Add-on components that need a route drop a snippet there and ship their own compose file, which `COMPOSE_FILE` lists. §9 describes the agent machine against this hook; nothing in core knows about it.

## 3. Shapes and options to delete

| Delete | Replaced by | Why | Lines (approx.) |
|---|---|---|---|
| Edge shape: `Caddyfile.netbird`, `docker-compose.edge.yml`, the hard-coded `cerea.example.org` alias and site | `TLS_MODE=upstream` in the one Caddyfile | A second Caddyfile without a `conf.d` import is why the installer splices files (O4); the alias exists only for the hairpin (O5) | 230 Pystino + about 200 installer |
| `conf.d-chat`, `conf.d-authelia`, `conf.d-idp`, `10-idp-keycloak.caddy.template`, the per-overlay proxy volume stanzas | Static routes baked into `pystino-proxy` | Routes are code; they version with the release | 110 |
| `ca-bundle` services, `deploy/tls/`, `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `idp_ca_dance`, `ensure_idp_trust`, `bundle_contains_cert` | Back-channel over internal URLs (§2) | The dance exists only because of the hairpin | about 200 |
| House IdP: `idp.py`, `routers/idp.py`, `GATEWAY_IDP__*`, `idp_authorization_codes`, the signing-key mount, the minting-path refusals in Caddy | Bundled Authelia or any external OIDC | It has no device flow (so agent enrolment fails on it), it adds 900 lines of security surface, and it is a third identity option in every matrix (X6) | about 900 + tests |
| Bundled Keycloak: `docker-compose.idp-keycloak.yml`, `keycloak-realm.json.template`, the installer's Keycloak branch | Keycloak as an *external* issuer (plus the admin-REST sync adapter, §8), and `deploy/dev/keycloak.yml` for developing that adapter | About 730 MB RSS, realm drift identical to Authelia's, hardening gaps (O6) and a second bundled path to test. **Decision D2** | about 850 |
| `docker-compose.keycloak.yml` + `deploy/keycloak/setup.sh` (development Keycloak) | `deploy/dev/keycloak.yml` (kept, trimmed) | Still useful for adapter work; stays out of every preset | kept |
| Two-phase bring-up, `--phase2`, recorded shape, `INSTALLER_META`, `SCRUB` | `depends_on: service_healthy` / `service_completed_successfully` plus the idempotent `bootstrap` one-shot | The three "post-start values" are either not needed or can be made by a job inside the stack: the catalogue key has been gone since ADR 0081, the admin comes from OIDC (§8), and the chat database is created by `bootstrap` | about 1,000 |
| `profiles/*.env` + `profiles/overlays.sh` (ADR 0076's mechanism) | `pystino init --preset …`: Python data writing `.env` values and `COMPOSE_PROFILES` | The profile *idea* is kept. The derived overlay list is gone because profiles are compose profiles now | 706 |
| Pystino `install.sh`, `deploy/teardown.sh` | `pystino init` and `docker compose down [-v]` | Two installers for one stack | 676 |
| Cerea `installer/` (install.sh, lib/, tests/, teardown.sh) | Nothing in Cerea. Cerea ships an image and a dev `docker-compose.yml` for its own tests | Cerea stops owning the deployment | about 6,370 |
| Cerea `deploy/compose/docker-compose.playwright.yml` | The `fetch` profile in `compose.yaml` | Same service, one owner | 60 |
| `CHAT_REPO` build from a mutable checkout | Published `cerea` image, or `CEREA_SRC` in dev with a revision label | Traceability | — |
| `docker-compose.smoke.yml` in deploy | `deploy/dev/smoke.yml` (fake upstream), never copied into a distributed install | Keeps ADR 0076's rule 2 (smoke travels with nothing) structurally true | moved |
| Local-password web login (ADR 0043) for humans | OIDC for every human; break-glass through `pystino admin grant <email>` via `docker compose exec` | "OIDC-only" as asked. **Decision D3** decides between removing the web form and keeping it hidden and off | about 400 when removed |

**A bug found while porting:** nothing creates the `vector` extension in the chat's database. The installer's `ensure_chat_database` and `deploy/chat-db-init.sql` create only the role and database, and the chat's `ensureSchema` (`knowledge/db.ts`) uses the `vector` type without creating the extension, which the non-superuser `chat` role couldn't do anyway. A fresh install's knowledge store therefore fails on first use unless someone ran `CREATE EXTENSION` by hand. `pystino bootstrap` now creates it as the superuser, idempotently.

**Kept unchanged:** API keys (ADR 0010), OIDC bearer tokens on `/v1` with audience (ADR 0040), `x-bill-to` (ADR 0061), membership provenance and sync modes (ADR 0057), and account linking (ADR 0056), which the migration in §10 relies on.

**Not touched (out of scope by instruction):** `deploy/opencode/`, `deploy/compose/docker-compose.code-relay.yml`, Cerea's `deploy/code-relay/` and `/code`. They keep working on the old stack; §9 says how an agent component attaches to the new one.

## 4. Configuration model

**One source of truth per kind of fact, and exactly one file on the host that an operator edits.**

| Kind | Lives in | Written by | Edited by |
|---|---|---|---|
| Deployment facts: origin, TLS mode, profiles, versions, image registry, upstream key | `.env` (0600) in the deploy dir | `pystino init` | the operator (a text editor or `pystino set KEY=VALUE`) |
| Secrets: DB passwords, session/secret keys, Authelia HMAC/session/storage keys, OIDC client secrets | the same `.env` | minted once by `init` (`secrets.token_urlsafe`, `token_hex`) | nobody; `pystino rotate <name>` where rotation is safe |
| Multi-line key material (Authelia JWKS RSA key) | the `authelia-config` volume, created by `bootstrap` **only if absent** | `bootstrap` | never; backed up with the volumes |
| Topology and routes | `compose.yaml` + the Caddyfile in `pystino-proxy` | release | nobody (they are release artefacts) |
| Service config (the Authelia `configuration.yml`: clients, redirect URIs, policy) | baked into `pystino-authelia`; values via `{{ env }}` / `{{ secret }}` (Authelia's `template` filter, verified on 4.39.22) | release | nobody. A new client arrives with the image; a changed `.env` value changes the container's env, so compose recreates it |
| Identity *data* (Authelia `users_database.yml`) | the `authelia-config` volume, created once with the first admin | `bootstrap` (first run), then the operator or the console (D10) | per D10 |
| Runtime policy: identity-provider policy, quotas, redaction, models | Postgres rows, editable in the console | console | console |

Three rules make this hold:

1. **Separate generated config from state.** The Authelia YAML used to hold both the clients list (config, which should change when the release adds a client) and the keys (state, which must never change). Now the config is a release artefact (baked into `pystino-authelia`) that holds no secrets and no keys. It pulls secrets from the environment and the key from a file `bootstrap` creates once and never overwrites. Adding the `opencode-enrollment` client to an existing install becomes "upgrade and `up`". There is no regeneration step left to be unsafe. Rendering files on `up` was rejected: compose doesn't recreate a running container when a file in a volume changes, so a rendered change would silently not apply, which is the bind-mount staleness class again. The JWKS PEM and the storage key are state and persist; the storage key is in `.env`, so the opaque subjects in Authelia's sqlite stay stable.
2. **`.env` is flat, single-line and typed.** `init` writes it with a `PYSTINO_CONFIG_VERSION=1` header, and `pystino` validates it with pydantic before any `up` (`doctor`, and `bootstrap`, which fails the stack closed on a bad file). Two things leave `.env`: JSON and multi-line values (the chat's `MODELS` becomes a mounted file if it's ever needed), and the chat's `DOTENV_LOCAL` block. The chat takes plain `environment:` entries, because `$env/dynamic/private` reads the process environment, so the environment scrubbing goes away.
3. **Build args that matter at runtime become runtime config, or fixed release constants.**
   - `APP_BASE=/chat` is compile-time in SvelteKit, so published Cerea images are built with `/chat`, the only path any deployment uses (D13).
   - `PUBLIC_APP_NAME` is read at runtime already.
   - `INCLUDE_CONSOLE=true` is fixed for published gateway images.
   - `SPACY_MODELS` becomes two image variants (`-pattern`, `-ner`).

**Secrets lifecycle.** `init` mints every secret and never asks for one. The exceptions are values only the operator can know: the upstream provider key, and an external IdP's client secret. Secrets never appear on a command line (`init` reads them from prompts or `--from-file`) and never in `docker inspect` of the host shim. Backup is `.env` plus the named volumes `postgres-data`, `chat-mongo-data` and `authelia-config`/`authelia-data`; `doctor` prints that list. `GATEWAY_SECRET_KEY` rotation keeps ADR 0027's comma-list semantics.

**Volume names are kept** (`postgres-data`, `valkey-data`, `chat-mongo-data`, `authelia-data`, `caddy-data`, `caddy-config`). An adopted install keeps its compose project name (§10), so the new file mounts the same volumes with no data copy.

## 5. What replaces the bash installer; upgrades

A `pystino` console script in the gateway package (`gateway.deploy`, beside `gateway.cli`). Tests are pytest. It runs from the gateway image, so the host needs Docker and nothing else. In dev it also runs from the checkout (`uv run pystino …`).

| Command | Where it runs | What it does |
|---|---|---|
| `pystino init [--preset homelab\|team\|enterprise\|satellite\|generic] [--mode dev\|dist] [--origin URL] [--tls acme\|internal\|upstream] [--idp authelia\|external] [--admin-email E] [--non-interactive]` | host shim / `uv run` | Asks at most about 8 questions (fewer with flags), mints secrets, and writes `.env` + `pystino` shim + `proxy.d/`. In dist mode it also copies `compose.yaml`. Refuses to overwrite an existing `.env` |
| `pystino bootstrap` | the `bootstrap` service, on every `up` | Idempotent. Validates `.env`; ensures the chat Postgres role and database exist (password from `.env`, re-asserted every time, which fixes drift); creates the Authelia JWKS key and first-user file in `authelia-config` if absent (never overwrites); records `PYSTINO_BOOTSTRAP_ADMIN_EMAIL` for the gateway (§8). Exit 0 means the dependent services start |
| `pystino doctor` | shim | Checks the Compose version, `.env` schema, image revisions vs pins, origin reachability, back-channel discovery, backup list |
| `pystino upgrade <version>` | shim (runs the **target** version's image) | Writes the new `compose.yaml`, migrates `.env` keys across `PYSTINO_CONFIG_VERSION`, and bumps `PYSTINO_VERSION` and the pinned `CEREA_VERSION` from that release's manifest. It never runs `up` itself; the operator does, and `migrate` applies alembic |
| `pystino set K=V`, `pystino rotate <secret>` | shim | Typed edits of `.env` |
| `pystino admin grant\|revoke <email>` | `docker compose exec gateway` | Break-glass admin flag (replaces `gateway passwd --admin` for OIDC-only) |
| `pystino adopt <old-deploy-dir>` | shim | Migration from today's installs (§10) |

**The host shim** (`./pystino`, written by `init`, about 20 lines of POSIX sh): `docker run --rm -it -u "$(id -u):$(id -g)" -v "$PWD:/deploy" -w /deploy "${PYSTINO_REGISTRY}/pystino-gateway:${PYSTINO_VERSION}" pystino "$@"`, reading the two variables from `.env`. **First contact** in dist mode is a one-liner: `docker run --rm -it -u "$(id -u):$(id -g)" -v "$PWD:/deploy" -w /deploy ghcr.io/<ns>/pystino-gateway:1.4.0 pystino init`.

**Bring-up order is declarative:** `postgres` (healthy) → `migrate` (completed) → `bootstrap` (completed) → `authelia` (healthy, if on) → `gateway` (healthy) → `chat` → `proxy`. The gateway's OIDC discovery is lazy per client (ADR 0051 already built it that way), so it doesn't need the IdP to be up *before* it starts. What remains of "the IdP must answer first" is covered by `depends_on`, and the post-IdP gateway restart goes away.

**What the Cerea TUI becomes.** Nothing, initially. If a friendlier front-end is still wanted, it's a thin wrapper that calls `pystino init` with flags, which is §3.4's recommendation too.

**Upgrades.**
- *Dist:* `./pystino upgrade 1.5.0 && docker compose pull && docker compose up -d --wait`. Rollback means restoring the previous `compose.yaml`/`.env` (upgrade writes `*.bak-<version>`) plus a DB restore if migrations ran. Down-migrations aren't promised, so `doctor` tells you to snapshot first.
- *Dev:* `git pull` in the checkouts, then `docker compose up -d --build --wait`.

Both paths run `migrate` and `bootstrap`, so a new Authelia client or a new chat database grant arrives the same way everywhere.

## 6. Images: build, tag, publish

| Image | Repo | Dockerfile | Variants | Size today |
|---|---|---|---|---|
| `pystino-gateway` | Pystino | `apps/gateway/Dockerfile` (`INCLUDE_CONSOLE=true`) | — (also serves `migrate` and `bootstrap`) | 333 MB |
| `pystino-proxy` | Pystino | `deploy/stack/proxy/Dockerfile` (`FROM caddy:2.11-alpine` + Caddyfile) | — | about 90 MB |
| `pystino-authelia` | Pystino | `deploy/stack/authelia/Dockerfile` (`FROM authelia/authelia:4.39.22` + configuration.yml) | — | about 110 MB |
| `pystino-redaction` | Pystino | `services/redaction/Dockerfile` | `-pattern` (empty `SPACY_MODELS`) and `-ner` (`en_core_web_lg`, CC BY-NC-SA 3.0; **D6**) | 150 MB / 1.9 GB |
| `cerea` | Cerea | `Dockerfile` (`APP_BASE=/chat`, `sync-pyodide` inside) | — | 2.1 GB |

**Registry and visibility (D5, accepted):** `ghcr.io/paoloviviani/*`, **private for now**. Packages pushed with `GITHUB_TOKEN` from a private repository inherit its visibility. Pulling needs `docker login ghcr.io` with a token holding `read:packages`. `pystino init` (dist mode) and `doctor` check the Docker client config for a `ghcr.io` credential and print the exact login step when it's missing, and the host shims (`./pystino`, `scripts/cerea`) say the same when a pull is denied. **Going public later** is one setting per package (Package settings → Danger Zone → Change visibility), once the repositories are public. Nothing in the stack changes; the login simply stops being needed.

**Tags (lean, because private storage counts against the plan's Packages quota):**
- push to `main`: `edge` (moving);
- push to `deploy/rearch`: `rearch` (moving; lets the pipeline be exercised before merge);
- git tag `vX.Y.Z`: `X.Y.Z` and `X.Y`. A release tag is never overwritten; the job refuses if it exists.
- A PR builds and pushes nothing.

A moving tag leaves the previous build untagged, and a **cleanup job** (`actions/delete-package-versions`, untagged only) keeps the newest five untagged versions per image and deletes the rest. There are no per-commit tags: pins are by **digest**, which is an immutable reference without a tag. Provenance and SBOM attestations are **off**, because GHCR stores them as extra untagged manifests and pruning those would break the image index. They can be turned back on together with a cleanup that understands them (D8, when public).

Labels: `org.opencontainers.image.{source,revision,version,created,licenses}` (Apache-2.0).

**Pipeline** (GitHub Actions, `docker/build-push-action` with buildx): `linux/amd64` (arm64 is D7), GHA layer cache, `packages: write` via `GITHUB_TOKEN`. Each build's digest is written to the job summary, which is what `release.env` pins.

**Status of the workflows (D14):** written for both repos, and **refused by GitHub** from the agent's token with exactly `refusing to allow a Personal Access Token to create or update workflow '.github/workflows/images.yml' without 'workflow' scope`. They're parked in `deploy/ci/github-workflows/` with the one-line move. The token (a fine-grained PAT) needs *Repository permissions → Workflows: Read and write*, or you push them yourself.

**Release manifest and lockstep.** `deploy/stack/release.env` in Pystino holds `PYSTINO_VERSION`, `CEREA_VERSION`, `CEREA_DIGEST` and the upstream images (postgres, valkey, mongo, caddy, authelia, playwright), each pinned by tag and digest. `compose.yaml` takes its defaults from it, and `init` and `upgrade` copy it into `.env`. A Pystino release tag therefore names one tested pair, and the pair is what the fresh-install job ran.

**Cerea releases** stand on their own (`cerea:1.3.2`). The operator doesn't have to track them: upgrading Pystino brings the Cerea version that release pins. `CEREA_VERSION` in `.env` can be overridden deliberately, and `doctor` warns when it's off-manifest.

## 6a. How the layout lands in the repo

```
Pystino/deploy/
  stack/
    compose.yaml          # the one topology file (images only)
    compose.build.yaml    # dev: build: stanzas → PYSTINO_SRC / CEREA_SRC
    release.env           # pinned versions + digests (the compatibility manifest)
    proxy/Dockerfile, proxy/Caddyfile
    authelia/Dockerfile, authelia/configuration.yml   # static; Authelia's template filter reads env + key file
  dev/
    smoke.yml             # fake upstream (never shipped)
    keycloak.yml          # external-IdP dev target for the admin-REST adapter
  (legacy, deleted once §10 is done: compose/, caddy/, idp/, profiles/, keycloak/, tls/, install.sh)
apps/gateway/src/gateway/deploy/   # pystino CLI: init, bootstrap, doctor, upgrade, adopt
```

## 7. Repositories

You prefer two repos, for brand recognition. The review recommended merging them (§3.1), because cross-repo seams cause many of the bugs. Once the deployment has one owner, those two positions are closer than they look. Most of the seams the review listed are **deployment** seams (the installer driving the other repo's compose files and editing its tracked files, IdP clients for the chat generated in Pystino, two installers). This design moves every one of them into Pystino. What stays cross-repo is the *runtime* contract (`/v1`, `/v1/me`, `/v1/pystino/*` capabilities, OIDC client ids), and that is a real product boundary either way.

| Option | How versions stay in lockstep | Cross-repo change | Fits "no checkouts on host" | Brand | Cost / failure mode |
|---|---|---|---|---|---|
| **A. Two independent repos + pinned manifest in Pystino** (recommended) | `deploy/stack/release.env` pins `cerea` by digest; a Pystino tag names one tested pair | Cerea PR merges (backward-compatible or behind a flag) and publishes `sha-…`. A Pystino PR bumps the pin and carries the gateway half. Fresh-install CI tests the pair; release | Yes: images only | Two repos, two images, two changelogs | Two PRs for a cross-cutting feature. Mitigated by the contract tests and the capability endpoint, which make half-landed states safe |
| B. Git submodules (Cerea inside Pystino, or both in a meta repo) | Superproject pins a commit | Two commits plus a submodule bump, same as A but at source level | Irrelevant, since images are the artefact; submodules pin *sources* | Two repos | Detached HEADs, forgotten `--recursive`, and dirty-submodule confusion on this box's worktree-heavy workflow. They solve source pinning, which images already solve |
| C. Git subtree (vendor Cerea into Pystino) | The vendored copy is the pin | Edit in either place, then `subtree push`/`pull` | Same as B | The Cerea repo becomes a mirror | Two histories to reconcile; contributors don't know where to commit |
| D. Thin third "deploy/meta" repo | Its manifest pins both | Up to three PRs | Yes | Three repos | It adds a third owner for what Pystino already owns (compose, proxy, init). `pystino init` would then need to live somewhere else, or read a manifest from a repo it doesn't ship with. It recreates the "two owners of the deployment" problem |
| E. Monorepo, two published products | One commit, one CI run | One PR | Yes | Brand survives on image names, docs sites and READMEs (`ghcr.io/…/cerea`), but the GitHub repo is shared | Best engineering (the review's pick). It costs about 2 days (subtree/filter-repo import) and the repo-level brand you asked to keep |

**Recommendation: A, now.** It keeps the brands, and it becomes nearly as good as E once the deployment seams are gone (this design) and three mechanical guards exist:

1. **Pystino is the distribution.** It owns the compose, proxy, init, IdP config and the manifest. Cerea owns one Dockerfile and its app; it has no `deploy/` for the stack (the relay overlay is left alone until the thin agent lands).
2. **Runtime contract tests.** Cerea CI runs its gateway-facing server modules (`admin.ts` `callerIdentity`, the usage provider, the forwarder) against a real `pystino-gateway` container at the **pinned** version *and* at `edge`. Pystino CI runs the fresh-install job with the pinned `cerea` *and* with `cerea:edge` (non-blocking, as an early warning).
3. **Additive gateway API with feature detection.** Cerea reads `/v1/pystino/capabilities` (ADR 0074's namespace) instead of assuming a version. Gateway changes are additive within a minor, and removals wait one minor after Cerea stops using them.

**When to revisit (switch to E):** if over a quarter more than about a third of features still need paired PRs, or a manifest bump has broken the pair twice, the brand cost is worth paying. An import with `git subtree add --prefix apps/chat` keeps Cerea's history, and the published image names don't change, so users see no difference.

**Lockstep, stated as a procedure** (for option A):

1. A cross-cutting feature starts in whichever repo holds the *provider* side of the contract (usually the gateway), shipped dark or additive.
2. The consumer side (Cerea) merges behind capability detection, and its `edge` image publishes.
3. A Pystino PR bumps `CEREA_VERSION`/`CEREA_DIGEST` to that `sha-` build. Fresh-install CI must pass on the pair.
4. A Pystino tag makes the pair a release; Cerea tags its own `vX.Y.Z` on the same commit for its changelog.

**Paired branches** (like `opencode-enrollment` plus `code-panel`) become a Pystino PR whose manifest points at the Cerea branch's `sha-` image. CI tests the exact pair, and merge order is Cerea first, then Pystino.

## 8. Identity: OIDC-only, console-configured

### 8.1 What exists and what's asked

Much of the policy surface exists already. There is a per-provider row (ADR 0051) with `groups_claim`, mappings and `group_sync` (`every_login`/`first_login`/`never`, ADR 0057). Membership provenance is `oidc` or `manual`. Global `auto_provision` and `unknown_user_policy` live in `oidc_config` (ADR 0048), and ADR 0069 made `first_login` the default and removed claim-derived admin. What's missing:

1. **batch sync** (today's sync is just-in-time only, at browser login or on a `/v1` bearer call);
2. a **provider-capability model**, so the console offers only what a provider can do;
3. **admin from a claim**, back as a per-provider *opt-in* with provenance. This amends ADR 0069 and doesn't reverse its default;
4. a **group authority** knob that separates *where* groups come from and *how often* the IdP may answer;
5. the **house IdP** removed, with a migration.

### 8.2 What each IdP can offer (researched, with confidence marked)

| Provider | Groups in token | Pull (we list users/groups) | Push (IdP calls us) | Subject known before first login | Deprovision signal | Confidence |
|---|---|---|---|---|---|---|
| **Authelia 4.39, file backend** (bundled) | yes, `groups` scope | **read `users_database.yml`**: username, email, displayname, groups, `disabled` | none | **no**: `sub` is an opaque UUID minted at first OIDC use and stored in Authelia's DB | entry removed or `disabled: true` | High (file format is the one we generate; opaque subjects per 4.38+ docs) |
| Authelia, LDAP backend | yes | query the LDAP directory itself (the Authelia side adds nothing) | none | no (opaque) | LDAP | Medium; LDAP adapter not proposed now |
| **Keycloak 26** (external; dev overlay) | yes, via a group-membership mapper | **Admin REST**: `GET /admin/realms/{r}/users`, `/groups`, `/users/{id}/groups`, using a confidential client with a service account granted `realm-management: view-users, query-groups` | no stable built-in SCIM server (community extensions exist) | **yes**: `sub` = user id by default | `enabled=false`, deletion | High for the REST API; SCIM status unverified for 26.7 |
| Microsoft Entra ID | yes (group *ids*; overage over about 200 sends a Graph link instead) | MS Graph (`User.Read.All`, `GroupMember.Read.All`, app-only) | **SCIM 2.0 provisioning to our endpoint** | yes via `oid` claim (`sub` is pairwise per app) | SCIM `active=false`, `accountEnabled` | High |
| Okta | yes (groups claim filter) | Management API (API token) | **SCIM 2.0** | yes | SCIM | High |
| Authentik | yes | REST API (token) | **SCIM provider** | yes | SCIM | Medium |
| Google Workspace | **no groups claim** | Admin SDK Directory API (domain-wide delegation) | no generic SCIM out | yes | `suspended` | Medium |
| Generic OIDC | maybe | **none**: OIDC has no listing API | none | no | none. The only signal is a refresh failure or a back-channel logout, if the IdP sends one | High |

Two consequences shape the design:
- **one inbound SCIM endpoint** covers the enterprise IdPs (Entra, Okta, Authentik, JumpCloud, OneLogin) with one implementation;
- **pull adapters** are needed only for what we ship or develop against (Authelia file, Keycloak). Graph and Google stay on the shelf until someone asks.

### 8.3 The capability model

Each provider row gets a `kind`, which sets defaults and the available adapter, and the console renders only the controls that `kind` supports:

```python
class ProviderCapabilities:          # derived from kind (+ adapter config), never stored
    claims_groups: bool              # a groups claim can be read at login
    directory_pull: bool             # an adapter can list users + groups
    directory_push: bool             # the IdP can SCIM-push to us
    subject_before_login: bool       # a pulled user can be keyed (issuer, sub) before first login
    deprovision: bool                # the directory can tell us someone is gone
```

| `kind` | claims_groups | pull adapter | push | subject_before_login |
|---|---|---|---|---|
| `authelia` | ✓ | `authelia_file` | — | ✗ (matched at first login) |
| `keycloak` | ✓ | `keycloak_admin` | — | ✓ |
| `entra`, `okta`, `authentik` | ✓ | — (later: Graph etc.) | `scim` | ✓ (`oid` for Entra) |
| `generic` | ✓ (if configured) | — | `scim` if the IdP supports it | ✗ |

### 8.4 Data model (additive migration; nothing renamed)

`identity_providers` gains:

| Column | Type | Default | Meaning |
|---|---|---|---|
| `kind` | enum | `generic` | capabilities and adapter |
| `internal_base_url` | text null | null | back-channel base (§2); set automatically for the bundled Authelia |
| `group_source` | enum `claim\|directory\|none` | `claim` | **Group authority**: *where* the IdP's group answer comes from. `none` means the console is the only authority |
| *(existing)* `groups_claim` | text | `groups` | *which* claim (dotted paths supported) |
| *(existing)* `group_sync` | enum | `first_login` | **Refresh policy**: how often the IdP's answer is applied: `every_login` (IdP authoritative for what it granted), `first_login` (seed once, then the console owns), `never` |
| `admin_source` | enum `console\|claim` | `console` | **Admin authority**. `claim` means admin iff the claim/group below matches, refreshed per `group_sync` |
| `admin_claim` | text | `groups` | claim to read (dotted path) |
| `admin_values` | json list | `[]` | values that confer admin (after mapping, like ADR 0048) |
| `subject_claim` | text | `sub` | the identity key claim; `oid` for Entra. Changing it on a provider with users is refused |
| `sync_adapter` | enum `none\|authelia_file\|keycloak_admin\|scim` | `none` | batch sync mechanism |
| `sync_config_encrypted` | text null | null | adapter credentials (Keycloak client id/secret/realm; SCIM bearer hash), in ADR 0027's box |
| `sync_interval_minutes` | int | 60 | pull schedule; 0 = manual only |
| `sync_deprovision` | enum `disable\|ignore` | `disable` | what "gone from the directory" does. **Never delete**: the ledger keeps its rows (ADR 0048) |
| `sync_create_users` | bool | true | pre-provision accounts before first login (subject to `auto_provision`) |

`users` gains `admin_source` (`manual|oidc`, default `manual`), which is provenance for the admin flag, mirroring memberships. It also gains `deactivated_by` (`manual|directory|null`), so a directory can only *reactivate* someone it deactivated.

A new table **`directory_entries`** mirrors what an adapter last saw, one row per `(provider_id, external_id)`: `username`, `email`, `display_name`, `groups` (IdP names), `active`, `user_id` (null until linked), `first_seen_at`, `last_seen_at`. And **`directory_sync_runs`** records `started_at`, `finished_at`, `trigger` (`schedule|manual|push`), `dry_run`, counts and errors. The mirror is what lets Authelia's opaque subjects work: a pulled entry is linked to a user **at first login**, by `external_id` when `subject_before_login` holds, else by username (Authelia's `preferred_username`) plus a verified email.

### 8.5 Semantics (one reconciler, three triggers)

`reconcile(provider, identity_facts, trigger)` is the single function behind:
- browser login;
- a `/v1` bearer call (only when claims diverge, as today);
- a sync run (pull) or a SCIM write (push).

It applies these rules:

- **Groups.** With `group_source=claim`, facts come from the token. With `directory`, they come from the mirror (and the token's groups are ignored). With `none`, nothing is applied. `group_sync` gates *when*: a pull counts as a "login" for `every_login` and is skipped for `first_login` once the user exists. Provenance holds everywhere: only `oidc` memberships are ever revoked.
- **Admin.** With `admin_source=claim`, admin is set iff a mapped value matches, and `users.admin_source=oidc` is recorded. It is revoked only when `admin_source=oidc`. A console grant (`manual`) is never removed by the IdP. **Guard:** a reconcile that would leave zero active admins is refused and logged; break-glass stays available via `pystino admin grant`.
- **Deprovisioning.** A pull that no longer sees an entry, or a SCIM `active=false`/DELETE, sets `is_active=false, deactivated_by=directory` when `sync_deprovision=disable`. The gateway already refuses inactive users on every `/v1` path and in the console (`deps.py`), so access stops within one request. **Safety valve:** a single run that would deactivate more than `max(5, 10%)` of the provider's users stops and asks for a manual confirmation in the console (the classic "the IdP returned an empty list" failure).
- **Pre-provisioning.** `sync_create_users` creates users for entries whose subject is known. For Authelia's opaque subjects, entries sit unlinked and are shown as "not yet signed in", and an administrator can pre-assign groups to the *entry*. The assignment becomes a `manual` membership at link time.

**Safe defaults** (a new provider and the bundled Authelia): `group_source=claim`, `groups_claim=groups`, `group_sync=first_login`, `admin_source=console`, `sync_adapter=none` (bundled Authelia: `authelia_file`, interval 15 min, deprovision `disable`). The first run of any adapter is forced to be a **dry run**, whose diff the console shows before it may be enabled.

### 8.6 The first administrator without passwords

`PYSTINO_BOOTSTRAP_ADMIN_EMAIL` goes in `.env`, written by `init`. The **first** OIDC login with that **verified** email, on any enabled provider, while **no active admin exists**, gets `is_admin=true, admin_source=manual`. After that the variable is inert. With the bundled Authelia, `bootstrap` creates that person in `users_database.yml`, with a generated password `init` prints once, or one typed at the prompt. That removes `gateway passwd --admin`, the local-account adoption dance (`ensure_bundled_admin`) and the "promote by hand with psql" instructions.

### 8.7 Console UI

These screens build on `AdminSettings` (providers) and `AdminIdentity` (policy). A provider opens a detail page with sections, each showing only what the `kind` supports:

1. **Connection:** kind, issuer, client id/secret, scopes, internal URL (pre-filled for the bundled Authelia). A **Test discovery** button runs a back-channel fetch and shows the resolved endpoints.
2. **Claims:** subject, username, email and groups claims. **Preview with my last login** shows the raw claims of the admin's own last token (kept in memory only, for 10 minutes) and what they resolve to: mapped groups, admin yes/no.
3. **Groups:** a *Who decides group membership?* radio: *the identity provider (claim)* / *the directory (sync)* / *this console only*. Then *When does the provider's answer apply?*: *every sign-in* / *first sign-in only* / *never*, with the provenance rule stated beside it. Then mappings and the allowlist (existing).
4. **Administrators:** *Who decides who is an administrator?*: *this console* (default) / *a claim or group from the provider*, with claim and values. A warning explains the zero-admin guard and the break-glass command.
5. **Directory sync** (only if an adapter exists for the kind): the adapter credentials and a **Test** button (lists 5 users). Then the interval, deprovision policy, create-users toggle, **Run now (dry run)** / **Run now**, the last-run report (added, updated, deactivated, errors), and the diff for a pending confirmation. For SCIM: the endpoint URL `/scim/v2/{provider}`, **Generate token** (shown once, hash stored) and the last push received.
6. **Unlinked directory entries:** a list with *pre-assign groups*.

`AdminUsers` gains source badges (`IdP`/`console`) on the admin flag and on each membership (memberships already have provenance), plus "deactivated by directory".

### 8.8 How Cerea stays consistent

- **One issuer, two clients.** The `pystino-console` and `cerea` clients use the same issuer and scopes (`openid profile email groups offline_access`), and the same client ids on every IdP (the review found `cerea` vs `pystino-chat`). Both key people by `(issuer, sub)`. *Cerea today keys by `sub` alone* (`updateUser.ts`, `hfUserId: sub`); it gains the issuer in the key, with a migration that sets it on existing documents from the configured provider.
- **The gateway is the only authorisation authority.** Cerea never derives admin, groups or active status from claims. It already asks `GET /v1/me` (`admin.ts` `callerIdentity`) for admin; that becomes the rule for groups (sharing) and active status too. The HuggingFace-org `isAdmin` in `updateUser.ts` is deleted. `whoami-v2` and `TRUSTED_EMAIL_HEADER` (review C7/C8) are being deleted on `thin-agent/quickwins`, so this design assumes they are gone and doesn't touch them.
- **Freshness.** Cerea caches `/v1/me` per session for 60 s. A 401/403 whose body says the account is inactive ends the Cerea session. Since `/v1` itself refuses inactive users, a directory deprovision stops chat completions immediately and the chat UI within a minute. No webhook is needed.
- **Multi-provider.** Cerea signs in against one issuer (`OPENID_*`), the deployment's primary. If a deployment enables several providers on the gateway, Cerea's login uses the gateway's first enabled provider. Supporting a picker in Cerea is out of scope and noted as a later option.

### 8.9 Removing the house IdP (code)

Delete `idp.py`, `routers/idp.py`, the `GATEWAY_IDP__*` settings (a startup error if set, per ADR 0065's rule), and `IdpAuthorizationCode` (drop migration after the adoption window). Remove the house-issuer alias resolution in `_identity_select`, but only after `pystino adopt` has linked every `issuer="local"` user (§10). The local-password door: see D3.

## 9. The agent machine as a pluggable component

The coding-agent machine side is being rebuilt on `thin-agent/main`: `pystino-agent`, a thin agent over `opencode serve` that dials **out** to Cerea over WSS. The paseo relay is deleted on that branch; the old installer still wires it in. The new stack carries the agent side as the interface below, with **no relay**. It's a switch, not a service: `pystino init --agents` (`CODE_AGENTS_ENABLED=true`).

**What the stack provides** (built on `deploy/rearch`):
1. **Identity:** the machine's public OIDC client `opencode-enrollment` (device grant, loopback PKCE, `refresh_token`, audience `pystino-api`, the `agent_machine` lifespan: 1 h access, 90 d refresh), baked into `pystino-authelia`, so it reaches every install on upgrade. External IdPs register the same client.
2. **Dial-in:** `wss://<origin>/chat/api/v2/code/machine` rides the existing `/chat/*` route (Caddy proxies the upgrade), so there's no extra service, port or snippet.
3. **Token validation:** the chat receives `CODE_MACHINE_ISSUER` (default: the browser login's issuer), `CODE_MACHINE_AUDIENCE=pystino-api` and `CODE_MACHINE_CLIENT_ID=opencode-enrollment`, which is what thin-agent's `machineAuth` reads.
4. **Inference and billing:** `/v1` with bearer tokens and `x-bill-to` (ADR 0040/0061), unchanged.
5. **Extension hook** (for anything more): a component's own `compose.<name>.yaml` in `COMPOSE_FILE`, plus a `proxy.d/<name>.caddy` snippet in the mounted directory.

**Integration note (a real seam):** thin-agent's `machineAuth.ts` fetched discovery and JWKS from the *public* issuer URL, which on the new stack is the hairpin §2 removes. The fix is on branch **`deploy/thin-agent-backchannel`** (Cerea, based on `thin-agent/main`, commit 0f718e23). It's self-contained, depends only on `OPENID_INTERNAL_URL`, and is ready to cherry-pick. `machineAuth.spec` (11) and a new spec (4) pass, and check is 0/0.

**What the stack does not do:** install anything on the agent machine, or know about paseo. Distributing `pystino-agent` binaries (a goreleaser job beside the image workflow) is the thin-agent team's call.

## 10. Migration from today's installs

There are two populations: this box's live stack (`llm-platform`, edge shape, bundled Authelia, relay), and anybody who ran either installer.

### 10.1 Deployment migration: `pystino adopt <old-deploy-dir>`

1. **Read** the old `deploy/.env` (plus Cerea's recorded installer metadata if present), and map old keys to the new schema. For example: `PUBLIC_HOST/HTTPS_PORT/TLS_DIRECTIVE` becomes `SITE_ADDRESS/TLS_MODE`; edge becomes `TLS_MODE=upstream`; `IDP_*` secrets become `AUTHELIA_*`; `CHAT_REPO` becomes `CEREA_SRC` (dev) or a version pin (dist). Unknown keys are reported rather than dropped.
2. **Keep** `COMPOSE_PROJECT_NAME` equal to the old project (`llm-platform`), so the same named volumes are mounted: postgres, mongo, valkey, authelia-data, caddy-data.
3. **Copy Authelia state:** the JWKS PEM and `users_database.yml` from the old `deploy/idp/` into the `authelia-config` volume. The storage encryption key, session and HMAC secrets go into `.env` **verbatim**. This is the critical step: Authelia's opaque subjects live in `authelia-data` and are decrypted with the storage key, so preserving both keeps every `(issuer, sub)` identical, and nobody is re-provisioned.
4. **Write** `.env`, `compose.yaml` (dist) and `proxy.d/` (the relay snippet if the relay was on). Print the diff and the cutover commands. **Adopt doesn't stop or start anything.**
5. **Cutover** (operator), in this order:
   - `docker compose down` in the old directory, **without `-v`**;
   - in the new directory, `docker compose run --rm --no-deps -v "$PWD/adopt/authelia-config:/import:ro" bootstrap pystino bootstrap --import-only /import`;
   - `docker compose up -d --wait`.

   The import must come after the old stack is down and must use `--no-deps`. The adopted project shares the old project's name, so starting any of its services earlier would recreate the live containers.

   **When the new Cerea carries the thin-agent machine link** (from `thin-agent/main`): its `codeDevices` index on `{ userId: 1, updatedAt: -1 }` becomes non-partial. On `main` it has `partialFilterExpression: { userId: { $exists: true } }`, and both keep the default name **`userId_1_updatedAt_-1`**. Mongo refuses to re-create an index under the same name with different options; it logs an error and keeps the old one. So before the new chat starts: `docker compose up -d --wait chat-mongo`, then drop `userId_1_updatedAt_-1` *if it is the partial one*. `adopt` prints the exact `mongo --eval` line, which is safe to repeat. The same applies to an `upgrade` across that change. It belongs in a Cerea migration routine on `thin-agent/main`, so the drop happens by itself; until then it's a cutover step. Rollback is `down`, and then `up` in the old directory, which is untouched. Downtime is about a minute.

Verification before cutover: `pystino doctor --against-running` compares image revisions, env and volumes with the running containers, read-only.

### 10.2 Identity migration off the house IdP

Users signed in through the house IdP are rows with `issuer="local"` and `subject=<casefolded email>` (ADR 0068's alias).

1. Enable the new provider (bundled Authelia, or external) with **`link_local_by_email=true`** (ADR 0056). Each person's first login with a verified matching email links the new identity to their existing row via `user_identities`. The row keeps its ledger, API keys, memberships, admin flag and default billing group.
2. For the bundled Authelia, `pystino adopt --export-house-users` writes each active local user into `users_database.yml` with a random password. Authelia's password-reset e-mail flow is enabled when SMTP is configured (the gateway's `email_settings` are reused); otherwise the operator hands out the passwords printed once.
3. **Cerea:** its user documents are keyed by the house IdP's `sub`, and the new issuer's `sub` differs. A one-shot `cerea migrate-users --by-email` rekeys by verified email: `{hfUserId: oldSub}` becomes `{issuer, sub: newSub}` on first login from the new issuer, so conversations, memory and knowledge bases follow the person. It is implemented as a login-time lookup-and-rekey behind `CHAT_MIGRATE_ISSUER_FROM=<old issuer>`, so no batch pass has to know every new subject in advance.
4. After a window (say 30 days, or when `pystino doctor` reports no unlinked local rows with recent logins), the house-IdP code is deleted, and the gateway refuses `GATEWAY_IDP__*` at startup.

**The live stack doesn't need step 1–3:** it already runs bundled Authelia (`llm-platform-authelia-1`). Only local password accounts matter (the break-glass admin), and they are covered by D3.

### 10.3 Transition period

The old installer and compose files stay in the repos, untouched and marked legacy, until the live stack has been adopted and a fresh-install CI run is green on the new path. Deleting them is the last phase, not the first, so the live stack always has a known-good way back.

## 11. CI

Shaped by the **GitHub free plan's Action minutes** (2,000 a month for private repositories on Linux runners, counted per job and rounded up to the minute). The rules:
- no image builds on PRs;
- path filters everywhere, so a skipped workflow costs nothing;
- one job wherever the steps can share a runner;
- layer and package caches;
- `cancel-in-progress` on PR workflows;
- the expensive tests only on release PRs, on demand, or weekly.

All workflows are parked in `deploy/ci/github-workflows/` until the token has GitHub's workflow permission (D14).

One PR workflow per repository: `thin-agent/main`'s parked `ci.yml` (Pystino: pytest, ruff, mypy, Go; Cerea: check, lint, vitest) is folded in at the same path, so the integration merge resolves to one file.

| Workflow | Repo | Trigger | Jobs | Est. minutes/run |
|---|---|---|---|---|
| `ci.yml` | Pystino | PRs (docs excluded) | `changes` (~1) → only what changed: gateway (ruff, mypy, pytest, compose/Caddy parse), console (typecheck, tests), go (every module in one job) | ~1 + 7 / 3 / 2 |
| `images.yml` | Pystino | push to main (path-filtered), `v*` tags | 4 images (cached) + 1 cleanup job + release-pin check on tags | ~8 cached, ~20 cold |
| `stack.yml` | Pystino | release PRs (`release/*`), manual, **Mondays** | fresh install + upgrade, each with a scripted browser sign-in | ~25 |
| `ci.yml` | Cerea | PRs (docs excluded); Mondays for the client project | one job: lint, check, server + ssr tests (Mongo service); weekly: client project in the Playwright image | ~9 (weekly +8) |
| `contract.yml` | Cerea | PRs touching gateway-facing code (**pinned** gateway); **Mondays** (`edge`, non-blocking) | the gateway contract spec against a real gateway | ~5 |
| `images.yml` | Cerea | push to main (path-filtered), `v*` tags | the chat image (pyodide sync inside) + cleanup step | ~15 |

**Estimated monthly minutes**, assuming about 30 PR pushes to each repository and about 15 merges to main a month:

| | Runs/month | Minutes |
|---|---|---|
| Pystino PR checks (every run pays ~1 for `changes`; about half run the gateway job, a third the console, a few Go) | ~30 | ~170 |
| Pystino images | ~15 | ~120 |
| Pystino stack tests (4 Mondays plus about 1 release PR) | ~5 | ~125 |
| Cerea PR checks (30) plus the weekly client suite (4) | ~34 | ~300 |
| Cerea contract (about 8 PRs plus 4 Mondays) | ~12 | ~60 |
| Cerea images | ~15 | ~225 |
| **Total** | | **~1,000 of 2,000** |

Compared with keeping both sets side by side, folding in the thin-agent workflows saves about 400 minutes a month: they ran on every push to main as well as on PRs, Cerea's three jobs each paid for `npm ci`, and the client suite ran on every PR.

**Actual, first runs (2026-09-24).** Billed as GitHub bills: each job's duration rounded up to a whole minute.

| Run | Jobs (duration → billed) | Billed | Estimate |
|---|---|---|---|
| Pystino PR CI, every job triggered | changes 6 s → 1, gateway 227 s → 4, console 70 s → 2, go 57 s → 1 | **8 min** | ~13 (1 + 7 / 3 / 2) |
| Cerea PR CI | check 311 s → 6 (client skipped) | **6 min** | ~9 |

Activating CI cost about 35 minutes in all, across the failed and cancelled iterations. The fixes were a flaky agent test (fixed by the thin agent), a pyodide spec that needs a generated dist (now skips without it), and one force-push that cancelled a run. At these rates the monthly estimate of ~1,000 of 2,000 minutes is conservative. Images, stack and contract are `workflow_dispatch` only while publishing is held; each file carries the one-line `on:` that turns it on.

The largest levers, if the budget tightens:
- build the Cerea image only on tags, with `workflow_dispatch` for ad-hoc images (−200);
- move Cerea's lint and check to a pre-commit hook and keep only the tests in CI (−100).

GitHub-hosted runners have AVX, so Cerea's Mongo-backed specs run there, unlike on this box.

## 12. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Authelia doesn't honour `X-Forwarded-Host/Proto` on the back-channel, so the `iss` mismatches | **retired for discovery** | the back-channel rule fails for the bundled IdP | **Verified 2026-09-24** against a throwaway `authelia/authelia:4.39.22`: `GET http://<internal>:9091/authelia/.well-known/openid-configuration` with `X-Forwarded-Proto: https` and `X-Forwarded-Host: example.test` returns `issuer=https://example.test/authelia` and public endpoints. Without the headers it returns nothing, so the headers are **mandatory**, not optional. **Then verified end to end** with the baked `pystino-authelia` image, `bootstrap`'s key and users file, and `init`'s `.env`, from a non-loopback source (the Docker bridge): a PKCE code flow for `pystino-console` over the internal address. Both `id_token` and `access_token` carry the **public** issuer, `aud=pystino-api` is on the access token, `email_verified` is a real boolean, and the argon2 client-secret digest is accepted. The trial also found that Authelia's template filter executes YAML *comments*, so template syntax in a comment crashes it at start (fixed, with a test) |
| Authelia deprecates plaintext client secrets | certain | a future Authelia refuses the config | Verified: 4.39.22 warns that `$plaintext$` "will be removed in the near future". `init` stores an argon2id **digest** of each client secret in `.env` beside the plaintext (the gateway and chat need the plaintext), and the config reads the digest |
| Losing Authelia's storage key or `authelia-data` on adoption re-keys every user | low | every user gets a new account (ledger split) | `adopt` copies keys verbatim, and `doctor --against-running` checks that the subject of a known user is unchanged before cutover |
| `APP_BASE` is compile-time, so a published Cerea image only serves `/chat` | certain | no custom base path | D13; nobody uses another path |
| The published NER redaction image redistributes a CC BY-NC-SA model | certain if published | licence exposure | D6: publish only `-pattern`, and build `-ner` locally in dev mode |
| Compose-version dependence (`profiles`, `required: false`, `--wait`) | low | old Docker hosts fail | `doctor` checks, and `init` refuses Compose < 2.24 |
| Transition: two ways to deploy for a while | certain | confusion | legacy is marked in READMEs; deleting legacy is an explicit phase |
| Chat image build in CI (about 300 MB pyodide sync, 2 GB image) is slow | high | about 15 min builds | GHA cache; build `cerea` only when Cerea changes (it's Cerea's pipeline anyway) |
| A batch sync disables people en masse on an IdP glitch | medium | outage | the dry-run-first rule and the mass-deactivation threshold (§8.5) |
| Admin from claim re-opens the ADR 0069 concern | low | an IdP admin becomes a gateway admin | opt-in per provider, provenance, the zero-admin guard, and the default stays `console` |
| Overlap with `thin-agent/quickwins` | medium | merge conflicts | That branch hardens the Keycloak realm template (O6) that §3 proposes to demote to a dev overlay, so if D2 is accepted the hardening moves with it into `deploy/dev/keycloak.yml`. Its CI workflows and mine use distinct file names. `auth.ts`/`handle.ts` edits here are limited to the `/v1/me` freshness check and issuer-in-key |

## 13. Implementation plan and status

Phases are ordered by how unambiguous they are. Everything lands on `deploy/rearch`, and legacy files stay until phase 5.

| Phase | Status (2026-09-24) |
|---|---|
| **1. Config and bring-up core** | **Done and verified.** `deploy/stack/`, `pystino init/bootstrap/doctor/set/upgrade/adopt/admin/release-pin`, the gateway and Cerea back-channels. **A fresh distributed-mode install from the `:rearch` images was brought up on this box** (project `pystino-rearch`, chat included, all services healthy). A scripted browser sign-in went through the proxy, Authelia and the gateway's back-channel, and `/api/me` showed the bootstrap address as admin. The chat signed in on the same session over its own back-channel, and its user carries the issuer. No `SSL_CERT_FILE` and not one certificate error. Torn down |
| **2. Image pipeline** | **Written, lean for the free plan, parked (D14).** GHCR pushes from this box are refused for the agent's PAT (`permission_denied: The token provided does not match expected scopes`), so images publish only through CI's `GITHUB_TOKEN`. The images were built locally for the trials and removed afterwards |
| **3a. Identity policy** | **Done:** kind and capabilities, group source, admin source with provenance and the last-admin guard, subject claim, console UI |
| **3a′. Bootstrap admin** | **Done** |
| **3b. Directory sync + D10** | **Done:** mirror, Authelia-file and Keycloak adapters, one engine, forced first dry run, mass-deactivation valve, scheduler with a Valkey lock, console Directory and People dialogs |
| **3c. SCIM inbound** | **Done:** `/scim/v2/<provider>` Users and Groups, per-provider token |
| **3d. Cerea consistency** | **Done:** admin from `/v1/me` (60 s cache; a 401 ends the session), issuer recorded and enforced, `CHAT_MIGRATE_ISSUER_FROM` rekey, HF-org admin removed |
| **4. Adopt + cutover** | **`adopt` done and rehearsed.** A legacy-installer-shaped deployment (old generator, old compose overlays, real Authelia state) was adopted, cut over and signed into through the new stack: the **same Authelia subject before and after, one account, still administrator**. The rehearsal found two adoption bugs, both fixed: an adopted provider row got neither the internal URL nor the `groups` scope. The live stack was later **replaced by a fresh install instead** (no data needed preserving; §13.3), so §13.1 was never executed. `doctor --against-running` was not built |
| **5. Delete legacy** | **Done:** house IdP, local-password door, ADR 0046 token endpoints, bundled Keycloak, edge shape, CA bundle, all overlays, both bash installers (about 8,400 lines). Note: commit `d2e1ff3` carries the legacy deploy-file deletions as well as the door removals, because they were staged together; `59a9f23` has the docs and dev fixtures |

**Test status at the end:** the full gateway suite passes, and mypy (strict) is clean over 113 files. The console type check is 0 and its suite 228/228. Cerea `npm run check` is 0/0 and its new specs pass (real Mongo). **Known gap:** the gateway's live scripts (`scripts/*_live.py`) still sign in through the removed password door. Their shared helper `scripts/live_session.py` needs porting to an OIDC login, and `deploy/ci/e2e_login.py` is the model.

### 13.1 Live cutover plan (`llm-platform`, when you decide; D12)

Preconditions:
- the workflows are activated and `main` builds have published `pystino-*:edge` and `cerea:edge`, or a release tag;
- the Cerea image you run includes `thin-agent/main`, with `deploy/thin-agent-backchannel` merged, if the agent panel is to work.

1. On the host: `docker login ghcr.io` with a `read:packages` token.
2. `docker run … pystino-gateway:<version> pystino adopt /home/ubuntu/test/Pystino/deploy --tls upstream --http-port 8443 --dir /opt/llm-platform`. It reads only: the edge shape becomes `TLS_MODE=upstream`, with NetBird still terminating TLS and forwarding to 8443. Add `--agents` via `./pystino set CODE_AGENTS_ENABLED=true`. The relay isn't carried; the thin agent dials the chat directly.
3. `./pystino doctor`. It flags a leftover `GATEWAY_LOCAL_AUTH__ENABLED` from the old `.env` as retired (the old installer set it true on the edge shape). The new `.env` doesn't contain it.
4. Stop the old stack from its own directory, **without `-v`**.
5. `docker compose run --rm --no-deps -v "$PWD/adopt/authelia-config:/import:ro" bootstrap pystino bootstrap --import-only /import`
6. Before the new chat starts: `docker compose up -d --wait chat-mongo`, then the printed `mongo --eval` line, which drops `codeDevices` index `userId_1_updatedAt_-1` only if it's the old partial one.
7. `docker compose up -d --wait`.
8. Sign in at `https://cerea.example.org`. The old local admin account becomes the Authelia login with the same verified email (`link_local_by_email`, which the old installer set), so keys, spend and admin carry over.
9. Rollback: `docker compose down` (no `-v`) here, then start the old stack as before; its files were never touched.

### 13.2 Reproducing the trials

`deploy/ci/stack.yml` is the fresh-install and upgrade trial as CI runs it. By hand, on any box:

```sh
uv run pystino init --dir /tmp/stack --mode dev --tls internal --origin https://stack.pystino.test:18443 \
  --https-port 18443 --http-port 18080 --gateway-port 18000 --admin-email ops@pystino.test --preset homelab --project pystino-trial
cd /tmp/stack && docker compose up -d --build --wait
uv run python deploy/ci/e2e_login.py /tmp/stack '<password init printed>' --chat
docker compose down -v
```

### 13.3 Integration and the live install (2026-09-24)

**Integration.** `integrate/all` merged `thin-agent/main`, `deploy/rearch` and (Cerea) `deploy/thin-agent-backchannel`, then fast-forwarded `main`. Pystino `main` = `ab80fb9`, Cerea `main` = `820b0700`. CI resolves to the one lean `ci.yml` per repo, still parked. Relay, paseo and old-installer references are gone in favour of `pystino init --agents` and `pystino-agent enroll`/`run`.

Bugs the integration and live checks found, all fixed with tests:

| Found by | Bug | Fix |
|---|---|---|
| a clean worktree's test run | `deploy/stack/release.env` was never committed: `.gitignore`'s `*.env` swallowed it, so every clean clone lacked the release manifest | explicit re-include |
| reading the shim for the live install | in dist mode the CLI treated `PYSTINO_DEPLOY_DIR` (the host path) as its working directory inside the container | files go to `--dir`/cwd; the variable is only the host path recorded in `.env` |
| the fresh-install trial, team preset | the gateway would not start with redaction on: `init` never minted `REDACTION_PLACEHOLDER_KEY` and `adopt` never carried it | minted, carried and checked by `doctor`; a new test runs the gateway's `Settings` on compose's environment for every preset |
| the live machine check | the machine link's upgrade handler ignored the `/chat` base path, so every machine socket was dropped (502) | compare with `base`; a spec with `base=/chat` |
| reading the pairing dialog | its printed `--cerea` lacked `/chat` | the origin carries the base |

**Verified on the integrated tree:**
- Pystino: pytest 1470 (plus the new tests), mypy strict, ruff check, console tsc and 228/228, and Go gofmt, vet and test.
- Cerea: check 0/0, lint, and vitest server+ssr: 1965 pass, with one pre-existing failure, `replayRoundTrip` "degrades the oldest turns", which fails identically on the old `main`.
- Cerea Playwright: the `/code` suite, P0 and parity, 35/35 in chromium.
- A fresh dist-mode trial (team preset, chat, `--agents`, through the documented `docker run … pystino init`) passed the scripted sign-in to the console and the chat, and was torn down.

**Live.** The old `llm-platform` was backed up to `/home/ubuntu/backups/llm-platform-2026-09-24/`:
- `gateway.pgdump`, which lists 26 tables with data;
- `chat-mongo.archive.gz`;
- `old.env` (0600);
- `idp/`;
- `SHA256SUMS`.

It was then wiped: containers, volumes, network and images. A fresh install went into `/opt/llm-platform`:
- project `llm-platform`, same origin `https://cerea.example.org`;
- `TLS_MODE=upstream` on host port 8443 behind the NetBird edge, with 443 published but unused, and the gateway on 127.0.0.1:8000;
- the team preset plus `fetch` and `--agents`;
- locally built images `local/*:gab80fb9` and `local/cerea:g820b0700`;
- the old `GATEWAY_SECRET_KEY` carried over, so the backed-up provider keys stay decryptable.

What was verified live:
- `doctor` is clean;
- a scripted OIDC sign-in with real DNS and a verified certificate works to the console (admin) and to the chat;
- `/code` loads;
- `pystino-agent enroll` → `run` → confirm → paired → workspace works, and revoking ends the link and the refresh token.

**Redeployed (same day, M7 + M8):** the stack was wiped again, provider rows included, as the user asked (the provider is to be re-created by hand), and fresh-installed from local images of Pystino `9f5456d` / Cerea `70067318`. The install command was unchanged. The same live checks passed: `doctor`, console and chat sign-in, `/code`, enroll → confirm → paired → workspace → revoke.

**Follow-ups, landed on `main`:**
- `docs/deployment.md` gained sections on running without the registry and on TLS at an edge;
- `docs/agent-machines.md` is new, with the unit, LaunchAgent and build script in `deploy/agent/packaging/`;
- the live checks sign in over OIDC again (`scripts/live_session.py`);
- `pystino doctor --against-running` exists; `upgrade` re-creates the helper.

**Not verified live (earlier):** a chat completion and an agent prompt. The fresh gateway has no upstream key, and restoring the old provider rows into the live database was refused by the agent's permission guard, so it needs your action.

## 14. Decisions for the user

**All accepted on 2026-09-24 (D1–D15)**, with these specifics:
- **D5:** GHCR under `ghcr.io/paoloviviani/`, **private for now**; build and push now, on `main`, `deploy/rearch` and tags, with digest pinning; `init` detects the missing login; keep tags lean and prune untagged versions (see §6).
- **D9:** a Cerea-only install is `pystino init --preset satellite|generic`, and the Cerea-branded **`cerea init`** runs the same code: a console script in the gateway image, plus `scripts/cerea` in the Cerea repo, which the README points to.
- **D12:** the live test stack is cut over only after phase 4 passes, and the thin-agent test deployment waits for the new stack. That stack carries the agent side with no relay (§9).
- **D14:** the workflows were pushed and GitHub refused them (exact error in §6); they wait on the token's workflow permission.

The original recommendations are kept below for the record.


Each has a recommendation. Phases that depend on a decision wait for it, or proceed on the recommended default where the change is easily reversible (noted).

| # | Decision | Recommendation | Blocks |
|---|---|---|---|
| **D1** | Repo strategy | **Two repos + a pinned manifest in Pystino** (option A, §7); revisit a monorepo on the stated trigger | nothing now (A is the status quo plus a file) |
| **D2** | Keep Keycloak *bundled*? | **No.** It stays a first-class external IdP with the admin-REST sync adapter and a dev overlay | phase 5 deletion |
| **D3** | Local email+password door (ADR 0043) | **Remove the web form for humans**; break-glass is `pystino admin grant` via `docker compose exec`. Alternative: keep it compiled in, off by default, never in presets | phase 3a/5 (the new stack ships with it off either way) |
| **D4** | Admin from a claim | **Allow as a per-provider opt-in with provenance and the zero-admin guard**; the default stays console (amends ADR 0069, doesn't reverse it) | phase 3a admin UI |
| **D5** | Registry and visibility | **GHCR under `ghcr.io/paoloviviani/`, public packages** (images contain only OSI-licensed first-party and upstream code plus upstream bases). Approve before the first push | any push (the pipeline builds without it) |
| **D6** | Publish the NER redaction image? | **No**: publish `-pattern` only, build `-ner` locally (CC BY-NC-SA model) | phase 2 variant list |
| **D7** | arm64 images | **Later**: amd64 only until someone runs on arm | — |
| **D8** | Sign images (cosign keyless) | **Yes**, once publishing is on (cheap on GHA) | — |
| **D9** | Keep the satellite/generic presets (Cerea without a local gateway) | **Yes**, as `init` presets (profile `gateway` off); no extra topology | — |
| **D10** | Console-managed users for the bundled Authelia (the gateway writes `users_database.yml`: create, disable, reset password) | **Yes, in 3b**: it gives the bundled IdP the admin UI Authelia lacks | phase 3b |
| **D11** | SCIM inbound priority | **After 3b**, unless an Entra/Okta deployment is imminent | phase 3c |
| **D12** | When to cut the live stack over | after phase 4 passes `doctor --against-running` and a fresh-install CI run | phase 4 |
| **D13** | Published Cerea images fixed at base path `/chat` | **Yes** | phase 2 |
| **D14** | Activate the CI workflows | Move `deploy/ci/github-workflows/images.yml` into `.github/workflows/` in each repo, with a token or SSH key that has the `workflow` scope (the agent's token doesn't) | CI on PRs |
| **D15** | Consent screen for first-party clients | Switch `pystino-console` and `cerea` from `consent_mode: pre-configured` (a consent page on first login) to `implicit` (no page), matching ADR 0068's "first-party clients are auto-approved". Keep `pre-configured` for the agent machine client | UX only |
