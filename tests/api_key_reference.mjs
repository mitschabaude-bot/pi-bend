import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const start=source.indexOf('const resolvedApiKey =');
const end=source.indexOf('\n\n',start);
if(start<0 || end<=start) throw new Error('upstream API-key expression missing');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const resolve=new AsyncFunction('config',source.slice(start,end)+'return resolvedApiKey;');
const cases=[];
for(let mode=0;mode<5;mode++) for(const fallback of [undefined,'','fallback']) for(const rotate of [false,true]) {
  let entered,release,settled=false,calls=0;
  const ready=new Promise(r=>entered=r),gate=new Promise(r=>release=r);
  const config={apiKey:fallback,model:{provider:'test-provider'}};
  if(mode) config.getApiKey=async provider=>{
    if(provider!=='test-provider') throw new Error('provider mismatch');
    calls++;if(rotate) config.apiKey='rotated';entered();await gate;
    if(mode===4) throw 'resolver failure';
    return mode===1?undefined:mode===2?'':'resolved';
  };
  const task=resolve(config).then(value=>{settled=true;return {value};},error=>{settled=true;return {error};});
  if(mode) {await ready;if(settled) throw new Error('resolver not awaited');release();}
  const {value,error}=await task;
  cases.push({mode,fallback:fallback??null,rotate,calls,result:error?'error:'+error:value===undefined?'none':'key:'+value,retained:config.apiKey??null});
}
console.log(JSON.stringify({cases}));
