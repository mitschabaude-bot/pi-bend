const upstream=process.env.PI_MONO_ROOT!;
const {stream}=await import(`${upstream}/packages/ai/src/api/anthropic-messages.ts`);
const {getModel}=await import(`${upstream}/packages/ai/src/compat.ts`);
const {normalizeContext}=await import(`${upstream}/packages/ai/src/utils/transcript.ts`);
const payloads=JSON.parse(process.argv[2]);
const body=payloads.map((p:any)=>`event: ${p.type}\ndata: ${JSON.stringify(p)}\n`).join('\n')+'\n';
const response=new Response(body,{status:200,headers:{'content-type':'text/event-stream'}});
const client={beta:{messages:{create:()=>({asResponse:async()=>response})}}};
const s=stream(getModel('anthropic','claude-opus-5'),normalizeContext({messages:[{role:'user',content:'Hello',timestamp:1}]}),{client:client as any});
const observed=[];let final:any;
for await (const e of s){if(e.type!=='start') observed.push(e.type);if(e.type==='done'||e.type==='error') final=e.message??e.error;}
const content=final.content.map((x:any)=>x.type==='text'?`text:${x.text}`:x.type==='thinking'?`thinking:${x.thinking}:${x.thinkingSignature??''}`:`tool:${x.id}:${x.name}`);
console.log(JSON.stringify({events:observed,content,responseModel:final.responseModel??null,responseId:final.responseId??null,input:final.usage.input,output:final.usage.output,total:final.usage.totalTokens,reason:final.stopReason,errorMessage:final.errorMessage??null}));
