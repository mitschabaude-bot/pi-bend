// Execute the pinned internal loop and all its helpers, including streaming,
// declarations, tool dispatch and completion. Only the provider is a fixture.
import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import assert from 'node:assert/strict';
const { setDefaultStreamFn, getDefaultStreamFn } = await import(UPSTREAM + '/packages/agent/src/stream-fn.ts');
import {stripTypeScriptTypes} from 'node:module';
const { getCurrentTools, getToolStateChanges, toToolDeclaration, normalizeContext } = await import(UPSTREAM + '/packages/ai/src/utils/transcript.ts');
import {Compile} from '../build/schema-reference/node_modules/typebox/build/compile/index.mjs';
import {Value} from '../build/schema-reference/node_modules/typebox/build/value/index.mjs';
const validationSource = fs.readFileSync(UPSTREAM + '/packages/ai/src/utils/validation.ts', 'utf8');
const validationBody = stripTypeScriptTypes(validationSource.slice(validationSource.indexOf('const validatorCache ='))).replace(/^export /gm, '');
const validateToolArguments = new Function('Compile', 'Value', validationBody + ';return validateToolArguments;')(Compile, Value);
const source = fs.readFileSync(UPSTREAM + '/packages/agent/src/agent-loop.ts', 'utf8');
const entry = source.slice(source.indexOf('export async function runAgentLoop('), source.indexOf('function createAgentStream('));
const body = stripTypeScriptTypes(entry + source.slice(source.indexOf('async function runLoop('))).replace(/^export /gm, '');
let input = ''; for await (const chunk of process.stdin) input += chunk;
const results = [];
for (const fixture of JSON.parse(input)) {
  const trace = [], requests = [];
  const policy = fixture.selection ?? 0;
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
  const updateDefault = name => {
    if (policy === 3 && name === 'agent_start') setDefaultStreamFn(stream);
    if (policy === 4 && name === 'turn_start') setDefaultStreamFn(undefined);
    if (policy === 5 && name === 'steering' || policy === 6 && name === 'turn_start') setDefaultStreamFn(replacement);
  };
  const emit = async event => {
    const key = event.type.startsWith('message_') ? event.type + ':' + name(event.message)
      : event.type.startsWith('tool_execution_') ? event.type + ':' + event.toolCallId : event.type;
    trace.push(key);updateDefault(key);
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
    convertToLlm: async messages => {trace.push('convert');if (fixture.kind === 5) throw new Error('conversion failed');return messages.map(m => m.role === 'custom' ? {...m,role:'user'} : m);},
    finishTurn: async completed => {snapshot(completed);trace.push('finish');if (fixture.kind === 6) throw new Error('finish failed');return fixture.stop ? {action:'end'} : undefined;},
    prepareNextTurn: async completed => {snapshot(completed);trace.push('prepare');return {messages:[custom('prepared')],model:{api:'changed',provider:'custom-provider'},thinkingLevel:'off'};},
    getSteeringMessages: async () => {trace.push('steering');updateDefault('steering');return fixture.steering && steering++ === 1 ? [custom('steering')] : [];},
    getFollowUpMessages: async () => {trace.push('follow');return fixture.follow && follow++ === 0 ? [custom('follow')] : [];},
  };
  const provider = async (label, model, context) => {
    const index = providers++;
    assert.ok(index < 4); assert.equal(model.api, index === 0 ? 'original' : 'changed');
    requests.push(names(context.messages));trace.push(label);
    if (fixture.kind === 8) throw new Error('provider open failed');
    const kind = index === 0 ? Math.min(fixture.kind, 4) : 4;
    const content = [kind === 0 || kind === 1 || kind === 3 ? {type:'toolCall',id:'call',name:'echo',arguments:{value:'42'}} : {type:'text',text:kind === 2 ? 'error' : 'done'}];
    const final = {role:'assistant',content,stopReason:['toolUse','length','error','aborted','stop'][kind],api:'custom-api',provider:'custom-provider',model:'model',timestamp:0};
    return {result:async () => final, async *[Symbol.asyncIterator]() {
      yield {type:'start',partial:{...final,content:[{type:'text',text:'partial'}],stopReason:'pending'}};
      yield {type:['error','aborted'].includes(final.stopReason) ? 'error' : 'done',reason:final.stopReason,message:final,error:final};
    }};
  };
  const stream = (model, context) => provider('provider', model, context);
  const replacement = (model, context) => provider('provider:replacement', model, context);
  setDefaultStreamFn([1,4,5,6].includes(policy) ? stream : policy === 7 ? replacement : undefined);
  const selected = policy === 0 || policy === 7 ? stream : undefined;
  const validate = (tool, call) => {validations++;return validateToolArguments(tool, call);};
  const run = new Function('getCurrentTools','getToolStateChanges','toToolDeclaration','normalizeContext','validateToolArguments','getDefaultStreamFn',body + ';return {runLoop, runAgentLoop, runAgentLoopContinue};')(getCurrentTools,getToolStateChanges,toToolDeclaration,normalizeContext,validate,getDefaultStreamFn);
  let history = [custom('prompt')], error = '';
  const messages = fixture.entry === 1 ? [custom('old')] : fixture.entry === 3 ? []
    : fixture.entry === 4 ? [custom('old'),{role:'assistant'}] : [custom('old'),custom('prompt')];
  const context = {messages,tools:[tool]};
  try {
    if (!fixture.entry) await run.runLoop(context,history,config,undefined,emit,stream);
    else if (fixture.entry === 1) history = await run.runAgentLoop([custom('prompt')],context,config,emit,undefined,selected);
    else history = await run.runAgentLoopContinue(context,config,emit,undefined,selected);
  }
  catch (cause) {if (!['provider open failed','conversion failed','finish failed','delivery failed','Cannot continue: no messages in context','Cannot continue from message role: assistant','No default stream function configured. Pass streamFn explicitly or call setDefaultStreamFn().'].includes(cause.message)) throw cause; error = cause.message;}
  results.push({history:error ? '' : names(history),error,trace:trace.join('|'),requests:requests.join(';'),providers,executions,validations});
}
process.stdout.write(JSON.stringify(results));
