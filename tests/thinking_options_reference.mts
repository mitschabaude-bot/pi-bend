// Test-only oracle: execute the pinned helper bodies, not a rewritten policy.
import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import assert from 'node:assert/strict';
const source = fs.readFileSync('../pi-mono/packages/ai/src/api/simple-options.ts', 'utf8');
const js = stripTypeScriptTypes(source).replace(/^import .*estimate.*;$/m, '').replace(/^export /gm, '');
assert(!/^import /m.test(js));
const helpers = new Function(js + ';return {clampReasoning, thinkingBudgetForLevel, clampThinkingBudgetToAnswerRoom, adjustMaxTokensForThinking};')();
let input = ''; for await (const chunk of process.stdin) input += chunk;
const decode = v => v === 'nan' ? NaN : v === 'infinity' ? Infinity : v === '-infinity' ? -Infinity : v;
const encode = v => Number.isNaN(v) ? 'nan' : v === Infinity ? 'infinity' : v === -Infinity ? '-infinity' : v;
const results = JSON.parse(input).map(c => {
  const custom = c.custom == null ? undefined : Object.fromEntries(Object.entries(c.custom).map(([k,v]) => [k,decode(v)]));
  const budget = helpers.thinkingBudgetForLevel(c.level, custom);
  const adjusted = helpers.adjustMaxTokensForThinking(c.base == null ? undefined : decode(c.base), decode(c.model), c.level, custom);
  return {level: helpers.clampReasoning(c.level), budget: encode(budget), room: encode(helpers.clampThinkingBudgetToAnswerRoom(budget, decode(c.model))), maxTokens: encode(adjusted.maxTokens), thinkingBudget: encode(adjusted.thinkingBudget)};
});
assert.equal(helpers.clampReasoning(undefined), undefined);
process.stdout.write(JSON.stringify(results));
