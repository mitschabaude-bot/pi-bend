// Source-pinned request oracle: run with PI_MONO_ROOT at pi-mono f07218c4d.
const root = process.env.PI_MONO_ROOT!;
const { stream, streamSimple } = await import(`${root}/packages/ai/src/api/google-generative-ai.ts`);
const { getModel } = await import(`${root}/packages/ai/src/compat.ts`);
const { normalizeContext } = await import(`${root}/packages/ai/src/utils/transcript.ts`);

const mode = process.argv[2] ?? "basic";
const model = getModel("google", "gemini-2.5-flash");
const tool = { name: "lookup", description: "Look up a value", parameters: { type: "object", properties: { value: { type: "string" } } } };
const system = { role: "system", content: "Use the lookup tool.", toolsAdded: [tool], timestamp: 1 };
const user = { role: "user", content: "lookup 42", timestamp: 2 };
const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
const assistant = { role: "assistant", content: [{ type: "toolCall", id: "call-1", name: "lookup", arguments: { value: "42" } }], api: "google-generative-ai", provider: "google", model: model.id, usage, stopReason: "toolUse", timestamp: 3 };
const signedAssistant = { role: "assistant", content: [{ type: "thinking", thinking: "reasoning", thinkingSignature: "c2ln" }, { type: "text", text: "", textSignature: "c2ln" }], api: "google-generative-ai", provider: "google", model: model.id, usage, stopReason: "stop", timestamp: 2 };
const result = { role: "toolResult", toolCallId: "call-1", toolName: "lookup", content: [{ type: "text", text: "found 42" }], isError: false, timestamp: 4 };
const messages = mode === "basic" || mode === "simple-basic" ? [{ role: "user", content: "ping", timestamp: 1 }] : mode === "signed" ? [{ role: "user", content: "ping", timestamp: 1 }, signedAssistant] : mode === "tool-first" ? [system, user] : [system, user, assistant, result];
const context = normalizeContext({ messages });
let payload: unknown;
const original = globalThis.fetch;
globalThis.fetch = async (_input, init) => {
  payload = JSON.parse(String(init?.body));
  return new Response('data: {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}\n\n', { headers: { "content-type": "text/event-stream" } });
};
try {
  await (mode === "basic" || mode === "signed" ? stream(model, context, { apiKey: "test-google-key" }) : streamSimple(model, context, { apiKey: "test-google-key" })).result();
  console.log(JSON.stringify(payload));
} finally {
  globalThis.fetch = original;
}
