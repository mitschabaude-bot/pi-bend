import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

// Execute the unmodified leaf-function tail of pinned models.ts. Importing the
// whole registry would load provider/auth dependencies unrelated to these tests.
const path = new URL('../../pi-mono/packages/ai/src/models.ts', import.meta.url);
const source = readFileSync(path, 'utf8');
const start = source.indexOf('export function hasApi<');
if (start < 0) throw new Error('upstream model helper boundary changed');
const code = stripTypeScriptTypes(source.slice(start));
const api = await import('data:text/javascript,' + encodeURIComponent(code));
const input = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const levels = ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'];
function number(bits: string): number {
  const bytes = Buffer.from(bits, 'hex');
  return bytes.readDoubleBE();
}
function word(value: number): string {
  const bytes = Buffer.alloc(8); bytes.writeDoubleBE(value); return bytes.toString('hex');
}
function rates(input: string[]) {
  const [i, o, r, w] = input.map(number);
  return {input:i, output:o, cacheRead:r, cacheWrite:w};
}
const results = process.argv[3] === 'cost'
  ? input.map(([base, tiers, values]: any[]) => {
      const cost = { ...rates(base), ...(tiers === null ? {} : {tiers: tiers.map(([threshold, prices]: any[]) => ({...rates(prices), inputTokensAbove:number(threshold)}))}) };
      const [i,o,r,w,long,reason,total] = values;
      const original = {input:11, output:22, cacheRead:33, cacheWrite:44, total:55};
      const usage = { input:number(i), output:number(o), cacheRead:number(r), cacheWrite:number(w),
        ...(long===null ? {} : {cacheWrite1h:number(long)}), ...(reason===null ? {} : {reasoning:number(reason)}), totalTokens:number(total), cost:original };
      const returned = api.calculateCost({cost}, usage);
      if (returned !== original || usage.cost !== original) throw new Error('upstream cost identity changed');
      return [returned.input, returned.output, returned.cacheRead, returned.cacheWrite, returned.total].map(word);
    })
  : process.argv[3] === 'identity'
  ? (() => {
      const models = input.models.map((value: any) => value === '__undefined__' ? undefined : value);
      return { equal: models.flatMap((a: any) => models.map((b: any) => api.modelsAreEqual(a, b))),
        api: input.apiChecks.map(([index, value]: any[]) => api.hasApi(models[index], value)) };
    })()
  : input.map(([reasoning, entries]: any[]) => {
      const map = entries === null ? undefined : Object.fromEntries(entries.map(([key, value]: any[]) => [key, value === '__undefined__' ? undefined : value]));
      const model = { reasoning, thinkingLevelMap: map };
      return { levels: api.getSupportedThinkingLevels(model), clamped: levels.map(level => api.clampThinkingLevel(model, level)) };
    });
console.log(JSON.stringify(results));
