// Test-only oracle pinned to ../pi-mono@46c9de402; no production dependency.
import { TuiMainScreen } from "../../pi-mono/packages/tui/src/tui-main-screen.ts";

class Terminal {
  writes: string[] = [];
  columns = 20;
  rows = 5;
  kittyProtocolActive = true;
  start() {}
  stop() {}
  async drainInput() {}
  write(value: string) { this.writes.push(`W${value}`); }
  moveBy() {}
  hideCursor() { this.writes.push("H"); }
  showCursor() { this.writes.push("S"); }
  clearLine() {}
  clearFromCursor() {}
  clearScreen() {}
  setTitle() {}
  setProgress() {}
}
class Component {
  lines: string[] = [];
  render() { return this.lines; }
  invalidate() {}
}
function setup() {
  const terminal = new Terminal();
  const tui = new TuiMainScreen(terminal as never);
  const component = new Component();
  tui.addChild(component as never);
  return { terminal, tui, component };
}
function frame(target: ReturnType<typeof setup>, lines: string[], width = 20, height = 5) {
  const { terminal, tui, component } = target;
  terminal.columns = width;
  terminal.rows = height;
  component.lines = lines;
  terminal.writes.length = 0;
  tui.renderNow();
  console.log(JSON.stringify(terminal.writes));
  const snapshot = tui.captureRenderState();
  console.log(JSON.stringify([snapshot.previousLines.length, snapshot.previousWidth, snapshot.previousHeight, snapshot.cursorRow, snapshot.hardwareCursorRow, snapshot.maxLinesRendered, snapshot.previousViewportTop, tui.fullRedraws, [...((tui as never) as { previousKittyImageIds: Set<number> }).previousKittyImageIds]]));
}
const regular = setup();
frame(regular, ["a", "b"]);
frame(regular, ["a", "c"]);
frame(regular, ["a", "c", "d"]);
frame(regular, ["a"]);
frame(regular, ["a"], 21);
const previousTermux = process.env.TERMUX_VERSION;
process.env.TERMUX_VERSION = "1";
frame(regular, ["a"], 21, 4);
if (previousTermux === undefined) delete process.env.TERMUX_VERSION;
else process.env.TERMUX_VERSION = previousTermux;
const image = setup();
frame(image, ["\x1b_Gi=7,r=2;abc\x1b\\", "", "tail"]);
frame(image, ["plain", "", "tail"]);
const shrink = setup();
shrink.tui.setClearOnShrink(true);
frame(shrink, ["one", "two", "three"]);
frame(shrink, ["one"]);
const above = setup();
above.terminal.rows = 3;
frame(above, ["0", "1", "2", "3", "4", "5"], 20, 3);
frame(above, ["changed", "1", "2", "3", "4", "5"], 20, 3);
frame(above, ["0", "1"], 20, 3);
const scrollingImage = setup();
frame(scrollingImage, ["0", "1", "2", "3", "4"]);
frame(scrollingImage, ["0", "1", "2", "3", "\x1b_Gi=8,r=2;abc\x1b\\", ""]);
const marked = setup();
const mark = "\x1b_pi:c\x07";
frame(marked, [`left${mark}`, "tail"]);
frame(marked, [`left${mark}`, "tail"]);
frame(marked, ["left", `tail${mark}`]);
marked.tui.setShowHardwareCursor(true);
frame(marked, ["left", `tail${mark}`]);
const middle = setup();
frame(middle, ["0", "1", "2", "3"]);
frame(middle, ["0", "X", "2", "3"]);
frame(middle, ["0", "X", "2"]);
frame(middle, ["0", "Y"]);
frame(middle, ["0", "Y", "2", "3", "4", "5", "6"], 20, 3);
const ids = setup();
frame(ids, ["\x1b_Gi=1;abc\x1b\\", "\x1b_Gi=2;def\x1b\\"]);
frame(ids, ["plain"], 21);
