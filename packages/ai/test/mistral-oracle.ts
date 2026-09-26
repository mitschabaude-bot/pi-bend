// Source-pinned oracle for tests/mistral_check.py: runs upstream
// mistral-conversations.ts (PI_MONO at f07218c4d) for one case of the Bend
// runner packages/ai/test/mistral.bend and prints the same JSON lines. Run
// with Node (pi's runtime), whose fetch and DOMException messages pi reports.
const root0 = process.env.PI_MONO!;
const { Type } = await import(`${root0}/node_modules/typebox/build/index.mjs`);

const root = process.env.PI_MONO!;
const { stream, streamSimple } = await import(`${root}/packages/ai/src/api/mistral-conversations.ts`);
const { getModel, normalizeContext } = await import(`${root}/packages/ai/src/compat.ts`);
const { AssistantMessageEventStream } = await import(`${root}/packages/ai/src/utils/event-stream.ts`);

// Events are immutable snapshots in the port (docs/native-bend.md): record
// each event as it is pushed. `partialArgs` is upstream's scratch buffer on
// streaming tool-call blocks, outside the ToolCall type; it is dropped.
const pushed: string[] = [];
const push = AssistantMessageEventStream.prototype.push;
AssistantMessageEventStream.prototype.push = function (event: unknown) {
	pushed.push(JSON.stringify(event, (key, value) => (key === "partialArgs" ? undefined : value)));
	return push.call(this, event);
};

const [mode, baseUrl] = process.argv.slice(2);
const large = () => ({ ...getModel("mistral", "mistral-large-latest"), baseUrl });
const devstral = () => ({ ...getModel("mistral", "devstral-medium-latest"), baseUrl });
const makeModel = (id: string, reasoning: boolean) => ({
	id,
	name: id,
	api: "mistral-conversations",
	provider: "mistral",
	baseUrl,
	reasoning,
	input: ["text"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
});
const hello = () => normalizeContext({ messages: [{ role: "user", content: "hello", timestamp: 1 }] });
const capture = (payload: unknown) => {
	console.log(`payload ${JSON.stringify(payload)}`);
	return payload;
};
const simple = (model: object, options: object = {}) =>
	streamSimple(model, hello(), { ...options, apiKey: "fake-key", onPayload: capture });

let events;
switch (mode) {
	case "sdk-payload":
		events = stream(
			large(),
			normalizeContext({
				systemPrompt: "Be precise",
				messages: [
					{
						role: "user",
						content: [
							{ type: "text", text: "describe" },
							{ type: "image", data: "aGVsbG8=", mimeType: "image/png" },
						],
						timestamp: 1,
					},
				],
				tools: [{ name: "lookup", description: "Look something up", parameters: Type.Object({ query: Type.String() }) }],
			}),
			{
				apiKey: "secret",
				headers: { "x-custom": "value" },
				maxTokens: 123,
				promptMode: "reasoning",
				reasoningEffort: "high",
				toolChoice: { type: "function", function: { name: "lookup" } },
				sessionId: "session-1",
				onPayload: (payload: Record<string, unknown>) => {
					console.log(`payload ${JSON.stringify(payload)}`);
					return {
						...payload,
						topP: 0.9,
						randomSeed: 42,
						responseFormat: {
							type: "json_schema",
							jsonSchema: {
								name: "result",
								schemaDefinition: { type: "object", properties: { maxTokens: { type: "number" } } },
							},
						},
						presencePenalty: 0.1,
						frequencyPenalty: 0.2,
						parallelToolCalls: true,
						safePrompt: true,
					};
				},
				onResponse: (response: unknown) => {
					console.log(`response ${JSON.stringify(response)}`);
				},
			},
		);
		break;
	case "replay":
		events = stream(
			large(),
			normalizeContext({
				messages: [
					{
						role: "assistant",
						api: "mistral-conversations",
						provider: "mistral",
						model: "mistral-large-latest",
						content: [
							{ type: "thinking", thinking: "reason" },
							{ type: "text", text: "answer" },
							{ type: "toolCall", id: "abc123456", name: "lookup", arguments: { query: "pi" } },
						],
						usage: {
							input: 0,
							output: 0,
							cacheRead: 0,
							cacheWrite: 0,
							totalTokens: 0,
							cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
						},
						stopReason: "toolUse",
						timestamp: 1,
					},
					{
						role: "toolResult",
						toolCallId: "abc123456",
						toolName: "lookup",
						content: [
							{ type: "text", text: "found" },
							{ type: "image", data: "aGVsbG8=", mimeType: "image/png" },
						],
						isError: false,
						timestamp: 2,
					},
				],
			}),
			{ apiKey: "test" },
		);
		break;
	case "header-overrides":
		events = stream({ ...large(), headers: { Authorization: "Bearer model-key", "X-Affinity": "model-affinity" } }, hello(), {
			apiKey: "request-key",
			sessionId: "automatic-affinity",
			headers: { authorization: null, "x-affinity": null, "User-Agent": "custom-agent" },
		});
		break;
	case "abort": {
		const controller = new AbortController();
		events = stream(large(), hello(), { apiKey: "test", signal: controller.signal });
		setTimeout(() => controller.abort(), 300);
		break;
	}
	case "timeout":
		events = stream(large(), hello(), { apiKey: "test", timeoutMs: 5 });
		break;
	case "raw-stop":
	case "raw-error":
	case "raw-unmapped":
		events = stream(devstral(), hello(), { apiKey: "test" });
		break;
	case "reasoning-small-medium":
		events = simple(makeModel("mistral-small-2603", true), { reasoning: "medium" });
		break;
	case "reasoning-small-off":
		events = simple(makeModel("mistral-small-2603", true));
		break;
	case "reasoning-magistral":
		events = simple(makeModel("magistral-medium-latest", true), { reasoning: "medium" });
		break;
	case "reasoning-glm-on":
		events = simple(makeModel("zai-glm-5-2", true), { reasoning: "medium" });
		break;
	case "reasoning-glm-off":
		events = simple(makeModel("zai-glm-5-2", true));
		break;
	case "reasoning-medium-2604-on":
		events = simple(makeModel("mistral-medium-2604", true), { reasoning: "medium" });
		break;
	case "reasoning-medium-2604-off":
		events = simple(makeModel("mistral-medium-2604", true));
		break;
	case "reasoning-medium-latest-on":
		events = simple(makeModel("mistral-medium-latest", true), { reasoning: "medium" });
		break;
	case "reasoning-medium-latest-off":
		events = simple(makeModel("mistral-medium-latest", true));
		break;
	case "reasoning-medium-2505":
		events = simple(makeModel("mistral-medium-2505", false), { reasoning: "medium" });
		break;
	case "cache-key":
		events = simple(makeModel("mistral-large-latest", false), { sessionId: "session-123" });
		break;
	case "cache-none":
		events = simple(makeModel("mistral-large-latest", false), { sessionId: "session-123", cacheRetention: "none" });
		break;
	case "tool-schema":
		events = stream(
			devstral(),
			normalizeContext({
				messages: [{ role: "user", content: "Hi", timestamp: 1 }],
				tools: [
					{
						name: "inspect_schema",
						description: "Inspect the schema",
						parameters: Type.Object({ nested: Type.Object({ value: Type.String() }) }),
						constrainedSampling: { type: "json_schema", strict: "require" },
					},
				],
			}),
			{ apiKey: "fake-key", onPayload: capture },
		);
		break;
	default:
		events = stream(large(), hello(), { apiKey: "test" });
}
for await (const _ of events);
for (const event of pushed) console.log(`event ${event}`);
console.log(`result ${JSON.stringify(await events.result(), (key, value) => (key === "partialArgs" ? undefined : value))}`);
