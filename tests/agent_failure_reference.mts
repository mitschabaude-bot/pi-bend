// Actual pinned runWithLifecycle/handleRunFailure/processEvents; injected executor failure.
import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const { createInitialSystemMessage, getCurrentSystemMessage, getCurrentSystemPrompt, toToolDeclaration } = await import(UPSTREAM + '/packages/ai/src/utils/transcript.ts');
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent.ts','utf8');
const body=stripTypeScriptTypes(source.slice(source.indexOf('function defaultConvertToLlm('))).replace(/^export /gm,'');
const {Agent}=new Function('createInitialSystemMessage','getCurrentSystemMessage','getCurrentSystemPrompt','toToolDeclaration','getDefaultStreamFn',body+';return {Agent};')(createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration,()=>{throw Error('unexpected fallback')});
const roles=messages=>messages.map(m=>({system:'s',user:'u',assistant:'a'}[m.role]??'?')).join('');
const key=agent=>[agent.state.systemPrompt,roles(agent.state.messages),agent.state.isStreaming?'1':'0',agent.state.streamingMessage?roles([agent.state.streamingMessage]):'-',[...agent.state.pendingToolCalls].join(','),'one:','one:'].join('|')+'~'+(agent.state.errorMessage??'none');
let input='';for await(const part of process.stdin)input+=part;
const results=[];
for(const f of JSON.parse(input)){
 const agent=new Agent({streamFn:()=>{throw Error('unexpected provider')},initialState:{systemPrompt:'base',model:{id:'failure-model',api:'failure-api',provider:'failure-provider'}}});
 let trace='',stamp;
 for(let listener=0;listener<2;listener++)agent.subscribe((event,signal)=>{
  const stage=['message_start','message_end','turn_end','agent_end'].indexOf(event.type);if(stage<0)return;
  const message=event.type==='agent_end'?event.messages[0]:event.message;
  if(stamp!==undefined&&stamp!==message.timestamp)throw Error('timestamp changed');stamp=message.timestamp;
  if(signal.aborted!==f.aborted||message.stopReason!==(f.aborted?'aborted':'error')||message.errorMessage!==f.error)throw Error('invalid failure message');
  trace+=['start','end','turn','agent'][stage]+'.'+listener+'@'+key(agent)+';';
  if(stage===f.stage&&listener===f.listener)throw Error('listener failed');
 });
 let result='ok';
 try{await agent.runWithLifecycle(async()=>{agent.state.pendingToolCalls=new Set(['pending']);if(f.aborted)agent.abort();throw Error(f.error);});}catch(e){result=e.message;}
 await agent.waitForIdle();results.push(trace+'#'+result+'#'+key(agent));
}
process.stdout.write(JSON.stringify(results));
