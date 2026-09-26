// Test-only oracle: pinned Codex provider over a real loopback WebSocket.
import { zstdDecompressSync } from "node:zlib";
import { UPSTREAM } from "./upstream_pin.mjs";
const { stream, streamSimple, closeOpenAICodexWebSocketSessions } = await import(UPSTREAM + "/packages/ai/src/api/openai-codex-responses.ts");
const { normalizeContext } = await import(UPSTREAM + "/packages/ai/src/utils/transcript.ts");

function modelOf(c: any): any {
	const m = c.model ?? {};
	return {
		id: m.id ?? "gpt-5.1-codex",
		name: m.name ?? m.id ?? "gpt-5.1-codex",
		api: "openai-codex-responses",
		provider: "openai-codex",
		baseUrl: c.url,
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

const c = JSON.parse(await new Response(Bun.stdin.stream()).text());
const controller = new AbortController();
const events: string[] = [];
const context = normalizeContext({systemPrompt: c.systemPrompt, messages: c.messages ?? [], tools: c.tools});
const options = {...c.options, signal: controller.signal};
const s = c.entry === "simple" ? streamSimple(modelOf(c), context, options) : stream(modelOf(c), context, options);
for await (const event of s) {
  const name = label(event);
  events.push(name);
  if (c.abortOnEvent === name) controller.abort();
}
const message = await s.result();
closeOpenAICodexWebSocketSessions();
await Bun.write(Bun.stdout, JSON.stringify({events, message}) + "\n");
