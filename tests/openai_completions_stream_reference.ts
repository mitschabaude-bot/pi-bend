// Test-only oracle: pinned pi-mono's Chat Completions `stream`/`streamSimple`
// against the scripted local server of tests/openai_completions_stream_check.py.
// stdin: {cases: [...]}; stdout: per case the events (without the aliased
// `partial`) and the final message.
import { stream, streamSimple } from "/home/agent/code/pi-mono/packages/ai/src/api/openai-completions.ts";
import { normalizeContext } from "/home/agent/code/pi-mono/packages/ai/src/utils/transcript.ts";

function modelOf(c: any): any {
	return { ...c.model, api: "openai-completions", provider: c.provider, baseUrl: c.baseUrl };
}

const input = JSON.parse(await new Response(Bun.stdin.stream()).text());
const results = [];
for (const c of input.cases) {
	const context = normalizeContext({ systemPrompt: c.systemPrompt, messages: c.messages ?? [], tools: c.tools });
	const controller = new AbortController();
	const options = { ...(c.options ?? {}), signal: controller.signal };
	const events = c.entry === "stream" ? stream(modelOf(c), context, options) : streamSimple(modelOf(c), context, options);
	const seen: any[] = [];
	let trigger = c.abortAfter;
	for await (const event of events) {
		const { partial: _partial, ...rest } = event as any;
		seen.push(rest);
		// A caller cancelling mid-stream after the first event of this type.
		if (trigger !== undefined && event.type === trigger) {
			trigger = undefined;
			controller.abort();
		}
	}
	const message = await events.result();
	results.push(JSON.parse(JSON.stringify({ events: seen, message })));
}
console.log(JSON.stringify(results));
