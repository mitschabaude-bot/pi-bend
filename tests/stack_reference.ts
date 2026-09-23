import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { strict as assert } from "node:assert";
import { allocateStackSizes } from "/home/agent/code/pi-mono/packages/tui/src/components/stack.ts";
import { VStack } from "/home/agent/code/pi-mono/packages/tui/src/components/v-stack.ts";
import { HStack } from "/home/agent/code/pi-mono/packages/tui/src/components/h-stack.ts";
import { getLayoutBoxesAt, renderLayoutFrame } from "/home/agent/code/pi-mono/packages/tui/src/layout.ts";
import { stripTerminalSequences } from "/home/agent/code/pi-mono/packages/tui/src/utils.ts";
import type { Component } from "/home/agent/code/pi-mono/packages/tui/src/tui.ts";
const source = "/home/agent/code/pi-mono/packages/tui/src/";
for (const [file, digest] of [
  ["layout.ts", "7530a8eaa30f44fef82e8b7020b5068ba89d34884463c6cb526073b20fcdeef0"],
  ["components/stack.ts", "93208d326fa43431b930eaa3250a1e19747063d696e97ec2f002f5feaa54fc18"],
  ["components/h-stack.ts", "6622e1e2605e500a420c3cdf3ffcae0548b2d86ec496a0f6bf1dd5c95aeb0b6b"],
  ["components/v-stack.ts", "0f36c9417bfffe5f6b9cc5fd40d420390cf9bebae70a073a409ac5f931f1f813"],
] as const) assert.equal(createHash("sha256").update(readFileSync(source + file)).digest("hex"), digest);
const c = (...lines: string[]): Component => ({ render: () => lines, invalidate: () => {} });
const top = c("top"), body = c("body"), a = c("a1", "a2", "a3"), b = c("b1", "b2", "b3"), left = c("left"), right = c("right"), no = c("hidden"), yes = c("shown");
const clean = (lines: readonly string[]) => lines.map(line => stripTerminalSequences(line).trimEnd()).join("|");
function report(label: string, stack: Component, width: number, height: number) {
  const frame = renderLayoutFrame(stack, width, height, () => {});
  console.log(`${label}:${frame.root.children.map(x => x.rect.height).join(",")}:${frame.root.children.map(x => x.rect.width).join(",")}:[${clean(frame.lines)}]`);
}
report("grow", new VStack([{component: top, basis: 1, shrink: 0}, {component: body, basis: 0, grow: 1}]), 10, 4);
report("shrink", new VStack([{component: a, minSize: 1}, {component: b, shrink: 0}]), 10, 4);
const horizontal = new HStack([{component: left, basis: 6, shrink: 0}, {component: right, basis: 6, shrink: 0}]);
report("horizontal", horizontal, 12, 1);
const hitFrame = renderLayoutFrame(horizontal, 12, 1, () => {});
console.log(`hits:${getLayoutBoxesAt(hitFrame, 0, 0).length},${getLayoutBoxesAt(hitFrame, 6, 0).length},${getLayoutBoxesAt(hitFrame, 12, 0).length}`);
report("zero", new HStack([{component: no, basis: 0, shrink: 0}, {component: yes, basis: 0, grow: 1}]), 5, 1);
const stack = new VStack([top, {component: no, visible: () => false}, body], {gap: 1});
report("visibility", stack, 10, 3);
console.log(`standalone-v:[${clean(stack.render(10))}]`);
console.log(`standalone-h:[${clean(new HStack([{component: left, basis: 6, shrink: 0}, {component: right, basis: 6, shrink: 0}]).render(12))}]`);

console.log(`grow-cap:[${allocateStackSizes([{component: top, basis: 1, grow: 1, maxSize: 2}, {component: body, basis: 1, grow: 1, maxSize: 10}], [0, 0], 6, 0).join(",")}]`);
console.log(`weighted-shrink:[${allocateStackSizes([{component: top, basis: 6, shrink: 1}, {component: body, basis: 6, shrink: 2}], [0, 0], 8, 0).join(",")}]`);
