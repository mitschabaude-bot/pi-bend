import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source = fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts', 'utf8');
const body = source.slice(source.indexOf('async function runLoop('), source.indexOf('\n/**\n * Declare tool loadout changes'));
let text = ''; for await (const chunk of process.stdin) text += chunk;
const output = [];
for (const fixture of JSON.parse(text)) {
  const events = []; let responding = false, pending = '';
  const nextTurn = Symbol('next turn');
  const assistant = {role:'assistant', content:fixture.tools ? [{type:'toolCall',id:'call',name:'echo'}] : [{type:'text',text:'done'}], stopReason:'stop'};
  const context = {messages:[{role:'custom',name:'old'}]};
  const history = [{role:'custom',name:'prompt'}];
  const toolResult = {role:'toolResult',toolCallId:'call',toolName:'echo',details:'tool',isError:false};
  const record = async name => {
    events.push(name);
    if (name === fixture.failAt) throw new Error('delivery failed');
  };
  const names = values => values.map(v => v.role === 'custom' ? v.name : v.role === 'assistant' ? 'assistant' : v.toolCallId).join('|') + (values.length ? '|' : '');
  const expectedContext = fixture.tools ? 'old|assistant|call|' : 'old|assistant|';
  const expectedHistory = fixture.tools ? 'prompt|assistant|call|' : 'prompt|assistant|';
  const emit = async event => {
    if (event.type === 'turn_end') {
      if (event.toolResults.length !== Number(fixture.tools)) throw new Error('source tool-result count mismatch');
    }
    if (event.type === 'agent_end' && names(event.messages) !== expectedHistory) throw new Error('source agent history mismatch');
    await record(event.type);
  };
  const queued = async (name, mode) => {
    await record(name);
    if (mode === 2) throw new Error(`${name} failed`);
    pending = mode === 1 ? `${name}|` : '';
    return mode === 1 ? [{role:'custom',name}] : [];
  };
  const config = {
    shouldStopAfterTurn: async completed => {
      if (names(completed.context.messages) !== expectedContext || names(completed.newMessages) !== expectedHistory) throw new Error('source stop-hook snapshot mismatch');
      await record('stop');
      if (fixture.stopMode === 2) throw new Error('stop failed');
      return fixture.stopMode === 1;
    },
    getSteeringMessages: async () => responding ? queued('steering', fixture.steeringMode) : [],
    getFollowUpMessages: async () => queued('follow', fixture.followMode),
    prepareNextTurn: async () => { throw nextTurn; },
  };
  const stream = async current => {
    responding = true; current.messages.push(assistant); return assistant;
  };
  const execute = async () => {
    for (const key of ['start:call','end:call','message_start:call','message_end:call']) await record(key);
    return {messages:[toolResult],terminate:fixture.terminate};
  };
  // Preserve runLoop's actual history, turn-end, stop, steering and follow-up
  // control flow. Provider/declaration/tool helpers isolate this turn phase.
  const run = new Function('streamAssistantResponse', 'executeToolCalls', 'failToolCallsFromTruncatedMessage', 'declareToolChanges', stripTypeScriptTypes(body) + ';return runLoop;')(stream, execute, execute, (_context, messages) => messages);
  let category = 0, error = '';
  try { await run(context, history, config, undefined, emit, undefined); }
  catch (cause) {
    if (cause === nextTurn) category = 1;
    else { category = 2; error = cause.message; }
  }
  output.push({category, pending:category === 1 ? pending : '', error, events});
}
process.stdout.write(JSON.stringify(output));
