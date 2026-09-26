import { UPSTREAM } from "./upstream_pin.mjs";
process.env.COLORTERM = "truecolor";
process.env.FORCE_COLOR = "3";
const { initTheme } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/theme.ts");
const { TreeSelectorComponent } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/components/tree-selector.ts");
const { setKeybindings } = await import(UPSTREAM + "/packages/tui/src/keybindings.ts");
const { KeybindingsManager } = await import(UPSTREAM + "/packages/coding-agent/src/core/keybindings.ts");
setKeybindings(new KeybindingsManager());
initTheme("dark");
const keys = { up: "\x1b[A", down: "\x1b[B", enter: "\r", escape: "\x1b", left: "\x1b[D", right: "\x1b[C", fold: "\x1b[1;5D", unfold: "\x1b[1;5C", all: "\x01", default: "\x04", "no-tools": "\x14", user: "\x15", labeled: "\x0c", cycle: "\x0f", copy: "\x18", backspace: "\x7f", label: "L", "word-left": "\x1b[1;5D", "word-right": "\x1b[1;5C", "kill-word": "\x17", home: "\x01", end: "\x05", "kill-start": "\x15", "kill-end": "\x0b", yank: "\x19", "paste-start": "\x1b[200~", "paste-end": "\x1b[201~" };
let input = "";
for await (const chunk of process.stdin) input += chunk;
const output = JSON.parse(input).map(c => {
  function nodes(index = 0, parentId = null, shape = c.shape) {
    if (index === c.texts.length) return [];
    const id = String(index);
    const entry = { type: "message", id, parentId, timestamp: "2025-01-01T00:00:00Z", message: { role: "user", content: c.texts[index], timestamp: 1 } };
    const hidden = shape === "hidden" || shape === "hidden-star";
    let children = shape === "roots" ? [] : nodes(index + 1, hidden ? "m" + id : id, shape === "star" || shape === "hidden-star" ? "roots" : shape);
    if (hidden) children = [{ entry: {type: "model_change", id: "m" + id, parentId: id, timestamp: entry.timestamp, provider: "test", modelId: "test-model"}, children }];
    return [{ entry, children }, ...(shape === "roots" ? nodes(index + 1, parentId, shape) : [])];
  }
  function toolNodes() {
    const [name, args, result] = c.texts;
    const base = (id, parentId, message) => ({ type: "message", id, parentId, timestamp: "2025-01-01T00:00:00Z", message });
    const usage = { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2, cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0} };
    return [{entry: base("0", null, {role: "user", content: "tool request", timestamp: 1}), children: [{entry: base("1", "0", {role: "assistant", content: [{type: "toolCall", id: c.shape === "missing-tool" ? "other" : "call", name, arguments: JSON.parse(args)}], api: "openai-responses", provider: "openai", model: "test-model", usage, stopReason: "toolUse", timestamp: 1}), children: [{entry: base("2", "1", {role: "toolResult", toolCallId: "call", toolName: name, content: [{type: "text", text: result}], isError: false, timestamp: 1}), children: []}]}]}];
  }
  let action = "continue";
  const component = new TreeSelectorComponent(c.shape.endsWith("tool") ? toolNodes() : nodes(), c.initial || null, 24, id => { action = "chosen:" + id; }, () => { action = "cancel"; }, (id, label) => { action = "labeled:" + id + ":" + (label ?? "<none>"); });
  component.focused = true;
  component.onCopy = text => { action = "copied:" + (text ?? "<none>"); };
  const list = component.getTreeList();
  const snapshot = () => ({ selected: list.getSelectedNode()?.entry.id ?? null, label: list.getSelectedNode()?.label ?? null, action, lines: component.render(c.width) });
  const result = [snapshot()];
  for (const name of c.actions) {
    action = "continue";
    component.handleInput(keys[name] ?? name);
    result.push(snapshot());
  }
  return result;
});
await new Promise<void>(resolve => process.stdout.write(JSON.stringify(output), () => resolve()));
process.exit(0);
