// Test-only oracle for tests/live_replay_check.py: one request of pi-mono's
// live provider suites through pinned pi-mono (compat stream/streamSimple),
// against the check's loopback server. Arguments and output match
// packages/coding-agent/test/live-replay.bend: the base URL, then the path of the
// case as JSON; "E <type>[:<delta>]" per event, then "R <message JSON>", or
// "T <message>" when streaming throws before a stream exists.
import { UPSTREAM } from "./upstream_pin.mjs";

const { getModel, stream, streamSimple } = await import(UPSTREAM + "/packages/ai/src/compat.ts");
// entry "api": the API module's own stream, as the suites that import it call it.
const apiStreams: Record<string, string> = {
	"openai-responses": "/packages/ai/src/api/openai-responses.ts",
	"openai-completions": "/packages/ai/src/api/openai-completions.ts",
	"anthropic-messages": "/packages/ai/src/api/anthropic-messages.ts",
};
const { isContextOverflow } = await import(UPSTREAM + "/packages/ai/src/utils/overflow.ts");

const LOREM_IPSUM = `Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. `;

// context-overflow.test.ts generateOverflowContent.
function generateOverflowContent(contextWindow: number): string {
	const targetTokens = contextWindow + 10000;
	const targetChars = targetTokens * 4 * 1.5;
	const repetitions = Math.ceil(targetChars / LOREM_IPSUM.length);
	return LOREM_IPSUM.repeat(repetitions);
}

// Text as comma-separated code points (lone surrogates as their units).
const points = (text: string) => Array.from(text, (c) => c.codePointAt(0)).join(",");

const [base, path] = process.argv.slice(2);
const spec = JSON.parse(await Bun.file(path).text());
if (spec.catalog) {
	const { getModels } = await import(UPSTREAM + "/packages/ai/src/compat.ts");
	const { getSupportedThinkingLevels } = await import(UPSTREAM + "/packages/ai/src/models.ts");
	const out = getModels(spec.catalog).map((m: any) => `M ${points(JSON.stringify({ ...m, supportedThinkingLevels: getSupportedThinkingLevels(m) }))}`);
	console.log(out.join("\n"));
	process.exit(0);
}
const found = spec.customModel ?? getModel(spec.provider, spec.model);
if (!found) throw new Error(`unknown model ${spec.provider}/${spec.model}`);
let model: any = { ...found };
if (spec.api) {
	const { compat: _compat, ...rest } = model;
	model = { ...rest, api: spec.api };
}
const override = spec.modelOverride ?? {};
if (override.provider) model.provider = override.provider;
if (override.compat) model.compat = override.compat;
if (override.compatMerge) model.compat = { ...model.compat, ...override.compatMerge };
model.baseUrl = `${base}/${spec.run}` + (override.hostPath ? `/${(override.baseUrl ?? found.baseUrl).replace(/^https?:\/\//, "")}` : "");
const context = spec.overflow
	? {
			systemPrompt: "You are a helpful assistant.",
			messages: [{ role: "user", content: generateOverflowContent(model.contextWindow), timestamp: 1 }],
		}
	: spec.context;
const controller = new AbortController();
if (spec.abortBefore) controller.abort();
const options = { ...(spec.options ?? {}), signal: controller.signal };
const lines: string[] = [];
try {
	const apiStream = spec.entry === "api" ? (await import(UPSTREAM + apiStreams[model.api])).stream : undefined;
	const { normalizeContext } = await import(UPSTREAM + "/packages/ai/src/utils/transcript.ts");
	const events = apiStream ? apiStream(model, normalizeContext(context), options) : (spec.entry === "simple" ? streamSimple : stream)(model, context, options);
	let seen = 0;
	let fired = false;
	for await (const event of events) {
		const delta = "delta" in event ? `:${points(event.delta)}` : "";
		lines.push(`E ${event.type}${delta}`);
		if (event.type === "text_delta" || event.type === "thinking_delta") seen += event.delta.length;
		if (!fired && spec.abortAfterChars !== undefined && seen >= spec.abortAfterChars) {
			fired = true;
			controller.abort();
		}
	}
	const message = await events.result();
	lines.push(`R ${points(JSON.stringify(message))}`);
	if (spec.overflow) lines.push(`O ${isContextOverflow(message, model.contextWindow)}`);
} catch (error) {
	lines.push(`T ${error instanceof Error ? error.message : String(error)}`);
}
console.log(lines.join("\n"));
