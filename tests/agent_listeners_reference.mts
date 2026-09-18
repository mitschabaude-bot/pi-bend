// Actual pinned Agent.subscribe/processEvents; no provider execution.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {stripTypeScriptTypes} from 'node:module';
import {createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration} from '../../pi-mono/packages/ai/src/utils/transcript.ts';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent.ts','utf8');
const body=stripTypeScriptTypes(source.slice(source.indexOf('function defaultConvertToLlm('))).replace(/^export /gm,'');
const {Agent}=new Function('createInitialSystemMessage','getCurrentSystemMessage','getCurrentSystemPrompt','toToolDeclaration','getDefaultStreamFn',body+';return {Agent};')(createInitialSystemMessage,getCurrentSystemMessage,getCurrentSystemPrompt,toToolDeclaration,()=>{throw Error('unexpected fallback')});
const results=[];
for(let mode=0;mode<8;mode++){
 const agent=new Agent({streamFn:()=>{throw Error('unexpected provider')}});
 let trace='',name='',removeMiddle,removeFirst;
 const callbacks=[0,1,2].map(id=>async(event,signal)=>{
  trace+=id+':'+name+':'+(signal.aborted?'1':'0')+';';
  if(id===0){if(mode===2)removeMiddle();if(mode===3)agent.subscribe(callbacks[2]);if(mode===4){removeMiddle();removeMiddle=agent.subscribe(callbacks[1]);}if(mode===5)removeFirst();}
  if((mode===6&&id===0)||(mode===7&&id===1))throw Error('error'+id);
 });
 removeFirst=agent.subscribe(callbacks[0]);if(mode===1)agent.subscribe(callbacks[0]);removeMiddle=agent.subscribe(callbacks[1]);if(mode!==3)agent.subscribe(callbacks[2]);
 if(trace!=='')throw Error('unexpected initial emission');
 const outcomes=[];
 for(const [index,n] of ['first','second','third'].entries()){
  if(index===2){removeFirst();agent.subscribe(callbacks[0]);removeFirst();removeFirst();}
  const controller=new AbortController();if(index===1)controller.abort();agent.activeRun={abortController:controller};name=n;
  try{await agent.processEvents({type:'agent_start'});outcomes.push('ok');}catch(e){outcomes.push(e.message);}
 }
 results.push(trace+'|'+outcomes.join(','));
}
// Starting a second event must be possible while the first listener awaits it.
// Assert only causal ordering; independent completions need no fixed schedule.
for (const fail of [false, true]) {
 const agent = new Agent({streamFn:()=>{throw Error('unexpected provider')}});
 agent.activeRun = {abortController:new AbortController()};
 let release, starts=0, completed=false, later=0;
 const gate = new Promise(resolve=>{release=resolve;});
 agent.subscribe(async event=>{
  starts++;
  if(event.type==='agent_start'){
   await gate;
   completed=true;
   if(fail)throw Error('first failed');
  }else release();
 });
 agent.subscribe(event=>{
  if(event.type==='agent_start')assert.ok(completed);
  later++;
 });
 const first = agent.processEvents({type:'agent_start'}).then(()=>'',e=>e.message);
 assert.equal(starts,1);assert.equal(completed,false);assert.equal(later,0);
 const second = agent.processEvents({type:'turn_start'});
 assert.equal(starts,2);
 await second;
 assert.equal(await first,fail?'first failed':'');
 assert.equal(later,fail?1:2);
}
process.stdout.write(JSON.stringify(results));
