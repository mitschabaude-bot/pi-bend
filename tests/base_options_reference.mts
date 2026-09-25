import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const load = path => stripTypeScriptTypes(fs.readFileSync(UPSTREAM + '/packages/ai/src/'+path+'.ts','utf8')).replace(/^export /gm,'').replace(/^import .*;$/gm,'');
const helpers = new Function(load('utils/text')+'\n'+load('utils/estimate')+'\n'+load('api/simple-options')+';return {buildBaseOptions};')();
let input='';for await(const chunk of process.stdin)input+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(c=>helpers.buildBaseOptions(c.model,{messages:c.messages},c.options??undefined,c.key??undefined))));
