# 0086 — One stack, two image sources: a static compose project, `pystino init`, and published images

- Status: **accepted**, 2026-09-24
- Supersedes: the mechanism of [0076](0076-deployment-profiles.md) (profile fragments plus a derived overlay list; the profile *idea* survives as `init` presets), the edge half of [0035](0035-public-tls-exposure.md), the phase-1/CA-dance wiring of [0084](0084-bundled-idps-authelia-keycloak.md)
- Superseded in part by: 0091 (decision 2, decision 5's mechanism, and `init`/`doctor`/`upgrade` in the gateway image; the proxy and Authelia run stock images with config from the cerea-deploy repository)
- Related: [0082](0082-satellite-and-generic-profiles.md), [0087](0087-two-repos-pystino-is-the-distribution.md), [0088](0088-oidc-only-identity-with-directory-sync.md)
- Design: `reports/2026-09-24-deployment-rearchitecture.md` §2–§6, §10–§11

## Context

The deployment is about 6,000 lines of bash across two repos, and most of it compensates for choices:
- two Caddy shapes, one of which has no `conf.d` import, so the installer splices a tracked file and hits bind-mount inode staleness;
- a CA trust bundle that exists only because server-to-server OIDC hairpins through the public TLS listener;
- three identity options;
- a two-phase bring-up with resume memory;
- chat images built from whatever a local checkout holds.

Every live failure of the week of 09-16 was one of those shapes. There were two new requirements:
- a **development** mode that builds from local checkouts;
- a **distributed** mode that pulls versioned images, with no source on the host, upgraded by bumping a version.

Both should use the same config and the same bring-up.

## Decision

1. **One static `compose.yaml` in Pystino `deploy/stack/`, images only.**
   - Add-ons are compose profiles chosen by `COMPOSE_PROFILES` in `.env`.
   - Cross-profile `depends_on` use `required: false`.
   - A second file, `compose.build.yaml`, only adds `build:` stanzas pointing at `PYSTINO_SRC`/`CEREA_SRC`.
   - The mode is `COMPOSE_FILE` in `.env`: dev lists both files, distributed lists one.
   - The bring-up is `docker compose up -d --wait` in both modes.
2. **One Caddyfile, baked into a `pystino-proxy` image**, with `TLS_MODE=acme|internal|upstream`. `upstream` is the former edge shape. Routes are static. Components add routes through a *directory* mount (`proxy.d/`), never by editing a file.
3. **Server-to-server OIDC never crosses the proxy.** A provider's `internal_base_url` carries discovery, token, JWKS and userinfo, with forwarded headers naming the public origin. The browser sees public URLs only. Caddy's local CA is therefore never trusted by any server, and the trust bundle is deleted.
4. **`pystino` CLI in the gateway image replaces the installers:**
   - `init` writes `.env` and mints secrets;
   - `bootstrap` is a one-shot service on every `up`, and idempotent: it creates the chat DB/role, creates Authelia key material and the first-user file only if absent, and records the bootstrap admin;
   - `doctor` checks the install;
   - `upgrade <version>` swaps `compose.yaml` and bumps the pins;
   - `adopt` migrates old installs.

   The host needs Docker and a 20-line shim.
5. **Release config is separated from state.** The Authelia config is a static file baked into a `pystino-authelia` image. It uses Authelia's `template` filter to read secrets from the environment and the JWKS key from a file, which `bootstrap` creates once and never overwrites. Nothing is rendered on `up`, because compose doesn't recreate a running container when a file in a volume changes. A config change therefore always arrives as an image or env change, and compose recreates the container for those.
6. **Published images:** `pystino-gateway` (also `migrate` and `bootstrap`), `pystino-proxy`, `pystino-authelia`, `pystino-redaction` (`-pattern`, with `-ner` built locally) and `cerea` (base `/chat`).
   - Tags are `sha-<7>` and `edge` on `main`, and `X.Y.Z` and `X.Y` on tags.
   - Images carry OCI labels, provenance and an SBOM.
   - GHCR pushes are gated by a repository variable.
7. **Deleted:**
   - the edge compose/Caddyfile;
   - conf.d splicing;
   - `ca-bundle`;
   - the two-phase bring-up;
   - `overlays.sh` and the profile fragments;
   - both bash installers, after live adoption and a green fresh-install CI run.

## Consequences

- A release is one `compose.yaml` plus a manifest of image digests, so dev and prod differ only in image origin.
- Adding an OIDC client or a route reaches existing installs on the next `up`. Neither did before.
- Volume names are kept, so adopting an install keeps its data by keeping its project name.
- CI gains a fresh-install job and an upgrade job. They are the only tests the installer ever had that weren't run by hand on one box.
- Cost: Compose ≥ 2.24 is required, and `APP_BASE` is fixed at `/chat` for published chat images.

## Amendment 2026-09-24 (acceptance)

Accepted with decisions D1–D15. Images are published to `ghcr.io/paoloviviani/`, **private** while the repositories are; pulling needs `docker login ghcr.io` with a `read:packages` token, which `pystino init` and `doctor` detect. The tag set is lean because private storage counts against the Packages quota: `edge` on main, `rearch` on deploy/rearch, and `X.Y.Z`/`X.Y` on tags (never overwritten). Untagged versions are pruned beyond five, and attestations are off (pruning their untagged manifests would break images). Releases pin the Cerea image and every upstream image by digest (`pystino release-pin`). A Cerea-only install is `cerea init`, the same tool behind a Cerea-branded entry point. The agent machine is a switch (`--agents`), not a service, with no relay.
