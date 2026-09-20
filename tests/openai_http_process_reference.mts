// Test-only oracle: execute the pinned pi processor, snapshot events at emission.
import {processStream} from './responses_stream_reference.mts';
let input=''; for await (const chunk of process.stdin) input+=chunk;
const scalars=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
const contents=m=>m.content.map(c=>c.type==='text'?scalars(c.text)+';':'other;').join('');
function bits(n){const b=Buffer.alloc(8);b.writeDoubleBE(n);return `${b.readUInt32BE(0)},${b.readUInt32BE(4)}`;}
const results=[];
for(const c of JSON.parse(input)){
 const usage={input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};
 const output={content:[],stopReason:'pending',usage}; const trace=[];let error='ok';
 const sink={push(e){
  if(e.type==='text_start')trace.push('text-start:'+contents(e.partial));
  else if(e.type==='text_delta')trace.push('text-delta:'+scalars(e.delta)+':'+contents(e.partial));
  else if(e.type==='text_end')trace.push('text-end:'+scalars(e.content)+':'+contents(e.partial));
  else trace.push('other-event');
  if(c.sinkFail&&e.type==='text_delta')throw Error('sink');
 }};
 async function* source(){yield* c.events;if(c.readError)throw Error(c.readError);}
 try{await processStream(source(),output,sink,{cost:{input:1000000,output:2000000,cacheRead:3000000,cacheWrite:4000000}});}catch(e){
  if(e.message==='sink')error='emit:sink';
  else if(c.readError&&e.message===c.readError)error='read:'+c.readError;
  else error='terminal';
 }
 const u=output.usage;
 results.push({trace,output:'output:'+contents(output)+':'+(output.responseId??'none')+':'+output.stopReason+':'+[u.input,u.output,u.cacheRead,u.cacheWrite,u.totalTokens,u.cost.total].map(bits).join(':'),result:'result:'+error});
}
process.stdout.write(JSON.stringify(results));
