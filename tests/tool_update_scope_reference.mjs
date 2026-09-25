// Execute the pinned helper to check error selection around tool settlement.
import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
const source = fs.readFileSync(UPSTREAM + '/packages/agent/src/agent-loop.ts', 'utf8');
const start = source.indexOf('async function executePreparedToolCall(');
const end = source.indexOf('\nasync function finalizeExecutedToolCall(', start);
if (start < 0 || end <= start) throw new Error('upstream execution helper missing');
const declaration = source.slice(start, end).trim();
const body = declaration.slice(declaration.indexOf('): Promise<ExecutedToolCallOutcome> {') + '): Promise<ExecutedToolCallOutcome> {'.length, -1)
  .replace('const updateEvents: Promise<void>[] = [];', 'const updateEvents = [];')
  .replace('prepared.args as never', 'prepared.args');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const execute = new AsyncFunction('prepared', 'signal', 'emit', 'createErrorToolResult', body);
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  promise.catch(() => {}); // Observe fixture rejections before the helper awaits them.
  return { promise, resolve, reject };
}
async function scenario(kind) {
  const tool = deferred(), first = deferred(), second = deferred();
  let update;
  const events = [];
  const running = execute({toolCall: {id: 'id', name: 'tool', arguments: {}}, args: {}, tool: {
    execute(_id, _args, _signal, onUpdate) {
      update = onUpdate;
      onUpdate('first'); onUpdate('second');
      return tool.promise;
    },
  }}, undefined, event => {
    events.push(event.partialResult);
    return event.partialResult === 'first' ? first.promise : second.promise;
  }, message => ({content: [{type: 'text', text: message}], details: {}}));
  const observed = running.then(() => 'success', error => error);
  if (kind === 'alreadyFailed') {
    second.reject('second'); first.reject('first');
  } else if (kind === 'pending') {
    second.reject('second');
  }
  tool.resolve({content: [], details: {}});
  // The helper registered its await before this observer, so it closes first.
  await tool.promise;
  if (kind === 'afterClose') second.reject('second');
  const result = await observed;
  first.reject('first');
  update('late');
  if (events.join('|') !== 'first|second') throw new Error('settled helper accepted a late update');
  return result;
}
const results = {};
for (const kind of ['alreadyFailed', 'afterClose', 'pending']) results[kind] = await scenario(kind);
console.log(JSON.stringify(results));
