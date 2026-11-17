# 0091 — A deployment repository, `cerea-deploy`; the installer leaves the gateway image

- Date: 2026-09-25
- Status: **accepted**. The user took the decision on 2026-09-25.
- Supersedes: from 0086, decision 2 (the Caddyfile baked into `pystino-proxy`), decision 5's mechanism (the Authelia configuration baked into `pystino-authelia`), and the part of decision 4 that ships `init`, `doctor` and `upgrade` in the gateway image. `bootstrap` stays. From 0087, the rejection of option 4 (a thin deploy repository).
- Amends: 0086 decision 6 (the published images) and 0087's pinning chain.
- Related: 0082 (the satellite and generic presets), 0088 (OIDC only, Authelia bundled).

## Context

Adoption depends on the first run once the project is open source. 0086 left operators with this path:

- `docker run` the gateway image to reach `pystino init`;
- a 20-line `./pystino` shim for every later step;
- `pystino set` to pin versions;
- `--mode dist` versus `--mode dev`.

None of it can be read before running it. The proxy and IdP configuration sit inside two images an operator never sees, and the operator types version numbers.

Projects operators already know (LibreChat, Immich, Authentik) use a different pattern: a repository you clone and read, with a compose file, a documented `.env`, and `docker compose up -d`.

0087 rejected a third "deploy" repository because it would add a third owner for what Pystino already owned. That rejection assumed the deploy repository would own code. It doesn't have to: it can hold operator-facing files only, while Pystino keeps the gateway image, `bootstrap`, and the Cerea pin.

Two constraints shape the rest. Serving the installer or images from the reference stack is ruled out, because it is a development box. And a gateway-only operator must not need a repository branded after the chat.

## Decision

1. **`paoloviviani/cerea-deploy`: OSI-licensed (Apache-2.0 since 0094), and the full stack.** It carries Cerea, Pystino, the bundled Authelia, Caddy and the add-ons. It is **private for now**, like Pystino and Cerea: operators clone it with credentials that can read it, and build images with `dev/build.sh` until images are published. Making it public, and so a credential-free `git clone` from a public URL, is a later decision for the user; nothing in the layout changes when it happens. Its contents:
   - `compose.yaml`: 0086's file, moved and not rewritten. Add-ons stay profiles chosen by `COMPOSE_PROFILES`.
   - `.env.example`: the documented source of truth. It explains every variable and names the command that generates each secret, so a hand-written `.env` is a supported path.
   - `./configure`: one Python 3 file, standard library only, executable. It mints every secret it can, and asks for the origin, the administrator's email, the preset, the TLS mode and the IdP. It writes `.env` at mode 0600 in `.env.example`'s layout.
     - Re-running it edits an existing `.env` and never overwrites it.
     - `--check` absorbs `doctor`, including `doctor`'s refusals (acme on an IP, Authelia on a dotless host, an http origin).
     - `--set` and `--unset` replace `pystino set`.
     - Every question has a flag for scripted installs.
   - `caddy/` and `authelia/`: plain files, mounted read-only into the **stock** `caddy` and `authelia/authelia` images. A mounted file changing is invisible to compose, which was 0086's reason for baking. Instead, each of those services carries a `cerea.config-rev` label holding a digest of its directory. `tools/pin` rewrites the label, and CI fails when it is stale. A release that changes the Caddyfile therefore changes `compose.yaml`, and `up -d` recreates the proxy.
   - `dev/build.sh`: builds the images from Pystino and Cerea at the pinned commits (or given refs), then writes `local/` overrides into `.env`. Building is a development concern and is kept out of the main README's path.

   Nothing in the repository ever builds or pulls unasked. The first run is `git clone`, `./configure`, `docker compose up -d`. The upgrade is `git pull`, `docker compose pull`, `docker compose up -d`.

2. **Nobody types a version.** Image tags are the defaults inside `compose.yaml`, rewritten by `tools/pin` on each release of the deploy repository. `.env` overrides them only for local builds or a mirror. The pinning chain gains one hop:
   - cerea-deploy pins a Pystino release;
   - that release's `release.env` pins Cerea, as 0087 decided;
   - cerea-deploy copies both into `compose.yaml`.

   Before anything is published, pins are `sha-<7>` tags, which `dev/build.sh` maps back to commits.

3. **Three published images:** `pystino-gateway` (also `migrate` and `bootstrap`), `pystino-redaction`, and `cerea`. `pystino-proxy` and `pystino-authelia` are no longer built. Every other image is upstream and pinned by tag.

4. **Client-secret digests are PBKDF2-SHA512**, because `./configure` has no dependencies. Authelia verifies any digest it supports, so argon2id digests in existing installs stay valid.

5. **The installer leaves the gateway image.**
   - Retired from the `pystino` CLI once cerea-deploy works end to end: `init`, `set`, `upgrade`, `doctor`, and the `./pystino` shim. The gateway image stops copying `deploy/stack`.
   - Staying, because they are runtime or break-glass: `bootstrap` (the one-shot service on every `up`: the first Authelia user, the chat's database role, extensions) and `admin grant|revoke`.
   - `release-pin` stays in Pystino for its own hop.
   - `adopt` stays unchanged until no install predates 0086.

6. **A Pystino-only deployment lives in Pystino** as a self-contained `deploy/compose.yaml` plus `deploy/.env.example`. It is not a profile of cerea-deploy and does not depend on it.
   - It runs gateway, migrate, bootstrap, valkey, postgres, and the proxy (stock Caddy with a mounted Caddyfile). Authelia and redaction are optional profiles.
   - It uses the same variable names and `.env` conventions as cerea-deploy. Moving to the full stack is therefore: carry `.env` and the project name, re-run `./configure` to add the chat's secrets, then `up`.
   - It replaces `deploy/stack/` once cerea-deploy carries the full stack.

7. **Drift guard, cheap in Actions minutes.**
   - Pystino's release workflow, **on tags only**, brings up cerea-deploy's `compose.yaml` with the smoke upstream and requires `/healthz` on the gateway and the chat.
   - cerea-deploy runs static checks on pushes to `main` and on pull requests, a minute or so each: `configure`'s tests, `tools/pin --check`, `compose config` on every profile, and `caddy validate` in all three TLS modes. Nothing is pulled or built there.

## Consequences

- An operator can read everything before running anything, and never pins a version.
- Proxy and IdP configuration changes are ordinary diffs in the deploy repository, reviewable by operators before they `git pull`.
- The Caddyfile and the Authelia configuration exist twice: the full copy in cerea-deploy, and a copy in Pystino without the chat's routes and client. That is the price of a self-contained Pystino-only deployment. The tag-time drift guard exercises the first copy; the second is Pystino CI's.
- A local edit to `caddy/` or `authelia/` needs `docker compose up -d --force-recreate proxy authelia`, or `tools/pin`, before compose notices it. The README says so.
- 0086's `COMPOSE_FILE` dev and dist modes disappear: there is one file, and local images are only an override.
- Existing installs made by `pystino init` keep their variable names. Their `.env` carries over, minus `COMPOSE_FILE`, `PYSTINO_DEPLOY_DIR` and the version pins, which `./configure --check` flags. The reference deployment moves by fresh install, on the user's instruction.

## Amendment 2026-09-25 (implementation)

As built. cerea-deploy main e8a178d; Pystino main ba25a9a (merge of `deploy/split`); Cerea branch `docs/cerea-deploy`.

- **`adopt` went too**, together with `bootstrap --import-only`. This reverses decision 5's "adopt stays unchanged": it imported from `init`, which was removed. No install that predates 0086 remains, because the reference deployment was fresh-installed from cerea-deploy at `/opt/cerea`.
- **The `cerea` entry point (`cerea init`) and Cerea's `scripts/cerea` are removed.** A Cerea-only install is cerea-deploy's `satellite` or `generic` preset.
- **`release.env` moves to Pystino `deploy/release.env`.** `release-pin` reads it there. It is a maintainer tool run from a checkout; the gateway image no longer carries any stack files.
- **The first Authelia password's digest is SHA512-crypt.** The gateway's bootstrap accepted only argon2 or `$6$`; it now also accepts `$pbkdf2`. Client-secret digests stay PBKDF2-SHA512. Both are implemented in the standard library and checked against Authelia 4.39.22.
- **The chat's renderer address follows the `fetch` profile.** `PLAYWRIGHT_WS_ENDPOINT` is empty unless the profile runs, and Cerea reads an empty value as "not configured" instead of probing a default host.
- **Still pending with the user:** the drift guard's `CEREA_DEPLOY_TOKEN` secret, and Actions access to the Cerea package.
