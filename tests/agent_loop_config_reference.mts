// Actual pinned Agent configuration/context snapshots and queue readers.
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration} from '../../pi-mono/packages/ai/src/utils/transcript.ts';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent.ts','utf8');
const body=stripTypeScriptTypes(source.slice(source.indexOf('function defaultConvertToLlm('))).replace(/^export /gm,'');
const {Agent}=new Function('createInitialSystemMessage','getCurrentSystemMessage','getCurrentSystemPrompt','toToolDeclaration','getDefaultStreamFn',body+';return {Agent};')(createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration,()=>{throw Error('unexpected fallback')});
let input='';for await(const part of process.stdin)input+=part;
const user=content=>({role:'user',content,timestamp:0});
const roles=messages=>messages.map(m=>m.role==='system'?'s':'u').join('');
const batch=messages=>messages.map(m=>m.content).join(',');
const results=[];
for(const f of JSON.parse(input)){
 const agent=new Agent({streamFn:()=>{throw Error('unexpected provider')},initialState:{systemPrompt:'base',messages:[user('initial')],model:{id:'current'},thinkingLevel:['off','low','high'][f.thinking]},steeringMode:f.steering?'all':'one-at-a-time',followUpMode:f.follow?'all':'one-at-a-time',sessionId:'session',transport:'sse',maxRetryDelayMs:123,toolExecution:'sequential'});
 for(const name of ['s0','s1'])agent.steer(user(name));for(const name of ['f0','f1'])agent.followUp(user(name));
 const config=agent.createLoopConfig({skipInitialSteeringPoll:f.skip}),context=agent.createContextSnapshot();
 const header=[config.model.id,config.reasoning??'off',config.sessionId,config.transport,config.maxRetryDelayMs,config.toolExecution,roles(context.messages),context.tools.length].join(';');
 const trace=[header,batch(await config.getSteeringMessages()),batch(await config.getFollowUpMessages())];
 agent.steer(user('s2'));agent.followUp(user('f2'));agent.steeringMode='all';agent.followUpMode='all';
 trace.push(batch(await config.getSteeringMessages()),batch(await config.getFollowUpMessages()),batch(await config.getSteeringMessages()));
 try{await agent.processEvents({type:'message_end',message:user('later')});}catch{}
 trace.push(roles(context.messages),roles(agent.createContextSnapshot().messages));
 agent.steer(user('s3'));
 const fresh=agent.createLoopConfig({skipInitialSteeringPoll:true});
 trace.push(batch(await fresh.getSteeringMessages()),batch(await config.getSteeringMessages()),batch(await fresh.getSteeringMessages()));
 results.push(trace.join('|'));
}
process.stdout.write(JSON.stringify(results));
