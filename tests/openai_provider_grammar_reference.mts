import fs from 'node:fs';
import {processStream,clean} from './responses_stream_reference.mts';
const c=JSON.parse(fs.readFileSync(0,'utf8'));
const output={role:'assistant',content:[],api:'openai-responses',provider:'openai',model:'test',timestamp:123,usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}},stopReason:'pending'};
const events=[];
await processStream((async function*(){yield* c.events;})(),output,{push(e){events.push(e.type);}},c.model,{grammarToolInputProperties:new Map(Object.entries(c.grammar))});
console.log(JSON.stringify({content:output.content.map(clean),events,stopReason:output.stopReason}));
