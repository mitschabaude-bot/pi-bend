import fs from 'node:fs';
const source = fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts', 'utf8');
const start = source.indexOf('async function finalizeExecutedToolCall(');
const body = source.slice(start).match(/if \(afterResult\) \{([\s\S]*?)\n\t\t\t\}/)[0];
const apply = new Function('result', 'isError', 'afterResult', body + '\nreturn { result, isError };');
const cases = [];
for (let content = 0; content < 3; content++) for (let details = 0; details < 6; details++) for (let flags = 0; flags < 6; flags++) {
  const originalDetails = 'old-details', replacementDetails = 'new-details';
  const oldUsage = {marker: 'old'}, newUsage = {marker: 'new'};
  const original = {content:['old'], details:originalDetails, usage:oldUsage, terminate: [undefined,false,true,undefined,true,false][flags]};
  const detailValues = [undefined, null, false, 0, '', replacementDetails];
  const patch = {content:[undefined,[],['new']][content], details:detailValues[details],
    usage:flags & 1 ? newUsage : undefined,
    terminate:flags === 0 || flags === 4 ? undefined : flags === 1,
    isError:flags === 0 || flags === 4 ? undefined : flags === 2};
  const beforeError = (flags & 1) === 0;
  const outcome = apply(original, beforeError, patch);
  const result = outcome.result;
  const expectedDetails = result.details === originalDetails ? 6 : detailValues.indexOf(result.details);
  cases.push({content, details, flags, expectedDetails, expectedContent:result.content.join(','),
    expectedUsage:result.usage.marker === newUsage.marker, expectedTerminate:result.terminate ?? null,
    expectedError:outcome.isError});
}
const original = {content:['old'], details:{}, terminate:true};
if (JSON.stringify(apply(original, false, undefined).result) !== JSON.stringify(original)) throw new Error('absent hook must preserve original');
console.log(JSON.stringify({cases}));
