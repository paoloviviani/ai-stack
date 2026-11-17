# Brief: server sandboxes, build step 1 (ADR 0115)

Owner go 2026-11-13: "start server sandboxes". Design: `ai-stack/docs/adr/0115-server-sandboxes.md`. Read it fully; don't redesign it. Shared box rules: `ai-stack/reports/briefs/2026-11-12-box-rules.md`.

## Scope of this PR (step 1 only)

The control plane, off by default:

1. **`sandbox-manager`**, a new small service in the Cerea repo (`sandbox/manager/`, TypeScript on Node 24 like the rest, or Go if you can justify it in the PR; keep it small and dependency-light).
   - HTTP API with a service token (`SANDBOX_MANAGER_TOKEN`, constant-time compare), never exposed on the host:
     `POST /v1/leases` `{kind: "exec"|"machine", owner, conversation?, limits?}` → lease id; `DELETE /v1/leases/:id`; `POST /v1/leases/:id/exec` (run a command, bounded stdout/stderr, timeout); `PUT/GET /v1/leases/:id/files/*path` (bounded size, path normalised, no escape from the workspace); `GET /v1/leases/:id` status; `GET /v1/health`.
   - Talks to Docker **only through the socket proxy** (never mounts `/var/run/docker.sock` itself).
   - Every container it creates carries a manager label (e.g. `cerea.sandbox=1`, plus lease/owner/kind labels) and it refuses to act on containers without it.
   - Container hardening: runtime `runsc` by default (`SANDBOX_RUNTIME`, default `runsc`; `runc` allowed only with `SANDBOX_ALLOW_RUNC=true`, documented as dev/test only and logged loudly), non-root user, read-only root fs + a tmpfs/volume workspace, `no-new-privileges`, all capabilities dropped, pids/memory/CPU limits from the lease, no host mounts, network `none` for `exec` leases, a dedicated internal network through the egress proxy for `machine` leases.
   - Quotas/accounting skeleton: per-owner concurrent-lease cap and CPU-seconds/wall-time counters recorded per lease (in memory + an append-only audit log; the audit records follow OCSF-ish fields: time, actor, action, lease, outcome). No billing integration yet — leave a seam.
   - Idle reaper: leases have an idle timeout; on manager start, orphaned labelled containers from a previous run are removed.
2. **Socket proxy**: a restricted Docker API proxy (evaluate an existing small one, e.g. `tecnativa/docker-socket-proxy`-style allow-lists, but it must also restrict to labelled containers — if no off-the-shelf proxy can filter by label, write a tiny one in the manager's language that allows only the specific endpoints the manager uses and checks labels on container ids). Pin images by digest.
3. **Egress proxy**: default-deny forward proxy (HTTP CONNECT) with a per-class allow-list from config; logs host + decision, never bodies. Only `machine` leases route through it in this step; `exec` leases have no network.
4. **Kit**: three services under a compose profile (e.g. `sandbox`), off by default; `.env.example` entries with comments; `./configure` checks that `runsc` is registered as a Docker runtime (`docker info`) and, if not, leaves the feature off with a clear message. Never touch the host Docker daemon config from scripts.
5. **Cerea**: only a typed client (`src/lib/server/sandbox/client.ts`) + config parsing + a health line in logs. No `execute_code` wiring yet (that is step 2).

## This box

There is **no `runsc` on this box**, and installing gVisor needs sudo and a Docker daemon restart that would bounce the live stack: **do not install it and do not restart Docker.** Develop and run local integration tests with `SANDBOX_RUNTIME=runc SANDBOX_ALLOW_RUNC=true` under your own compose project name and ports (run `docker compose ls` first; never touch the `cerea` or `uireview` projects). In CI, add a job that installs gVisor on the GitHub runner (`runsc install` + Docker restart is fine there) and runs the integration tests with the real `runsc` runtime.

## Tests

Unit tests for the API (auth, path normalisation, size bounds, label checks, quotas, idle reaper), socket-proxy allow-list tests (denied endpoints, unlabelled containers), egress allow/deny tests, an integration test that leases an `exec` sandbox, runs `python -c`, puts/gets a file, verifies no network and the hardening flags via `docker inspect`, and releases it. Security tests: a lease cannot read another lease's files; path traversal is refused; exec output is bounded.

## Delivery

Worktree `../Cerea-wt-sandbox` on `feat/sandbox-manager` from origin/main. Focused commits; docs page `docs/sandboxes.md` (operator view); `kit/CHANGELOG.md` Unreleased bullet. PR body ends with "🤖 Generated with [Claude Code](https://claude.com/claude-code)". Wait for CI and fix failures at the cause. Do not merge. Report the design choices (language, socket-proxy choice, label enforcement), files, tests, CI, and what step 2 needs.

## Owner refinements (2026-11-13, later the same day)

- The sandbox services may run in the kit's compose (optional `sandbox` profile, off by default) **or on a separate host** (standalone compose under `kit/sandbox/`). Cerea reaches the manager only via `SANDBOX_MANAGER_URL` + token.
- Clear, documented resource constraints: limits for every service, per-lease defaults/maxima, global and per-owner concurrency, warm-pool size; sizing section in `docs/sandboxes.md`.
- Phase 1 = orchestrator + execute_code (class E) only. Hosted galopin machines (class P) are a second phase, enabled separately (`SANDBOX_MACHINES_ENABLED`, default false); only a refused stub now. The egress proxy may ship with P.
