import {readFileSync} from 'node:fs';
const M=await import(process.argv[2]+'/core/messages.ts');
for(const c of JSON.parse(readFileSync(process.argv[3],'utf8'))){
 console.log(JSON.stringify(c.kind==='date'?Date.parse(c.timestamp):M.bashExecutionToText(c.message)));
}
