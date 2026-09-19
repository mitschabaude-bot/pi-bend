import {processStream,clean} from './responses_stream_reference.mts';
let input='';for await(const chunk of process.stdin)input+=chunk;
const results=[];
for(const c of JSON.parse(input)){
 const output={content:[],responseId:'initial',stopReason:'toolUse',errorMessage:'old error',rawStopReason:'old raw',usage:{input:11,output:3,cacheRead:7,cacheWrite:2,cacheWrite1h:1,reasoning:9,totalTokens:23,cost:{input:99,output:99,cacheRead:99,cacheWrite:99,total:99}}};
 const events=[];
 const partial=m=>({content:m.content.map(clean),stopReason:m.stopReason});
 const stream={push(e){const value={type:e.type,contentIndex:e.contentIndex};for(const k of ['delta','content'])if(e[k]!==undefined)value[k]=e[k];if(e.toolCall)value.toolCall=clean(e.toolCall);value.partial=partial(e.partial);events.push(value);}};
 let error;
 try{await processStream((async function*(){yield*c.events;})(),output,stream,{cost:c.cost});}catch(e){error=e.message;}
 const u=output.usage;
 const usage={input:u.input,output:u.output,cacheRead:u.cacheRead,cacheWrite:u.cacheWrite,totalTokens:u.totalTokens,cost:u.cost};
 for(const k of ['cacheWrite1h','reasoning'])if(u[k]!==undefined)usage[k]=u[k];
 const message={content:output.content.map(clean),usage,stopReason:output.stopReason};
 for(const k of ['responseId','errorMessage','rawStopReason'])if(output[k]!==undefined)message[k]=output[k];
 const result={output:message,events};if(error)result.error=error;
 results.push(JSON.stringify(result));
}
process.stdout.write(JSON.stringify(results));
