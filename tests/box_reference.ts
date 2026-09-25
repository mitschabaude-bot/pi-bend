import { UPSTREAM } from "./upstream_pin.mjs";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { strict as assert } from "node:assert";
const { Box } = await import(UPSTREAM + "/packages/tui/src/components/box.ts");

assert.equal(createHash("sha256").update(readFileSync(UPSTREAM + "/packages/tui/src/components/box.ts")).digest("hex"), "f79d30c9c263064df656dc55674b5d951bf765ffbbf658f400f449c44f6dab98");
let value = "abc";
let seen = "";
let invalidations = 0;
const child: Component = {
  render: () => [value],
  invalidate: () => { invalidations++; },
  handleMouse: (event) => {
    seen = `${event.x},${event.y},${event.width},${event.height}`;
    return { handled: true, capture: false, focus: true };
  },
};
const show = (lines: string[]) => console.log(`[${lines.join("|")}]`);
show(new Box(1, 1).render(6));
const box = new Box(1, 1);
box.addChild(child);
show(box.render(6));
value = "xyz";
show(box.render(6));
const mouse = (x: number, y: number): TuiMouseEvent => ({ type: "press", button: "left", x, y, screenX: 10 + x, screenY: 20 + y, width: 6, height: 3, shift: false, alt: false, ctrl: false });
box.handleMouse(mouse(2, 1));
console.log(seen);
box.handleMouse(mouse(0, 1));
console.log(seen);
box.invalidate();
console.log(invalidations);
box.setBgFn(text => `<${text}>`);
show(box.render(6));
