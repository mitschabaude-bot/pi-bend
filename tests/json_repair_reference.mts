import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync('../pi-mono/packages/ai/src/utils/json-parse.ts','utf8');
const code=source.slice(source.indexOf('const VALID_JSON_ESCAPES'),source.indexOf('/**\n * Attempts to parse potentially incomplete JSON'));
const api=new Function(stripTypeScriptTypes(code).replace(/^export /gm,'')+';return {repairJson,parseJsonWithRepair};')();
let input='';for await(const chunk of process.stdin)input+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(text=>{const repaired=api.repairJson(text);try{return {repaired,ok:true,value:api.parseJsonWithRepair(text)}}catch{return {repaired,ok:false}}})));
