import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const body=source.match(/function prepareToolCallArguments\([^\n]*\): AgentToolCall \{([\s\S]*?)\n\}/)[1].replace('preparedArguments as Record<string, any>', 'preparedArguments');
const prepare=new Function('tool','toolCall',body);
const cases=[];
for (let mode=0;mode<6;mode++) {
  const old={value:'same'}, fresh={value:'same'}, failure={message:'failure'};
  const call={id:'old-id',name:'old-name',arguments:old,thoughtSignature:'old-signature',namespace:'old-namespace'};
  let invocations=0;
  const tool={};
  if (mode) tool.prepareArguments=args=>{
    invocations++;
    if (args !== old) throw new Error('wrong input');
    if (mode>=3) Object.assign(call,{id:'new-id',name:'new-name',arguments:fresh,thoughtSignature:'new-signature',namespace:'new-namespace'});
    if (mode===5) throw failure;
    return mode===2 || mode===3 ? fresh : old;
  };
  let result, failed=false;
  try {result=prepare(tool,call);} catch(error) {if(error!==failure) throw error; failed=true;}
  cases.push({mode,invocations,failed,same:result===call,id:result?.id??'',name:result?.name??'',signature:result?.thoughtSignature??'',namespace:result?.namespace??'',args:result?.arguments===fresh?'fresh':'old',originalChanged:call.arguments===fresh});
}
console.log(JSON.stringify({cases}));
