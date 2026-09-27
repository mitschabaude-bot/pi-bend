import { UPSTREAM } from "./upstream_pin.mjs";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { strict as assert } from "node:assert";
const { VStack } = await import(UPSTREAM + "/packages/tui/src/components/v-stack.ts");
const { HStack } = await import(UPSTREAM + "/packages/tui/src/components/h-stack.ts");
const { ScrollView } = await import(UPSTREAM + "/packages/tui/src/components/scroll-view.ts");
const { renderLayoutFrame } = await import(UPSTREAM + "/packages/tui/src/layout.ts");
const { stripTerminalSequences } = await import(UPSTREAM + "/packages/tui/src/utils.ts");

const source = UPSTREAM + "/packages/tui/src/";
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

// Regular mode renders the whole document, regardless of terminal height.
const inline = (root: Component) => {
  const heights = root instanceof VStack ? root.children.map(child => child.render(10).length).join(",") : "";
  const lines = root.render(10).map(line => stripTerminalSequences(line).trimEnd()).join("|");
  console.log(`horizontal:${heights}:[${lines}]`);
};
inline(new VStack([new ScrollView(staticText("one\ntwo\nthree")), staticText("dock")]));
inline(new VStack([staticText("body"), staticText("dock")]));
inline(staticText("one\ntwo\nthree"));
report("horizontal", new HStack([
  new VStack([staticText("below"), staticText("footer")]),
  staticText("right"),
], {align: "start"}), 16, 2);

// Compare complete terminal rows: stripping controls would hide prefix mistakes.
for (const text of [
  "hello", "\x1b[31mred\x1b[0m",
  "\x1b]133;A\x07text", "\x1b]133;B\x1b\\text",
  "\x1b]133;C\x07\x1b]133;A\x1b\\text",
  "\x1b]133;D\x07text", "\x1b]133;Afoo",
  "\x1b]133;A\x1bXtext", "\x1b]133;A",
  "before\x1b]133;A\x07text", "\x1b]133;A\x07",
  "\x1b]133;A\x07😀 日本 é",
]) {
  const frame = renderLayoutFrame(staticText(text), 80, 1, () => {});
  console.log(`zones:[${frame.lines.map(line => Array.from(line, char => char.codePointAt(0)).join(",")).join("|")}]`);
}

// Full-width vertical regions: clipping, padding, gaps and natural overflow.
for (const text of ["", "plain", "\x1b[31mred\x1b[0m", "\x1b]133;A\x07first", "\x1b]133;B\x1b\\first", "\x1b]133;C\x07\x1b]133;A\x07first", "before\x1b]133;A\x07first", "\x1b]133;D\x07first", "\x1b_Gi=1;payload\x1b\\", "😀 日本 é"]) {
  const a = staticText(text + "\nsecond"), b = staticText(text + "\nsecond");
  for (const [root, height] of [
    [new VStack([{ component: a, basis: 1, shrink: 0 }, { component: b, basis: 3, shrink: 0 }], { gap: 1 }), 5],
    [new VStack([a, b], { gap: 1 }), 5],
  ] as const) {
    const frame = renderLayoutFrame(root, 80, height, () => {});
    console.log(`zones:[${frame.lines.map(line => Array.from(line, char => char.codePointAt(0)).join(",")).join("|")}]`);
  }
}
