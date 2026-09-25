// Actual pinned Agent methods and full loop helpers; only the provider is a fixture.
import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {stripTypeScriptTypes} from 'node:module';
const { createInitialSystemMessage, getCurrentSystemMessage, getCurrentSystemPrompt, getCurrentTools, getToolStateChanges, toToolDeclaration, normalizeContext } = await import(UPSTREAM + '/packages/ai/src/utils/transcript.ts');
const { getDefaultStreamFn } = await import(UPSTREAM + '/packages/agent/src/stream-fn.ts');
import {Compile} from '../build/schema-reference/node_modules/typebox/build/compile/index.mjs';
import {Value} from '../build/schema-reference/node_modules/typebox/build/value/index.mjs';
const validationSource=fs.readFileSync(UPSTREAM + '/packages/ai/src/utils/validation.ts','utf8');
const validationBody=stripTypeScriptTypes(validationSource.slice(validationSource.indexOf('const validatorCache ='))).replace(/^export /gm,'');
const validateToolArguments=new Function('Compile','Value',validationBody+';return validateToolArguments;')(Compile,Value);
const loopSource=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent-loop.ts','utf8');
const entries=loopSource.slice(loopSource.indexOf('export async function runAgentLoop('),loopSource.indexOf('function createAgentStream('));
const loopBody=stripTypeScriptTypes(entries+loopSource.slice(loopSource.indexOf('async function runLoop('))).replace(/^export /gm,'');
const {runAgentLoop,runAgentLoopContinue}=new Function('getCurrentTools','getToolStateChanges','toToolDeclaration','normalizeContext','validateToolArguments','getDefaultStreamFn',loopBody+';return {runAgentLoop,runAgentLoopContinue};')(getCurrentTools,getToolStateChanges,toToolDeclaration,normalizeContext,validateToolArguments,getDefaultStreamFn);
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent.ts','utf8');
const body=stripTypeScriptTypes(source.slice(source.indexOf('function defaultConvertToLlm('))).replace(/^export /gm,'');
const {Agent}=new Function('createInitialSystemMessage','getCurrentSystemMessage','getCurrentSystemPrompt','toToolDeclaration','getDefaultStreamFn','runAgentLoop','runAgentLoopContinue',body+';return {Agent};')(createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration,getDefaultStreamFn,runAgentLoop,runAgentLoopContinue);

const trace=[];
let agent,calls=0;
const hookPair=name=>({
 beforeToolCall:async(context,signal)=>{assert.ok(signal);assert.equal(signal.aborted,false);assert.equal(context.toolCall.id,'call');assert.equal(context.toolCall.name,'echo');assert.deepEqual(context.args,{});trace.push('b'+name);if(name==='a')Object.assign(agent,second);},
 afterToolCall:async(context,signal)=>{assert.ok(signal);assert.equal(signal.aborted,false);assert.equal(context.toolCall.id,'call');assert.equal(context.toolCall.name,'echo');assert.deepEqual(context.args,{});assert.equal(context.isError,false);assert.deepEqual(context.result.content,[{type:'text',text:'executed'}]);trace.push('a'+name);return {content:[{type:'text',text:'patched-'+name}]};}
});
const first=hookPair('a'),second=hookPair('b');
const assistant=()=>({role:'assistant',content:[{type:'text',text:'answer'}],api:'unknown',provider:'unknown',model:'unknown',stopReason:'stop',timestamp:0});
const streamFn=async()=>{
 trace.push('p');
 const tool=calls++%2===0;
 const message=tool?{...assistant(),content:[{type:'toolCall',id:'call',name:'echo',arguments:{}}],stopReason:'toolUse'}:assistant();
 return {result:async()=>message,async *[Symbol.asyncIterator](){yield {type:'done',reason:message.stopReason,message};}};
};
agent=new Agent({streamFn,initialState:{tools:[{name:'echo',label:'Echo',description:'Echo',parameters:{type:'object'},execute:async()=>{trace.push('x');return {content:[{type:'text',text:'executed'}],details:null};}}]}});
assert.equal(agent.beforeToolCall,undefined);assert.equal(agent.afterToolCall,undefined);
Object.assign(agent,first);
assert.equal(agent.beforeToolCall,first.beforeToolCall);assert.equal(agent.afterToolCall,first.afterToolCall);
await agent.prompt('first');
assert.equal(agent.beforeToolCall,second.beforeToolCall);assert.equal(agent.afterToolCall,second.afterToolCall);
await agent.prompt('next');
Object.assign(agent,{beforeToolCall:undefined,afterToolCall:undefined});
await agent.prompt('cleared');
assert.equal(trace.join(';')+';','p;ba;x;aa;p;p;bb;x;ab;p;p;x;p;');
assert.deepEqual(agent.state.messages.filter(m=>m.role==='toolResult').map(m=>m.content[0].text),['patched-a','patched-b','executed']);
console.log('PASS upstream Agent before/after tool hook replacement, capture and transcript updates');
