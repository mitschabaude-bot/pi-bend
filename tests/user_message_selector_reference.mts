import { UPSTREAM } from "./upstream_pin.mjs";
process.env.COLORTERM = "truecolor";
process.env.FORCE_COLOR = "3";
const { initTheme } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/theme.ts");
const { UserMessageSelectorComponent } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/components/user-message-selector.ts");
initTheme("dark");
const keys = { up: "\x1b[A", down: "\x1b[B", enter: "\r", escape: "\x1b", left: "\x1b[D" };
let input = "";
for await (const chunk of process.stdin) input += chunk;
const output = JSON.parse(input).map(c => {
  let action = "continue";
  const component = new UserMessageSelectorComponent(c.texts.map((text, i) => ({ id: String(i), text })), id => { action = "chosen:" + id; }, () => { action = "cancel"; }, c.initial || undefined);
  const list = component.getMessageList();
  const snapshot = () => ({ selected: list.messages[list.selectedIndex]?.id ?? null, action, lines: component.render(c.width) });
  const result = [snapshot()];
  for (const name of c.actions) {
    action = "continue";
    list.handleInput(keys[name] ?? name);
    result.push(snapshot());
  }
  return result;
});
await new Promise<void>(resolve => process.stdout.write(JSON.stringify(output), () => resolve()));
process.exit(0);
