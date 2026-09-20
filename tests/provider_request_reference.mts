import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { headersToRecord } from '../../pi-mono/packages/ai/src/utils/headers.ts';
const provider = fs.readFileSync('../pi-mono/packages/ai/src/api/openai-responses.ts', 'utf8');
const start = provider.indexOf('const nextParams = await options?.onPayload?.(params, model);');
const end = provider.indexOf('stream.push({ type: "start", partial: output });', start);
if (start < 0 || end < 0) throw new Error('Upstream request stage not found');
const stage = stripTypeScriptTypes(provider.slice(start, end));
const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
const run = new AsyncFunction('params', 'model', 'options', 'client', 'retryProviderRequest', 'headersToRecord', stage + '\nreturn response;');
const retrySource = stripTypeScriptTypes(fs.readFileSync('../pi-mono/packages/ai/src/utils/provider-retry.ts', 'utf8'))
 .replace(/^export /gm, '').replace('function abortableSleep(', 'function originalAbortableSleep(');
function bits(n) { const b=Buffer.alloc(8);b.writeDoubleBE(n);return b.readUInt32BE(0)+':'+b.readUInt32BE(4); }
const cases=JSON.parse(fs.readFileSync(0,'utf8'));
const results=[];
for (const c of cases) {
 const trace=[];const sent=[];let index=0;
 const math=Object.create(Math);math.random=()=>{trace.push('random');return 0;};
 const retry=new Function('Math','sleep',retrySource+'\nfunction abortableSleep(ms,signal){return sleep(ms);}\nreturn retryProviderRequest;')(math,async ms=>{trace.push('sleep '+bits(ms));});
 const payloadError=new Error('payload');const responseError=new Error('response');
 // Give hook failures a retryable-looking status: their location outside the
 // request loop, rather than incidental error shape, must prevent retry.
 Object.assign(payloadError,{status:429});Object.assign(responseError,{status:429});
 const options={maxRetries:2,
  onPayload:[0,9].includes(c.mode)?undefined:async(value,model)=>{
   trace.push('payload:'+String(value)+':'+model);
   if(c.mode===4)throw payloadError;
   return c.mode===2?9:c.mode===3?0:c.mode===10?null:undefined;
  },
  onResponse:[0,8].includes(c.mode)?undefined:async(response,model)=>{
   trace.push('response:'+model+':'+bits(response.status)+':'+(response.headers['x-response']??'missing'));
   if([5,6].includes(c.mode))throw responseError;
  }};
 const original=new Error('bad');
 const client={responses:{create:(payload,requestOptions)=>({withResponse:async()=>{
  if(requestOptions.maxRetries!==0)throw new Error('SDK retries unexpectedly enabled');
  trace.push('request:'+String(payload));sent.push(JSON.stringify(payload));
  const response=c.responses[index++];if(!response)throw new Error('unexpected attempt');
  if(response.status<200||response.status>=300)throw Object.assign(original,{status:response.status,headers:new Headers(response.headers)});
  return {data:{},response:{status:response.status,headers:new Headers(response.headers)}};
 }})}};
 let outcome;
 try {await run(7,'model',options,client,retry,headersToRecord);outcome='success';}
 catch(error){outcome=error===payloadError?'payload':error===responseError?'response':error===original?'request':'unexpected';if(outcome==='unexpected')throw error;}
 if(index!==c.responses.length)throw new Error('unused response');
 results.push({mode:c.mode,trace,sent,outcome});
}
console.log(JSON.stringify({stage,results}));
