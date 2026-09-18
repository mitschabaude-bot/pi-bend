import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const start=source.indexOf('let messages = context.messages;');
const end=source.indexOf('const llmContext = normalizeContext',start);
if(start<0 || end<=start) throw new Error('upstream conversion prefix missing');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const run=new AsyncFunction('context','config','signal',source.slice(start,end)+'return llmMessages;');
const cases=[];
for(let mode=0;mode<5;mode++) for(let signaled=0;signaled<2;signaled++) {
  const original=[],replacement=[],output=[],context={messages:original},signal=signaled?{}:undefined,trace=[];
  let ready,release,nextReady,nextRelease,settled=false;
  const entered=new Promise(r=>ready=r),gate=new Promise(r=>release=r);
  const converted=new Promise(r=>nextReady=r),convertGate=new Promise(r=>nextRelease=r);
  const converter=async messages=>{
    if(messages!==(mode===2?replacement:original)) throw new Error('wrong conversion input');
    trace.push('convert');nextReady();await convertGate;
    if(mode===4) throw 'conversion failure';return output;
  };
  const config={convertToLlm:mode?()=>{throw new Error('stale converter');}:converter};
  if(mode) config.transformContext=async(messages,receivedSignal)=>{
    if(messages!==original || receivedSignal!==signal) throw new Error('wrong transform input');
    trace.push('transform');context.messages=replacement;config.convertToLlm=converter;
    ready();await gate;if(mode===3) throw 'transform failure';return mode===2?replacement:messages;
  };
  const task=run(context,config,signal).then(value=>{settled=true;return {value};},error=>{settled=true;return {error};});
  if(mode) {await entered;if(settled || trace.join('|')!=='transform') throw new Error('transform not awaited');release();}
  if(mode!==3) {await converted;if(settled) throw new Error('converter not awaited');nextRelease();}
  const {value,error}=await task;
  cases.push({mode,signaled,result:error??(value===output?'output':'bad identity'),trace:trace.join('|'),replaced:context.messages===replacement});
}
console.log(JSON.stringify({cases}));
