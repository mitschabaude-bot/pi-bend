// Test-only upstream oracle; never loaded by the native application.
import { UPSTREAM } from "./upstream_pin.mjs";
const { truncateHead, truncateTail } = await import(`${UPSTREAM}/packages/coding-agent/src/core/tools/truncate.ts`);
const cases = JSON.parse(await Bun.file(process.argv[2]).text());
console.log(JSON.stringify(cases.map(({text, lines, bytes}) => ({
  head: truncateHead(text, {maxLines: lines, maxBytes: bytes}),
  tail: truncateTail(text, {maxLines: lines, maxBytes: bytes}),
}))));
