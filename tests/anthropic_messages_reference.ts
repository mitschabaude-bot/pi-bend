// Test-only oracle: pinned pi-mono's Anthropic Messages `stream`/`streamSimple`.
// stdin: {cases: [...]}; stdout: one JSON result per case, as
// packages/ai/test/anthropic-differential.bend reports them:
// "payload" captures the params in onPayload, "request" the SDK's fetch call,
// "response" streams the case's SSE body through an injected client.
import { UPSTREAM } from "./upstream_pin.mjs";
const { stream, streamSimple } = await import(UPSTREAM + "/packages/ai/src/api/anthropic-messages.ts");
const { getModel } = await import(UPSTREAM + "/packages/ai/src/compat.ts");
const { normalizeContext } = await import(UPSTREAM + "/packages/ai/src/utils/transcript.ts");

function modelOf(spec: any): any {
	if (spec.catalog) {
		const model = getModel(spec.catalog[0], spec.catalog[1]);
		return spec.compat === undefined ? model : { ...model, compat: spec.compat };
	}
	const c = spec.custom;
	return {
		id: c.id,
		name: c.name ?? c.id,
		api: "anthropic-messages",
		provider: c.provider,
		baseUrl: c.baseUrl ?? "http://127.0.0.1:9",
		reasoning: c.reasoning ?? false,
		...(c.thinkingLevelMap === undefined ? {} : { thinkingLevelMap: c.thinkingLevelMap }),
		input: c.input ?? ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, ...(c.cost ?? {}) },
		contextWindow: c.contextWindow ?? 200000,
		maxTokens: c.maxTokens ?? 32000,
		...(c.headers === undefined ? {} : { headers: c.headers }),
		...(c.compat === undefined ? {} : { compat: c.compat }),
	};
}

function contextOf(c: any): any {
	return normalizeContext({ systemPrompt: c.systemPrompt, messages: c.messages ?? [], tools: c.tools });
}

function eventJson(event: any): any {
	const { partial, ...rest } = event;
	return rest;
}

async function run(c: any): Promise<any> {
	const model = modelOf(c.model);
	const context = contextOf(c);
	let payload: any;
	let request: any;
	const options: any = { ...(c.options ?? {}) };
	if (c.mode === "payload" || c.mode === undefined) {
		options.onPayload = (value: any) => {
			payload = value;
			throw new Error("payload captured");
		};
	} else if (c.mode === "request") {
		options.fetch = async (url: any, init: any) => {
			const headers: Record<string, string> = {};
			new Headers(init?.headers).forEach((value, key) => {
				headers[key.toLowerCase()] = value;
			});
			request = { url: String(url), method: String(init?.method ?? "GET").toLowerCase(), headers, body: typeof init?.body === "string" ? init.body : null };
			throw new TypeError("Invalid request");
		};
	} else {
		const response = new Response(c.body, { status: 200, headers: { "content-type": "text/event-stream" } });
		options.client = { beta: { messages: { create: () => ({ asResponse: async () => response }) } } };
	}
	const events = c.entry === "simple" ? streamSimple(model, context, options) : stream(model, context, options);
	const emitted: any[] = [];
	for await (const event of events) emitted.push(JSON.parse(JSON.stringify(eventJson(event))));
	const message = await events.result();
	if (c.mode === "request") return request ?? null;
	if (c.mode === "response") return { message: JSON.parse(JSON.stringify(message)), events: emitted };
	return payload ?? { error: message.errorMessage ?? "" };
}

const input = JSON.parse(await new Response(Bun.stdin.stream()).text());
const results = [];
for (const c of input.cases) {
	delete process.env.PI_CACHE_RETENTION;
	try {
		results.push(await run(c));
	} catch (error: any) {
		results.push({ thrown: String(error?.message ?? error) });
	}
}
await Bun.write(Bun.stdout, JSON.stringify(results) + "\n");
