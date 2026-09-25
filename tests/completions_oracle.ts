// Test-only oracle: pinned pi-mono's actual Chat Completions request builder and stream.
import { streamSimple } from "/home/agent/code/pi-mono/packages/ai/src/api/openai-completions.ts";
import { normalizeContext } from "/home/agent/code/pi-mono/packages/ai/src/utils/transcript.ts";
import { Type } from "/home/agent/code/pi-mono/node_modules/typebox/build/index.mjs";

const model: any = { id: "test-model", name: "Test Model", api: "openai-completions", provider: "openai", baseUrl: "http://localhost:1/v1", reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 128000, maxTokens: 4096 };
const text = 'data: {"id":"chatcmpl-1","model":"test-model","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}\n\ndata: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n';
const tool = 'data: {"id":"chatcmpl-tool","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call-1","type":"function","function":{"name":"lookup","arguments":"{\\"value\\":"}}]},"finish_reason":null}]}\n\ndata: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"42\\"}"}}]},"finish_reason":"tool_calls"}]}\n\ndata: [DONE]\n\n';
const reply = 'data: {"id":"chatcmpl-answer","choices":[{"index":0,"delta":{"content":"found"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n';
const payloads: any[] = [];
const eventTypes: string[] = [];
let call = 0;
const mode = process.argv[2] ?? "basic";
const fakeFetch = async () => new Response((mode === "tool" || mode === "tool_image") ? (call++ === 0 ? tool : reply) : text, { status: 200, headers: { "content-type": "text/event-stream" } });
async function request(context: any, extra: any = {}) {
  const events = streamSimple(model, context, { apiKey: "test-completions-key", fetch: fakeFetch as any, onPayload: (params: any) => { payloads.push(params); }, ...extra });
  for await (const event of events) eventTypes.push(event.type);
  return events.result();
}
if (mode === "tool" || mode === "tool_image") {
  if (mode === "tool_image") model.input = ["text", "image"];
  const system: any = { role: "system", content: "Use the lookup tool.", toolsAdded: [{ name: "lookup", description: "Look up a value", parameters: Type.Object({ value: Type.String() }) }], timestamp: 1 };
  const user: any = { role: "user", content: "lookup 42", timestamp: 2 };
  const first = await request(normalizeContext({ messages: [system, user] }));
  const result: any = { role: "toolResult", toolCallId: "call-1", toolName: "lookup", content: [{ type: "text", text: "found 42" }, ...(mode === "tool_image" ? [{ type: "image", data: "ZmFrZQ==", mimeType: "image/png" }] : [])], isError: false, timestamp: 3 };
  await request(normalizeContext({ messages: [system, user, first, result] }));
} else if (mode === "compat") {
  model.compat = { supportsStore: false, supportsUsageInStreaming: false, maxTokensField: "max_tokens" };
  await request(normalizeContext({ messages: [{ role: "user", content: "ping", timestamp: 1 }] }));
} else if (mode === "reasoning") {
  model.reasoning = true;
  await request(normalizeContext({ messages: [{ role: "user", content: "ping", timestamp: 1 }] }), { reasoning: "low" });
} else if (mode === "reasoning_off") {
  model.reasoning = true;
  await request(normalizeContext({ messages: [{ role: "user", content: "ping", timestamp: 1 }] }));
} else if (mode === "sampling") {
  model.samplingParams = { seed: 7, temperature: 1, top_p: 0 };
  await request(normalizeContext({ messages: [{ role: "user", content: "ping", timestamp: 1 }] }), { temperature: 2, samplingParams: { temperature: 3, top_p: 1, presence_penalty: 1 } });
} else if (mode === "openrouter" || mode === "openrouter_off" || mode === "together" || mode === "together_off" || mode === "deepseek") {
  model.provider = mode.startsWith("openrouter") ? "openrouter" : mode === "deepseek" ? "deepseek" : "together";
  model.reasoning = true;
  await request(normalizeContext({ messages: [{ role: "user", content: "ping", timestamp: 1 }] }), mode.endsWith("_off") ? {} : { reasoning: "low" });
} else {
  await request(normalizeContext({ messages: [{ role: "user", content: "ping", timestamp: 1 }] }));
}
console.log(JSON.stringify({ payloads, eventTypes }));
