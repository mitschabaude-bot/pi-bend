import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { Compile } from '../build/schema-reference/node_modules/typebox/build/compile/index.mjs';
import { Value } from '../build/schema-reference/node_modules/typebox/build/value/index.mjs';
const source = fs.readFileSync('../pi-mono/packages/ai/src/utils/validation.ts', 'utf8');
const start = source.indexOf('const validatorCache =');
if (start < 0) throw new Error('upstream validation helpers missing');
const code = stripTypeScriptTypes(source.slice(start)).replace(/^export /gm, '');
const helpers = new Function('Compile', 'Value', code + '\nreturn {validateToolArguments, normalizeOptionalNulls, coerceWithJsonSchema, formatValidationPath};')(Compile, Value);
let input = '';
for await (const chunk of process.stdin) input += chunk;
const request = JSON.parse(input);
const messages = request.cases.map(({name, schema, value}) => {
  const tool = {name, description:'', parameters:schema};
  const call = {type:'toolCall', id:'id', name, arguments:structuredClone(value)};
  let message;
  try { helpers.validateToolArguments(tool, call); throw new Error('fixture must fail validation'); }
  catch (error) { message = error.message; }
  if (!message.startsWith('Validation failed')) throw new Error(message);
  let converted = structuredClone(value);
  helpers.normalizeOptionalNulls(converted, schema);
  Value.Convert(schema, converted);
  converted = helpers.coerceWithJsonSchema(converted, schema);
  return {message, issues:Compile(schema).Errors(converted)};
});
process.stdout.write(JSON.stringify({messages,
  paths:request.paths.map(error => helpers.formatValidationPath(error)),
  pretty:request.values.map(value => JSON.stringify(value, null, 2))
}));
