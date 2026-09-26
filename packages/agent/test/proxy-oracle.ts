// Source-pinned oracle for tests/agent_proxy_check.py: runs upstream
// packages/agent/src/proxy.ts (PI_MONO at f07218c4d) against the checker's
// loopback server and prints the same JSON lines as the Bend runner
// packages/agent/test/proxy.bend. pi-ai is not built in the checkout, so its
// package name resolves to the source entry point.
const root = process.env.PI_MONO!;
Bun.plugin({
	name: "pi-ai-source",
	setup(build) {
		build.onResolve({ filter: /^@earendil-works\/pi-ai$/ }, () => ({ path: `${root}/packages/ai/src/index.ts` }));
	},
});
const { streamProxy } = await import(`${root}/packages/agent/src/proxy.ts`);
const { normalizeContext, EventStream } = await import(`${root}/packages/ai/src/index.ts`);

// Events are immutable snapshots in the port (docs/native-bend.md): record
// each event as it is pushed, before later events mutate the shared partial.
const pushed: string[] = [];
const push = EventStream.prototype.push;
EventStream.prototype.push = function (event: unknown) {
	pushed.push(JSON.stringify(event));
	return push.call(this, event);
};

const baseUrl = process.argv[2];
// The upstream test's model.
const model = {
	id: "gpt-5.4",
	name: "GPT-5.4",
	api: "openai-responses",
	provider: "openai",
	baseUrl: "https://api.openai.com/v1",
	reasoning: true,
	input: ["text"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 400000,
	maxTokens: 128000,
};
const stream = streamProxy(model, normalizeContext({ systemPrompt: "", messages: [] }), {
	authToken: "test-token",
	proxyUrl: baseUrl,
});
for await (const _event of stream) {
}
const result = await stream.result();
for (const event of pushed) console.log(`event ${event}`);
console.log(`result ${JSON.stringify(result)}`);
