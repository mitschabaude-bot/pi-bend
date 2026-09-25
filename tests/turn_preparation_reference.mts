import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const { getCurrentTools, getToolStateChanges, toToolDeclaration } = await import(UPSTREAM + '/packages/ai/src/utils/transcript.ts');
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent-loop.ts','utf8');
const declarations=source.slice(source.indexOf('function declareToolChanges('),source.indexOf('\n/**\n * Stream an assistant response'));
const body=source.slice(source.indexOf('let preparedMessages: AgentMessage[] = [];'),source.indexOf('// Stream assistant response'));
const code=declarations+'\nasync function stage(currentContext,newMessages,config,lastCompletedTurn,pendingMessages,emit){\n'+body+'\nreturn {currentContext,newMessages,config};\n}';
const stage=new Function('getCurrentTools','getToolStateChanges','toToolDeclaration','Date',stripTypeScriptTypes(code)+';return stage;')(getCurrentTools,getToolStateChanges,toToolDeclaration,{now:()=>777});
let text='';for await(const chunk of process.stdin)text+=chunk;
const tool=name=>({name,description:'',parameters:null});
const custom=content=>({role:'custom',content});
const name=message=>message.role==='system'?(message.content||'system')+':'+(message.toolsAdded??[]).map(t=>t.name+',').join(''):message.content;
const names=messages=>messages.map(m=>name(m)+'|').join('');
const results=[];
for(const fixture of JSON.parse(text)){
  const events=[];
  const context={messages:[custom('old')],tools:[tool('old')]};
  const config={model:{name:'original'},reasoning:'high',
    prepareNextTurn:async completed=>{
      events.push('prepare');
      if(names(completed.context.messages)!=='old|'||names(completed.newMessages)!=='generated|')throw new Error('source completed snapshot mismatch');
      if(fixture.mode===2)throw new Error('prepare failed');
      if(fixture.mode===0)return undefined;
      return {context:{messages:[custom('compacted')],tools:[tool('new')]},messages:[custom('prepared'),{role:'system',content:'intent',toolsAdded:[tool('bogus')],timestamp:33}],model:{name:'replacement'},thinkingLevel:'off'};
    },
    getSteeringMessages:async()=>{events.push('queue');if(fixture.queueMode===2)throw new Error('queue failed');return fixture.queueMode===1?[custom('queued')]:[];}
  };
  const emit=async event=>{
    const key=event.type==='turn_start'?event.type:(event.type==='message_start'?'start:':'end:')+name(event.message);
    events.push(key);if(key===fixture.failAt)throw new Error('delivery failed');
  };
  let result;
  try{
    const actual=await stage(context,[custom('generated')],config,fixture.initial?undefined:{context,newMessages:[custom('generated')]},fixture.retained?[custom('retained')]:[],emit);
    const replaced=!fixture.initial&&fixture.mode===1;
    if(actual.config.model.name!==(replaced?'replacement':'original')||actual.config.reasoning!==(replaced?undefined:'high'))throw new Error('source configuration mismatch');
    const added=names(actual.newMessages).slice('generated|'.length);
    if(names(actual.currentContext.messages)!==(replaced?'compacted|':'old|')+added)throw new Error('source histories mismatch');
    result={messages:added,error:''};
  }catch(error){result={messages:'',error:error.message};}
  results.push({...result,events});
}
process.stdout.write(JSON.stringify(results));
