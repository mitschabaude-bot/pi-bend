// Upstream ModelRuntime streaming for the Cloudflare providers with a
// capturing fetch: per case, the request URL, headers and body the SDK sends, or
// the stream's error message. The context declares one tool and the request
// carries a session id. Credentials are in-memory; ambient values come
// from this process's environment.
// Usage: bun tests/cloudflare_request_reference.ts <pi-mono> < cases.json
import fs from "node:fs";

const [piMono] = process.argv.slice(2);
const { AuthStorage } = await import(`${piMono}/packages/coding-agent/src/core/auth-storage.ts`);
const { ModelRuntime } = await import(`${piMono}/packages/coding-agent/src/core/model-runtime.ts`);
const cases = JSON.parse(fs.readFileSync(0, "utf8"));

const tool = {
	name: "lookup",
	description: "Look up a value",
	parameters: { type: "object", properties: { value: { type: "string" } }, required: ["value"] },
};
const results = [];
for (const c of cases) {
	const credentials = AuthStorage.inMemory(c.credential ? { [c.provider]: c.credential } : {});
	const runtime = await ModelRuntime.create({ credentials, modelsPath: null });
	const model = runtime.getModel(c.provider, c.modelId);
	let captured;
	const fetch = async (url, init) => {
		captured = { url: String(url), headers: Object.fromEntries(new Headers(init.headers).entries()), body: init.body };
		throw new Error("captured");
	};
	let error;
	try {
		const message = await runtime.completeSimple(model, { messages: [{ role: "user", content: "hi", timestamp: 1 }], tools: [tool] }, { fetch, maxRetries: 0, sessionId: "session-1" });
		error = message.errorMessage;
	} catch (cause) {
		error = String(cause?.message ?? cause);
	}
	results.push(captured ?? { error });
}
console.log(JSON.stringify(results));
