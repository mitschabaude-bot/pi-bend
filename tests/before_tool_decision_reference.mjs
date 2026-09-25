import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent-loop.ts','utf8');
const start=source.indexOf('if (signal?.aborted)',source.indexOf('const beforeResult ='));
const end=source.indexOf('\n\t\t}\n\t\tif (signal?.aborted)',start);
if(start<0||end<=start)throw new Error('upstream before-hook decision block missing');
const decide=new Function('signal','beforeResult','createErrorToolResult',source.slice(start,end)+'return {kind:"prepared"};');
const cases=[];
for(const aborted of [false,true])for(const present of [false,true])for(const block of [undefined,false,true])for(const reason of [undefined,'','because',' '])for(const terminate of [undefined,false,true]){
  if(!present && (block!==undefined||reason!==undefined||terminate!==undefined))continue;
  const result=decide({aborted},present?{block,reason,terminate}:undefined,message=>({content:[{type:'text',text:message}],details:{}}));
  cases.push({aborted,present,block:block??null,reason:reason??null,terminate:terminate??null,rendered:result.kind==='prepared'?'proceed':result.result.content[0].text+'|'+(result.result.terminate===true)});
}
console.log(JSON.stringify({cases}));
