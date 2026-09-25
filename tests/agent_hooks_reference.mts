// Actual pinned createLoopConfig wrappers; hooks and run lifetime are controlled fixtures.
import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const { createInitialSystemMessage, getCurrentSystemMessage, getCurrentSystemPrompt, toToolDeclaration } = await import(UPSTREAM + '/packages/ai/src/utils/transcript.ts');
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent.ts','utf8');
const body=stripTypeScriptTypes(source.slice(source.indexOf('function defaultConvertToLlm('))).replace(/^export /gm,'');
const {Agent}=new Function('createInitialSystemMessage','getCurrentSystemMessage','getCurrentSystemPrompt','toToolDeclaration','getDefaultStreamFn',body+';return {Agent};')(createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration,()=>{throw Error('unexpected fallback')});
let input='';for await(const part of process.stdin)input+=part;
const results=[];
for(const f of JSON.parse(input)){
 let log='';const hooks={};
 for(const version of ['A','B']){
  const invoke=(kind,context,signal)=>{
   const label=kind+version;const marker=kind==='legacy'?'-':context.context.messages[0].content;
   if(kind!=='legacy'&&context.newMessages[0].content!==marker)throw Error('wrong context');
   log+=label+'@'+marker+'@'+(!signal?'none':signal.aborted?'aborted':'live')+';';
   if(f.fail)throw Error(label);
   return {messages:[{role:'custom',content:label}],thinkingLevel:'off'};
  };
  hooks[version]={legacy:signal=>invoke('legacy',undefined,signal),context:(context,signal)=>invoke('context',context,signal)};
 }
 const agent=new Agent({streamFn:()=>{throw Error('unexpected provider')}});
 const set=(version,mode)=>{agent.prepareNextTurn=mode&1?hooks[version].legacy:undefined;agent.prepareNextTurnWithContext=mode&2?hooks[version].context:undefined;};
 const outcomes=[];
 const checkpoint=async(config,marker)=>{
  const turn={message:{role:'assistant',content:[]},toolResults:[],context:{messages:[{role:'user',content:marker}]},newMessages:[{role:'custom',content:marker}]};
  try{const value=config.prepareNextTurn?await config.prepareNextTurn(turn):'missing';outcomes.push(value==='missing'?'missing':value?.messages[0].content??'none');}catch(e){outcomes.push('error:'+e.message);}
 };
 set('A',f.initial);const original=agent.createLoopConfig();await checkpoint(original,'initial');
 let release;const run=agent.runWithLifecycle(async()=>await new Promise(resolve=>{release=resolve}));
 set('B',f.later);await checkpoint(original,'active');const fresh=agent.createLoopConfig();await checkpoint(fresh,'fresh');
 agent.abort();await checkpoint(original,'aborted');release();await run;
 set('B',0);await checkpoint(original,'idle');
 results.push(log+'#'+outcomes.join(','));
}
process.stdout.write(JSON.stringify(results));
