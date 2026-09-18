import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const start=source.indexOf('const nextTurnSnapshot = await config.prepareNextTurn?.(lastCompletedTurn);');
const end=source.indexOf('\n\t\t\t\t// Preparation can be long-running',start);
if(start<0 || end<=start) throw new Error('upstream next-turn preparation block not found');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const prepare=new AsyncFunction('currentContext','config','lastCompletedTurn','let preparedMessages=[];'+source.slice(start,end)+'\nreturn {currentContext,config,preparedMessages};');
const cases=[];
for(let mode=0;mode<5;mode++) {
  const context={},completed={},messages=[],config={reasoning:'high',model:{}};
  let calls=0,release,entered,settled=false;
  const ready=new Promise(resolve=>{entered=resolve;});
  const gate=new Promise(resolve=>{release=resolve;});
  if(mode) config.prepareNextTurn=async turn=>{
    if(turn!==completed) throw new Error('completed context identity changed');
    calls++; config.reasoning='low'; entered(); await gate;
    if(mode===4) throw 'hook failure';
    return mode===1 ? undefined : mode===2 ? {} : {messages,thinkingLevel:'off'};
  };
  const task=prepare(context,config,completed).then(result=>{settled=true;return {result};},error=>{settled=true;return {error};});
  if(mode) {await ready;if(settled) throw new Error('hook not awaited');release();}
  const {result,error}=await task;
  const rendered=error ?? [result.config===config,result.config.reasoning??'none',result.config.model===config.model,result.preparedMessages===messages,result.currentContext===context].join('|');
  cases.push({mode,rendered,calls,original:config.reasoning});
}
console.log(JSON.stringify({cases}));
