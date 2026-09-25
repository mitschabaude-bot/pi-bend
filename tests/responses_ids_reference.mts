import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const shared=fs.readFileSync(UPSTREAM + '/packages/ai/src/api/openai-responses-shared.ts','utf8');
const start=shared.indexOf('\tconst normalizeIdPart =');
const end=shared.indexOf('\n\tconst transformedMessages =',start);
const hash=fs.readFileSync(UPSTREAM + '/packages/ai/src/utils/hash.ts','utf8');
const factory=new Function('model','allowedToolCallProviders',stripTypeScriptTypes(hash+'\n'+shared.slice(start,end)).replace(/^export /gm,'')+';return normalizeToolCallId;');
let input='';for await(const chunk of process.stdin)input+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(c=>{
 const model={provider:'openai',api:'openai-responses'};
 const normalize=factory(model,new Set(c.allowed?['openai']:['other']));
 return normalize(c.id,model,{provider:c.foreignProvider?'other':'openai',api:c.foreignApi?'other':'openai-responses'});
})));
