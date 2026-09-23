import { readFileSync, existsSync } from 'node:fs';
const {executeBashWithOperations}=await import(process.argv[2]+'/core/bash-executor.ts');
for(const c of JSON.parse(readFileSync(process.argv[3],'utf8'))){
 const seen:string[]=[];const ctrl=new AbortController();
 const operations={exec:async(_command:string,_cwd:string,{onData}:{onData:(data:Buffer)=>void})=>{
  for(const bytes of c.chunks)onData(Buffer.from(bytes));
  if(c.mode==='cancel')ctrl.abort();
  if(c.exit==='fail')throw new Error('injected failure');
  return {exitCode:c.exit==='none'?null:Number(c.exit)};
 }};
 try{
  const result=await executeBashWithOperations('injected','.',operations,{signal:ctrl.signal,onChunk:(s:string)=>seen.push(s)});
  let full:string|null=null;
  if(result.fullOutputPath){for(let n=0;n<100;n++){await Bun.sleep(5);if(existsSync(result.fullOutputPath)){full=readFileSync(result.fullOutputPath,'utf8');if(full===seen.join(''))break;}}}
  console.log(JSON.stringify({output:result.output,exit:result.exitCode??null,cancelled:result.cancelled,truncated:result.truncated,full,chunks:seen.join('')}));
 }catch(e){console.log(JSON.stringify({error:(e as Error).message,chunks:seen.join('')}));}
}
