// Upstream Azure OpenAI Responses `stream` with a capturing fetch: the SDK
// request (URL, headers, body) or the stream's error message, per case.
// Usage: bun tests/azure_openai_responses_reference.ts <pi-mono> <catalog.json> < cases.json
import fs from "node:fs";

const [piMono, catalogPath] = process.argv.slice(2);
const { stream } = await import(`${piMono}/packages/ai/src/api/azure-openai-responses.ts`);
const { getPiUserAgent } = await import(`${piMono}/packages/ai/src/utils/pi-user-agent.ts`);
const { getPlatformHeaders } = await import(`${piMono}/node_modules/openai/internal/detect-platform.mjs`);
const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"))["azure-openai-responses"];
const cases = JSON.parse(fs.readFileSync(0, "utf8"));

const results = [];
for (const c of cases) {
	const model = structuredClone(catalog[c.modelId]);
	if ("baseUrl" in c) model.baseUrl = c.baseUrl;
	if ("modelHeaders" in c) model.headers = c.modelHeaders;
	if ("compat" in c) model.compat = c.compat;
	let captured;
	const fetch = async (url, init) => {
		captured = {
			url: String(url),
			headers: Object.fromEntries(new Headers(init.headers).entries()),
			body: init.body,
		};
		throw new Error("captured");
	};
	const options = { ...c.options, fetch, maxRetries: 0 };
	const message = await stream(model, { messages: c.messages }, options).result();
	results.push(captured ?? { error: message.errorMessage });
}
console.log(JSON.stringify({ userAgent: getPiUserAgent(), platform: getPlatformHeaders(), results }));
