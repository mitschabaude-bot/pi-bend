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
const parameters={type:'object',properties:{value:{type:'number'},note:{type:'string'}},required:['value'],additionalProperties:false};
for(const valid of [true,false]){
 // The shared subset supplies an actual number; coercible strings are rejected
 // by Bend's deliberately strict default agent validator in separate cases.
 const raw={value:valid?42:'bad',note:null};
 const expected=valid?'accepted':'Validation failed for tool "echo":\n  - value: must be number\n\nReceived arguments:\n'+JSON.stringify(raw,null,2);
 let requests=0,executions=0;
 const provider=async(model,context,options)=>{
  const index=requests++;
  assert.ok(index<2);
  if(index===1){
   const result=context.messages.find(m=>m.role==='toolResult');
   assert.equal(result.isError,!valid);
   assert.deepEqual(result.content,[{type:'text',text:expected}]);
  }
  const final={role:'assistant',content:index===0?[{type:'toolCall',id:'call',name:'echo',arguments:structuredClone(raw)}]:[{type:'text',text:'done'}],api:'unknown',provider:'unknown',model:'unknown',stopReason:index===0?'toolUse':'stop',timestamp:0};
  return {result:async()=>final,async *[Symbol.asyncIterator](){yield {type:'done',reason:final.stopReason,message:final};}};
 };
 const agent=new Agent({streamFn:provider,initialState:{tools:[{name:'echo',label:'Echo',description:'Echo',parameters,execute:async(id,args,signal,update)=>{
  executions++;assert.equal(id,'call');assert.ok(signal);assert.ok(update);assert.deepEqual(args,{value:42});
  return {content:[{type:'text',text:'accepted'}],details:'done'};
 }}]}});
 await agent.prompt('run tool');
 assert.equal(requests,2);assert.equal(executions,valid?1:0);
 assert.deepEqual(agent.state.messages.find(m=>m.role==='assistant').content[0].arguments,raw);
 console.log('PASS upstream Agent native plain-schema validation integration');
}
