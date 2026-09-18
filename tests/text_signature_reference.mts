import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync('../pi-mono/packages/ai/src/api/openai-responses-shared.ts','utf8');
const start=source.indexOf('function encodeTextSignatureV1(');
const end=source.indexOf('type ToolResultOutputContent',start);
const api=new Function(stripTypeScriptTypes(source.slice(start,end))+';return {encodeTextSignatureV1,parseTextSignature};')();
let input='';for await(const chunk of process.stdin)input+=chunk;
const data=JSON.parse(input);
process.stdout.write(JSON.stringify({decoded:data.signatures.map(s=>api.parseTextSignature(s??undefined)??null),encoded:data.encodings.map(c=>api.encodeTextSignatureV1(c.id,c.phase??undefined))}));
