import {processStream,clean} from './responses_stream_reference.mts';
let input='';for await(const chunk of process.stdin)input+=chunk;
const results=[];
for(const c of JSON.parse(input)){
 const output={content:[]};const signals=[];
 const stream={push(event){const item=clean(event.partial.content[event.contentIndex]);const value={kind:event.type.endsWith('_start')?'started':event.type.endsWith('_end')?'ended':'delta',content:item};if(event.delta!==undefined)value.delta=event.delta;signals.push(value);}};
 const events=[{type:'response.output_item.added',output_index:0,item:c.item},...c.events.map(e=>({...e,output_index:0}))];
 let error;
 try{await processStream((async function*(){yield*events;})(),output,stream,{}, {grammarToolInputProperties:new Map(Object.entries(c.properties))});}
 catch(e){if(e.message!=='OpenAI Responses stream ended before a terminal response event')error=e.message;}
 const result=output.content.length?{content:clean(output.content[0]),signals}:null;
 if(error)result.error=error;
 results.push(JSON.stringify(result));
}
process.stdout.write(JSON.stringify(results));
