// Test-only source oracle. Actual Agent methods run; only loop execution is gated.
import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const { createInitialSystemMessage, getCurrentSystemMessage, getCurrentSystemPrompt, toToolDeclaration } = await import(UPSTREAM + '/packages/ai/src/utils/transcript.ts');
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent.ts','utf8');
const body=stripTypeScriptTypes(source.slice(source.indexOf('function defaultConvertToLlm('))).replace(/^export /gm,'');
const {Agent}=new Function('createInitialSystemMessage','getCurrentSystemMessage','getCurrentSystemPrompt','toToolDeclaration','getDefaultStreamFn',body+';return {Agent};')(createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration,()=>{throw Error('unexpected fallback')});
let input='';for await(const part of process.stdin)input+=part;
const user=content=>({role:'user',content,timestamp:0});
const assistant={role:'assistant',content:[],timestamp:0};
const roles=messages=>messages.map(m=>({system:'s',user:'u',assistant:'a',toolResult:'t'}[m.role]??'c')).join('');
const queue=q=>(q.mode==='all'?'all':'one')+':'+q.messages.map(m=>m.content).join(',');
const snapshot=agent=>[agent.state.systemPrompt,roles(agent.state.messages),agent.state.isStreaming?'1':'0',agent.state.streamingMessage?roles([agent.state.streamingMessage]):'-',[...agent.state.pendingToolCalls].sort().join(','),queue(agent.steeringQueue),queue(agent.followUpQueue)].join('|');
const all=[];
for(const f of JSON.parse(input)){
 const agent=new Agent({streamFn:()=>{throw Error('unexpected provider')},initialState:{systemPrompt:'base',messages:f.history===0?[]:f.history===1?[user('user')]:[assistant]},steeringMode:f.steering?'all':'one-at-a-time',followUpMode:f.follow?'all':'one-at-a-time'});
 let release,run,decision='';
 agent.runPromptMessages=async(messages,options)=>{decision='prompt:'+messages.map(m=>m.content).join(',')+':'+(options?.skipInitialSteeringPoll?'1':'0');await agent.runWithLifecycle(async()=>await new Promise(resolve=>{release=resolve}));};
 agent.runContinuation=async()=>{decision='continue';await agent.runWithLifecycle(async()=>await new Promise(resolve=>{release=resolve}));};
 const trace=[];
 for(const op of f.ops){decision='ok';try{
  if(op===0)agent.reset();
  if(op===1)agent.steer(user('s'));
  if(op===2)agent.followUp(user('f'));
  if(op===3||op===4){const busy=!!agent.activeRun;const candidate=op===3?agent.prompt([user('prompt')]):agent.continue();if(busy||!agent.activeRun)await candidate;else run=candidate;}
  if(op===5){if(run){release();await run;run=undefined;decision='finished';}else decision='idle';}
  if(op===6)await agent.processEvents({type:'message_end',message:user('user')});
  if(op===7)await agent.processEvents({type:'message_end',message:assistant});
  if(op===8)await agent.processEvents({type:'message_start',message:assistant});
  if(op===9)await agent.processEvents({type:'tool_execution_start',toolCallId:'call',toolName:'tool',args:{}});
  if(op===10)await agent.processEvents({type:'agent_end',messages:[]});
  if(op===12)agent.steeringMode='all';
  if(op===13)agent.followUpMode='all';
  if(op===14)agent.clearSteeringQueue();
  if(op===15)agent.clearFollowUpQueue();
  if(op===16)agent.clearAllQueues();
  if(op===17)decision='drained:'+agent.steeringQueue.drain().map(m=>m.content).join(',');
  if(op===18)decision='drained:'+agent.followUpQueue.drain().map(m=>m.content).join(',');
  if(op===11)await agent.processEvents({type:'message_end',message:{role:'system',content:'updated',timestamp:0}});
 }catch(e){decision='error:'+e.message;}
 trace.push(decision+'#'+snapshot(agent));
 }
 if(run){release();await run;}
 all.push(trace);
}
process.stdout.write(JSON.stringify(all));
