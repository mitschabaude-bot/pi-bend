import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source = fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts', 'utf8');
const body = source.slice(source.indexOf('async function executeToolCallsParallel('), source.indexOf('\ntype PreparedToolCall ='));
const termination = source.match(/function shouldTerminateToolBatch\([^\n]*\)\s*:\s*boolean \{([\s\S]*?)\n\}/)[1];
const shouldTerminate = new Function('finalizedCalls', termination);
let input = ''; for await (const chunk of process.stdin) input += chunk;
const results = [];
for (const fixture of JSON.parse(input)) {
  const events = []; let calls = 0, hooks = 0;
  const signal = {aborted: fixture.initialAbort};
  const emit = async event => {
    const key = event.type === 'tool_execution_start' ? `start:${event.toolCallId}` : event.key;
    events.push(key);
    if (fixture.abortAfter && ['end:call', 'end:bad'].includes(key)) signal.aborted = true;
    if (key === fixture.failAt) throw new Error('delivery failed');
  };
  // Inject per-call operations into the unmodified upstream scheduler. Native
  // cases run the actual Bend validator, before/after hooks and update scope.
  const prepare = async (_context, _assistant, call) => {
    if (call.id !== 'call') return {kind:'immediate', result:{}, isError:true};
    if (signal.aborted) return {kind:'immediate', result:{}, isError:true};
    if (fixture.blockBefore) return {kind:'immediate', result:{terminate:true}, isError:true};
    return {kind:'prepared', toolCall:call};
  };
  const execute = async prepared => {
    calls++; await emit({key:`update:${prepared.toolCall.id}`});
    return {result:{}, isError:false};
  };
  const finalize = async (_context, _assistant, prepared, executed) => {
    hooks++;
    return {toolCall:prepared.toolCall, ...executed, result:{terminate:true}};
  };
  const end = async finalized => emit({key:`end:${finalized.toolCall.id}`});
  const message = finalized => ({id:finalized.toolCall.id, isError:finalized.isError});
  const deliver = async message => {
    await emit({key:`message_start:${message.id}`});
    await emit({key:`message_end:${message.id}`});
  };
  const run = new Function('prepareToolCall', 'executePreparedToolCall', 'finalizeExecutedToolCall', 'emitToolExecutionEnd', 'createToolResultMessage', 'emitToolResultMessage', 'shouldTerminateToolBatch', 'createErrorToolResult', stripTypeScriptTypes(body) + ';return executeToolCallsParallel;')(prepare, execute, finalize, end, message, deliver, shouldTerminate, () => ({}));
  let outcome;
  try { outcome = {ok:true, ...await run({}, {}, [{id:'call'}, {id:'bad'}, {id:'missing'}], {}, signal, emit)}; }
  catch (error) { outcome = {ok:false, error:error.message}; }
  results.push({...outcome, events, calls, hooks});
}
process.stdout.write(JSON.stringify(results));
