/**
 * The chat-server stand-in for the ADR 0085 PoC.
 *
 * Drives a paseo daemon on a "NAT'd" machine from outside, exactly the way
 * Cerea's server-side proxy would: the only configured address is the relay,
 * the only credential is the daemon's pairing offer, and every operation —
 * pair, list/create agent, stream timeline, approve a permission, read a
 * diff — crosses the relay end-to-end encrypted. Nothing here talks to the
 * daemon's own port, which is bound loopback inside a container this process
 * cannot even resolve.
 */
import { readFileSync, appendFileSync } from "node:fs";
import { execSync } from "node:child_process";
// The published SDK exports only createPaseoClient (which pins clientType
// "cli"); the chat server is a machine client, so use the DaemonClient class
// directly, which the package exposes under its documented internal export.
import { DaemonClient } from "@getpaseo/client/internal/daemon-client";
import { buildRelayWebSocketUrl } from "@getpaseo/protocol/daemon-endpoints";

const OFFER_PATH = process.env.OFFER_PATH ?? "/offer/offer.json";
const CWD = "/workspace/demo";
const MODEL = "cortecs/glm-5.3-flash";
const PROMPT =
	"Create a file named hello.txt containing exactly the text 'hello from the relay PoC' and nothing else. Do not run any other command.";

const log = (...args) => {
	const line = args
		.map((a) => (typeof a === "string" ? a : JSON.stringify(a)))
		.join(" ");
	console.log(line);
	appendFileSync("/transcript/run.log", line + "\n");
};

const step = (name) => log(`\n=== ${name} ===`);

function readOffer() {
	const raw = JSON.parse(readFileSync(OFFER_PATH, "utf8"));
	if (!raw.relayEnabled || !raw.url) {
		throw new Error(`offer at ${OFFER_PATH} is not a relay pairing offer: ${JSON.stringify(raw)}`);
	}
	const fragment = new URL(raw.url).hash; // "#offer=base64url(json)"
	const encoded = fragment.replace(/^#offer=/, "");
	const offer = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
	log("offer decoded:", {
		serverId: offer.serverId,
		relay: offer.relay,
		daemonPublicKeyB64: `${offer.daemonPublicKeyB64.slice(0, 8)}…`,
	});
	return offer;
}

function makeLogger(tag) {
	return {
		debug: () => {},
		info: (obj, msg) => log(`[${tag}]`, msg ?? ""),
		warn: (obj, msg) => log(`[${tag}] WARN`, msg ?? JSON.stringify(obj)),
		error: (obj, msg) => log(`[${tag}] ERROR`, msg ?? JSON.stringify(obj)),
	};
}

function connectClient(offer, clientId) {
	const url = buildRelayWebSocketUrl({
		endpoint: offer.relay.endpoint,
		useTls: offer.relay.useTls === true,
		serverId: offer.serverId,
		role: "client",
		version: "2",
	});
	log(`[${clientId}] relay url:`, url);
	const client = new DaemonClient({
		url,
		clientId,
		clientType: "hub", // the machine-client type; the chat server is not a phone
		appVersion: "0.8.0",
		e2ee: { enabled: true, daemonPublicKeyB64: offer.daemonPublicKeyB64 },
		logger: makeLogger(clientId),
	});
	return client;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitFor(predicate, what, timeoutMs = 240_000) {
	const start = Date.now();
	for (;;) {
		const value = predicate();
		if (value !== undefined) return value;
		if (Date.now() - start > timeoutMs) throw new Error(`timed out waiting for ${what}`);
		await sleep(500);
	}
}

const negativeControl = () => {
	step("negative control: the daemon must not be reachable from here");
	let resolved = null;
	try {
		resolved = execSync("getent hosts userbox || true").toString().trim();
	} catch {}
	if (resolved) throw new Error(`userbox unexpectedly resolvable from the cloud side: ${resolved}`);
	log("OK: 'userbox' does not resolve on the cloud network — no direct path exists.");
};

async function main() {
	negativeControl();

	step("pair: read the offer and connect through the relay");
	const offer = readOffer();
	const client = connectClient(offer, "cerea-driver");
	await client.connect();
	log("connected through the relay (E2EE handshake complete).");

	step("daemon identity");
	const status = await client.getDaemonStatus();
	log("daemon:", {
		serverId: status.serverId,
		version: status.version,
		listen: status.listen,
		relay: status.relay,
	});
	if (status.serverId !== offer.serverId) {
		throw new Error(`relay routed us to ${status.serverId}, expected ${offer.serverId}`);
	}
	log("OK: the relay routed us to exactly the daemon we paired with.");

	step("list workspaces and agents");
	const workspaces = await client.fetchWorkspaces();
	log("workspaces:", workspaces.entries.map((w) => w.id));
	const agentsBefore = await client.fetchAgents();
	log("agents before:", agentsBefore.entries.length);

	step("create an agent (opencode, plan-gated writes)");
	// A titled workspace up front: the daemon otherwise auto-names untitled
	// directory workspaces with an LLM call of its own, which would make the
	// PoC's outcome depend on whichever fallback credential it picks.
	const workspace = await client.createWorkspace({
		source: { kind: "directory", path: CWD },
		title: "relay-poc",
	});
	log("workspace:", workspace.workspace?.id ?? "(none)");
	// Create the agent idle, subscribe to its timeline, then send the prompt:
	// the subscription demonstrably carries the whole turn. On a cold box the
	// first opencode boot can outlast the client's 60s request timeout even
	// though creation succeeds server-side — so on timeout, adopt the agent
	// the daemon actually created rather than failing the run.
	let agent;
	try {
		agent = await client.createAgent({
			provider: "opencode",
			cwd: CWD,
			workspaceId: workspace.workspace?.id,
			model: MODEL,
			modeId: "build",
			providerOptions: { permission: { edit: "ask", bash: "ask" } },
		});
	} catch (err) {
		log("createAgent request timed out or failed; checking what the daemon created:", String(err).slice(0, 120));
		// The daemon may still be booting opencode; its RPCs answer slowly
		// until then. Poll rather than give up.
		let adopted;
		for (let attempt = 0; attempt < 12 && !adopted; attempt++) {
			try {
				const after = await client.fetchAgents();
				const candidates = after.entries.filter((e) => e.agent?.cwd === CWD);
				if (candidates.length > 0) adopted = { id: candidates[candidates.length - 1].agent.id };
			} catch {
				// daemon still busy; wait and retry
			}
			if (!adopted) await sleep(10_000);
		}
		if (!adopted) throw err;
		agent = adopted;
		log("adopted daemon-created agent:", agent.id);
	}
	log("agent created:", { id: agent.id, provider: agent.provider });
	const agentId = agent.id;

	step("stream the timeline through the relay");
	const seen = { permission: undefined, completed: false, toolCalls: 0, text: 0 };
	client.subscribeAgentTimeline(agentId, (message) => {
		if (message.type !== "agent_stream") return;
		const event = message.event ?? message.payload?.event;
		if (!event) return;
		log("event:", event.type);
		switch (event.type) {
			case "permission_requested":
				seen.permission = event.request;
				log("permission_requested:", {
					id: event.request.id,
					name: event.request.name,
					kind: event.request.kind,
					title: event.request.title,
				});
				break;
			case "permission_resolved":
				log("permission_resolved:", event.requestId);
				break;
			case "timeline": {
				const item = event.item;
				if (item?.type === "tool_call") seen.toolCalls++;
				if (item?.type === "assistant_message") seen.text++;
				break;
			}
			case "turn_completed":
				seen.completed = true;
				log("turn_completed");
				break;
			case "turn_failed":
				seen.error = JSON.stringify(event.error ?? event).slice(0, 400);
				log("turn_failed:", seen.error);
				break;
			case "attention_required":
				if (event.reason === "error") seen.error = seen.error ?? "attention_required(error)";
				break;
			default:
				break;
		}
	});

	await client.sendAgentMessage(agentId, PROMPT);
	log("prompt sent through the relay; waiting for the agent's turn.");

	step("approve the permission");
	const request = await waitFor(() => seen.permission, "a permission request");
	log("responding allow to:", request.id);
	await client.respondToPermission(agentId, request.id, { behavior: "allow" });
	log("respondToPermission sent through the relay.");

	await waitFor(() => seen.completed || seen.error ? true : undefined, "turn completion");
	if (seen.error) throw new Error(`agent turn failed: ${seen.error}`);
	log(`turn finished: ${seen.toolCalls} tool calls, ${seen.text} assistant messages.`);

	step("read the diff");
	const diff = await client.getCheckoutDiff(CWD, { mode: "uncommitted" });
	const files = diff.files ?? diff;
	log("diff files:", Array.isArray(files) ? files.map((f) => f.path ?? f.file ?? "?") : files);
	const flat = JSON.stringify(diff);
	if (!flat.includes("hello.txt")) {
		throw new Error("diff does not mention hello.txt — the edit did not round-trip");
	}
	log("OK: the agent's edit is visible in the checkout diff.");

	step("Q1: a second independent client, same daemon, same relay");
	const second = connectClient(offer, "cerea-second-client");
	await second.connect();
	const status2 = await second.getDaemonStatus();
	const agents2 = await second.fetchAgents();
	log("second client sees:", {
		serverId: status2.serverId,
		agents: agents2.entries.length,
		sameDaemon: status2.serverId === offer.serverId,
	});
	let secondSawTraffic = false;
	second.subscribeAgentTimeline(agentId, (message) => {
		if (message.type === "agent_stream") secondSawTraffic = true;
	});
	// Nudge the same agent with a trivial follow-up so the second client's
	// subscription demonstrably carries live traffic for an agent it did not
	// create.
	await client.sendAgentMessage(agentId, "Reply with the single word: acknowledged.");
	const sawText = await waitFor(
		() => (secondSawTraffic ? "yes" : undefined),
		"live timeline traffic on the second client",
		120_000
	);
	log(`OK: second client received live timeline traffic: ${sawText}`);

	second.close();
	client.close();
	log("\n=== POC COMPLETE: every control-surface step crossed the relay. ===");
}

main().catch((err) => {
	log("POC FAILED:", err?.stack ?? String(err));
	process.exit(1);
});
