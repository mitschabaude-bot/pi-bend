// Pinned AgentSession recovery scenarios behind tests/agent_session_check.py:
// overflow compact-and-retry (once, then exhausted) and transient-error retry.
// Needs pi-mono's gitignored model data (packages/ai/src/providers/data) hydrated.
// Run from ../pi-mono/packages/coding-agent: bun <this file>.
import { UPSTREAM } from "./upstream_pin.mjs";
const { fauxAssistantMessage } = await import(UPSTREAM + "/packages/ai/src/compat.ts");
const { createHarness } = await import(UPSTREAM + "/packages/coding-agent/test/suite/harness.ts");
const OVERFLOW = "prompt is too long: 213462 tokens > 200000 maximum";
for (const retryTwice of [false, true]) {
  const harness = await createHarness({ settings: { compaction: { keepRecentTokens: 1 } } });
  const text = (value: string) => () => fauxAssistantMessage(value);
  const overflow = () => { Bun.sleepSync(5); return fauxAssistantMessage("", { stopReason: "error", errorMessage: OVERFLOW }); };
  const responses: any[] = [text("a1"), overflow, text("overflow summary"), text("prefix summary"), retryTwice ? overflow : text("recovered"), text("unused")];
  harness.setResponses(responses);
  await harness.session.prompt("one");
  await harness.session.prompt("two");
  const ends = harness.eventsOfType("compaction_end");
  console.log(JSON.stringify({
    ends: ends.map((e: any) => ({ willRetry: e.willRetry, summary: e.result?.summary, errorMessage: e.errorMessage })), starts: harness.eventsOfType("compaction_start").length,
    roles: harness.session.messages.map((m: any) => m.role),
    entries: harness.session.sessionManager.getEntries().map((e: any) => e.type === "context_edit" ? "context_edit:" + (e.replacement === null ? "omit" : "replace") : e.type),
    appended: harness.eventsOfType("entry_appended" as any).length,
    calls: harness.faux.state.callCount,
    last: (harness.session.messages.at(-1) as any)?.stopReason + ":" + (harness.session.messages.at(-1) as any)?.errorMessage,
    types: harness.events.map((e: any) => e.type).filter((t: string) => t.startsWith("compaction") || t === "agent_end"),
  }));
  harness.cleanup();
}
{ const harness = await createHarness({ settings: { retry: { enabled: true, maxRetries: 3, baseDelayMs: 1 } } });
harness.setResponses([() => fauxAssistantMessage("", { stopReason: "error", errorMessage: "overloaded_error" }), () => fauxAssistantMessage("recovered")]);
await harness.session.prompt("test");
console.log(JSON.stringify({
  types: harness.events.map((e: any) => e.type).filter((t: string) => ["agent_end", "auto_retry_start", "auto_retry_end", "entry_appended", "message_end", "agent_settled"].includes(t)),
  entries: harness.session.sessionManager.getEntries().map((e: any) => e.type === "context_edit" ? "context_edit:" + (e.replacement === null ? "omit" : "replace") + ":" + (harness.session.sessionManager.getEntry(e.targetId) as any)?.message?.stopReason : e.type + ":" + (e.message?.role ?? "")),
  roles: harness.session.messages.map((m: any) => m.role),
}));
harness.cleanup(); }
