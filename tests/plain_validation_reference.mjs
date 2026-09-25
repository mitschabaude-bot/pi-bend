import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { Compile } from '../build/schema-reference/node_modules/typebox/build/compile/index.mjs';
import { Value } from '../build/schema-reference/node_modules/typebox/build/value/index.mjs';
const source = fs.readFileSync(UPSTREAM + '/packages/ai/src/utils/validation.ts', 'utf8');
const start = source.indexOf('const validatorCache =');
if (start < 0) throw new Error('upstream validation body missing');
const code = stripTypeScriptTypes(source.slice(start)).replace(/^export /gm, '');
const validate = new Function('Compile', 'Value', code + '\nreturn validateToolArguments;')(Compile, Value);
let input = '';
for await (const chunk of process.stdin) input += chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(({schema, value}) => {
  const tool = {name:'echo', description:'', parameters:schema};
  const call = {type:'toolCall', id:'id', name:'echo', arguments:structuredClone(value)};
  try { return {ok:true, value:validate(tool, call)}; }
  catch (error) { return {ok:false, message:String(error.message)}; }
})));
