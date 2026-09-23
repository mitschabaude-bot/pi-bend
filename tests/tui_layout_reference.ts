import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { strict as assert } from "node:assert";
import { ScrollView } from "/home/agent/code/pi-mono/packages/tui/src/components/scroll-view.ts";
import { renderLayoutFrame } from "/home/agent/code/pi-mono/packages/tui/src/layout.ts";
import { stripTerminalSequences } from "/home/agent/code/pi-mono/packages/tui/src/utils.ts";
import type { Component } from "/home/agent/code/pi-mono/packages/tui/src/tui.ts";
const source = "/home/agent/code/pi-mono/packages/tui/src/";
for (const [file, digest] of [
  ["layout.ts", "7530a8eaa30f44fef82e8b7020b5068ba89d34884463c6cb526073b20fcdeef0"],
  ["components/scroll-view.ts", "76dfd9f8a88cabc064f0652b83f16a945fbc988c9fe7c0423a4cd796907ef77d"],
] as const) assert.equal(createHash("sha256").update(readFileSync(source + file)).digest("hex"), digest);
const child: Component = {render: () => ["one", "two", "three", "four", "five", "six"], invalidate: () => {}};
const view = new ScrollView(child, {follow: "end", primary: true, scrollbar: "always", scrollbarHideDelayMs: 10});
function frame(label: string, width: number, height: number) {
  const lines = renderLayoutFrame(view, width, height, () => {}).lines;
  console.log(`${label}:${view.scrollTop}:[${lines.map(line => stripTerminalSequences(line).trimEnd()).join("|")}]`);
}
frame("initial", 6, 3);
view.scrollBy(-2);
frame("back", 6, 3);
frame("resize", 6, 4);
view.scrollBy(9);
frame("end", 6, 4);
