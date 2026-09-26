import { UPSTREAM } from "./upstream_pin.mjs";
process.env.COLORTERM = "truecolor";
process.env.FORCE_COLOR = "3";
const { initTheme } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/theme.ts");
const { TreeSelectorComponent } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/components/tree-selector.ts");
const { setKeybindings } = await import(UPSTREAM + "/packages/tui/src/keybindings.ts");
const { KeybindingsManager } = await import(UPSTREAM + "/packages/coding-agent/src/core/keybindings.ts");
setKeybindings(new KeybindingsManager());
initTheme("dark");
const keys = { up: "\x1b[A", down: "\x1b[B", enter: "\r", escape: "\x1b", left: "\x1b[D", right: "\x1b[C", fold: "\x1b[1;5D", unfold: "\x1b[1;5C", all: "\x01", default: "\x04", "no-tools": "\x14", user: "\x15", labeled: "\x0c", cycle: "\x0f", copy: "\x18", backspace: "\x7f" };
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
  let action = "continue";
  const component = new TreeSelectorComponent(nodes(), c.initial || null, 24, id => { action = "chosen:" + id; }, () => { action = "cancel"; });
  component.onCopy = text => { action = "copied:" + (text ?? "<none>"); };
  const list = component.getTreeList();
  const snapshot = () => ({ selected: list.getSelectedNode()?.entry.id ?? null, action, lines: component.render(c.width) });
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
