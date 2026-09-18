import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync('../pi-mono/packages/ai/src/api/transform-messages.ts','utf8');
const body=stripTypeScriptTypes(source).replace(/^export /gm,'');
const transform=new Function(body+';return transformMessages;')();
let input='';for await(const chunk of process.stdin)input+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(({vision,content})=>transform([
 {role:'user',content:structuredClone(content),timestamp:41},
 {role:'toolResult',toolCallId:'call',toolName:'tool',content:structuredClone(content),details:'details',isError:true,timestamp:42},
 {role:'user',content:'plain',timestamp:43}
],{id:'test',api:'openai-responses',provider:'test-provider',input:vision?['text','image']:['text']}))));
