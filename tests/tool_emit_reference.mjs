import fs from 'node:fs';
const source = fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts', 'utf8');
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
const extract = name => source.match(new RegExp('async function '+name+'\\([^\\n]*\\): Promise<void> \\{([\\s\\S]*?)\\n\\}'))[1];
const messages = new AsyncFunction('toolResultMessage','emit',extract('emitToolResultMessage'));
const execution = new AsyncFunction('finalized','emit',extract('emitToolExecutionEnd'));
const cases=[];
for (const failure of ['none','start','end']) {
  const message={details:'before'}, trace=[];
  let entered, release;
  const ready=new Promise(resolve => {entered=resolve;});
  const gate=new Promise(resolve => {release=resolve;});
  let completed=false;
  const task=messages(message, async event => {
    if (event.message !== message) throw new Error('identity lost');
    trace.push(event.type+':'+event.message.details);
    if (event.type === 'message_start') {
      entered(); await gate;
      if (failure === 'start') throw new Error('start failure');
      message.details='after';
    } else if (failure === 'end') throw new Error('end failure');
  }).then(() => { completed=true; return 'done'; }, error => {completed=true; return error.message;});
  await ready;
  if (completed || trace.length !== 1) throw new Error('start callback was not awaited');
  release();
  cases.push({failure, trace, outcome:await task});
}
for (const fail of [false,true]) {
  const result={details:'original'}, trace=[];
  const finalized={toolCall:{id:'id',name:'tool'},result,isError:true};
  let outcome='done';
  try { await execution(finalized, async event => {
    if (event.result !== result) throw new Error('execution result identity lost');
    trace.push(`${event.type}:${event.toolCallId}:${event.toolName}:${event.isError}`);
    event.result.details='updated';
    if (fail) throw new Error('execution failure');
  }); } catch(error) {outcome=error.message;}
  cases.push({fail, trace, outcome, details:result.details});
}
console.log(JSON.stringify({cases}));
