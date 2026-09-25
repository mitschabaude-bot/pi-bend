// Test-only oracle: pinned pi-mono's Chat Completions request path.
// stdin: {cases: [...]} or {models: [[provider, id], ...]}; stdout: JSON results.
// "simple"/"stream"/"params" run upstream streamSimple/stream with a capturing
// fetch and report the request URL, headers and body; "convert" reports
// convertMessages under the case's explicit compat, as the upstream suites call it.
import { convertMessages, stream, streamSimple } from "/home/agent/code/pi-mono/packages/ai/src/api/openai-completions.ts";
import { getModel } from "/home/agent/code/pi-mono/packages/ai/src/compat.ts";
import { normalizeContext } from "/home/agent/code/pi-mono/packages/ai/src/utils/transcript.ts";

const done = 'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n';

function modelOf(c: any): any {
	if (c.catalog) return getModel(c.catalog[0], c.catalog[1]);
	return { ...c.model, api: "openai-completions", provider: c.provider, baseUrl: c.baseUrl };
}

function contextOf(c: any): any {
	return normalizeContext({ systemPrompt: c.systemPrompt, messages: c.messages ?? [], tools: c.tools });
}

async function request(c: any): Promise<any> {
	let captured: any;
	const fetch = async (url: any, init: any) => {
		const headers: Record<string, string> = {};
		new Headers(init?.headers).forEach((value, key) => {
			headers[key.toLowerCase()] = value;
		});
		captured = { url: String(url), headers, body: typeof init?.body === "string" ? init.body : null };
		return new Response(done, { status: 200, headers: { "content-type": "text/event-stream" } });
	};
	const saved = process.env.PI_CACHE_RETENTION;
	if (c.processEnv?.PI_CACHE_RETENTION !== undefined) process.env.PI_CACHE_RETENTION = c.processEnv.PI_CACHE_RETENTION;
	else delete process.env.PI_CACHE_RETENTION;
	try {
		const options = { ...(c.options ?? {}), fetch, maxRetries: 0 };
		const events = c.entry === "simple" ? streamSimple(modelOf(c), contextOf(c), options) : stream(modelOf(c), contextOf(c), options);
		const result = await events.result();
		return captured ?? { error: result.errorMessage ?? null };
	} catch (error: any) {
		return captured ?? { error: String(error?.message ?? error) };
	} finally {
		if (saved === undefined) delete process.env.PI_CACHE_RETENTION;
		else process.env.PI_CACHE_RETENTION = saved;
	}
}

const input = JSON.parse(await new Response(Bun.stdin.stream()).text());
if (input.models) {
	console.log(JSON.stringify(input.models.map(([provider, id]: [string, string]) => getModel(provider as any, id as any) ?? null)));
} else {
	const results = [];
	for (const c of input.cases) {
		if (c.entry === "metadata") {
			results.push({ model: modelOf(c) ?? null });
		} else if (c.entry === "convert") {
			try {
				results.push({ messages: JSON.stringify(convertMessages(modelOf(c), contextOf(c), c.compat)) });
			} catch (error: any) {
				results.push({ error: String(error?.message ?? error) });
			}
		} else {
			results.push(await request(c));
		}
	}
	console.log(JSON.stringify(results));
}
