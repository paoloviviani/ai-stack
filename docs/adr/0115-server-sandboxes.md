# ADR 0115: Server-side sandboxes: one sandbox manager, two workload classes (code execution and hosted machines)

- Status: accepted 2026-11-12. Step 1 (manager, socket proxy) and step 2 (class E, `execute_code` on the server) shipped in Cerea v0.52.1 (#225, #231), off by default. Class P (hosted machines) is C116; packages C117; shared budget C118; follow-ups C119.
- Backlog: C72 (Cerea #184, "Sandbox ADR for coding agents"). This ADR covers it and also covers the server backend for `execute_code`.
- Related: the execution-engine direction (Pyodide in the browser, with self-healing), ADR 0097/0099 (Plan · Ask · Allow and delegate report-back), ADR 0110 (goose engine), and the privacy-withheld files of Cerea #193.

## Context

Cerea runs code in two ways today, and neither runs on the server:
- `execute_code`: the model's code tool runs Python in the browser with Pyodide. It costs nothing to host and is isolated by the browser, but it can't use native packages, has little memory, and loses its state when the page reloads.
- Agents: galopin with opencode or goose runs on a machine the user brings (a laptop or a dev server), reached through the relay. A user with no machine of their own has no agent.

Small deployments have no Kubernetes cluster. Open WebUI's Open Terminal works, but it is essentially single-user. Starting a gVisor sandbox per user at the right moment is real work, and an isolated runtime alone still lacks an execution layer.

Both are needed:
- **(E)** a server backend for `execute_code`;
- **(P)** hosted machines for agents.

## Decision

**Share the control plane, not the container.** One sandbox manager serves two workload classes. They share the isolation runtime, quotas, egress control and the file model, but each has its own sandboxes and blast radius.

### The sandbox manager (control plane)

It is a separate small service, never inside the chat process, because it is the only component allowed to control containers.
- It reaches Docker only through a **restricted socket proxy**, limited to creating, starting, stopping, removing and inspecting containers that carry the manager's label.
- Cerea calls it with a service token.

The API:
- `lease(kind, owner, conversation?, limits)` and `release`;
- `exec` or `attach` (the kernel or terminal channel), `put_file` / `get_file`, `status`.

It also enforces:
- **Quotas and accounting** per user and billing group: CPU-seconds, wall time, storage. They follow Pystino's quota model and are reported the same way.
- **Egress:** one proxy, default-deny, with an allow-list per class.

**Backends are swappable.** Docker with the `runsc` (gVisor) runtime is first; it needs no Kubernetes. Kubernetes (a gVisor or Kata `RuntimeClass`, or an agent-sandbox controller) or a managed provider can follow later. The front ends never see which backend runs them.

### Two workload classes

| | **E: code execution** (`execute_code`) | **P: persistent machine** (hosted agent) |
|---|---|---|
| Unit | one conversation | one user (later: one project) |
| Supply | a generic warm pool of pristine sandboxes, leased to a conversation on its first call | started on demand, stopped when idle |
| State | a kernel kept for the lease (idle timeout, e.g. 20 min); nothing persists after release | a persistent volume |
| Data in | staged from the attachment store; files withheld by privacy (#193) are **never** staged | whatever the user or the agent puts there |
| Data out | produced files are uploaded to the attachment store as conversation files | they stay on the volume; shared only by explicit export |
| Network | none by default; an optional allow-list (e.g. a package index) | through the egress proxy |
| Credentials | none, ever | scoped and short-lived, minted by Cerea (galopin enrolment, the gateway token through Pystino) |
| Front end | an **exec daemon** speaking the Jupyter kernel protocol, so rich outputs (`display_data` MIME bundles: images, tables, HTML) map onto Cerea's renderers | **galopin** with opencode or goose, auto-enrolled as the user's "Cloud machine" |
| Caller | the Cerea server, request/response, no approvals (it is trusted because it is sandboxed) | the user through /code, under Plan · Ask · Allow |
| Image | a scientific Python stack, rebuilt often | a developer toolchain |
| Limits | small per-call timeouts and memory; a runaway snippet only kills its own lease | per-user CPU, memory and process limits; idle stop |

**Why they are separate.** `execute_code` runs code the model wrote, often after reading untrusted content (web pages, uploaded documents, tool results): the prompt-injection path. A P machine holds the user's projects and, in time, credentials. Sharing a container or a volume would let one injected snippet in a chat read or change a user's repositories. The two classes also differ in lifecycle (bursty and latency-critical, versus long and interactive), in how they warm up (only a generic pool gives E an instant first call), and in their images.

**The bridge between them is the attachment store, not a shared disk.** "Continue this analysis in /code" copies a conversation's files onto the user's machine, and the other direction is an explicit export. One file model, one quota model, one manager, one isolation runtime; two blast radii.

### In Cerea

- **`execute_code`** gets a backend setting, `EXECUTE_CODE_BACKEND=pyodide|sandbox`.
  - **Pyodide stays the default** and the fallback when the manager is down or not configured.
  - The model sees the same tool, the same arguments and the same output format.
  - Tool results still pass through Pystino's redaction on their way to the model.
- **Hosted machines** appear in /code as one more machine per user. The relay, approvals and session UI are reused unchanged. An administrator can turn the hosted machine off, or force Ask on it, for a deployment or a group.
- **Model calls from inside either class** go through Pystino with the user's short-lived token, so quotas, billing and privacy pipelines apply. Connectors stay on the server, reached through the MCP relay. **No secret is ever placed inside a sandbox.**
- **Credentials are injected at egress** (amended 2026-11-12). When a sandbox must use a credential, for example a P machine pushing to a git host or calling an approved API, the egress proxy adds it only to requests bound for that credential's approved endpoint. The sandbox never holds it. This is what makes "no secret inside a sandbox" workable for P. Each credential is tied to an endpoint, and a policy change that sends a credential to a new host needs administrator review.

## Consequences

- Kernel state does not outlive a lease: after the idle timeout only the files remain. That is the same as Pyodide today, and the model can re-run code.
- Moving files between chat and agent is an explicit copy, not automatic. This is intended: the user decides what crosses.
- The manager holds the most privileged access in the stack, so it stays small and narrow: label-scoped operations through the socket proxy, its own token, and audit logs of every lease.
- A host needs `runsc` installed and registered as a Docker runtime. The kit's `./configure` will check it, and if it is missing, server execution stays off and Pyodide keeps working.
- The kit gains up to three services: the manager, the socket proxy and the egress proxy. All are off by default.

## Alternatives considered

- **One container per user running both front ends on one volume:** simpler, but it puts model-written code and the user's projects and credentials in the same trust zone, couples two opposite lifecycles, and allows only a per-user warm pool. Rejected.
- **Server-side WebAssembly** (Pyodide or Python on WASI in Node or wasmtime): very light, but it keeps the package and native-code limits that server execution is meant to remove.
- **A pool per user for E:** worse latency and density than a generic pool, with no security gain, because every lease is a fresh sandbox anyway.
- **Firecracker or Kata from the start:** stronger isolation, but more operations work on a single host. Kept as a later backend behind the manager.
- **Kubernetes as a requirement:** excludes the small deployments this targets. It is a later backend instead.

## OpenShell as a candidate backend (amended 2026-11-12)

[NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) (Apache-2.0, Rust, 0.1.x, moving to the CNCF) overlaps with this design's control plane:
- a gateway with compute drivers (Docker, Podman, Kubernetes, VM, MXC);
- a supervisor in each sandbox that **dials out** to the gateway;
- an isolation backend for the filesystem, syscalls and network mediation;
- per-endpoint network policy, with a prover that flags risky policy changes;
- credential injection at egress, inference endpoints included;
- SDKs in Python, TypeScript, Go and Rust, OCSF audit events and OpenTelemetry.

Its example agent is opencode.

**Where it fits:** class P (hosted agent machines), its sweet spot. galopin still runs inside, to keep the relay, approvals and /code.

**Where it does not fit (yet):**
- Class E. Its focus is long-lived agent sandboxes: it has no per-conversation lease from a warm pool and no kernel or exec-daemon layer.
- Multi-user. Workspaces, roles and quotas are a draft (its RFC 0011), so Cerea would map users and ownership itself.

**Defaults to change:** telemetry is on by default (`OPENSHELL_TELEMETRY_ENABLED=false`). It is also a substantial stack for a small box.

**Decision:**
- The manager stays a thin interface.
- OpenShell is a candidate **backend for class P**. Before build step 3, a time-boxed evaluation (not a prototype) checks:
  - the Docker driver on one host;
  - exec and file transfer through the TypeScript SDK;
  - many labelled sandboxes owned through Cerea's own user mapping;
  - credential injection toward Pystino and a git host;
  - resource limits, and turning telemetry off.
- If it passes, P is mostly integration work. If it doesn't, P is built on our own manager as planned.
- Class E stays on our manager (Docker + `runsc`) unless that evaluation shows OpenShell meets E's start-up and exec latency.
- Also borrowed as designs, whatever the outcome: credential injection at egress (above), administrator review of risky policy changes, and OCSF as the schema for the manager's lease and audit log.

## Build order

1. The manager with the Docker + `runsc` backend, the socket proxy and the egress proxy (kit services, off by default, checked by `./configure`).
2. Class E: the exec daemon image, the generic warm pool, staging in and out of the attachment store (honouring #193), and `EXECUTE_CODE_BACKEND=sandbox`.
3. Class P: evaluate OpenShell as its backend (see above), then the hosted galopin image, auto-enrolment, idle stop and the persistent volume, then "continue in /code" and export.
4. Other backends (Kubernetes, managed providers) when a deployment needs them.
