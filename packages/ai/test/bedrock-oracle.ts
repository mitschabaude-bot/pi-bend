// Source-pinned oracle for tests/bedrock_check.py: runs upstream
// bedrock-converse-stream.ts (PI_MONO at f07218c4d) with the real AWS SDK for
// one case of packages/ai/test/bedrock.bend and prints the same JSON lines.
// Run with Node (pi's runtime).
const root = process.env.PI_MONO!;
const { Type } = await import(`${root}/node_modules/typebox/build/index.mjs`);
const { stream, streamSimple } = await import(`${root}/packages/ai/src/api/bedrock-converse-stream.ts`);
const { getModel, normalizeContext } = await import(`${root}/packages/ai/src/compat.ts`);
const { AssistantMessageEventStream } = await import(`${root}/packages/ai/src/utils/event-stream.ts`);

// Streaming scratch members (index, partialJson, redactedChunks) are outside
// the content types; events are recorded as immutable snapshots.
const scratch = (key: string, value: unknown) =>
	key === "index" || key === "partialJson" || key === "redactedChunks" ? undefined : value;
const pushed: string[] = [];
const push = AssistantMessageEventStream.prototype.push;
AssistantMessageEventStream.prototype.push = function (event: unknown) {
	pushed.push(JSON.stringify(event, scratch));
	return push.call(this, event);
};

const spec = JSON.parse(process.argv[2]);
const { catalog, compat, ...overrides } = spec.model ?? {};
const model: Record<string, unknown> = { ...getModel("amazon-bedrock", catalog ?? "us.anthropic.claude-opus-4-8"), ...overrides };
if (compat === null) delete model.compat;
else if (compat !== undefined) model.compat = compat;
// Tool parameter schemas arrive as TypeBox-shaped JSON; upstream passes the
// TypeBox objects, which serialize the same.
const tools = spec.context?.tools?.map((tool: Record<string, unknown>) => ({ ...tool }));
const context = normalizeContext({ ...spec.context, ...(tools ? { tools } : {}) });
const options: Record<string, unknown> = { ...(spec.options ?? {}) };
if (spec.abort) options.signal = AbortSignal.abort();
if (spec.capture)
	options.onPayload = (payload: unknown) => {
		console.log(
			`payload ${JSON.stringify(payload, (_key, value) => (value instanceof Uint8Array ? Buffer.from(value).toString("base64") : value))}`,
		);
		return payload;
	};
if (spec.observe)
	options.onResponse = (response: unknown) => {
		console.log(`response ${JSON.stringify(response)}`);
	};
void Type;
const events = spec.mode === "simple" ? streamSimple(model, context, options) : stream(model, context, options);
for await (const _ of events);
for (const event of pushed) console.log(`event ${event}`);
console.log(`result ${JSON.stringify(await events.result(), scratch)}`);
