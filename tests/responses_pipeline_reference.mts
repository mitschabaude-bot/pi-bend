// Actual pinned SDK byte-to-JSON iterator feeding pi's actual Responses processor.
import fs from 'node:fs';
import {processStream,clean} from './responses_stream_reference.mts';
const sdk='/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai';
if(JSON.parse(fs.readFileSync(sdk+'/package.json','utf8')).version!=='6.40.0')throw Error('SDK version mismatch');
const {Stream}=await import(sdk+'/core/streaming.mjs');
let input='';for await(const chunk of process.stdin)input+=chunk;
const saved=console.error;
const results=[];
const encodeUsage=u=>{const v={input:u.input,output:u.output,cacheRead:u.cacheRead,cacheWrite:u.cacheWrite,totalTokens:u.totalTokens,cost:structuredClone(u.cost)};for(const k of ['cacheWrite1h','reasoning'])if(u[k]!==undefined)v[k]=u[k];return v;};
for(const c of JSON.parse(input)){
 const output={content:[],responseId:'initial',stopReason:'toolUse',errorMessage:'old error',rawStopReason:'old raw',usage:{input:11,output:3,cacheRead:7,cacheWrite:2,cacheWrite1h:1,reasoning:9,totalTokens:23,cost:{input:99,output:99,cacheRead:99,cacheWrite:99,total:99}}};
 const trace=[];let at=0,emits=0;
 const aborted=()=>Object.assign(new Error('cancelled'),{name:'AbortError'});
 const raw={
  [Symbol.asyncIterator](){return this;},
  async next(){trace.push('read');if(at===c.chunks.length)return {done:true};const chunk=c.chunks[at++];if(chunk?.error)throw Error('read failed');if(chunk?.abort)throw aborted();return {done:false,value:Array.isArray(chunk)?Uint8Array.from(chunk):chunk};},
  async return(){trace.push('close');if(c.closeMode==='1')throw Error('close failed');if(c.closeMode==='2')throw aborted();return {done:true};}
 };
 const diagnostic=target=>(...args)=>{if(args[0]==='Could not parse message into JSON:')trace.push('diagnostic:'+target);};
 console.error=diagnostic('console');
 const stream=Stream.fromSSEResponse({body:raw,headers:new Headers()},{abort(){trace.push('abort');}},{logLevel:'error',logger:{error:diagnostic('client')}},false);
 const sink={push(e){const value={type:e.type,contentIndex:e.contentIndex};for(const k of ['delta','content'])if(e[k]!==undefined)value[k]=e[k];if(e.toolCall)value.toolCall=clean(e.toolCall);value.partial={content:e.partial.content.map(clean),stopReason:e.partial.stopReason};trace.push({emit:value});if(c.sinkMode!=='0'&&emits===Number(c.sinkMode)-1)throw Error('sink failed');emits++;}};
 let error;
 try{await processStream(stream,output,sink,{cost:{input:0,output:0,cacheRead:0,cacheWrite:0}},{});}
 catch(e){error=e instanceof SyntaxError?'json':e.constructor.name==='APIError'?'api':e.message;}
 const message={content:output.content.map(clean),usage:encodeUsage(output.usage),stopReason:output.stopReason};for(const k of ['responseId','errorMessage','rawStopReason'])if(output[k]!==undefined)message[k]=output[k];
 const result={output:message,trace};if(error)result.error=error;results.push(result);
}
console.error=saved;
process.stdout.write(JSON.stringify(results));
