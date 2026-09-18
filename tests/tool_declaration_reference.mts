import { toToolDeclaration, declarationsEqual, getToolStateChanges, hasToolRedefinitions, hasNonAdditiveToolChanges } from '../../pi-mono/packages/ai/src/utils/transcript.ts';
import type { Tool } from '../../pi-mono/packages/ai/src/types.ts';
import { readFileSync } from 'node:fs';

function schema(v: any): any {
  switch (v[0]) {
    case 'undefined': return undefined;
    case 'null': return null;
    case 'boolean': return v[1];
    case 'number': { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt('0x' + v[1])); return b.readDoubleBE(); }
    case 'string': return String.fromCodePoint(...v[1]);
    case 'symbol': return Symbol.for(String(v[1]));
    case 'callable': return () => { throw new Error('unexpected callback'); };
    case 'bigint': return 1n;
    case 'array': return v[1].map(schema);
    case 'object': {
      const out = Object.create(null);
      for (const [key, value, enumerable] of v[1]) Object.defineProperty(out, key, { value: schema(value), enumerable, configurable: true });
      for (const [key, value] of v[2]) out[Symbol.for(String(key))] = schema(value);
      return out;
    }
    default: throw new Error('unknown fixture');
  }
}
function tool(v: any): Tool {
  return { name: v.name, description: v.description, parameters: schema(v.parameters),
    ...(v.sampling === null ? {} : { constrainedSampling: v.sampling }) };
}
function result(fn: () => unknown) {
  try { return { value: fn() }; }
  catch (error) {
    if (error instanceof SyntaxError) return { error: 'omitted' };
    if (error instanceof TypeError) return { error: 'bigint' };
    throw error;
  }
}
const cases = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const output = process.argv[3] === 'history'
  ? cases.map(([values, entries]: any[]) => {
      const pool = values.map(tool);
      const messages = entries.map(([role, added, removed]: any[]) => ({
        role, toolsAdded: added.map((index: number) => pool[index]), toolsRemoved: removed.map((name: string) => ({name})),
      }));
      return { redefined: result(() => hasToolRedefinitions(messages)), nonAdditive: hasNonAdditiveToolChanges(messages) };
    })
  : process.argv[3] === 'state'
  ? cases.map(([previous, current]: any[]) => result(() => {
      const changes = getToolStateChanges(previous.map(tool), current.map(tool));
      return { toolsAdded: changes.toolsAdded.map(value => JSON.stringify(value)), toolsRemoved: changes.toolsRemoved.map(value => value.name) };
    }))
  : cases.map(([a, b]: any[]) => ({
      left: result(() => JSON.stringify(toToolDeclaration(tool(a)))),
      right: result(() => JSON.stringify(toToolDeclaration(tool(b)))),
      equal: result(() => declarationsEqual(tool(a), tool(b))),
    }));
console.log(JSON.stringify(output));
