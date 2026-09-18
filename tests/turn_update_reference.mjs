import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const start=source.indexOf('if (nextTurnSnapshot) {');
const end=source.indexOf('\n\t\t\t\t// Preparation can be long-running',start);
const apply=new Function('currentContext','config','nextTurnSnapshot','let preparedMessages=[];'+source.slice(start,end)+'\nreturn {currentContext,config,preparedMessages};');
const cases=[];
for (const previous of [null,'minimal','max']) for (const requested of [null,'off','minimal','low','medium','high','xhigh','max']) for(let mask=0;mask<8;mask++) {
  const context={},replacementContext={},model={},replacementModel={},messages=[],marker={};
  const config={model,reasoning:previous??undefined,marker};
  const snapshot={thinkingLevel:requested??undefined};
  if(mask&1) snapshot.context=replacementContext;
  if(mask&2) snapshot.model=replacementModel;
  if(mask&4) snapshot.messages=messages;
  const result=apply(context,config,snapshot);
  if(result.config.marker!==marker) throw new Error('unrelated config field lost');
  cases.push({previous,requested,mask,present:true,reasoning:result.config.reasoning??null,sameConfig:result.config===config,sameContext:result.currentContext===context,sameModel:result.config.model===model,suppliedMessages:result.preparedMessages===messages});
}
for (const previous of [null,'minimal','max']) {
  const context={},config={reasoning:previous??undefined};
  const result=apply(context,config,undefined);
  cases.push({previous,requested:null,mask:0,present:false,reasoning:result.config.reasoning??null,sameConfig:result.config===config,sameContext:result.currentContext===context,sameModel:true,suppliedMessages:false});
}
console.log(JSON.stringify({cases}));
