// Test-only oracle: pinned pi-mono's OpenAI Codex Responses `stream`/
// `streamSimple` over SSE with a stubbed global fetch serving each case's
// scripted response. stdin: {cases: [...]}; stdout: one result per case with
// the request the SDK-less client sent (zstd bodies decoded), the event labels
// and the final message, as tests/openai_codex_stream_check.py compares them.
import { zstdDecompressSync } from "node:zlib";
import { UPSTREAM } from "./upstream_pin.mjs";
const { stream, streamSimple } = await import(UPSTREAM + "/packages/ai/src/api/openai-codex-responses.ts");
const { normalizeContext } = await import(UPSTREAM + "/packages/ai/src/utils/transcript.ts");

function modelOf(c: any): any {
	const m = c.model ?? {};
	return {
		id: m.id ?? "gpt-5.1-codex",
		name: m.name ?? m.id ?? "gpt-5.1-codex",
		api: "openai-codex-responses",
		provider: "openai-codex",
		baseUrl: "https://chatgpt.com/backend-api",
		reasoning: m.reasoning ?? true,
		...(m.thinkingLevelMap === undefined ? {} : { thinkingLevelMap: m.thinkingLevelMap }),
		input: m.input ?? ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, ...(m.cost ?? {}) },
		contextWindow: m.contextWindow ?? 400000,
		maxTokens: m.maxTokens ?? 128000,
	};
}

function body(init: any): any {
	const value = init?.body;
	if (typeof value === "string") return JSON.parse(value);
	if (value instanceof Uint8Array) return JSON.parse(Buffer.from(zstdDecompressSync(value)).toString("utf8"));
	return null;
}

function label(event: any): string {
	return event.type === "text_delta" ? `text_delta:${event.delta}` : event.type;
}

function respond(step: any, signal: AbortSignal | undefined): Promise<Response> {
	const encoder = new TextEncoder();
	const chunks: [number, string][] = step.chunks ?? [];
	const readable = new ReadableStream<Uint8Array>({
		async start(controller) {
			for (const [delay, text] of chunks) {
				if (delay > 0) await new Promise((resolve) => setTimeout(resolve, delay));
				try {
					controller.enqueue(encoder.encode(text));
				} catch {
					return;
				}
			}
			if (!step.keepOpen) controller.close();
		},
	});
	const response = new Response(readable, { status: step.status ?? 200, headers: step.headers ?? { "content-type": "text/event-stream" } });
	if (!step.headerDelay) return Promise.resolve(response);
	return new Promise((resolve, reject) => {
		const timer = setTimeout(() => resolve(response), step.headerDelay);
		signal?.addEventListener("abort", () => {
			clearTimeout(timer);
			reject(signal.reason instanceof Error ? signal.reason : new Error("aborted"));
		}, { once: true });
	});
}

async function run(c: any): Promise<any> {
	const requests: any[] = [];
	let index = 0;
	globalThis.fetch = (async (input: any, init: any) => {
		const headers: Record<string, string> = {};
		new Headers(init?.headers).forEach((value, key) => {
			headers[key.toLowerCase()] = value;
		});
		requests.push({ url: String(input), headers, body: body(init) });
		const step = c.script[Math.min(index++, c.script.length - 1)];
		return respond(step, init?.signal);
	}) as typeof fetch;
	const model = modelOf(c);
	const context = normalizeContext({ systemPrompt: c.systemPrompt, messages: c.messages ?? [], tools: c.tools });
	const controller = new AbortController();
	const options = { ...(c.options ?? {}), signal: controller.signal };
	const events: string[] = [];
	const s = c.entry === "simple" ? streamSimple(model, context, options) : stream(model, context, options);
	for await (const event of s) {
		const name = label(event);
		events.push(name);
		if (c.abortOnEvent === name) controller.abort();
	}
	const message = await s.result();
	return { requests, events, message: JSON.parse(JSON.stringify(message)) };
}

const input = JSON.parse(await new Response(Bun.stdin.stream()).text());
const results = [];
for (const c of input.cases) {
	try {
		results.push(await run(c));
	} catch (error: any) {
		results.push({ thrown: String(error?.message ?? error) });
	}
}
await Bun.write(Bun.stdout, JSON.stringify(results) + "\n");
