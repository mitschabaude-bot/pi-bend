// Test-only oracle: actual pinned Agent construction, processEvents and finishRun,
// plus the unmodified begin-run block. Provider/executor/listener paths are not invoked.
import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const { createInitialSystemMessage, getCurrentSystemMessage, getCurrentSystemPrompt, getCurrentTools, toToolDeclaration } = await import(UPSTREAM + '/packages/ai/src/utils/transcript.ts');
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent.ts','utf8');
const body=stripTypeScriptTypes(source.slice(source.indexOf('function defaultConvertToLlm('))).replace(/^export /gm,'');
const {Agent,defaultConvertToLlm}=new Function('createInitialSystemMessage','getCurrentSystemMessage','getCurrentSystemPrompt','toToolDeclaration','getDefaultStreamFn',body+';return {Agent,defaultConvertToLlm};')(createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration,()=>{throw Error('unexpected fallback')});
const beginStart=source.indexOf('const abortController =',source.indexOf('private async runWithLifecycle'));
const begin=new Function(stripTypeScriptTypes(source.slice(beginStart,source.indexOf('\n\t\ttry {',beginStart))));
const user={role:'user',content:'user',timestamp:0};
const custom={role:'custom',content:'custom'};
const assistant=error=>({role:'assistant',content:[{type:'text',text:'reply'}],errorMessage:error,stopReason:'stop'});
const name=m=>m.role==='system'?'system':m.role==='assistant'?'assistant:reply':m.role==='toolResult'?'tool:ok':m.content;
const events=[
 {type:'agent_start'},{type:'turn_start'},{type:'message_start',message:user},
 {type:'message_update',message:assistant(undefined)},{type:'message_end',message:user},
 {type:'tool_execution_start',toolCallId:'a'},{type:'tool_execution_start',toolCallId:'a'},
 {type:'tool_execution_start',toolCallId:'b'},{type:'tool_execution_end',toolCallId:'missing'},
 {type:'tool_execution_end',toolCallId:'a'},{type:'turn_end',message:assistant('failure')},
 {type:'turn_end',message:assistant('')},{type:'turn_end',message:user},
 {type:'message_start',message:custom},{type:'agent_end',messages:[user]},
 {type:'tool_execution_update',toolCallId:'b'},{type:'message_end',message:custom}
];
const key=s=>[s.model.id,s.thinkingLevel,s.tools.map(t=>t.name).join(','),s.systemPrompt,s.messages.map(name).map(v=>v+'|').join(''),s.isStreaming?'1':'0',s.streamingMessage?name(s.streamingMessage)+'|':'none',[...s.pendingToolCalls].join(','),s.errorMessage??'none',getCurrentTools(s.messages).map(t=>t.name).join(','),defaultConvertToLlm(s.messages).map(name).map(v=>v+'|').join('')].join(';');
let input='';for await(const part of process.stdin)input+=part;
const results=[];
for(const mode of JSON.parse(input)){
 const initialState={};
 if([1,3,4,6].includes(mode))initialState.systemPrompt='seed';
 if(mode===2)initialState.systemPrompt='';
 if(mode===3)initialState.messages=[{role:'system',content:'existing',timestamp:1}];
 if(mode===4)initialState.messages=[user];
 if(mode===5){initialState.messages=[custom];initialState.model={id:'test'};initialState.thinkingLevel='low';}
 if(mode===6)initialState.tools=[{name:'echo',description:'Echo',parameters:{type:'object'},execute:()=>{throw Error('must not execute')}}];
 const agent=new Agent({streamFn:()=>{throw Error('must not stream')},initialState});
 const states=[key(agent.state)];
 begin.call(agent);states.push(key(agent.state));
 for(const event of events){await agent.processEvents(event);states.push(key(agent.state));}
 agent.finishRun();states.push(key(agent.state));
 begin.call(agent);states.push(key(agent.state));agent.finishRun();states.push(key(agent.state));
 agent.reset();states.push(key(agent.state));
 results.push(states);
}
process.stdout.write(JSON.stringify(results));
