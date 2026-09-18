import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const start=source.indexOf('if (await config.shouldStopAfterTurn?.(lastCompletedTurn))');
const marker='pendingMessages = (await config.getSteeringMessages?.()) || [];';
const end=source.indexOf(marker,start);
if(start<0 || end<start) throw new Error('upstream completed-turn decision block missing');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const run=new AsyncFunction('config','lastCompletedTurn','newMessages','emit','let pendingMessages;'+source.slice(start,end+marker.length)+'return pendingMessages;');
const cases=[];
for(let mode=0;mode<6;mode++) {
  const messages=[], replacement=[], queued=[], completed={newMessages:messages}, trace=[];
  let entered,release,nextEntered,nextRelease,settled=false;
  const ready=new Promise(r=>entered=r),gate=new Promise(r=>release=r);
  const nextReady=new Promise(r=>nextEntered=r), nextGate=new Promise(r=>nextRelease=r);
  const poll=async()=>{trace.push('queue');nextEntered();await nextGate;if(mode===5) throw 'queue failure';return queued;};
  const config={getSteeringMessages:mode ? ()=>{throw new Error('stale queue callback');} : poll};
  if(mode) config.shouldStopAfterTurn=async value=>{
    if(value!==completed) throw new Error('completed context copied');
    trace.push('hook');config.getSteeringMessages=poll;value.newMessages=replacement;
    entered();await gate;
    if(mode===3) throw 'hook failure';
    return mode===2 || mode===4;
  };
  const emit=async event=>{
    if(event.type!=='agent_end' || event.messages!==messages) throw new Error('incorrect end event');
    trace.push('end');nextEntered();await nextGate;if(mode===4) throw 'emit failure';
  };
  const task=run(config,completed,messages,emit).then(value=>{settled=true;return {value};},error=>{settled=true;return {error};});
  if(mode) {await ready;if(settled || trace.join('|')!=='hook') throw new Error('hook not awaited');release();}
  if(mode!==3) {await nextReady;if(settled) throw new Error('queue/event not awaited');nextRelease();}
  const {value,error}=await task;
  const result=error ?? (value===undefined ? 'stopped' : value===queued ? 'queued' : 'bad array');
  cases.push({mode,result,trace:trace.join('|'),replaced:completed.newMessages===replacement});
}
console.log(JSON.stringify({cases}));
