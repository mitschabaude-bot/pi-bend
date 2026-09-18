import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const start=source.indexOf('const resolvedApiKey =');
const end=source.indexOf('\n\n',start);
if(start<0 || end<=start) throw new Error('upstream API-key expression missing');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const optionsStart=source.indexOf('{',source.indexOf('const response = await streamFunction',end));
const optionsEnd=source.indexOf('});',optionsStart);
if(optionsStart<0 || optionsEnd<=optionsStart) throw new Error('upstream request options missing');
const resolve=new AsyncFunction('config','signal',source.slice(start,end)+'return ('+source.slice(optionsStart,optionsEnd+1)+');');
const cases=[];
for(let mode=0;mode<5;mode++) for(const fallback of [undefined,'','fallback']) for(const rotate of [false,true]) for(const signaled of [false,true]) {
  let entered,release,settled=false,calls=0;
  const ready=new Promise(r=>entered=r),gate=new Promise(r=>release=r);
  const signal=signaled?{}:undefined;
  const convertToLlm=()=>{};
  const config={apiKey:fallback,signal:{},model:{provider:'test-provider'},convertToLlm};
  if(mode) config.getApiKey=async provider=>{
    if(provider!=='test-provider') throw new Error('provider mismatch');
    calls++;if(rotate) config.apiKey='rotated';entered();await gate;
    if(mode===4) throw 'resolver failure';
    return mode===1?undefined:mode===2?'':'resolved';
  };
  const task=resolve(config,signal).then(value=>{settled=true;return {value};},error=>{settled=true;return {error};});
  if(mode) {await ready;if(settled) throw new Error('resolver not awaited');release();}
  const {value,error}=await task;
  if(!error && (value===config || value.signal!==signal || value.model!==config.model || value.convertToLlm!==convertToLlm)) throw new Error('request snapshot identity/overrides differ');
  cases.push({mode,signaled,fallback:fallback??null,rotate,calls,result:error?'error:'+error:value.apiKey===undefined?'none':'key:'+value.apiKey,retained:config.apiKey??null});
}
console.log(JSON.stringify({cases}));
