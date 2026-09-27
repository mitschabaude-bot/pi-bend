// Test-only: compare actual xterm cells, including colors and attributes.
// Equivalent SGR span boundaries are not a user-visible rendering contract.
import assert from "node:assert/strict";
import { UPSTREAM } from "./upstream_pin.mjs";
const { VirtualTerminal } = await import(`${UPSTREAM}/packages/tui/test/virtual-terminal.ts`);
const { visibleWidth } = await import(`${UPSTREAM}/packages/tui/src/utils.ts`);
const [expected, actual]: string[] = JSON.parse(await Bun.stdin.text());
const frames = (text: string) => text.trimEnd().split("\n").map(frame => {
  const [name, body] = frame.split("\x1e");
  return { name, lines: body.split("\x1f") };
});
async function cells(lines: string[], width: number) {
  const terminal = new VirtualTerminal(width, Math.max(24, lines.length + 2));
  terminal.write(lines.join("\r\n"));
  await terminal.flush();
  const buffer = (terminal as unknown as { xterm: { buffer: { active: any } } }).xterm.buffer.active;
  return lines.map((_, y) => Array.from({ length: width }, (_, x) => {
    const cell = buffer.getLine(y).getCell(x);
    return [cell.getChars(), cell.getWidth(), cell.getFgColorMode(), cell.getFgColor(),
      cell.getBgColorMode(), cell.getBgColor(), cell.isBold(), cell.isDim(),
      cell.isItalic(), cell.isUnderline(), cell.isInverse(), cell.isInvisible(), cell.isStrikethrough()];
  }));
}
const left = frames(expected), right = frames(actual);
assert.equal(left.length, right.length);
for (let i = 0; i < left.length; i++) {
  assert.equal(left[i].name, right[i].name);
  assert.equal(left[i].lines.length, right[i].lines.length, left[i].name);
  const width = Math.max(28, ...left[i].lines.map(visibleWidth), ...right[i].lines.map(visibleWidth));
  const actualCells = await cells(right[i].lines, width);
  const expectedCells = await cells(left[i].lines, width);
  for (let y = 0; y < expectedCells.length; y++) {
    for (let x = 0; x < width; x++) {
      assert.deepEqual(actualCells[y][x], expectedCells[y][x], `${left[i].name} row ${y} column ${x}`);
    }
  }
}
console.log(`${left.length} tool frames match xterm cells and styles`);
