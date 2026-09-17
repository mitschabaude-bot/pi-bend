// Test-only upstream oracle; never loaded by the native application.
const reference = process.env.PI_REFERENCE ?? "../pi-mono";
const { truncateHead, truncateTail } = await import(`${process.cwd()}/${reference}/packages/coding-agent/src/core/tools/truncate.ts`);
const cases = JSON.parse(await Bun.file(process.argv[2]).text());
console.log(JSON.stringify(cases.map(({text, lines, bytes}) => ({
  head: truncateHead(text, {maxLines: lines, maxBytes: bytes}),
  tail: truncateTail(text, {maxLines: lines, maxBytes: bytes}),
}))));
