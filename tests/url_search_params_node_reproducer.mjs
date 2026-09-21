// Isolate the reference-runtime discrepancy without Bend or networking.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
const sources = process.binding('natives');
const cases = ['x=%FFé🙂', 'x=%éF🙂'];
const observations = cases.map(input => {
  const canonical = input.replace(/[^\x00-\x7f]/gu, c => encodeURIComponent(c));
  const raw = [...new URLSearchParams(input)];
  const byteEncoded = [...new URLSearchParams(canonical)];
  return { input, canonical, raw, byteEncoded, differs: JSON.stringify(raw) !== JSON.stringify(byteEncoded) };
});
assert.deepEqual(observations[0].byteEncoded, [['x', '\uFFFDé🙂']]);
assert.deepEqual(observations[1].byteEncoded, [['x', '%éF🙂']]);
console.log(JSON.stringify({ node: process.version, sourceHashes: Object.fromEntries(['internal/url', 'querystring'].map(name => [name, createHash('sha256').update(sources[name]).digest('hex')])), observations }, null, 2));
