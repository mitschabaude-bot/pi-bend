// Execute the pinned upstream normalization helper; TypeScript erasure is test-only.
import fs from 'node:fs';
import { Compile } from '../build/schema-reference/node_modules/typebox/build/compile/index.mjs';
const source = fs.readFileSync('../pi-mono/packages/ai/src/utils/validation.ts', 'utf8');
const start = source.indexOf('function normalizeOptionalNulls(');
const end = source.indexOf('\nfunction getValidator(', start);
if (start < 0 || end <= start) throw new Error('upstream normalization helper missing');
const body = source.slice(start, end)
  .replace('(value: unknown, schema: JsonSchemaObject): void', '(value, schema)')
  .replace('value as Record<string, unknown>', 'value')
  .replace('(propertySchema as { $ref?: unknown })', 'propertySchema');
const validatorEnd = source.indexOf('\nfunction formatValidationPath(', end);
if (validatorEnd <= end) throw new Error('upstream validator cache helper missing');
const validatorBody = source.slice(end, validatorEnd)
  .replace('(schema: Tool["parameters"]): ReturnType<typeof Compile>', '(schema)')
  .replace('schema as object', 'schema');
const normalize = new Function('Compile',
  'const validatorCache = new WeakMap();\n' + validatorBody +
  '\nfunction getSubSchemaValidator(schema) { try { return getValidator(schema); } catch { return undefined; } }\n' +
  body + '\nreturn normalizeOptionalNulls;'
)(Compile);
let input = '';
for await (const chunk of process.stdin) input += chunk;
process.stdout.write(JSON.stringify(JSON.parse(input).map(({schema, value}) => {
  const result = structuredClone(value);
  normalize(result, schema);
  return result;
})));
