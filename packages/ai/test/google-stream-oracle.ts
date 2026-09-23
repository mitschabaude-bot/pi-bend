// Source-pinned event oracle: run with PI_MONO_ROOT at pi-mono f07218c4d.
const root = process.env.PI_MONO_ROOT!;
const { stream, streamSimple } = await import(`${root}/packages/ai/src/api/google-generative-ai.ts`);
const { getModel } = await import(`${root}/packages/ai/src/compat.ts`);
const { normalizeContext } = await import(`${root}/packages/ai/src/utils/transcript.ts`);

const model = getModel("google", "gemini-2.5-flash");
const context = normalizeContext({ messages: [{ role: "user", content: "ping", timestamp: 1 }] });
const original = globalThis.fetch;
globalThis.fetch = async () => new Response(process.env.GOOGLE_SSE!, { headers: { "content-type": "text/event-stream" } });
try {
  const events = process.argv[2] === "simple" ? streamSimple(model, context, { apiKey: "test-google-key" }) : stream(model, context, { apiKey: "test-google-key" });
  for await (const event of events) console.log(event.type);
} finally {
  globalThis.fetch = original;
}
