import fs from 'node:fs';
const source = fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts', 'utf8');
const start = source.indexOf('if (pendingMessages.length === 0)');
const end = source.indexOf('\n\t\t\t\tawait emit', start);
if (start < 0 || end <= start) throw new Error('upstream steering guard not found');
const steering = source.match(/pendingMessages = \(await config\.getSteeringMessages\?\.\(\)\) \|\| \[\];/);
const follow = source.match(/const followUpMessages = \(await config\.getFollowUpMessages\?\.\(\)\) \|\| \[\];/);
if (!steering || !follow) throw new Error('upstream queue polls not found');
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
const bodies = [steering[0] + 'return pendingMessages;', follow[0] + 'return followUpMessages;', source.slice(start,end) + 'return pendingMessages;'];
const cases = [];
for (let route=0; route<3; route++) for (let populated=0; populated<2; populated++) for (let mode=0; mode<4; mode++) {
  const pending=populated ? [{}] : [], supplied=[], item={};
  let calls=0, entered, release, settled=false;
  const ready=new Promise(r=>entered=r), gate=new Promise(r=>release=r);
  const callback=async()=>{calls++;entered();await gate;if(mode===3) throw 'queue failure';return supplied;};
  const forbidden=()=>{throw new Error('wrong queue selected');};
  const selected=mode ? callback : undefined;
  const config=route===1 ? {getFollowUpMessages:selected,getSteeringMessages:forbidden} : {getSteeringMessages:selected,getFollowUpMessages:forbidden};
  const task=new AsyncFunction('config','pendingMessages',bodies[route])(config,pending).then(value=>{settled=true;return {value};},error=>{settled=true;return {error};});
  if (mode && !(route===2 && populated)) {
    await ready;
    if(settled) throw new Error('queue not awaited');
    if(mode===2) supplied.push(item);
    release();
  }
  const {value,error}=await task;
  if(mode===2 && calls && value[0]!==item) throw new Error('message identity lost');
  const rendered=error ?? [value===pending,value===supplied,value.length].join('|');
  cases.push({route,populated,mode,calls,rendered});
}
console.log(JSON.stringify({cases}));
