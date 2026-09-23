import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { strict as assert } from "node:assert";
import { VStack } from "/home/agent/code/pi-mono/packages/tui/src/components/v-stack.ts";
import { HStack } from "/home/agent/code/pi-mono/packages/tui/src/components/h-stack.ts";
import { ScrollView } from "/home/agent/code/pi-mono/packages/tui/src/components/scroll-view.ts";
import { renderLayoutFrame } from "/home/agent/code/pi-mono/packages/tui/src/layout.ts";
import { stripTerminalSequences } from "/home/agent/code/pi-mono/packages/tui/src/utils.ts";
import type { Component } from "/home/agent/code/pi-mono/packages/tui/src/tui.ts";
const source = "/home/agent/code/pi-mono/packages/tui/src/";
for (const [file, digest] of [
  ["layout.ts", "7530a8eaa30f44fef82e8b7020b5068ba89d34884463c6cb526073b20fcdeef0"],
  ["components/stack.ts", "93208d326fa43431b930eaa3250a1e19747063d696e97ec2f002f5feaa54fc18"],
  ["components/h-stack.ts", "6622e1e2605e500a420c3cdf3ffcae0548b2d86ec496a0f6bf1dd5c95aeb0b6b"],
  ["components/v-stack.ts", "0f36c9417bfffe5f6b9cc5fd40d420390cf9bebae70a073a409ac5f931f1f813"],
  ["components/scroll-view.ts", "76dfd9f8a88cabc064f0652b83f16a945fbc988c9fe7c0423a4cd796907ef77d"],
] as const) assert.equal(createHash("sha256").update(readFileSync(source + file)).digest("hex"), digest);
const staticText = (text: string): Component => ({render: () => text.split("\n"), invalidate: () => {}});
const report = (label: string, root: Component, width: number, height: number) => {
  const frame = renderLayoutFrame(root, width, height, () => {});
  console.log(`${label}:${frame.root.children.map(child => child.rect.height).join(",")}:[${frame.lines.map(line => stripTerminalSequences(line).trimEnd()).join("|")}]`);
};
const dock = new VStack([
  staticText("top1\ntop2\ntop3"),
  {component: staticText("selector"), minSize: 3},
  staticText("below"),
  {component: staticText("footer"), minSize: 1},
]);
report("nested", new VStack([
  {component: staticText("body"), basis: 0, grow: 1, minSize: 1},
  {component: dock, basis: "auto", minSize: 1},
]), 10, 9);
report("horizontal", new HStack([
  {component: staticText("left"), basis: 6, shrink: 0},
  {component: staticText("right"), basis: 6, shrink: 0},
], {align: "start"}), 12, 1);
report("horizontal", new VStack([
  {component: new ScrollView(staticText("one\ntwo\nthree")), basis: 0, grow: 1},
  staticText("dock"),
]), 10, 3);
