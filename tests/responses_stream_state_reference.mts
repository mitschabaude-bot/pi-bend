import {processStream,clean} from './responses_stream_reference.mts';
let input='';for await(const chunk of process.stdin)input+=chunk;
const results=[];
for(const c of JSON.parse(input)){
 const output={content:structuredClone(c.initial),stopReason:'toolUse'};
 const events=[];
 const snapshot=message=>({content:message.content.map(clean),stopReason:message.stopReason});
 const stream={push(e){
  const value={type:e.type,contentIndex:e.contentIndex};
  for(const field of ['delta','content'])if(e[field]!==undefined)value[field]=e[field];
  if(e.toolCall)value.toolCall=clean(e.toolCall);
  value.partial=snapshot(e.partial);
  events.push(value);
 }};
 let error;
 try{await processStream((async function*(){yield*c.events;})(),output,stream,{}, {grammarToolInputProperties:new Map(Object.entries(c.properties))});}
 catch(e){if(e.message!=='OpenAI Responses stream ended before a terminal response event')error=e.message;}
 const result={output:snapshot(output),events};
 if(error)result.error=error;
 results.push(JSON.stringify(result));
}
process.stdout.write(JSON.stringify(results));
