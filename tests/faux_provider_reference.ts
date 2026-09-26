// Test-only oracle: pinned pi-mono's faux core usage estimates for the
// contexts tests/faux_provider_check.py sends (see packages/ai/test/faux-provider.bend
// "diff" mode); prints one "D input,output,cacheRead,cacheWrite" line per case.
import { UPSTREAM } from "./upstream_pin.mjs";
const { createFauxCore, fauxAssistantMessage, fauxText, fauxToolCall } = await import(UPSTREAM + "/packages/ai/src/providers/faux.ts");
const { normalizeContext } = await import(UPSTREAM + "/packages/ai/src/utils/transcript.ts");

const tool = { name: "echo", description: "Echo back text", parameters: { type: "object", required: ["text"], properties: { text: { type: "string" } } } };
const later = { name: "later", description: "Later tool", parameters: { type: "object", properties: {} } };
const assistant = fauxAssistantMessage([fauxText("prior é🙂"), fauxToolCall("echo", { text: "hi", n: [1, 2] }, { id: "t1" })], { stopReason: "toolUse", timestamp: 1 });
const cases: any[] = [
	{ context: { messages: [{ role: "user", content: "hi", timestamp: 1 }] } },
	{ context: { systemPrompt: "sys", tools: [tool], messages: [{ role: "user", content: [{ type: "text", text: "hello" }, { type: "image", mimeType: "image/png", data: "abcd" }], timestamp: 1 }, assistant, { role: "toolResult", toolCallId: "t1", toolName: "echo", content: [{ type: "text", text: "tool out" }], isError: false, timestamp: 2 }] } },
	{ context: { messages: [{ role: "system", content: "base", sections: { rules: "<rules>\nr\n</rules>" }, toolsAdded: [tool], timestamp: 0 }, { role: "user", content: "a", timestamp: 1 }, { role: "system", content: "update", toolsRemoved: [{ name: "echo" }], toolsAdded: [later], timestamp: 2 }] } },
	{ context: { messages: [{ role: "user", content: "hello 🙂 world", timestamp: 1 }] }, session: "s1" },
	{ context: { messages: [{ role: "user", content: "hello 🙂 world", timestamp: 1 }, assistant, { role: "user", content: "follow up", timestamp: 3 }] }, session: "s1" },
	{ context: { messages: [{ role: "user", content: "different", timestamp: 1 }] }, session: "s1", retention: "none" },
	{ context: { messages: [{ role: "user", content: "x🙂 tail", timestamp: 1 }] }, session: "s2" },
	{ context: { messages: [{ role: "user", content: "x😀 tail", timestamp: 1 }] }, session: "s2" },
];
const core = createFauxCore({});
const lines: string[] = [];
for (const c of cases) {
	core.setResponses([fauxAssistantMessage("done 🙂 ok")]);
	const options: any = {};
	if (c.session) options.sessionId = c.session;
	if (c.retention) options.cacheRetention = c.retention;
	const message = await core.stream(core.getModel(), normalizeContext(c.context), options).result();
	const u = message.usage;
	lines.push(`D ${u.input},${u.output},${u.cacheRead},${u.cacheWrite}`);
}
// Split: fixed one-token (four-unit) chunks cut the second pair of the text.
const splitCore = createFauxCore({ tokenSize: { min: 1, max: 1 } });
const splitText = "a🙂🙂🙂b";
splitCore.setResponses([fauxAssistantMessage(splitText)]);
const deltas: string[] = [];
for await (const event of splitCore.stream(splitCore.getModel(), normalizeContext({ messages: [{ role: "user", content: "hi", timestamp: 1 }] }), {})) {
	if (event.type === "text_delta") deltas.push(event.delta);
}
lines.push(`S ${deltas.map((d) => d.length).join(",")}`, `J ${deltas.join("") === splitText}`);
console.log(lines.join("\n"));
