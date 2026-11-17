# Brief: serve galopin's binaries publicly from the stack itself

Repo: Cerea. It contains the Go machine agent **galopin** in `agent/`. Worktree: `/home/ubuntu/.paseo/worktrees/gdist-cerea`, branch `feat/galopin-dist`, cut from `origin/main` after the galopin merge, with node_modules symlinked.

**Goal.** A person pairing a machine can install galopin with one command from the deployment itself, with no public repo or GitHub release needed:
```
curl -fsSL https://<origin>/chat/galopin/install.sh | sh
```
(`/chat` is the deployment's base path, SvelteKit `base`/`APP_BASE`; routes must work at root and under a base path.)

## 1. Build (`Dockerfile`)
- Add a Go builder stage (`golang:1.2x` matching `agent/go.mod`'s go line).
- Cache module download: copy `agent/go.mod` + `agent/go.sum` first and `go mod download` with a BuildKit cache mount, then copy `agent/`.
- Build 4 binaries (linux/darwin × amd64/arm64) with the SAME flags as `agent/packaging/build-dist.sh`: `CGO_ENABLED=0 go build -trimpath -ldflags='-s -w …'`, plus its version stamp (read the script; use the same `-X` variable and value source, e.g. a build arg `GALOPIN_VERSION` defaulting to the git describe / commit).
- Name them `galopin-<os>-<arch>`. Write `SHA256SUMS` (`sha256sum` format) and `REVISION`.
- Copy the lot into the final image at `/app/galopin-dist/`. Keep the growth to about 30 MB (4 stripped binaries); report the measured size.
- Build the image once to verify (`flock /tmp/heavy.lock docker build …` with a throwaway tag, e.g. `cerea-gdist-test`). Delete that image afterwards. Never touch the `llm-platform-*` containers or images.

## 2. Public routes (served by Cerea)
- `GET {base}/galopin/<os>-<arch>`: the binary. `application/octet-stream`, `Content-Disposition: attachment; filename="galopin-<os>-<arch>"`, `Cache-Control: public, max-age=…` (long), and an `ETag` from its checksum (answer `If-None-Match` with 304). Stream it; don't buffer the whole file.
- `GET {base}/galopin/SHA256SUMS` and `GET {base}/galopin/version`: text/plain.
- `GET {base}/galopin/install.sh`: a small POSIX `sh` script, `text/x-shellscript` (or text/plain). The serving origin plus base gets baked in at request time; use `PUBLIC_ORIGIN` when set, else the request origin, the same way `PairDeviceDialog.svelte` computes it.

  The script:
  - detects the OS (`uname -s` → linux/darwin) and arch (`uname -m` → amd64/arm64, mapping x86_64/aarch64/arm64); fails clearly otherwise;
  - downloads the binary and SHA256SUMS from that same origin with curl (or wget as a fallback);
  - verifies the checksum (`sha256sum`, or `shasum -a 256` on macOS) and aborts on a mismatch;
  - installs to `${GALOPIN_INSTALL_DIR:-$HOME/.local/bin}/galopin` with chmod 755;
  - on macOS, runs `xattr -d com.apple.quarantine` (ignoring failure);
  - warns if the install dir is not on PATH;
  - prints the next step: the exact enroll command for this deployment, pre-filled like the pairing dialog's (`galopin enroll --cerea <origin+base>`, plus the `--issuer`/gateway flags the dialog or `FeatureFlags` expose; check what `PairDeviceDialog.svelte` and `src/lib/server/api/types.ts` provide, and mirror them), then `galopin run`.
- Files map from an **allowlist of exactly the 4 binary names** plus the fixed names SHA256SUMS/version/install.sh. Anything else returns 404: no directory listing, no path traversal (`..`, encoded slashes, other names). The directory is configurable via `GALOPIN_DIST_DIR`, defaulting to `/app/galopin-dist`. When it's missing (dev), return 404 with a short text body.
- **Auth.** These routes must work with no session and no cookies. Exempt them in `src/lib/server/hooks/handle.ts` by **route id** (`event.route.id`), not by path prefix, following the existing pattern for unauthenticated routes (see how `/healthcheck` and the machine endpoint are treated). If the only existing pattern is path-based, add a small route-id allowlist and explain it in a comment. The AUTOMATIC_LOGIN redirect must not catch them either.

## 3. UI
In `src/lib/components/code/PairDeviceDialog.svelte`, show the one-liner `curl -fsSL <origin+base>/galopin/install.sh | sh` first (copyable, like the existing commands), then the enroll/run commands. Add a "Download manually" disclosure listing the 4 binaries and SHA256SUMS as links. Replace the current "Ask whoever runs this deployment for a download…" hint.

## 4. Docs
`docs/agent-machines.md`: make this the primary install path. Keep `agent/packaging/build-dist.sh` documented as building from source. Also check `agent/README.md`.

## 5. The Pystino proxy
Nothing to change in Pystino. Do verify that the proxy (Caddy) passes `/chat/*` through. Read Pystino's Caddyfile at `/home/ubuntu/workspace/Pystino/deploy/stack/proxy/Caddyfile` (and anything under `deploy/caddy/`) (read-only; do not edit or restart anything) and confirm there's no body-size limit or buffering directive that would break a ~10 MB download. Report what you found.

## 6. Tests (required)
- **vitest:** the allowlist (the 4 names are served; unknown names, `..`, `%2e%2e`, `%2f` and empty all 404), the headers (content-type, disposition, ETag, 304), `install.sh` templating (origin and base baked in, and the enroll command pre-filled), and the auth exemption (the route ids are exempt; a neighbouring route isn't). Run with `TEST_MONGODB_URL=mongodb://127.0.0.1:8797/ npx vitest run --no-file-parallelism <files>`.
- **shellcheck:** the rendered `install.sh` must be clean (`shellcheck -s sh`). If shellcheck isn't installed, report it; don't install system packages.
- **e2e (Playwright, a new spec `tests/galopin-dist.spec.ts`):** point `GALOPIN_DIST_DIR` at a temp dir that the test setup fills by building galopin for linux/amd64 from `agent/` (reuse `tests/machineHarness.ts`'s Go build), plus a generated SHA256SUMS. Without auth, the test:
  1. fetches `install.sh`;
  2. runs it with `sh` into a temp `GALOPIN_INSTALL_DIR` against the running app;
  3. checks that the checksum verified and that `<dir>/galopin --help` exits 0;
  4. fetches a bad name and gets 404.

  Run it at root and under `/chat`. The app's webServer env is in `playwright.config.ts`; add `GALOPIN_DIST_DIR` there. Build alone first (`flock /tmp/heavy.lock npm run build`, and `APP_BASE=/chat flock /tmp/heavy.lock npm run build` for `/chat`), then `E2E_SKIP_BUILD=1 E2E_APP_PORT=5331 E2E_MONGO_PORT=8797 MOCK_OPENAI_PORT=18831 MOCK_OIDC_PORT=18832 MOCK_MCP_PORT=18833 flock /tmp/heavy.lock npx playwright test tests/galopin-dist.spec.ts tests/code-enrollment.spec.ts --project=chromium --reporter=line` (plus `E2E_APP_BASE=/chat` for the /chat build). WebKit is not installed: always pass `--project=chromium`.
- `npm run check` 0/0, `npm run lint` clean, and the Go tests still pass (`cd agent && go test ./...`).

## Box rules (mandatory)
- Wrap every heavy command (build, docker build, check, Playwright, go test) in `flock /tmp/heavy.lock …`. The box OOMs otherwise.
- Use only the private ports listed above. Never use 5199. Kill only the servers you started, by recorded PID; never `pkill -f` with a pattern.
- Never run `ruff format`. Use `npx prettier --write` on the files you touched, and gofmt for Go.
- Cite ADRs by number only, never by link. Don't add dependencies without asking (a non-OSI dependency needs approval).
- No commit subjects starting "WIP:". Commit messages should be descriptive and end with `Co-Authored-By: Muse Spark <noreply@opencode.ai>`. Push the branch; don't merge to `main`.
- Never deploy, and never touch the `llm-platform-*` containers or images, or `/home/ubuntu/test/`.
- Delete `build/` and `test-results/` and your test docker image when done.
- If a capability is missing, stop and report it.

## Report
Reply with: the commits, the measured image growth, the route list with its headers, the auth-exemption mechanism, the Caddy findings, test results (commands plus pass counts at root and under `/chat`), and anything left undone.
