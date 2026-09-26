// Test-only oracle: pinned pi-mono's Google Generative AI `stream`/`streamSimple`.
// stdin: {cases: [...]}; stdout: one JSON result per case, as
// packages/ai/test/google-differential.bend reports them: "payload" captures
// the SDK parameters in onPayload, "request" the SDK's call to the global
// fetch, "response" streams the case's body through a stubbed global fetch.
import { UPSTREAM } from "./upstream_pin.mjs";
const { stream, streamSimple } = await import(UPSTREAM + "/packages/ai/src/api/google-generative-ai.ts");
const { getModel } = await import(UPSTREAM + "/packages/ai/src/compat.ts");
const { normalizeContext } = await import(UPSTREAM + "/packages/ai/src/utils/transcript.ts");

function modelOf(spec: any): any {
	if (spec.catalog) return getModel("google", spec.catalog);
	const c = spec.custom;
	return {
		id: c.id,
		name: c.name ?? c.id,
		api: "google-generative-ai",
		provider: c.provider,
		baseUrl: c.baseUrl ?? "https://example.invalid/v1beta",
		reasoning: c.reasoning ?? true,
		...(c.thinkingLevelMap === undefined ? {} : { thinkingLevelMap: c.thinkingLevelMap }),
		input: c.input ?? ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, ...(c.cost ?? {}) },
		contextWindow: c.contextWindow ?? 128000,
		maxTokens: c.maxTokens ?? 8192,
		...(c.headers === undefined ? {} : { headers: c.headers }),
	};
}

function eventJson(event: any): any {
	const { partial, ...rest } = event;
	return rest;
}

const original = globalThis.fetch;

async function run(c: any): Promise<any> {
	const model = modelOf(c.model);
	const context = normalizeContext({ systemPrompt: c.systemPrompt, messages: c.messages ?? [], tools: c.tools });
	let payload: any;
	let request: any;
	const options: any = { ...(c.options ?? {}) };
	if (c.mode === "payload" || c.mode === undefined) {
		options.onPayload = (value: any) => {
			payload = JSON.parse(JSON.stringify(value));
			throw new Error("payload captured");
		};
	}
	globalThis.fetch = (async (url: any, init: any) => {
		if (c.mode === "request") {
			const headers: Record<string, string> = {};
			new Headers(init?.headers).forEach((value, key) => {
				headers[key.toLowerCase()] = value;
			});
			request = { url: String(url), method: String(init?.method ?? "GET").toLowerCase(), headers, body: typeof init?.body === "string" ? init.body : null };
			throw new TypeError("fetch failed");
		}
		return new Response(c.body, { status: 200, headers: { "content-type": "text/event-stream" } });
	}) as typeof fetch;
	try {
		let events: any;
		try {
			events = c.entry === "simple" ? streamSimple(model, context, options) : stream(model, context, options);
		} catch (error: any) {
			return { thrown: String(error?.message ?? error) };
		}
		const emitted: any[] = [];
		for await (const event of events) emitted.push(JSON.parse(JSON.stringify(eventJson(event))));
		const message = await events.result();
		if (c.mode === "request") return request ?? { error: message.errorMessage ?? "" };
		if (c.mode === "response") return { message: JSON.parse(JSON.stringify(message)), events: emitted };
		return payload ?? { error: message.errorMessage ?? "" };
	} finally {
		globalThis.fetch = original;
	}
}

const input = JSON.parse(await new Response(Bun.stdin.stream()).text());
const results = [];
for (const c of input.cases) results.push(await run(c));
await Bun.write(Bun.stdout, JSON.stringify(results) + "\n");
