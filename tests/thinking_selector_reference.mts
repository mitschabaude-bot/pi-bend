import { UPSTREAM } from "./upstream_pin.mjs";
process.env.COLORTERM = "truecolor";
process.env.FORCE_COLOR = "3";
const { initTheme } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/theme.ts");
const { ThinkingSelectorComponent } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/components/thinking-selector.ts");
const { KEYBINDINGS } = await import(UPSTREAM + "/packages/coding-agent/src/core/keybindings.ts");
const { KeybindingsManager, setKeybindings } = await import(UPSTREAM + "/packages/tui/src/keybindings.ts");
setKeybindings(new KeybindingsManager(KEYBINDINGS));
initTheme("dark");
let input = "";
for await (const chunk of process.stdin) input += chunk;
const keys = {up:"\x1b[A", down:"\x1b[B", enter:"\r", escape:"\x1b", left:"\x1b[D", save:"\x13"};
const output = JSON.parse(input).map(c => {
  let action = "continue";
  const component = new ThinkingSelectorComponent(c.current, c.levels,
    level => {action = "chosen:" + level;}, () => {action = "cancel";},
    level => {action = "default:" + level;}, c.default);
  component.focused = true;
  const snapshot = response => ({selected:component.selectList.getSelectedItem()?.value ?? null, action,
    response:response ? {handled:response.handled ?? false, capture:response.capture ?? false, focus:response.focus ?? false, render:response.render ?? null} : null,
    lines:component.render(c.width)});
  const result = [snapshot(null)];
  for (const step of c.steps) {
    action = "continue";
    let response;
    if (typeof step === "string") component.handleInput(keys[step] ?? step);
    else {
      let base = 0;
      if (step.zone === "search" || step.zone === "list") {
        const target = step.zone === "search" ? component.searchInput : component.selectList;
        for (const child of component.mouseLayout.children) {
          if (child.component === target) break;
          base += child.height;
        }
      }
      const y = base + (step.y ?? 0);
      response = component.handleMouse({type:step.type, button:step.button ?? "left", x:step.x ?? 3, y,
      screenX:step.x ?? 3, screenY:y, width:c.width, height:1000,
      shift:false, alt:false, ctrl:false, wheelDelta:step.delta, clickCount:step.type === "click" ? 1 : undefined});
    }
    result.push(snapshot(response));
  }
  return result;
});
await new Promise(resolve => process.stdout.write(JSON.stringify(output),resolve));
process.exit(0);
