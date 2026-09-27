import { UPSTREAM } from "./upstream_pin.mjs";
const { CustomMessageComponent } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/components/custom-message.ts");
const { initTheme } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/theme.ts");
const { Text } = await import(UPSTREAM + "/packages/tui/src/components/text.ts");
initTheme("dark");
const message: any = { role: "custom", customType: "notice", content: "fallback body", display: true, details: undefined, timestamp: 0 };
const snapshot = (label: string, component: any) => process.stdout.write(label + "\x1e" + component.render(80).join("\x1f") + "\n");
const custom = new CustomMessageComponent(message, (message: any, options: any) => ({
  render: () => [`${message.customType}:${options.expanded ? "True" : "False"}:${options.outputPad}`],
  invalidate: () => {},
}));
snapshot("initial", custom);
custom.setExpanded(false);
custom.setOutputPad(1);
custom.setExpanded(true);
custom.setOutputPad(3);
snapshot("options", custom);
custom.invalidate();
snapshot("fallback", new CustomMessageComponent(message, () => { throw new Error("renderer failed"); }));
snapshot("fallback", new CustomMessageComponent(message, () => undefined));
snapshot("fallback", new CustomMessageComponent(message));
snapshot("fallback", new CustomMessageComponent({ ...message, customType: "skill" }));
const padded = new CustomMessageComponent(message, (_: any, options: any) => new Text("custom", options.outputPad, 0));
process.stdout.write("padding1\x1e" + padded.render(40).join("\x1f") + "\n");
padded.setOutputPad(0);
process.stdout.write("padding0\x1e" + padded.render(40).join("\x1f") + "\n");

const { Container, dispatchMouseEvent } = await import(UPSTREAM + "/packages/tui/src/tui.ts");
const assert = (await import("node:assert/strict")).default;
let nextId = 10000;
const events: string[] = [];
const mouseCustom = new CustomMessageComponent(message, () => {
  const id = ++nextId;
  return { id, render: () => ["control"], invalidate() {}, handleMouse(event: any) {
    events.push(`${id}:${event.y};`);
    return { handled: true, capture: true, focus: true };
  }};
});
const document = new Container();
document.addChild(mouseCustom);
const press = (y: number): any => ({type:"press",button:"left",x:2,y,screenX:2,screenY:y,width:80,height:2,shift:false,alt:false,ctrl:false});
const hit = (wanted: number) => {
  const result: any = dispatchMouseEvent(document, press(1));
  assert.equal(result.target.component.id, wanted);
  assert.equal(result.focusTarget.id, wanted);
  assert.equal(result.target.originY, 1);
  assert.equal(result.target.width, 80);
  assert.equal(result.target.height, 1);
  assert.equal(result.capture, true);
  assert.equal(result.focus, true);
};
document.render(80);
const pending = new Container();
pending.addChild(mouseCustom);
pending.render(80);
pending.clear();
assert.equal(dispatchMouseEvent(pending, press(1))?.target.component.id, 10001);
pending.render(80);
assert.equal(dispatchMouseEvent(pending, press(1)), undefined);
assert.equal(dispatchMouseEvent(document, press(0)), undefined);
hit(10001);
mouseCustom.setExpanded(true);
hit(10001);
document.render(80);
hit(10002);
process.stdout.write("mouse\x1e" + events.join("") + "\n");

// Captured and focused receivers survive replacement of their mounted renderer.
const { TuiAltScreen } = await import(UPSTREAM + "/packages/tui/src/tui-alt-screen.ts");
let gestureId = 10000;
const gestureEvents: string[] = [];
const gestureCustom = new CustomMessageComponent(message, () => {
  const id = ++gestureId;
  return { id, focused: false, render: () => ["control"], invalidate() {},
    handleInput(data: string) { gestureEvents.push(data); },
    handleMouse(event: any) {
      gestureEvents.push(`${id}:${event.y};`);
      if (gestureId === 10001) gestureCustom.setExpanded(true);
      return { handled: true, capture: true, focus: true };
    },
  };
});
const gestureDocument = new Container();
gestureDocument.addChild(gestureCustom);
const gestureTui: any = new TuiAltScreen({columns: 80, rows: 24, write() {}});
gestureTui.requestRender = () => {};
gestureTui.addChild(gestureDocument);
const rect = {x: 0, y: 0, width: 80, height: 2};
gestureTui.currentLayout = {root: {component: gestureDocument, rect, clip: rect, children: [], layer: 0}, width: 80, height: 24, lines: []};
gestureDocument.render(80);
gestureTui.handleViewportInput("\x1b[<0;3;2M");
const originalFocus = gestureTui.getFocusedComponent();
assert.equal(originalFocus.id, 10001);
gestureDocument.render(80);
gestureTui.handleViewportInput("\x1b[<32;3;4M");
gestureTui.handleViewportInput("\x1b[<0;3;4m");
assert.equal(gestureTui.getFocusedComponent(), originalFocus);
gestureTui.handleTerminalInput("typed");
assert.equal(gestureEvents.join(""), "10001:0;10001:2;10001:2;typed");
process.stdout.write("gesture\x1e" + gestureEvents.join("") + "\n");
gestureTui.setFocus(null);
