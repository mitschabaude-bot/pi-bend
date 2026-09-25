import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const load=name=>stripTypeScriptTypes(fs.readFileSync(UPSTREAM + '/packages/ai/src/utils/'+name+'.ts','utf8')).replace(/^export /gm,'');
const api=new Function(load('hash')+'\n'+load('sanitize-unicode')+';return {shortHash,sanitizeSurrogates};')();
let input='';for await(const chunk of process.stdin)input+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(text=>({hash:api.shortHash(text),clean:api.sanitizeSurrogates(text)}))));
