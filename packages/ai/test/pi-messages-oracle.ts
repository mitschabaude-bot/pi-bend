// Source-pinned oracle for tests/pi_messages_check.py: runs upstream
// pi-messages.ts (PI_MONO at f07218c4d) for one case of the Bend runner
// packages/ai/test/pi-messages.bend and prints the same JSON lines.
const root = process.env.PI_MONO!;
const { stream, streamSimple } = await import(`${root}/packages/ai/src/api/pi-messages.ts`);
const { normalizeContext } = await import(`${root}/packages/ai/src/utils/transcript.ts`);
const { AssistantMessageEventStream } = await import(`${root}/packages/ai/src/utils/event-stream.ts`);

// Events are immutable snapshots in the port (docs/native-bend.md): record
// each event as it is pushed, before later events mutate the shared partial.
const pushed: string[] = [];
const push = AssistantMessageEventStream.prototype.push;
AssistantMessageEventStream.prototype.push = function (event: unknown) {
	pushed.push(JSON.stringify(event));
	return push.call(this, event);
};

const [mode, baseUrl] = process.argv.slice(2);
const model = {
	id: "auto",
	name: "Radius Auto",
	api: "pi-messages",
	provider: "radius",
	baseUrl,
	reasoning: false,
	input: ["text"],
	cost: { input: 1, output: 2, cacheRead: 0.1, cacheWrite: 0.2 },
	contextWindow: 128000,
	maxTokens: 16384,
};
const context = normalizeContext({ messages: [{ role: "user", content: "Hello", timestamp: 1700000000 }] });

let events;
if (mode === "debug") {
	events = streamSimple(model, context, {
		apiKey: "test-key",
		debug: true,
		onResponse: (response: { headers: Record<string, string> }) => {
			console.log(`observed ${response.headers["x-pi-gateway-upstream-provider"] ?? "<missing>"}`);
		},
	});
} else {
	const options =
		mode === "stream"
			? { apiKey: "test-key", sessionId: "session-1", toolChoice: "auto", maxTokens: 100, headers: { "x-custom": "1" } }
			: mode === "stale"
				? { apiKey: "stale" }
				: mode === "no-key"
					? undefined
					: { apiKey: "test-key" };
	events = stream(model, context, options);
}
for await (const _ of events);
for (const event of pushed) console.log(`event ${event}`);
console.log(`result ${JSON.stringify(await events.result())}`);
