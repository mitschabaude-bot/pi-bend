// Actual pinned Agent methods and full loop helpers; only the provider is a fixture.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {stripTypeScriptTypes} from 'node:module';
import {createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,getCurrentTools,getToolStateChanges,toToolDeclaration,normalizeContext} from '../../pi-mono/packages/ai/src/utils/transcript.ts';
import {getDefaultStreamFn} from '../../pi-mono/packages/agent/src/stream-fn.ts';
import {Compile} from '../build/schema-reference/node_modules/typebox/build/compile/index.mjs';
import {Value} from '../build/schema-reference/node_modules/typebox/build/value/index.mjs';
const validationSource=fs.readFileSync('../pi-mono/packages/ai/src/utils/validation.ts','utf8');
const validationBody=stripTypeScriptTypes(validationSource.slice(validationSource.indexOf('const validatorCache ='))).replace(/^export /gm,'');
const validateToolArguments=new Function('Compile','Value',validationBody+';return validateToolArguments;')(Compile,Value);
const loopSource=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const entries=loopSource.slice(loopSource.indexOf('export async function runAgentLoop('),loopSource.indexOf('function createAgentStream('));
const loopBody=stripTypeScriptTypes(entries+loopSource.slice(loopSource.indexOf('async function runLoop('))).replace(/^export /gm,'');
const {runAgentLoop,runAgentLoopContinue}=new Function('getCurrentTools','getToolStateChanges','toToolDeclaration','normalizeContext','validateToolArguments','getDefaultStreamFn',loopBody+';return {runAgentLoop,runAgentLoopContinue};')(getCurrentTools,getToolStateChanges,toToolDeclaration,normalizeContext,validateToolArguments,getDefaultStreamFn);
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent.ts','utf8');
const body=stripTypeScriptTypes(source.slice(source.indexOf('function defaultConvertToLlm('))).replace(/^export /gm,'');
const {Agent}=new Function('createInitialSystemMessage','getCurrentSystemMessage','getCurrentSystemPrompt','toToolDeclaration','getDefaultStreamFn','runAgentLoop','runAgentLoopContinue',body+';return {Agent};')(createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration,getDefaultStreamFn,runAgentLoop,runAgentLoopContinue);

const traces=[];
for(const mode of [0,1,2]){
 const trace=[];let agent,calls=0;
 const live=signal=>{assert.ok(signal);assert.equal(signal.aborted,false);};
 const handlers=name=>({
  shouldStopAfterTurn:async(context,signal)=>{live(signal);trace.push('s'+name);return name==='b';},
  prepareNextTurn:async signal=>{live(signal);trace.push('l'+name);},
  prepareNextTurnWithContext:async(context,signal)=>{live(signal);assert.equal(context.toolResults.length,1);assert.equal(context.context.messages.at(-1).role,'toolResult');trace.push('c'+name);agent.prepareNextTurnWithContext=undefined;}
 });
 const first=handlers('a'),second=handlers('b');
 const assistant=()=>({role:'assistant',content:[{type:'text',text:'answer'}],api:'unknown',provider:'unknown',model:'unknown',stopReason:'stop',timestamp:0});
 const streamFn=async()=>{
  const index=calls++;trace.push('p');
  if(index===0){
   if(mode===0)Object.assign(agent,second);
   if(mode===1)agent.prepareNextTurn=second.prepareNextTurn;
   if(mode===2)Object.assign(agent,{shouldStopAfterTurn:undefined,prepareNextTurn:undefined,prepareNextTurnWithContext:undefined});
  }
  const tool=[0,1,3,4].includes(index);
  const message=tool?{...assistant(),content:[{type:'toolCall',id:'call',name:'echo',arguments:{}}],stopReason:'toolUse'}:assistant();
  return {result:async()=>message,async *[Symbol.asyncIterator](){yield {type:'done',reason:message.stopReason,message};}};
 };
 agent=new Agent({streamFn,initialState:{tools:[{name:'echo',label:'Echo',description:'Echo',parameters:{type:'object'},execute:async()=>({content:[],details:null})}]}});
 assert.equal(agent.shouldStopAfterTurn,undefined);assert.equal(agent.prepareNextTurn,undefined);assert.equal(agent.prepareNextTurnWithContext,undefined);
 if(mode!==1)Object.assign(agent,{shouldStopAfterTurn:first.shouldStopAfterTurn,prepareNextTurn:first.prepareNextTurn});
 await agent.prompt('first');
 assert.equal(agent.prepareNextTurnWithContext,undefined);
 assert.equal(agent.shouldStopAfterTurn,mode===0?second.shouldStopAfterTurn:undefined);
 assert.equal(agent.prepareNextTurn,mode===2?undefined:second.prepareNextTurn);
 await agent.prompt('next');
 assert.equal(calls,mode===0?4:6);
 traces.push(trace.join(';')+';');
}
assert.deepEqual(traces,['p;sa;cb;p;sa;lb;p;sa;p;sb;','p;p;p;p;lb;p;lb;p;','p;sa;p;sa;p;sa;p;p;p;']);
console.log('PASS upstream Agent turn-hook live selection, capture and late enablement');
