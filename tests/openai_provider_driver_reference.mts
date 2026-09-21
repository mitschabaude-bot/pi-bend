// Exact pinned outer wrapper and processor, with injected client/effects.
import fs from 'node:fs';
import {createRequire,stripTypeScriptTypes} from 'node:module';
import {headersToRecord} from '../../pi-mono/packages/ai/src/utils/headers.ts';
import {normalizeProviderError,formatProviderError} from '../../pi-mono/packages/ai/src/utils/error-body.ts';
import {processStream} from './responses_stream_reference.mts';
const source=fs.readFileSync('../pi-mono/packages/ai/src/api/openai-responses.ts','utf8');
const first=source.indexOf('const nextParams = await options?.onPayload?.(params, model);');
const last=source.indexOf('\n\t})();',first);
if(first<0||last<0)throw Error('wrapper source not found');
// Optional preparationError comes from the independently executed pinned
// preparation oracle; inject it into the original wrapper's catch boundary.
const wrapper=stripTypeScriptTypes('try {\nif (preparationError !== undefined) throw new Error(preparationError);\n'+source.slice(first,last));
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const run=new AsyncFunction('params','model','options','client','retryProviderRequest','headersToRecord','stream','output','processResponsesStream','grammarToolInputProperties','applyServiceTierPricing','normalizeProviderError','formatProviderError','preparationError',wrapper);
const retrySource=stripTypeScriptTypes(fs.readFileSync('../pi-mono/packages/ai/src/utils/provider-retry.ts','utf8')).replace(/^export /gm,'').replace('function abortableSleep(', 'function originalAbortableSleep(');
const scalars=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
function bits(n,sep=','){const b=Buffer.alloc(8);b.writeDoubleBE(n);return b.readUInt32BE(0)+sep+b.readUInt32BE(4);}
function shownMessage(m){const u=m.usage;return 'output:'+m.content.map(c=>c.type==='text'?scalars(c.text)+';':'other;').join('')+':'+(m.responseId??'none')+':'+m.stopReason+':'+[u.input,u.output,u.cacheRead,u.cacheWrite,u.totalTokens,u.cost.total].map(n=>bits(n)).join(':')+':error:'+(m.errorMessage===undefined?'none':scalars(m.errorMessage));}
const input=JSON.parse(fs.readFileSync(0,'utf8'));const results=[];
const pricingOffset=source.indexOf('function getServiceTierCostMultiplier(');
if(pricingOffset<0)throw Error('service tier source not found');
const defaultPricing=new Function(stripTypeScriptTypes(source.slice(pricingOffset))+'\nreturn applyServiceTierPricing;')();
let StatusError;
if(input.some(c=>c.sdkStatusError)){
 const path='/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai';
 if(JSON.parse(fs.readFileSync(path+'/package.json','utf8')).version!=='6.40.0')throw Error('SDK version mismatch');
 StatusError=createRequire(import.meta.url)(path).APIError;
}

for(const c of input){
 const trace=[],retained=[],sent=[];let attempt=0;
 const output={role:'assistant',content:[],api:'openai-responses',provider:'openai',model:'test',timestamp:123,usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}},stopReason:'pending'};
 const signal={aborted:c.preaborted??false}; const model={id:c.modelId??'test',provider:'openai',cost:{input:1000000,output:2000000,cacheRead:3000000,cacheWrite:4000000}};
 const options={maxRetries:2,signal,serviceTier:c.serviceTier,
  onPayload:async p=>{trace.push('payload:'+(c.structuredPayload?JSON.stringify(p):String(p))+':model');if(c.mode===2)throw Error('payload');return c.mode===14?9:c.mode===15?null:undefined;},
  onResponse:async r=>{trace.push('response:model:'+bits(r.status,':')+':'+r.headers['x-response']);if(c.mode===3)throw Error('response');}
 };
 const math=Object.create(Math);math.random=()=>{trace.push('random');return 0;};
 const retry=new Function('Math','sleep',retrySource+'\nfunction abortableSleep(ms,signal){return sleep(ms);}\nreturn retryProviderRequest;')(math,async ms=>trace.push('sleep '+bits(ms,':')));
 async function* read(){let ended=false;try{yield* c.events;if(c.mode===10){trace.push('diagnostic');throw Error('json');}ended=true;}finally{if(!ended){trace.push('abort-hook');if(c.abortCallerOnIteratorClose!==false)signal.aborted=true;}}}
 const client={responses:{create:(payload,opts)=>({withResponse:async()=>{
  if(opts.maxRetries!==0)throw Error('SDK retries enabled');
  // The real SDK rejects an already-aborted request before network dispatch.
  if(opts.signal?.aborted)throw Error('Request aborted');
  trace.push('request:'+(c.structuredPayload?JSON.stringify(payload):String(payload)));sent.push(JSON.stringify(payload));
  const status=c.statuses[attempt++];if(status===undefined)throw Error('unexpected attempt');
  if(status<200||status>=300)throw c.sdkStatusError?StatusError.generate(status,{error:{message:'original'}},undefined,new Headers()):Object.assign(Error('original'),{status,headers:new Headers()});
  return {data:read(),response:{status,headers:new Headers({'x-response':'ok'})}};
 }})}};
 const stream={push(e){const m=e.partial??e.message??e.error;trace.push('emit:'+e.type+':'+shownMessage(m));
  if((c.mode===4&&e.type==='start')||(c.mode===5&&e.type==='text_delta')||(c.mode===6&&e.type==='done')||(c.mode===7&&e.type==='error'))throw Error('sink');
  retained.push(structuredClone(e));},end(){trace.push('close');}};
 async function processor(...args){await processStream(...args);if(c.mode===8)signal.aborted=true;if(c.mode===17)output.stopReason='pending';if(c.mode===12)throw Error('cleanup');}
 let unhandled=null;try{await run(c.structuredPayload?c.params:7,model,options,client,retry,headersToRecord,stream,output,processor,{},c.defaultPricing?defaultPricing:x=>x,normalizeProviderError,formatProviderError,c.preparationError);}catch(e){unhandled=e.message;}
 if(attempt!==c.statuses.length)throw Error('unused scripted response');
 results.push({mode:c.mode,trace,sent,retained:retained.map(e=>'retained:'+e.type+':'+shownMessage(e.partial??e.message??e.error)),final:'final:'+shownMessage(output),error:output.errorMessage??null,unhandled});
}
console.log(JSON.stringify({wrapper,results}));
