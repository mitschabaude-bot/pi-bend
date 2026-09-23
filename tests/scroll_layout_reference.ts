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
const child: Component = { render: () => ["1", "2", "3", "4", "5", "6"], invalidate: () => {} };
const clean = (lines: string[]) => lines.map(line => stripTerminalSequences(line).trimEnd()).join("|");
function info(label: string, view: ScrollView, width: number, height: number) {
  const frame = renderLayoutFrame(view, width, height, () => {});
  const box = frame.root.children[0]!;
  console.log(`${label}:${view.scrollTop}:${box.rect.width}x${box.rect.height}:${-box.rect.y}:[${clean(frame.lines)}]`);
}
const follow = new ScrollView(child, {follow: "end", scrollbarHideDelayMs: 10});
info("follow", follow, 10, 3);
follow.scrollBy(-2);
info("back", follow, 10, 3);
const always = new ScrollView(child, {scrollbar: "always", scrollbarHideDelayMs: 10});
info("always", always, 6, 3);
const auto = new ScrollView(child, {scrollbar: "auto", scrollbarHideDelayMs: 10});
info("auto-initial", auto, 6, 3);
auto.scrollBy(1);
info("auto-moved", auto, 6, 3);
auto.scrollToEnd();
info("auto-end", auto, 6, 3);
