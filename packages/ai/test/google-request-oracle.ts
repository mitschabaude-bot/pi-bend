// Source-pinned request oracle: run with PI_MONO_ROOT at pi-mono f07218c4d.
const root = process.env.PI_MONO_ROOT!;
const { stream, streamSimple } = await import(`${root}/packages/ai/src/api/google-generative-ai.ts`);
const { getModel } = await import(`${root}/packages/ai/src/compat.ts`);
const { normalizeContext } = await import(`${root}/packages/ai/src/utils/transcript.ts`);

const mode = process.argv[2] ?? "basic";
const model = getModel("google", mode === "strict" || mode === "strict-prefer" || mode === "modern-image" ? "gemini-3-flash-preview" : "gemini-2.5-flash");
const tool = { name: "lookup", description: "Look up a value", parameters: { type: "object", properties: { value: { type: "string" } } } };
const system = { role: "system", content: "Use the lookup tool.", toolsAdded: [tool], timestamp: 1 };
const user = { role: "user", content: "lookup 42", timestamp: 2 };
const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
const assistant = { role: "assistant", content: [{ type: "toolCall", id: "call-1", name: "lookup", arguments: { value: "42" } }], api: "google-generative-ai", provider: "google", model: model.id, usage, stopReason: "toolUse", timestamp: 3 };
const signedAssistant = { role: "assistant", content: [{ type: "thinking", thinking: "reasoning", thinkingSignature: "c2ln" }, { type: "text", text: "", textSignature: "c2ln" }], api: "google-generative-ai", provider: "google", model: model.id, usage, stopReason: "stop", timestamp: 2 };
const result = { role: "toolResult", toolCallId: "call-1", toolName: "lookup", content: [{ type: "text", text: "found 42" }], isError: false, timestamp: 4 };
const strictSchema = { type: "object", properties: { optional: { type: "string" }, required: { type: "string" } }, required: ["required"] };
const unsupportedSchema = { type: "object", properties: { value: { $ref: "#/definitions/value" } } };
const strictTool = { name: "lookup", description: "Look up a value", parameters: mode === "strict-prefer" ? unsupportedSchema : strictSchema, constrainedSampling: { type: "json_schema", strict: mode === "strict-prefer" ? "prefer" : "require" } };
const strictMessages = [{ role: "system", content: "Use lookup.", toolsAdded: [strictTool], timestamp: 1 }, user];
const imageAssistant = { role: "assistant", content: [{ type: "toolCall", id: "call-img", name: "lookup", arguments: {} }, { type: "toolCall", id: "call-text", name: "lookup", arguments: {} }], api: "google-generative-ai", provider: "google", model: model.id, usage, stopReason: "toolUse", timestamp: 2 };
const imageMessages = [{ role: "user", content: "ping", timestamp: 1 }, imageAssistant, { role: "toolResult", toolCallId: "call-img", toolName: "lookup", content: [{ type: "image", data: "aGVsbG8=", mimeType: "image/png" }], isError: false, timestamp: 3 }, { role: "toolResult", toolCallId: "call-text", toolName: "lookup", content: [{ type: "text", text: "found" }], isError: false, timestamp: 4 }];
const updatedMessages = [{ role: "system", content: "Base rule.", toolsAdded: [{ name: "old", description: "Old tool", parameters: strictSchema }], timestamp: 1 }, { role: "user", content: "ping", timestamp: 2 }, { role: "system", content: "Second rule.", toolsAdded: [{ name: "lookup", description: "Look up a value", parameters: strictSchema }], toolsRemoved: [{ name: "old" }], timestamp: 3 }, { role: "user", content: "after update", timestamp: 4 }];
const messages = mode === "basic" || mode === "simple-basic" || mode === "hook" ? [{ role: "user", content: "ping", timestamp: 1 }] : mode === "signed" ? [{ role: "user", content: "ping", timestamp: 1 }, signedAssistant] : mode === "tool-first" ? [system, user] : mode.startsWith("strict") ? strictMessages : mode.endsWith("image") ? imageMessages : mode === "system-update" ? updatedMessages : [system, user, assistant, result];
const context = normalizeContext({ messages });
let payload: unknown;
const original = globalThis.fetch;
globalThis.fetch = async (_input, init) => {
  payload = JSON.parse(String(init?.body));
  return new Response('data: {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}\n\n', { headers: { "content-type": "text/event-stream" } });
};
try {
  const response = await (mode === "hook" ? streamSimple(model, context, { apiKey: "test-google-key", onPayload: (params) => ({ ...params, config: { ...params.config, temperature: 0.25 } }) }) : mode === "basic" || mode === "signed" || mode === "system-update" || mode.startsWith("strict") || mode.endsWith("image") ? stream(model, context, { apiKey: "test-google-key" }) : streamSimple(model, context, { apiKey: "test-google-key" })).result();
  console.log(JSON.stringify(mode === "strict-unsupported" ? { error: response.errorMessage } : payload));
} finally {
  globalThis.fetch = original;
}
