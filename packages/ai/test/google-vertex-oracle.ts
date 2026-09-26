// Source-pinned oracle for tests/google_vertex_check.py: runs upstream
// google-vertex.ts (PI_MONO at f07218c4d) with the pinned @google/genai SDK
// and google-auth-library for one case of packages/ai/test/google-vertex.bend
// and prints the same JSON lines. Run with Node (pi's runtime).
//
// google-auth-library sends its token request through gaxios, which uses a
// browser's `window.fetch` when one exists; the oracle provides one that sends
// requests for the Google token endpoint to the case's loopback token URL.
const root = process.env.PI_MONO!;
const spec = JSON.parse(process.argv[2]);
if (spec.tokenUrl) {
	const realFetch = globalThis.fetch;
	(globalThis as any).window = {
		fetch: (url: any, init: any) =>
			realFetch(String(url) === "https://oauth2.googleapis.com/token" ? spec.tokenUrl : url, init),
	};
}
const { stream, streamSimple } = await import(`${root}/packages/ai/src/api/google-vertex.ts`);
const { getModel, normalizeContext } = await import(`${root}/packages/ai/src/compat.ts`);
const { AssistantMessageEventStream } = await import(`${root}/packages/ai/src/utils/event-stream.ts`);

const pushed: string[] = [];
const push = AssistantMessageEventStream.prototype.push;
AssistantMessageEventStream.prototype.push = function (event: unknown) {
	pushed.push(JSON.stringify(event));
	return push.call(this, event);
};

const { catalog, ...overrides } = spec.model ?? {};
const model: Record<string, unknown> = { ...getModel("google-vertex", catalog ?? "gemini-3-flash-preview"), ...overrides };
const context = normalizeContext({ ...(spec.context ?? {}) });
const options: Record<string, unknown> = { ...(spec.options ?? {}) };
if (spec.abort) options.signal = AbortSignal.abort();
if (spec.capture)
	options.onPayload = (payload: unknown) => {
		console.log(`payload ${JSON.stringify(payload)}`);
		if (spec.throwPayload) throw new Error("payload captured");
		return undefined;
	};
if (spec.observe)
	options.onResponse = (response: unknown) => {
		console.log(`response ${JSON.stringify(response)}`);
	};
let events;
try {
	events = spec.mode === "simple" ? streamSimple(model, context, options) : stream(model, context, options);
} catch (error) {
	console.log(`thrown ${(error as Error).message}`);
	process.exit(0);
}
for await (const _ of events);
for (const event of pushed) console.log(`event ${event}`);
console.log(`result ${JSON.stringify(await events.result())}`);
