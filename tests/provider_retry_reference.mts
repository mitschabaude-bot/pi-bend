import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source = stripTypeScriptTypes(fs.readFileSync('../pi-mono/packages/ai/src/utils/provider-retry.ts', 'utf8'))
  .replace(/^export /gm, '').replace('function abortableSleep(', 'function originalAbortableSleep(');
function bits(n) { const b=Buffer.alloc(8); b.writeDoubleBE(n); return b.readUInt32BE(0)+':'+b.readUInt32BE(4); }
const cases = [
  {failures:1,retries:1,ms:'1000'},
  {failures:9,retries:2,should:'false'},
  {failures:9,retries:1,seconds:'277403',cap:1000},
  {failures:1,retries:1,seconds:'2',cap:0},
  {failures:9,retries:2,seconds:'277403',cap:0,abortSleep:true},
  {failures:9},
  {failures:9,retries:2,other:true},
  {failures:9,retries:2,status:500},
  {failures:0,retries:2,preAbort:true},
  {failures:9,retries:0,preAbort:true},
  {failures:1,retries:1,status:400,should:'true',ms:'1'},
  {failures:1,retries:1,seconds:'invalid-date'},
];
const traces=[];
for (const c of cases) {
  const trace=[];
  const math=Object.create(Math); math.random=()=>{trace.push('random');return 0;};
  const date={parse(text){trace.push('date '+text);return NaN;},now(){trace.push('now');return 1000;}};
  const sleep=async ms=>{trace.push('sleep '+bits(ms)); if(c.abortSleep) {const e=new Error('Request aborted');e.name='AbortError';throw e;}};
  const retry=new Function('Math','Date','injectedSleep',source+'\nfunction abortableSleep(ms,signal){return injectedSleep(ms,signal);}\nreturn retryProviderRequest;')(math,date,sleep);
  const controller=new AbortController();if(c.preAbort)controller.abort('stop');
  const headers=new Headers();
  for(const [key,value] of [['x-should-retry',c.should],['retry-after-ms',c.ms],['retry-after',c.seconds]])if(value!==undefined)headers.set(key,value);
  const original=new Error('provider message');
  if(!c.other)Object.assign(original,{status:c.status??429,headers});
  let count=0;
  try {
    const value=await retry(async()=>{trace.push('request');if(count++<c.failures)throw original;return 'ok';},
      {maxRetries:c.retries,maxRetryDelayMs:c.cap,signal:controller.signal});
    trace.push('done '+value);
  }catch(e){
    if(e===original)trace.push((c.other?'other':'provider')+' original');
    else if(e.name==='AbortError')trace.push('abort');
    else if(e.message.startsWith('Server requested '))trace.push('cap provider message');
    else throw e;
  }
  traces.push(trace.join('\n')+'\n');
}
console.log(JSON.stringify(traces));
