// Test-only oracle: actual pinned queue methods and Agent.continue, with only
// the selected run entry points intercepted to observe the planning decision.
import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const { createInitialSystemMessage, getCurrentSystemMessage, getCurrentSystemPrompt, toToolDeclaration } = await import(UPSTREAM + '/packages/ai/src/utils/transcript.ts');
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent.ts','utf8');
const body=stripTypeScriptTypes(source.slice(source.indexOf('function defaultConvertToLlm('))).replace(/^export /gm,'');
const {Agent,PendingMessageQueue}=new Function('createInitialSystemMessage','getCurrentSystemMessage','getCurrentSystemPrompt','toToolDeclaration','getDefaultStreamFn',body+';return {Agent,PendingMessageQueue};')(createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration,()=>{throw Error('unexpected fallback')});
let input='';for await(const part of process.stdin)input+=part;
const fixtures=JSON.parse(input);
const mode=n=>n?'all':'one-at-a-time';
const queueKey=(q,drained)=>[q.mode==='all'?'all':'one',q.hasItems()?'1':'0',q.messages.join(','),drained.join(',')].join(';');
const queues=fixtures.queues.map(f=>{
 const q=new PendingMessageQueue(mode(f.mode));const trace=[queueKey(q,[])];
 for(const op of f.ops){let drained=[];if(op===0)q.enqueue('a');if(op===1)q.enqueue('b');if(op===2)drained=q.drain();if(op===3)q.clear();if(op===4)q.mode='all';if(op===5)q.mode='one-at-a-time';trace.push(queueKey(q,drained));}
 return trace;
});
const user=content=>({role:'user',content,timestamp:0});
const system={role:'system',content:'system',timestamp:0};
const assistant={role:'assistant',content:[],timestamp:0};
const histories=[[],[system],[user('user')],[assistant],[{role:'custom',content:'custom'}],[{role:'toolResult',content:[]}],[user('user'),system],[system,assistant]];
const continuations=[];
for(const f of fixtures.continuations){
 const agent=new Agent({streamFn:()=>{throw Error('unexpected provider')},initialState:{messages:histories[f.history]},steeringMode:mode(f.steeringMode),followUpMode:mode(f.followMode)});
 for(let i=0;i<f.steering;i++)agent.steer(user('s'+i));for(let i=0;i<f.follow;i++)agent.followUp(user('f'+i));
 if(f.active)agent.activeRun={};
 let decision='';agent.runPromptMessages=async(messages,options)=>{decision='prompt:'+messages.map(m=>m.content).join(',')+':'+(options?.skipInitialSteeringPoll?'1':'0');};agent.runContinuation=async()=>{decision='continue';};
 try{await agent.continue();}catch(e){decision='error:'+e.message;}
 continuations.push([decision,agent.steeringQueue.messages.map(m=>m.content).join(','),agent.followUpQueue.messages.map(m=>m.content).join(','),agent.hasQueuedMessages()?'1':'0'].join(';'));
}
process.stdout.write(JSON.stringify({queues,continuations}));
