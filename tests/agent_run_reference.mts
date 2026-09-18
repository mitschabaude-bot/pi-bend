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
const role=m=>({system:'s',user:'u',assistant:'a'}[m.role]??'?');
const roles=messages=>messages.map(role).join('');
const key=agent=>roles(agent.state.messages)+':'+(agent.state.isStreaming?'1':'0')+':'+(agent.state.streamingMessage?role(agent.state.streamingMessage):'-')+':'+(agent.state.errorMessage??'none');
const user=text=>({role:'user',content:text,timestamp:0});
const assistant=()=>({role:'assistant',content:[{type:'text',text:'answer'}],api:'unknown',provider:'unknown',model:'unknown',stopReason:'stop',timestamp:0});
const eventName=e=>e.type==='message_start'?'start:'+role(e.message):e.type==='message_update'?'update:'+role(e.message):e.type==='message_end'?'end:'+role(e.message):e.type;
const results=[];
for(let mode=0;mode<10;mode++){
 let trace='',requests='',agent,calls=0;
 const provider=async(model,context,options)=>{
  assert.ok(options.signal);assert.equal(options.signal.aborted,false);
  requests+=roles(context.messages)+';';
  if(mode===3)agent.abort();
  assert.equal(options.signal.aborted,mode===3);
  if([1,3,8].includes(mode))throw Error('provider failed');
  const tool=mode===9&&calls++===0;
  const final=tool?{...assistant(),content:[{type:'toolCall',id:'call',name:'echo',arguments:{}}],stopReason:'toolUse'}:assistant();
  return {result:async()=>final,async *[Symbol.asyncIterator](){yield {type:'start',partial:final};yield {type:'done',reason:final.stopReason,message:final};}};
 };
 agent=new Agent({streamFn:provider,initialState:{systemPrompt:'base',...(mode===9?{tools:[{name:'echo',label:'Echo',description:'Echo',parameters:{type:'object'},execute:async(id,args,signal)=>{assert.equal(id,'call');assert.equal(signal.aborted,false);return {content:[],details:null};}}]}:{}),...(mode===6?{messages:[user('old')]}:mode===7?{messages:[assistant()]}:{})}});
 agent.subscribe(async event=>{
  agent.state.thinkingLevel='off';
  assert.equal(agent.state.isStreaming,true);
  if(event.type==='tool_execution_start')assert.ok(agent.state.pendingToolCalls.has(event.toolCallId));
  if(event.type==='tool_execution_end')assert.equal(agent.state.pendingToolCalls.has(event.toolCallId),false);
  if(event.type==='agent_start'){
   await assert.rejects(agent.prompt('busy'),{message:'Agent is already processing a prompt. Use steer() or followUp() to queue messages, or wait for completion.'});
   await assert.rejects(agent.continue(),{message:'Agent is already processing. Wait for completion before continuing.'});
   assert.throws(()=>agent.reset(),{message:'Agent is already processing. Wait for completion before resetting.'});
   assert.ok(agent.signal);
  }
  trace+=eventName(event)+'@'+key(agent)+';';
  if(mode===2&&event.type==='agent_start'||mode===8&&event.type==='message_start'&&event.message.role==='assistant')throw Error('listener failed');
 });
 if(mode===4)agent.steer(user('steer'));
 if(mode===5)agent.followUp(user('follow'));
 if(mode===7){agent.steer(user('first'));agent.steer(user('second'));}
 let outcome='ok';
 try {if(mode===6||mode===7)await agent.continue();else await agent.prompt(user('prompt'));}catch(e){outcome=e.message;}
 await agent.waitForIdle();
 results.push(trace+'#'+outcome+'#'+key(agent)+'#'+requests);
}
process.stdout.write(JSON.stringify(results));
