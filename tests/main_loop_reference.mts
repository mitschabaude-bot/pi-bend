// Execute the pinned internal loop and all its helpers, including streaming,
// declarations, tool dispatch and completion. Only the provider is a fixture.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {stripTypeScriptTypes} from 'node:module';
import {getCurrentTools, getToolStateChanges, toToolDeclaration, normalizeContext} from '../../pi-mono/packages/ai/src/utils/transcript.ts';
import {Compile} from '../build/schema-reference/node_modules/typebox/build/compile/index.mjs';
import {Value} from '../build/schema-reference/node_modules/typebox/build/value/index.mjs';
const validationSource = fs.readFileSync('../pi-mono/packages/ai/src/utils/validation.ts', 'utf8');
const validationBody = stripTypeScriptTypes(validationSource.slice(validationSource.indexOf('const validatorCache ='))).replace(/^export /gm, '');
const validateToolArguments = new Function('Compile', 'Value', validationBody + ';return validateToolArguments;')(Compile, Value);
const source = fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts', 'utf8');
const entry = source.slice(source.indexOf('export async function runAgentLoop('), source.indexOf('function createAgentStream('));
const body = stripTypeScriptTypes(entry + source.slice(source.indexOf('async function runLoop('))).replace(/^export /gm, '');
let input = ''; for await (const chunk of process.stdin) input += chunk;
const results = [];
for (const fixture of JSON.parse(input)) {
  const trace = [], requests = [];
  let providers = 0, executions = 0, validations = 0, steering = 0, follow = 0;
  const custom = content => ({role:'custom',content});
  const names = messages => messages.map(name).map(value => value + '|').join('');
  function name(message) {
    if (message.role === 'system') return 'system';
    if (message.role === 'toolResult') return message.isError ? 'tool:error' : 'tool:ok';
    if (message.role !== 'assistant') return message.content;
    if (['error','aborted'].includes(message.stopReason)) return 'assistant:' + message.stopReason;
    if (message.content[0].type === 'toolCall') return 'assistant:tool';
    return 'assistant:' + message.content[0].text;
  }
  const emit = async event => {
    const key = event.type.startsWith('message_') ? event.type + ':' + name(event.message)
      : event.type.startsWith('tool_execution_') ? event.type + ':' + event.toolCallId : event.type;
    trace.push(key);
    if (key === fixture.failAt) throw new Error('delivery failed');
  };
  const tool = {name:'echo',description:'',parameters:{type:'object',properties:{value:{type:'number'}},required:['value']},
    execute: async (id, args) => {
      executions++;
      assert.equal(id, 'call'); assert.deepEqual(args, {value:42});
      return {content:[],details:'tool',terminate:fixture.terminate};
    }};
  const snapshot = completed => assert.equal(names(completed.context.messages), (fixture.entry === 2 ? 'old|prompt|' : 'old|') + names(completed.newMessages));
  const config = {
    model:{api:'original',provider:'custom-provider'},
    convertToLlm: async messages => {trace.push('convert');return messages.map(m => m.role === 'custom' ? {...m,role:'user'} : m);},
    shouldStopAfterTurn: async completed => {snapshot(completed);trace.push('stop');return fixture.stop;},
    prepareNextTurn: async completed => {snapshot(completed);trace.push('prepare');return {messages:[custom('prepared')],model:{api:'changed',provider:'custom-provider'},thinkingLevel:'off'};},
    getSteeringMessages: async () => {trace.push('steering');return fixture.steering && steering++ === 1 ? [custom('steering')] : [];},
    getFollowUpMessages: async () => {trace.push('follow');return fixture.follow && follow++ === 0 ? [custom('follow')] : [];},
  };
  const stream = async (model, context) => {
    const index = providers++;
    assert.ok(index < 4); assert.equal(model.api, index === 0 ? 'original' : 'changed');
    requests.push(names(context.messages));trace.push('provider');
    const kind = index === 0 ? fixture.kind : 4;
    const content = [kind === 0 || kind === 1 || kind === 3 ? {type:'toolCall',id:'call',name:'echo',arguments:{value:'42'}} : {type:'text',text:kind === 2 ? 'error' : 'done'}];
    const final = {role:'assistant',content,stopReason:['toolUse','length','error','aborted','stop'][kind],api:'custom-api',provider:'custom-provider',model:'model',timestamp:0};
    return {result:async () => final, async *[Symbol.asyncIterator]() {
      yield {type:'start',partial:{...final,content:[{type:'text',text:'partial'}],stopReason:'pending'}};
      yield {type:['error','aborted'].includes(final.stopReason) ? 'error' : 'done',reason:final.stopReason,message:final,error:final};
    }};
  };
  const validate = (tool, call) => {validations++;return validateToolArguments(tool, call);};
  const run = new Function('getCurrentTools','getToolStateChanges','toToolDeclaration','normalizeContext','validateToolArguments',body + ';return {runLoop, runAgentLoop, runAgentLoopContinue};')(getCurrentTools,getToolStateChanges,toToolDeclaration,normalizeContext,validate);
  let history = [custom('prompt')], error = '';
  const messages = fixture.entry === 1 ? [custom('old')] : fixture.entry === 3 ? []
    : fixture.entry === 4 ? [custom('old'),{role:'assistant'}] : [custom('old'),custom('prompt')];
  const context = {messages,tools:[tool]};
  try {
    if (!fixture.entry) await run.runLoop(context,history,config,undefined,emit,stream);
    else if (fixture.entry === 1) history = await run.runAgentLoop([custom('prompt')],context,config,emit,undefined,stream);
    else history = await run.runAgentLoopContinue(context,config,emit,undefined,stream);
  }
  catch (cause) {if (!['delivery failed','Cannot continue: no messages in context','Cannot continue from message role: assistant'].includes(cause.message)) throw cause; error = cause.message;}
  results.push({history:error ? '' : names(history),error,trace:trace.join('|'),requests:requests.join(';'),providers,executions,validations});
}
process.stdout.write(JSON.stringify(results));
