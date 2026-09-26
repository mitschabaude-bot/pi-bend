import { UPSTREAM } from "./upstream_pin.mjs";
const { LlamaClient, normalizeLlamaServerUrl } = await import(`${UPSTREAM}/packages/coding-agent/src/extensions/llama/client.ts`);
const base = process.argv[2];
if (normalizeLlamaServerUrl("http://127.0.0.1:8080/v1/") !== "http://127.0.0.1:8080") throw Error("normalize");
if (normalizeLlamaServerUrl("https://EXAMPLE.com/prefix/v1?secret=gone#gone") !== "https://example.com/prefix") throw Error("normalize prefix");
const client = new LlamaClient(base + "/v1/", "test-key");
const signal = new AbortController();
const models = await client.list({ signal: signal.signal });
if (models[0].meta.n_ctx !== 32768) throw Error("catalog");
await client.list({ reload: true, signal: signal.signal });
await client.props({ model: "qwen + coder", signal: signal.signal });
await client.load('qwen"\\雪', signal.signal);
await client.unloadAndWait("qwen", signal.signal);
await client.download("owner/model:Q4", signal.signal);
try {
  await new LlamaClient(base + "/failure").list({ signal: signal.signal });
  throw Error("unexpected success");
} catch (error) {
  if (error.message !== "router unavailable") throw error;
}
signal.abort();
try { await client.list({ signal: signal.signal }); throw Error("unexpected success"); }
catch (error) { if (error.message === "unexpected success") throw error; }
